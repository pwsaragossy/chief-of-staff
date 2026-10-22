#!/bin/sh
# Self-test: builds a throwaway workspace and checks the hooks and the dispatcher. No network, no real claude.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/central" "$W/board" "$W/projects/alpha" "$W/projects/beta" "$W/knowledge/notes" "$W/knowledge/inbox"
: > "$W/.chief-of-staff"
for p in alpha beta; do
  sed -e "s/{{PROJECT_NAME}}/$p/" -e "s/{{DATE}}/2026-01-01/" -e "s/{{NEXT_ACTION}}/do $p thing/" \
    "$here/../templates/project/STATE.md" > "$W/projects/$p/STATE.md"
done
sed -e 's/{{PROJECT_SLUG}}/alpha/' -e 's/{{SESSION_NAME}}/session-alpha/' -e 's/{{DATE}}/2026-01-01/' \
  "$here/../templates/board/card.md" > "$W/board/Alpha.md"
fm_set "$W/board/Alpha.md" status waiting-owner
printf -- '---\nid: n1\nprojects: [beta, alpha]\nstatus: new\nconfidence: low\n---\n' > "$W/knowledge/notes/n1.md"
printf -- '---\nid: n2\nprojects: [alphabet]\nstatus: new\n---\n' > "$W/knowledge/notes/n2.md"

# front matter helpers
check "fm_get reads a field" '[ "$(fm_get "$W/projects/alpha/STATE.md" next)" = "do alpha thing" ]'
fm_set "$W/projects/alpha/STATE.md" dispatch ready
check "fm_set replaces a field" '[ "$(fm_get "$W/projects/alpha/STATE.md" dispatch)" = ready ]'
fm_set "$W/projects/alpha/STATE.md" newkey v
check "fm_set adds a missing field inside front matter" '[ "$(fm_get "$W/projects/alpha/STATE.md" newkey)" = v ]'
check "fm_set keeps the body" 'grep -q "^## 7. What I did not verify" "$W/projects/alpha/STATE.md"'
fm_set "$W/projects/alpha/STATE.md" newkey 'a\tb'
check "fm_set keeps backslashes literal" '[ "$(fm_get "$W/projects/alpha/STATE.md" newkey)" = "a\\tb" ]'
printf -- '---\r\nstatus: waiting-owner\r\nproject: beta\r\n---\r\nbody\r\n' > "$W/board/Crlf.md"
check "fm_get reads CRLF files" '[ "$(fm_get "$W/board/Crlf.md" status)" = waiting-owner ]'

# briefing
b() { CLAUDE_PROJECT_DIR="$1" sh "$here/briefing.sh"; }
check "briefing is silent outside a workspace" '[ -z "$(b /tmp)" ]'
check "central briefing lists waiting cards" 'b "$W/central" | grep -q "Alpha (project: alpha"'
check "central briefing lists projects" 'b "$W/central" | grep -q "beta: status in-progress"'
check "project briefing shows next action" 'b "$W/projects/alpha" | grep -q "Next action recorded: do alpha thing"'
check "project briefing lists its linked note" 'b "$W/projects/alpha" | grep -q "^- n1 "'
check "project briefing ignores a prefix match" '! b "$W/projects/alpha" | grep -q "^- n2"'
check "briefing stays under 2000 bytes" '[ "$(b "$W/central" | wc -c)" -le 2000 ]'

# ask guard
g() { CLAUDE_PROJECT_DIR="$1" sh "$here/ask-guard.sh" 2>/dev/null; echo $?; }
check "guard allows central" '[ "$(g "$W/central")" = 0 ]'
check "guard blocks a project" '[ "$(g "$W/projects/alpha")" = 2 ]'
check "guard ignores folders outside a workspace" '[ "$(g /tmp)" = 0 ]'

