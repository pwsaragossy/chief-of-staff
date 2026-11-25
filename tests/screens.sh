#!/bin/sh
# Screens: the design gate (no screen code before its design) and the review gate (no screen reaches the owner before
# an independent side-by-side review against real reference apps). Hook inputs shaped like the JSON the hooks receive.
# Run alone (sh tests/screens.sh) or from scripts/selftest.sh. Exit 1 when a check fails.
set -u
exec </dev/null
S=$(cd "$(dirname "$0")/../scripts" && pwd)
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
export CLAUDE_PLUGIN_DATA="$T/data"
P=$T/app; Q=$T/plain; mkdir -p "$P" "$Q"
{ sh "$S/project.sh" init "$P" && sh "$S/project.sh" init "$Q"; } >/dev/null || { echo "FAIL fixture: project.sh init"; exit 1; }
# P tests the TRACK.md design items alone: its owner turned the design system off (tests/design-system.sh covers it)
chmod u+w "$P/.chief-of-staff" && printf 'design-system: off\n' >> "$P/.chief-of-staff"
mkdir -p "$P/out" "$P/content" "$P/design/reviews" "$P/shots"
track() { cat > "$P/TRACK.md" <<EOF
---
track: software
stage: 1
---
## Stage 1: Design
- [x] flows | Flows | card: designer | needs: - | evidence: out/flows.md
$1
- [ ] review-1 | Review | card: reviewer | needs: flows, ui-spec | evidence:
EOF
}
echo flows > "$P/out/flows.md"
track '- [ ] ui-spec | Screens | card: designer | needs: flows | evidence:'

# hook input: event, then the rest of the JSON object
ev() { printf '{"session_id":"%s","hook_event_name":"%s"%s}' "${SID:-u1}" "$1" "${2:-}"; }
h() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$2" sh "$S/protocol.sh"; }
rc() { h "$1" "$2" >/dev/null 2>&1; echo $?; }
w() { ev PreToolUse ",\"tool_name\":\"${3:-Write}\",\"tool_input\":{\"file_path\":\"$1\",\"content\":\"$2\"}"; }
pw() { ev PostToolUse ",\"tool_name\":\"${3:-Write}\",\"tool_input\":{\"file_path\":\"$1\",\"content\":\"$2\"}"; }
art() { ev PreToolUse ",\"tool_name\":\"Artifact\",\"tool_input\":{\"file_path\":\"$1\"${2:-}}"; }
send() { ev PreToolUse ",\"tool_name\":\"SendUserFile\",\"tool_input\":{\"files\":[\"$1\"],\"status\":\"normal\"}"; }
stop() { ev Stop ",\"stop_hook_active\":false,\"last_assistant_message\":\"$1\""; }

# the design gate
check "screen code waits while the design item is open, and the block says how the designer works" 'o=$(h "$(w "$P/content/app.html" "<div>")" "$P" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "the design item ui-spec in TRACK.md is open" && printf "%s" "$o" | grep -q "Role card: designer" && printf "%s" "$o" | grep -q "fresh web research first" && printf "%s" "$o" | grep -q "1-2 real apps" && printf "%s" "$o" | grep -q "References:"'
check "an Edit and a MultiEdit of screen code wait too" '[ "$(rc "$(w "$P/content/app.css" "a{}" Edit)" "$P")" = 2 ] && [ "$(rc "$(w "$P/src/Home.tsx" "x" MultiEdit)" "$P")" = 2 ]'
check "the designer writes mockups under design/" '[ "$(rc "$(w "$P/design/home.html" "<div>")" "$P")" = 0 ]'
check "text, tests and plain scripts are not screen code" '[ "$(rc "$(w "$P/out/notes.md" "x")" "$P")" = 0 ] && [ "$(rc "$(w "$P/src/util.ts" "export const a = 1")" "$P")" = 0 ] && [ "$(rc "$(w "$P/src/Home.test.tsx" "x")" "$P")" = 0 ] && [ "$(rc "$(w "$P/tests/page.html" "x")" "$P")" = 0 ]'
check "native and script files count when they use a UI framework" '[ "$(rc "$(w "$P/App/HomeView.swift" "import SwiftUI")" "$P")" = 2 ] && [ "$(rc "$(w "$P/web/main.js" "document.createElement(1)")" "$P")" = 2 ] && [ "$(rc "$(w "$P/App/Model.swift" "struct A {}")" "$P")" = 0 ]'
check "a path through design/.. is not a mockup, through the hook and to screens.sh itself" '[ "$(rc "$(w "$P/design/../content/app.html" "x")" "$P")" = 2 ] && sh "$S/screens.sh" gate "$P" "$P/design/../content/app.html" >/dev/null; [ $? = 1 ]'
check "a file outside the project folder is not held" '[ "$(rc "$(w "$T/elsewhere/app.html" "x")" "$P")" = 0 ]'
echo 'A spec with no references.' > "$P/out/ui.md"
printf 'References: https://example.com\nLibrary: none\n' > "$P/README.md"
for e in "" "out" "/etc/hosts" "../app/README.md"; do
  track "- [x] ui-spec | Screens | card: designer | needs: flows | evidence: $e"
  check "a design item closed with evidence '$e' (empty, a folder, outside, ..) holds" '[ "$(rc "$(w "$P/content/app.html" "x")" "$P")" = 2 ]'
