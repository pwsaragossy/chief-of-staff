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
check "permission mode is default with a closed tool list" 'grep -q -- "--permission-mode default" "$W/.dispatch-alpha.out" && grep -q "Edit(/$W/.git/\*\*)" "$W/.dispatch-alpha.out" && grep -q "Edit(/$W/.dispatch\*)" "$W/.dispatch-alpha.out" && grep -q "Edit(/$W/\*\*/.gitattributes)" "$W/.dispatch-alpha.out" && ! grep -q "Bash(git" "$W/.dispatch-alpha.out"'
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

# protocol gates: inputs shaped like the JSON Claude Code sends to hooks
export CLAUDE_PLUGIN_DATA="$W/plugin-data"
P="$W/projects/alpha"
h() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$2" sh "$here/protocol.sh"; }
ev() { printf '{"session_id":"s1","hook_event_name":"%s"%s}' "$1" "${2:-}"; }
rc() { h "$1" "$2" >/dev/null 2>&1; echo $?; }
check "prompt hook restates the protocol" 'h "$(ev UserPromptSubmit ",\"prompt\":\"hi\"")" "$P" | grep -q "at least one specialist and the independent reviewer"'
check "prompt hook is silent outside a workspace" '[ -z "$(h "$(ev UserPromptSubmit)" /tmp)" ]'
check "a short turn ends freely" '[ "$(rc "$(ev Stop ",\"stop_hook_active\":false")" "$P")" = 0 ]'
check "web search is blocked before the library" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"WebSearch\"")" "$P")" = 2 ]'
h "$(ev PostToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sh /x/library.sh search tax\"}")" "$P"
check "web search is allowed after the library" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"WebSearch\"")" "$P")" = 0 ]'
h "$(ev PostToolUse ",\"tool_name\":\"WebSearch\"")" "$P"
check "research without specialists or saving cannot end" 'h "$(ev Stop ",\"stop_hook_active\":false")" "$P" 2>&1 | grep -q "specialists skill" && h "$(ev Stop ",\"stop_hook_active\":false")" "$P" 2>&1 | grep -q "saved nothing to the library"'
check "the gate lets go on the second stop" '[ "$(rc "$(ev Stop ",\"stop_hook_active\":true")" "$P")" = 0 ]'
h "$(ev PostToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: researcher ...\"}")" "$P"
check "a specialist without the reviewer cannot end" 'h "$(ev Stop ",\"stop_hook_active\":false")" "$P" 2>&1 | grep -q "1 specialist(s) and 0 reviewer(s)"'
h "$(ev PostToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: reviewer ...\"}")" "$P"
h "$(ev PostToolUse ",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$W/knowledge/notes/n9.md\"}")" "$P"
check "specialists plus a saved note end freely" '[ "$(rc "$(ev Stop ",\"stop_hook_active\":false")" "$P")" = 0 ]'
h "$(ev UserPromptSubmit)" "$P" >/dev/null
h "$(ev PostToolUse ",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/pitch.md\"}")" "$P"
check "a deliverable without specialists cannot end" '[ "$(rc "$(ev Stop ",\"stop_hook_active\":false")" "$P")" = 2 ]'
h "$(ev UserPromptSubmit)" "$P" >/dev/null
h "$(ev PostToolUse ",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/STATE.md\"}")" "$P"
check "updating STATE.md is not a deliverable" '[ "$(rc "$(ev Stop ",\"stop_hook_active\":false")" "$P")" = 0 ]'
check "every turn is logged for the adherence metric" 'grep -q "substantive=1 agents=2 specialists=1 reviewers=1 library=1 web=1 saved=1" "$W/.protocol.log"'
mkdir -p "$W/specialists"; : > "$W/specialists/researcher.md"
check "a subagent without a role card is blocked" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"do research\"}")" "$P")" = 2 ]'
check "a role card that does not exist is blocked" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: astrologer\"}")" "$P")" = 2 ]'
check "an existing role card is allowed" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: researcher\"}")" "$P")" = 0 ]'
check "a utility helper is allowed" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: utility\"}")" "$P")" = 0 ]'
check "a specialist cannot finish without its checklist" '[ "$(rc "$(ev SubagentStop ",\"stop_hook_active\":false,\"last_assistant_message\":\"Role: finance answer\"")" "$P")" = 2 ]'
check "a specialist with its checklist finishes" '[ "$(rc "$(ev SubagentStop ",\"stop_hook_active\":false,\"last_assistant_message\":\"Role: finance ## Never-skip checklist ok\"")" "$P")" = 0 ]'
check "a helper without a role finishes" '[ "$(rc "$(ev SubagentStop ",\"stop_hook_active\":false,\"last_assistant_message\":\"found 3 files\"")" "$P")" = 0 ]'