# dispatcher, with a stub CLI. The stub does a handoff only for alpha.
stub="$W/stub.sh"
cat > "$stub" <<EOF
#!/bin/sh
echo "stub called in \$PWD with: \$*"
case "\$PWD" in */alpha) . "$here/lib.sh"; fm_set STATE.md dispatch off ;; esac
EOF
chmod +x "$stub"
git -C "$W" init -q; git -C "$W" config user.name t; git -C "$W" config user.email t@t
check "dispatcher refuses without a remote" '! CLAUDE_BIN="$stub" sh "$here/dispatcher.sh" "$W" && grep -q "refused: workspace has no git remote" "$W/.dispatch.log"'
fm_set "$W/projects/beta/STATE.md" dispatch ready
CLAUDE_BIN="$stub" COS_ALLOW_NO_BACKUP=1 sh "$here/dispatcher.sh" "$W"
check "dispatcher ran both ready projects" '[ "$(grep -c " run " "$W/.dispatch.log")" = 2 ]'
check "handoff result is kept" 'grep -q "done alpha rc=0, dispatch now off" "$W/.dispatch.log"'
check "run without handoff is parked" '[ "$(fm_get "$W/projects/beta/STATE.md" dispatch)" = off ] && grep -q "done beta rc=0, no handoff" "$W/.dispatch.log"'
check "guard rails are passed to the CLI" 'grep -q "Edit(/$W/\*\*/CLAUDE.md)" "$W/.dispatch-alpha.out" && grep -q "Bash AskUserQuestion" "$W/.dispatch-alpha.out" && grep -q -- "--max-budget-usd 2" "$W/.dispatch-alpha.out"'
check "the run can reach the whole workspace" 'grep -q -- "--add-dir $W" "$W/.dispatch-alpha.out"'
check "lock is released" '[ ! -d "$W/.dispatch.lock" ]'
fm_set "$W/projects/alpha/STATE.md" dispatch ready
CLAUDE_BIN="$stub" COS_ALLOW_NO_BACKUP=1 COS_MAX_RUNS_PER_DAY=2 sh "$here/dispatcher.sh" "$W"
check "daily ceiling stops new runs" 'grep -q "ceiling: 2 runs today" "$W/.dispatch.log" && [ "$(fm_get "$W/projects/alpha/STATE.md" dispatch)" = ready ]'
check "missing CLI is refused" '! CLAUDE_BIN=/nonexistent/claude COS_ALLOW_NO_BACKUP=1 sh "$here/dispatcher.sh" "$W" && grep -q "not found; set CLAUDE_BIN" "$W/.dispatch.log"'
mkdir "$W/.dispatch.lock"; echo 999999 > "$W/.dispatch.lock/pid"
CLAUDE_BIN="$stub" COS_ALLOW_NO_BACKUP=1 COS_MAX_RUNS_PER_DAY=9 sh "$here/dispatcher.sh" "$W"
check "stale lock is taken over" 'grep -q "stale lock from pid 999999 removed" "$W/.dispatch.log" && [ ! -d "$W/.dispatch.lock" ]'
mkdir "$W/.dispatch.lock"; echo $$ > "$W/.dispatch.lock/pid"
CLAUDE_BIN="$stub" COS_ALLOW_NO_BACKUP=1 sh "$here/dispatcher.sh" "$W"
check "live lock is respected" 'grep -q "skipped: dispatcher $$ is running" "$W/.dispatch.log"'
rm -rf "$W/.dispatch.lock"
printf '#!/bin/sh\nexec sleep 30\n' > "$W/slow.sh"; chmod +x "$W/slow.sh"
fm_set "$W/projects/beta/STATE.md" dispatch ready
CLAUDE_BIN="$W/slow.sh" COS_ALLOW_NO_BACKUP=1 COS_MAX_RUNS_PER_DAY=9 COS_RUN_TIMEOUT=1 sh "$here/dispatcher.sh" "$W"
check "a hung run is killed and parked" 'grep -q "timeout: beta killed after 1s" "$W/.dispatch.log" && [ "$(fm_get "$W/projects/beta/STATE.md" dispatch)" = off ]'
fm_set "$W/projects/alpha/STATE.md" dispatch running
CLAUDE_BIN="$stub" COS_ALLOW_NO_BACKUP=1 sh "$here/dispatcher.sh" "$W"
check "an interrupted run is parked by the next dispatcher" 'grep -q "parked alpha: previous run was interrupted" "$W/.dispatch.log" && [ "$(fm_get "$W/projects/alpha/STATE.md" dispatch)" = off ]'
fm_set "$W/projects/alpha/STATE.md" next "$(printf 'evil\033[2Jline')"
check "briefing strips control characters" '! b "$W/projects/alpha" | grep -q "$(printf "\033")" && b "$W/projects/alpha" | grep -q "evil\[2Jline"'
check "permission mode is default with a closed tool list" 'grep -q -- "--permission-mode default" "$W/.dispatch-alpha.out" && grep -q "Edit(/$W/.git/\*\*)" "$W/.dispatch-alpha.out" && grep -q "Edit(/$W/.dispatch\*)" "$W/.dispatch-alpha.out" && ! grep -q "Bash(git" "$W/.dispatch-alpha.out"'
check "the dispatcher commits the run itself" 'git -C "$W" log --format=%s | grep -q "^dispatch: alpha$"'
cat > "$W/evil.sh" <<EOF
#!/bin/sh
printf '#!/bin/sh\n' > "$W/.git/hooks/pre-commit"
EOF
chmod +x "$W/evil.sh"
fm_set "$W/projects/beta/STATE.md" dispatch ready
fm_set "$W/projects/alpha/STATE.md" dispatch ready
CLAUDE_BIN="$W/evil.sh" COS_ALLOW_NO_BACKUP=1 COS_MAX_RUNS_PER_DAY=99 sh "$here/dispatcher.sh" "$W"
check "a git hook written during a run stops the dispatcher" 'grep -q "ALERT: .git/config or .git/hooks changed during the run of alpha" "$W/.dispatch.log" && [ "$(fm_get "$W/projects/beta/STATE.md" dispatch)" = ready ]'

[ $fail = 0 ] && echo "selftest: all passed" || { echo "selftest: FAILED"; exit 1; }