done; rm -f "$P/README.md"
track '- [x] ui-spec | Screens | card: designer | needs: flows | evidence: out/ui.md'
check "a design item closed with a stub still holds: it must name reference apps with links and the library" 'o=$(h "$(w "$P/content/app.html" "x")" "$P" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "no .References:. section with a link" && printf "%s" "$o" | grep -q "no .Library:. line"'
printf 'References:\n- Linear: https://linear.app (shots/linear.png)\n' > "$P/out/ui.md"
check "references without the library still hold" 'h "$(w "$P/content/app.html" "x")" "$P" 2>&1 | grep -q "no .Library:. line"'
printf '# Screens\n\n## References\n\n- Linear: https://linear.app (shots/linear.png)\n- Things: https://culturedcode.com/things/\n\nLibrary: [[n1]]\n' > "$P/out/ui.md"
check "the design done (references with links and the library) opens screen code" '[ "$(rc "$(w "$P/content/app.html" "x")" "$P")" = 0 ]'
track '- [-] ui-spec | Screens | card: designer | needs: flows | why: a command-line tool, no screens'
check "a design item marked not applicable opens screen code" '[ "$(rc "$(w "$P/content/app.html" "x")" "$P")" = 0 ]'
track '- [ ] ui-spec | Screens | card: designer | needs: flows | screens: content/app.html, src/* | evidence:'
check "screens: limits the gate to the product's screens (a video composition is not one)" '[ "$(rc "$(w "$P/video/scene.html" "x")" "$P")" = 0 ] && [ "$(rc "$(w "$P/content/app.html" "x")" "$P")" = 2 ] && [ "$(rc "$(w "$P/src/a/B.tsx" "x")" "$P")" = 2 ]'
track '- [ ] look | Look | card: designer | needs: flows | screens: * | evidence:'
check "any item with screens: is a design item, whatever its id" 'h "$(w "$P/x.vue" "x")" "$P" 2>&1 | grep -q "the design item look in TRACK.md is open"'
: > "$Q/b.css"; : > "$Q/index.html"; touch -t 202512310000 "$Q/b.css" "$Q/index.html"   # older than the reviews below
check "an existing screen of a project with no design system yet is not held, and the session is told once per turn to propose one" 'h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$Q" >/dev/null; [ "$(rc "$(w "$Q/index.html" "x")" "$Q")" = 0 ] && o=$(h "$(pw "$Q/index.html" "x")" "$Q") && printf "%s" "$o" | grep -q "additionalContext\":\"chief-of-staff: this turn changes screen code (index.html)" && printf "%s" "$o" | grep -q "This project keeps no design system yet" && [ -z "$(h "$(pw "$Q/b.css" "x")" "$Q")" ]'
check "outside a project the gates are silent" '[ "$(rc "$(w "$T/loose/a.html" "x")" "$T/loose")" = 0 ] && [ "$(rc "$(art "$T/loose/a.html")" "$T/loose")" = 0 ]'