# library: search follows links; replace deletes the old note and repoints references
N="$W/knowledge/notes"
printf -- '---\nid: tax-old\nconfidence: low\nlinks: [vat]\n---\nTax rate is 10%%.\n' > "$N/tax-old.md"
printf -- '---\nid: vat\nconfidence: high\nlinks: [tax-old]\n---\nVAT basics.\n' > "$N/vat.md"
printf -- '---\nid: tax-new\nconfidence: high\nlinks: [tax-old, vat]\nsupersedes: []\n---\nTax rate is 12%%.\n' > "$N/tax-new.md"
echo "see knowledge/notes/tax-old.md" >> "$P/STATE.md"
L() { CLAUDE_PROJECT_DIR="$P" sh "$here/library.sh" "$@"; }
check "library search finds a note and its links" 'L search "tax rate" | grep -q "tax-old.md" && L search "tax rate" | grep -q "linked: .*vat.md"'
check "library search says when there is nothing" 'L search zebra | grep -q "nothing on"'
L replace tax-old tax-new >/dev/null
check "replace deletes the old note" '[ ! -f "$N/tax-old.md" ]'
check "replace repoints links and STATE references" 'grep -q "links: \[tax-new\]" "$N/vat.md" && grep -q "tax-new.md" "$P/STATE.md"'
check "replace records supersedes and drops the self-link" '[ "$(fm_get "$N/tax-new.md" supersedes)" = "[tax-old]" ] && [ "$(fm_get "$N/tax-new.md" links)" = "[vat]" ]'

