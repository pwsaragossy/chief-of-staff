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

root=${1:?usage: dispatcher.sh /path/to/workspace}
[ -f "$root/.chief-of-staff" ] || { echo "not a workspace: $root" >&2; exit 1; }
max=${COS_MAX_RUNS_PER_DAY:-3}
budget=${COS_MAX_BUDGET_USD:-2}
limit=${COS_RUN_TIMEOUT:-1800}
bin=${CLAUDE_BIN:-claude}
log="$root/.dispatch.log"
today=$(date +%F)
note() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$log"; }

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

prompt='You were started by the chief-of-staff dispatcher, with nobody watching. Follow this folder'"'"'s CLAUDE.md. Do the next action recorded in STATE.md and nothing beyond it. Do not ask anyone anything: write questions on the project card with status waiting-owner. Finish with the handoff skill.'

for s in "$root"/projects/*/STATE.md; do
  [ -f "$s" ] || continue
  [ "$(fm_get "$s" status)" = "in-progress" ] && [ "$(fm_get "$s" dispatch)" = "ready" ] || continue
  runs=$(grep -c "^$today [0-9:]* run " "$log" 2>/dev/null || true)
  if [ "${runs:-0}" -ge "$max" ]; then note "ceiling: $max runs today, stopping"; break; fi
  p=$(basename "$(dirname "$s")")
  fm_set "$s" dispatch running
  note "run $p: $(fm_get "$s" next)"
  # Guard rails: the whole workspace is reachable (board, ROUTING.md); agent rules, settings,
  # Keychain, push and questions are not. These are permission rules, not a sandbox.
  (cd "$root/projects/$p" && exec "$bin" -p "$prompt" \
    --add-dir "$root" \
    --permission-mode acceptEdits \
    --max-budget-usd "$budget" \
    --allowedTools "Bash(git add:*)" "Bash(git commit:*)" "Bash(git status:*)" "Bash(git diff:*)" \
    --disallowedTools "Edit(**/CLAUDE.md)" "Edit(**/.claude/**)" \
      "Bash(security:*)" "Bash(git push:*)" "AskUserQuestion" \
    >> "$root/.dispatch-$p.out" 2>&1) &
  run=$!
  rm -f "$lock/timeout"
  # Watcher: kills the run after $limit seconds. Its own sleep dies with it (no orphan holding fds).
  (trap 'kill $sp 2>/dev/null; exit 0' TERM; sleep "$limit" & sp=$!; wait $sp || exit 0
   : > "$lock/timeout"; kill "$run" 2>/dev/null) &
  watch=$!
  wait "$run"; rc=$?
  kill "$watch" 2>/dev/null; wait "$watch" 2>/dev/null; run= watch=
  [ -f "$lock/timeout" ] && note "timeout: $p killed after ${limit}s"
  # A run that ended without a handoff must not loop: park it for a human look.
  if [ "$(fm_get "$s" dispatch)" = "running" ]; then fm_set "$s" dispatch off; note "done $p rc=$rc, no handoff: dispatch set to off"
  else note "done $p rc=$rc, dispatch now $(fm_get "$s" dispatch)"; fi
done

if [ "${COS_PUSH:-0}" = 1 ]; then
  git -C "$root" push -q 2>>"$log" && note "pushed" || note "push failed"
fi