# the review gate
SID=u2; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$Q" >/dev/null
mkdir -p "$Q/design/reviews" "$Q/shots"; echo ours > "$Q/shots/ours.png"; echo linear > "$Q/shots/linear.png"
echo '<div>' > "$Q/index.html"; touch -t 202601010000 "$Q/index.html"; h "$(pw "$Q/index.html" "x")" "$Q" >/dev/null
check "a changed screen with no review is not shown: an Artifact, a file sent" 'o=$(h "$(art "$Q/index.html")" "$Q" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "holds no review of the screens" && printf "%s" "$o" | grep -q "Role card: reviewer" && printf "%s" "$o" | grep -q "side by side" && [ "$(rc "$(send "$Q/shots/ours.png")" "$Q")" = 2 ]'
check "a drawing, a pdf or an avif picture of the screen is held too: sent, published, opened or pointed at" '[ "$(rc "$(send "$Q/shots/home.svg")" "$Q")" = 2 ] && [ "$(rc "$(send "$Q/out/home.PDF")" "$Q")" = 2 ] && [ "$(rc "$(art "$Q/home.avif")" "$Q")" = 2 ] && [ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"open shots/home.svg\"}")" "$Q")" = 2 ] && [ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"open out/home.pdf\"}")" "$Q")" = 2 ] && o=$(h "$(stop "Pronto: veja out/home.pdf")" "$Q" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "points at a screen"'
check "what is not a page or a picture, and an Artifact read or list, pass" '[ "$(rc "$(send "$Q/report.md")" "$Q")" = 0 ] && [ "$(rc "$(art "$Q/index.html" ",\"action\":\"list\"")" "$Q")" = 0 ]'
check "an answer that points the owner at the screen cannot end before the review" 'o=$(h "$(stop "Pronto: abre http://localhost:3013")" "$Q" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "This answer points at a screen" && ! h "$(stop "Feito, sem tela.")" "$Q" 2>&1 | grep -q "points at a screen"'
printf 'Verdict: pass\n' > "$Q/design/reviews/2026-01-01 0100 home.md"
check "an incomplete review is rejected as it is written, and does not clear the screen" 'o=$(h "$(pw "$Q/design/reviews/2026-01-01 0100 home.md" "x")" "$Q" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "Screen review rejected" && printf "%s" "$o" | grep -q "References:" && printf "%s" "$o" | grep -q "two different saved screenshots" && [ "$(rc "$(art "$Q/index.html")" "$Q")" = 2 ]'
review() { printf 'Reviewing: home\nVerdict: %s\nReferences:\n- Linear: https://linear.app\nSide by side:\n- [ours](shots/ours.png) | `shots/linear.png`\n' "$1" > "$Q/design/reviews/$2.md"; touch -t "$3" "$Q/design/reviews/$2.md"; }
: > "$Q/shots/empty1.png"; : > "$Q/shots/empty2.png"
printf 'Verdict: pass\nReferences: https://linear.app\nSide by side: shots/empty1.png | shots/empty2.png\n' > "$Q/design/reviews/x1.md"
printf 'Verdict: pass\nReferences: https://linear.app\nSide by side: shots/ours.png | `./shots/ours.png`\n' > "$Q/design/reviews/x2.md"
check "a review of empty pictures, or of one picture named twice, compares nothing and is rejected" '! sh "$S/screens.sh" review "$Q/design/reviews/x1.md" >/dev/null && sh "$S/screens.sh" review "$Q/design/reviews/x2.md" | grep -q "found 1"'
rm -f "$Q/design/reviews/x1.md" "$Q/design/reviews/x2.md"
review fail "2026-01-01 0100 home" 202601010100
check "a failed review keeps the screen from the owner" 'h "$(art "$Q/index.html")" "$Q" 2>&1 | grep -q "failed: fix the screen and review it again"'
review pass "2026-01-01 0200 home" 202601010200
sleep 1; SID=u2b; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$Q" >/dev/null   # a new turn: these reviews stand for the reviewer's
check "a passing review newer than every screen change clears it" '[ "$(rc "$(art "$Q/index.html")" "$Q")" = 0 ] && [ "$(rc "$(send "$Q/shots/ours.png")" "$Q")" = 0 ] && [ "$(rc "$(stop "Abre http://localhost:3013")" "$Q")" = 0 ] && sh "$S/screens.sh" state "$Q"'
touch -t 202601010300 "$Q/index.html"; h "$(pw "$Q/index.html" "x" Edit)" "$Q" >/dev/null
check "an edit after the passing review holds the screen again, and so does opening it in the owner.s browser" 'h "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"open http://localhost:3013\"}")" "$Q" 2>&1 | grep -q "this opens a screen for the owner"'
for c in "open -a Safari http://192.168.0.4:3000" "osascript -e \\\"open location \\\\\\\"http://[::1]:5173\\\\\\\"\\\"" "python3 -m webbrowser http://app.local:3000" "open $Q/index.html"; do
  check "a browser launcher aimed at the screen is held: $c" 'h "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$c\"}")" "$Q" 2>&1 | grep -q "this opens a screen for the owner"'