# tracks: minimum deliverables per stage, the Stop gate, and health colors
G="$W/projects/gamma"; mkdir -p "$G/out" "$W/t2"
sed -e "s/{{PROJECT_NAME}}/gamma/" "$here/../templates/project/STATE.md" > "$G/STATE.md"
cat > "$G/TRACK.md" <<'TRK'
---
track: brand
stage: 2
stale_hours: 48
---
## Stage 1: Strategy
- [ ] positioning | Positioning | card: marketing | needs: - | evidence:
- [-] tm | Trademark | card: legal | needs: - | why: internal codename
## Stage 2: Identity
- [ ] name | Name | card: marketing | needs: positioning | evidence:
- [ ] logo | Logo | card: designer | needs: name | evidence:
TRK
T() { sh "$here/track.sh" "$@"; }
H() { sh "$here/health.sh" "$W" | awk -F "$(printf '\037')" -v p="$1" '$1 == p { print $2 ": " $3 }'; }
check "a passed stage with an open item fails the track" '! T check "$G" >/dev/null && T check "$G" | grep -q "stage 1 is behind the current stage 2, but positioning is open"'
check "health is red on a track gap" 'H gamma | grep -q "^red: track: "'
sed -i.bak 's/^- \[ \] positioning | Positioning | card: marketing | needs: - | evidence:$/- [x] positioning | Positioning | card: marketing | needs: - | evidence: out\/pos.md/' "$G/TRACK.md"
check "done without its proof file fails" 'T check "$G" | grep -q "positioning is marked done, but its evidence out/pos.md does not exist"'
echo proof > "$G/out/pos.md"; echo proof > "$G/out/pos2.md"
check "a stage without a reviewer item fails" 'T check "$G" | grep -q "stage 1 has no item with card: reviewer"'
sed -i.bak 's/^## Stage 2: Identity$/- [x] review-1 | Review | card: reviewer | needs: positioning, tm | evidence: out\/pos2.md\
## Stage 2: Identity\
- [ ] review-2 | Review | card: reviewer | needs: name, logo | evidence:/' "$G/TRACK.md"
check "a closed stage passes" 'T check "$G"'
check "a reviewer item cannot be marked not applicable" 'sed "s/^- \[x\] review-1 | Review | card: reviewer | needs: positioning, tm | evidence: out\/pos2.md$/- [-] review-1 | Review | card: reviewer | needs: positioning, tm | why: owner said skip/" "$G/TRACK.md" > "$W/t2/TRACK.md" && T check "$W/t2" | grep -q "review-1 is a reviewer item and cannot be marked not applicable"'
check "n/a needs a reason" 'sed "s/ | why: internal codename//" "$G/TRACK.md" > "$G/T2" && mkdir -p "$W/t2" && cp "$G/T2" "$W/t2/TRACK.md" && T check "$W/t2" | grep -q "tm is marked not applicable without why"'
check "done before its prerequisite fails" 'sed "s/^- \[ \] logo | Logo | card: designer | needs: name | evidence:$/- [x] logo | Logo | card: designer | needs: name | evidence: out\/pos.md/" "$G/TRACK.md" > "$W/t2/TRACK.md" && T check "$W/t2" | grep -q "logo is marked done, but it needs name, which is open"'
check "the brief lists what is open now and what waits" 'T brief "$G" | grep -q "stage 2 of 2 (Identity). Open now: name (marketing). Waiting on prerequisites: review-2 needs name, logo; logo needs name."'
# track gates cannot be passed by shortcuts
bad() { [ -e "$W/t2/out" ] || ln -s "$G/out" "$W/t2/out"; sed "$1" "$G/TRACK.md" > "$W/t2/TRACK.md" && T check "$W/t2" | grep -q "$2"; }
check "evidence cannot be an absolute path" 'bad "s#evidence: out/pos.md#evidence: /etc/hosts#" "evidence /etc/hosts must be a proof file"'
check "evidence cannot climb out of the project" 'bad "s#evidence: out/pos.md#evidence: ../../x#" "must be a proof file inside the project"'
check "evidence cannot be TRACK.md" 'bad "s#evidence: out/pos.md#evidence: TRACK.md#" "not a control file"'
check "evidence cannot be a folder" 'bad "s#evidence: out/pos.md#evidence: out#" "must be a regular file"'
: > "$G/out/empty.md"
check "evidence cannot be an empty file" 'bad "s#evidence: out/pos.md#evidence: out/empty.md#" "out/empty.md is empty"'
check "two items cannot share one proof file" 'bad "s#evidence: out/pos2.md#evidence: out/pos.md#" "share the proof file out/pos.md"'
check "a stage that is not a number fails" 'bad "s/^stage: 2/stage: soon/" "stage: in the TRACK.md front matter must be a whole number"'
check "a stage missing from the front matter fails" 'bad "/^stage:/d" "front matter must be a whole number"'
check "a duplicate id fails" 'bad "s/^- \[ \] logo | /- [ ] name | /" "item id name appears twice"'
check "a mangled item line fails" 'bad "s/^- \[ \] name /-  [ ] name /" "not a valid item"'
check "an item hidden in a comment fails" 'bad "s/^- \[ \] name \(.*\)$/<!-- - [ ] name \1 -->/" "HTML comments hide items"'
check "a mangled stage header fails" 'bad "s/^## Stage 2: Identity/### Stage 2: Identity/" "not a valid stage header"'
check "stages must be numbered in order" 'bad "s/^## Stage 2: Identity/## Stage 3: Identity/" "numbered 1, 2, 3 in order"'
check "an item before the first stage fails" 'bad "1,/^## Stage 1/{/^## Stage 1/i\\
- [ ] orphan | Orphan | card: marketing | needs: - | evidence:
}" "orphan is before the first stage header"'
check "a need that points forward fails" 'bad "s/^- \[x\] positioning | Positioning | card: marketing | needs: -/- [x] positioning | Positioning | card: marketing | needs: logo/" "needs logo from the later stage 2"'
check "a need on an unknown id fails" 'bad "s/needs: name, logo/needs: name, ghost/" "review-2 needs ghost, which is not an item of the track"'
check "a loop in needs fails" 'bad "s/^- \[ \] name | Name | card: marketing | needs: positioning/- [ ] name | Name | card: marketing | needs: logo/" "wait on each other in a loop"'
check "an item without a card fails" 'bad "s/^- \[ \] logo | Logo | card: designer/- [ ] logo | Logo | card:/" "logo has no card"'
rm -f "$W/t2/TRACK.md"; echo "Read TRACK.md" > "$W/t2/CLAUDE.md"
check "a deleted TRACK.md fails when CLAUDE.md requires it" 'T check "$W/t2" | grep -q "TRACK.md is missing"'
check "no TRACK.md and no requirement stays silent" 'rm "$W/t2/CLAUDE.md"; [ -z "$(T check "$W/t2")" ]'
check "STATE done with open items fails" 'fm_set "$G/STATE.md" status done && T check "$G" | grep -q "STATE.md status is done, but name is open"; r=$?; fm_set "$G/STATE.md" status in-progress; [ $r = 0 ]'
check "health ignores an ALERT about another project" '! H beta | grep -q "ALERT"'
echo "2026-01-01 00:00:00 ALERT: .git/config or .git/hooks changed during the run of beta; dispatcher stopped" >> "$W/.dispatch.log"
check "health is red on a dispatcher ALERT for the project" 'H beta | grep -q "^red: dispatcher ALERT"'
check "health is green when the track is clean" 'H gamma | grep -q "^green: on track"'
printf -- '---\nstatus: waiting-owner\nproject: gamma\n---\n' > "$W/board/Gamma.md"
check "health is yellow on a card waiting on the owner" 'H gamma | grep -q "^yellow: waiting on the owner: Gamma"'
rm "$W/board/Gamma.md"
touch -t 202001010000 "$G/STATE.md"
check "health is yellow without a handoff for longer than stale_hours" 'H gamma | grep -q "^yellow: no handoff for more than 48 h"'
touch "$G/STATE.md"
check "the project briefing shows the track" 'CLAUDE_PROJECT_DIR="$G" sh "$here/briefing.sh" </dev/null | grep -q "Track brand, stage 2 of 2"'
fm_set "$G/TRACK.md" stage 3
check "the Stop hook blocks a track gap" 'h "$(ev Stop ",\"stop_hook_active\":false")" "$G" 2>&1 | grep -q "Track gate (projects/gamma/TRACK.md) not met"'
check "after the push the gap is logged as a violation" '[ "$(rc "$(ev Stop ",\"stop_hook_active\":true")" "$G")" = 0 ] && grep -q "project=gamma .*violation=1" "$W/.protocol.log"'
fm_set "$G/TRACK.md" stage 2
check "health is red after a violation" 'H gamma | grep -q "^red: a turn ended without"'

