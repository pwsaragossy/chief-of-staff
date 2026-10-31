#!/bin/sh
# Dispatcher: starts the next session on its own, from what the last one wrote in STATE.md.
# OFF by default. It runs only projects whose STATE.md front matter says `status: in-progress`
# and `dispatch: ready` (the handoff skill sets that when the next action needs nobody).
#
# Usage: dispatcher.sh /path/to/workspace
# Env:   COS_MAX_RUNS_PER_DAY (default 3)    ceiling across all projects, per calendar day
#        COS_MAX_BUDGET_USD (default 2)      API spend cap per run (passed to claude)
#        COS_RUN_TIMEOUT (default 1800)      seconds before a run is killed
#        COS_PUSH=1                          push the workspace after the runs (the backup)
#        COS_ALLOW_NO_BACKUP=1               run even if the workspace git repo has no remote
#        CLAUDE_BIN (default claude)         absolute path recommended under launchd or cron
. "$(dirname "$0")/lib.sh"

root=$(cd "${1:?usage: dispatcher.sh /path/to/workspace}" && pwd) || exit 1
[ -f "$root/.chief-of-staff" ] || { echo "not a workspace: $root" >&2; exit 1; }
max=${COS_MAX_RUNS_PER_DAY:-3}
budget=${COS_MAX_BUDGET_USD:-2}
limit=${COS_RUN_TIMEOUT:-1800}; case $limit in ""|*[!0-9]*) limit=1800 ;; esac
bin=${CLAUDE_BIN:-claude}
log="$root/.dispatch.log"
today=$(date +%F)
note() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$log"; }
# Everything in .git that can make git run code: config and hooks.
git_fingerprint() { cat "$root/.git/config" "$root"/.git/hooks/* 2>/dev/null | cksum; }
safegit() { git -C "$root" -c core.hooksPath=/dev/null -c core.fsmonitor= -c diff.external= "$@"; }

command -v "$bin" >/dev/null 2>&1 || { note "refused: '$bin' not found; set CLAUDE_BIN to its absolute path"; exit 1; }

# Backup first: unattended edits without an off-machine copy are not allowed by default.
if [ -z "$(git -C "$root" remote 2>/dev/null)" ] && [ "${COS_ALLOW_NO_BACKUP:-0}" != 1 ]; then
  note "refused: workspace has no git remote (backup). Set COS_ALLOW_NO_BACKUP=1 to override."
  exit 1
fi

# One dispatcher at a time. A lock whose process is gone (crash, kill -9) is stale and taken over.
lock="$root/.dispatch.lock"
if ! mkdir "$lock" 2>/dev/null; then
  old=$(cat "$lock/pid" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then note "skipped: dispatcher $old is running"; exit 0; fi
  note "stale lock from pid ${old:-unknown} removed"
  rm -rf "$lock" && mkdir "$lock" || exit 1
fi
echo $$ > "$lock/pid"
run= watch=
trap 'kill $watch $run 2>/dev/null; rm -rf "$lock"' EXIT
trap 'exit 130' INT TERM

# We hold the lock, so a project still marked running was cut off by a crash or a kill: park it.
for s in "$root"/projects/*/STATE.md; do
  [ -f "$s" ] && [ "$(fm_get "$s" dispatch)" = "running" ] || continue
  fm_set "$s" dispatch off; note "parked $(basename "$(dirname "$s")"): previous run was interrupted"
done

prompt='You were started by the chief-of-staff dispatcher, with nobody watching. Follow this folder'"'"'s CLAUDE.md. Do the next action recorded in STATE.md and nothing beyond it. Do not ask anyone anything: write questions on the project card with status waiting-owner. Finish with the handoff skill, but do not run git: the dispatcher commits after you.'

for s in "$root"/projects/*/STATE.md; do
  [ -f "$s" ] || continue
  [ "$(fm_get "$s" status)" = "in-progress" ] && [ "$(fm_get "$s" dispatch)" = "ready" ] || continue
  # a shared workspace: only this person's projects, so two teammates' dispatchers never run the same one
  cos_shared "$root" && { [ -n "$(cos_member "$root")" ] && [ "$(fm_get "$s" member)" = "$(cos_member "$root")" ] || continue; }
  runs=$(grep -c "^$today [0-9:]* run " "$log" 2>/dev/null || true)
  if [ "${runs:-0}" -ge "$max" ]; then note "ceiling: $max runs today, stopping"; break; fi
  p=$(basename "$(dirname "$s")")
  fm_set "$s" dispatch running
  note "run $p: $(fm_get "$s" next)"
  # Guard rails: read and edit tools only, no shell at all (so no git, no sed/cp around the denies).
  # The whole workspace is reachable (board, ROUTING.md); agent rules, settings, git internals and
  # the dispatcher's own files are denied by absolute paths ("//" + root). Permission rules, not a sandbox.
  before=$(git_fingerprint)
  (cos_gitenv_off; cd "$root/projects/$p" && exec "$bin" -p "$prompt" \
    --add-dir "$root" \
    --permission-mode default \
    --max-budget-usd "$budget" \
    --allowedTools Read Glob Grep Edit Write \
    --disallowedTools Bash AskUserQuestion \
      "Edit(/$root/**/CLAUDE.md)" "Edit(/$root/**/.claude/**)" "Edit(/$root/.git/**)" "Edit(/$root/**/.gitattributes)" "Edit(/$root/.dispatch*)" \
    >> "$root/.dispatch-$p.out" 2>&1) &
  run=$!
  rm -f "$lock/timeout"
  # Watcher: kills the run after $limit seconds. It polls in 1 s steps, so no long sleep outlives it
  # (a TERM racing the trap left "sleep $limit" orphaned, holding fds and the final wait for up to $limit s)
  ( n=0; while kill -0 "$run" 2>/dev/null; do
      [ $n -ge "$limit" ] && { : > "$lock/timeout"; kill "$run" 2>/dev/null; break; }
      sleep 1; n=$((n + 1)); done ) </dev/null >/dev/null 2>&1 &
  watch=$!
  wait "$run"; rc=$?
  kill "$watch" 2>/dev/null; wait "$watch" 2>/dev/null; run= watch=
  [ -f "$lock/timeout" ] && note "timeout: $p killed after ${limit}s"
  # Git config or hooks changed during an unattended run: stop everything, push nothing.
  if [ "$(git_fingerprint)" != "$before" ]; then
    fm_set "$s" dispatch off
    note "ALERT: .git/config or .git/hooks changed during the run of $p; dispatcher stopped, nothing pushed"
    exit 1
  fi
  # The dispatcher commits, with git's code-running config switched off.
  safegit add -A && safegit commit -qm "dispatch: $p" --no-verify >/dev/null 2>&1 && note "committed $p"
  # A run that ended without a handoff must not loop: park it for a human look.
  if [ "$(fm_get "$s" dispatch)" = "running" ]; then fm_set "$s" dispatch off; note "done $p rc=$rc, no handoff: dispatch set to off"
  else note "done $p rc=$rc, dispatch now $(fm_get "$s" dispatch)"; fi
done

# a shared workspace goes to the team only through the turn-end checks (sync.sh), never by a plain push
if [ "${COS_PUSH:-0}" = 1 ] && cos_shared "$root"; then note "COS_PUSH ignored: a shared workspace is pushed by each turn end, after its checks"
elif [ "${COS_PUSH:-0}" = 1 ]; then
  safegit push -q --no-verify 2>>"$log" && note "pushed" || note "push failed"
fi