done
check "a launcher aimed elsewhere, and a server URL in another command, pass" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"open https://example.com\"}")" "$Q")" = 0 ] && [ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"curl -s http://localhost:3013/api\"}")" "$Q")" = 0 ]'
check "an edit after the passing review holds the screen again" 'h "$(art "$Q/index.html")" "$Q" 2>&1 | grep -q "index.html changed after the newest passing review"'

# who writes the review: the independent reviewer subagent
SID=u3; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$Q" >/dev/null; sleep 1
review pass "2026-01-01 0400 home" 202601010400; touch "$Q/design/reviews/2026-01-01 0400 home.md"
check "a review written by the session itself is void and does not clear the screen" 'o=$(h "$(stop "ok")" "$Q" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "without the independent reviewer subagent, so it is void" && grep -q "^Void: " "$Q/design/reviews/2026-01-01 0400 home.md" && h "$(art "$Q/index.html")" "$Q" 2>&1 | grep -q "it is void"'
SID=u4; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$Q" >/dev/null; sleep 1
review pass "2026-01-01 0500 home" 202601010500; touch "$Q/design/reviews/2026-01-01 0500 home.md"
h "$(ev PostToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: reviewer. Library: none found for home\"}")" "$Q" >/dev/null
check "a review the reviewer subagent wrote stands and clears the screen" '[ "$(rc "$(stop "ok")" "$Q")" = 0 ] && ! grep -q "^Void: " "$Q/design/reviews/2026-01-01 0500 home.md" && [ "$(rc "$(art "$Q/index.html")" "$Q")" = 0 ] && [ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"open http://localhost:3013\"}")" "$Q")" = 0 ]'
check "once the screen is cleared, a pdf and a drawing reach the owner" '[ "$(rc "$(send "$Q/out/home.pdf")" "$Q")" = 0 ] && [ "$(rc "$(send "$Q/shots/home.svg")" "$Q")" = 0 ]'
touch -t 202601010600 "$Q/index.html"; h "$(pw "$Q/index.html" "x" Edit)" "$Q" >/dev/null; touch -t 202601010550 "$Q/shots/ours.png" "$Q/shots/linear.png"
review pass "2026-01-01 0700 home" 202601010700
check "a passing review whose screenshots are all older than the last change does not clear it" 'h "$(art "$Q/index.html")" "$Q" 2>&1 | grep -q "has no screenshot taken after the last change of index.html"'
echo ours2 > "$Q/shots/ours.png"; touch -t 202601010650 "$Q/shots/ours.png"
check "a fresh screenshot of the screen in the review clears it" '[ "$(rc "$(art "$Q/index.html")" "$Q")" = 0 ]'
SID=u4b; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$Q" >/dev/null
touch -t 202601010800 "$Q/index.html"; h "$(pw "$Q/index.html" "x" Edit)" "$Q" >/dev/null
check "a screen that is not cleared holds the second stop too, twice at most, then lets go" 'a=$(rc "$(stop "Abre http://localhost:3013")" "$Q"); b=$(rc "$(ev Stop ",\"stop_hook_active\":true,\"last_assistant_message\":\"Abre http://localhost:3013\"")" "$Q"); c=$(rc "$(ev Stop ",\"stop_hook_active\":true,\"last_assistant_message\":\"Abre http://localhost:3013\"")" "$Q"); d=$(rc "$(ev Stop ",\"stop_hook_active\":true,\"last_assistant_message\":\"Abre http://localhost:3013\"")" "$Q"); [ "$a$b$c$d" = 2220 ] || { echo "$a$b$c$d"; false; }'