# panel: token, Host check, api, import (only where python3 and curl exist)
if command -v python3 >/dev/null && command -v curl >/dev/null; then
  python3 "$here/panel.py" "$W" > "$W/panel.out" 2>&1 &
  pp=$!
  i=0; while [ $i -lt 50 ] && ! grep -q "^Panel:" "$W/panel.out"; do i=$((i + 1)); sleep 0.1; done
  U=$(sed -n 's/^Panel: //p' "$W/panel.out"); B=${U%%/?t=*}; TK=${U##*t=}
  check "panel refuses a request without the token" '[ "$(curl -s -o /dev/null -w %{http_code} "$B/api")" = 403 ]'
  check "panel refuses another Host" '[ "$(curl -s -o /dev/null -w %{http_code} -H "Host: evil.example" "$B/api?t=$TK")" = 403 ]'
  check "panel api reports projects and colors" 'curl -s "$B/api?t=$TK" | grep -q "\"slug\": \"gamma\", \"color\": \"red\""'
  check "panel imports a file into the inbox" 'printf hello | curl -s -X POST --data-binary @- -H "X-Name: ../../evil name.txt" -H "X-Kind: file" "$B/import?t=$TK" | grep -q saved && ls "$W/knowledge/inbox" | grep -q "evil_name.txt$" && [ ! -e "$W/evil name.txt" ]'
  check "panel saves a pasted link as a note" 'printf "https://example.com/a" | curl -s -X POST --data-binary @- -H "X-Name: link.md" -H "X-Kind: text" "$B/import?t=$TK" >/dev/null && grep -q "^source: https://example.com/a" "$W"/knowledge/inbox/*link.md'
  check "panel answers a non-ASCII token with 403" '[ "$(curl -s -o /dev/null -w %{http_code} "$B/api?t=%C3%A9")" = 403 ]'
  check "panel rejects an empty pasted text" '[ "$(printf "  " | curl -s -o /dev/null -w %{http_code} -X POST --data-binary @- -H "X-Kind: text" "$B/import?t=$TK")" = 400 ]'
  check "panel never sends the token on as a referrer" 'curl -s -D - -o /dev/null "$B/?t=$TK" | grep -qi "^referrer-policy: no-referrer"'
  kill $pp 2>/dev/null; wait $pp 2>/dev/null
else
  echo "skip panel checks: python3 or curl missing"
fi

mkdir -p "$W/t3"; printf ok > "$W/t3/v.md"
printf -- '---\nstage: 1\n---\n## Stage 1: A\n- [x] r | R | card: reviewer | needs: - | evidence: v.md (verdict: approve)\n' > "$W/t3/TRACK.md"
check "a note after the evidence path gets a clear message" 'T check "$W/t3" | grep -q "evidence must be the file path alone (found \"v.md (verdict: approve)\"); write evidence: v.md"'

mkdir -p "$W/projects/delta"; cp "$W/projects/beta/STATE.md" "$W/projects/delta/STATE.md"
printf '2026-01-01 00:00:00 t=%s turn=z1 project=delta substantive=1 agents=1 specialists=1 reviewers=0 pushed=true violation=1\n' "$(date +%s)" >> "$W/.protocol.log"
check "an unresolved violation makes the project red" 'H delta | grep -q "^red: a turn ended"'
printf '2026-01-01 00:00:01 t=%s turn=z1 project=delta substantive=0 agents=1 specialists=0 reviewers=1 pushed=false violation=0\n' "$(date +%s)" >> "$W/.protocol.log"
check "a violation fixed later in the same session clears" '! H delta | grep -q "^red"'

[ $fail = 0 ] && echo "selftest: all passed" || { echo "selftest: FAILED"; exit 1; }