# screen code written by a shell command meets the same design gate at the end of the turn
track '- [ ] ui-spec | Screens | card: designer | needs: flows | evidence:'
SID=u5; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$P" >/dev/null; sleep 1
echo '<div>' > "$P/content/shell.html"
check "screen code a shell command wrote while the design is open cannot end the turn quietly" 'o=$(h "$(stop "ok")" "$P" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "changed screen or video code by a shell command while its design is not done: content/shell.html"'
check "and it is recorded for the review gate" 'h "$(art "$P/content/shell.html")" "$P" 2>&1 | grep -q "content/shell.html changed and design/reviews/ holds no review"'
SID=u6; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$P" >/dev/null; sleep 1; echo '<p>' > "$P/design/mock.html"
check "a mockup a shell command wrote under design/ is the designer's" '! h "$(stop "ok")" "$P" 2>&1 | grep -q "by a shell command"'
mkdir -p "$P/src/design"; SID=u7; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$P" >/dev/null; sleep 1; echo 'x' > "$P/src/design/B.tsx"
check "a folder named design deeper in the project is not the designer's" 'h "$(stop "ok")" "$P" 2>&1 | grep -q "src/design/B.tsx"'
rm -f "$P/src/design/B.tsx" "$P/content/shell.html"
if command -v git >/dev/null; then
  git -C "$P" init -q && git -C "$P" -c user.name=t -c user.email=t@t add content && git -C "$P" -c user.name=t -c user.email=t@t commit -qm x content 2>/dev/null
  echo '<div>' > "$P/content/kept.html"; git -C "$P" add content/kept.html; git -C "$P" -c user.name=t -c user.email=t@t commit -qm y
  sleep 1; SID=u8; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" "$P" >/dev/null; sleep 1
  echo '<b>' > "$P/content/kept.html"; git -C "$P" checkout -q -- content/kept.html
  check "screen code a shell command changed and put back (git checkout) is no change" '! h "$(stop "ok")" "$P" 2>&1 | grep -q "by a shell command"'
  echo '<b>' > "$P/content/kept.html"; git -C "$P" -c user.name=t -c user.email=t@t commit -qam z
  GIT_COMMITTER_DATE="2001-01-01T00:00:00" git -C "$P" -c user.name=t -c user.email=t@t commit -q --amend --no-edit
  check "screen code a shell command wrote and committed this turn, even with an old commit date, is a change" 'h "$(stop "ok")" "$P" 2>&1 | grep -q "content/kept.html"'
fi

# the designer names its references
h "$(ev PostToolUse ",\"tool_name\":\"WebSearch\",\"tool_input\":{\"query\":\"apps\"}")" "$P" >/dev/null
check "a designer cannot finish without its references" 'o=$(h "$(ev SubagentStop ",\"stop_hook_active\":false,\"last_assistant_message\":\"Role: designer ## Never-skip checklist ok\"")" "$P" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "References:"'
check "a designer with references finishes" '[ "$(rc "$(ev SubagentStop ",\"stop_hook_active\":false,\"last_assistant_message\":\"Role: designer References: Linear https://linear.app ## Never-skip checklist ok\"")" "$P")" = 0 ]'

# the cards and the templates say the same
D=$S/../templates
check "the designer card searches the library and names 1-2 reference apps before screens" 'grep -q "References:" "$D/specialists/designer.md" && grep -q "1-2 real apps" "$D/specialists/designer.md" && grep -q "design/" "$D/specialists/designer.md"'
check "the reviewer card reviews a screen side by side and writes the verdict file" 'grep -q "design/reviews/" "$D/specialists/reviewer.md" && grep -q "Side by side:" "$D/specialists/reviewer.md" && grep -q "Verdict: pass" "$D/specialists/reviewer.md"'
check "the new tracks: the hackathon look holds screen code until it is done, the software ui-spec asks for references, and both still pass track.sh check" '( d=$(mktemp -d); cp "$D/tracks/hackathon.md" "$d/TRACK.md"; o=$(sh "$S/screens.sh" gate "$d" "$d/web/index.html"); r=$?; sh "$S/track.sh" check "$d" >/dev/null 2>&1; c=$?; cp "$D/tracks/software.md" "$d/TRACK.md"; sh "$S/track.sh" check "$d" >/dev/null 2>&1; c2=$?; rm -rf "$d"; [ $r = 1 ] && printf "%s" "$o" | grep -q "design item look" && [ $c -le 1 ] && [ $c2 -le 1 ] && grep -q "^- \[ \] ui-spec .*References: section with links" "$D/tracks/software.md" )'
[ $fail = 0 ] && echo "screens: all passed" || { echo "screens: FAILED"; exit 1; }
