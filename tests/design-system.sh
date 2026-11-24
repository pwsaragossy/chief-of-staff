#!/bin/sh
# The design system: the owner picks each piece (typography, colors, components, motion, tone, rhythm, script) from 2-3
# references that fresh web research found and the independent reviewer opened; screens and videos wait for the pick.
# Hook inputs shaped like the JSON the hooks receive. Run alone (sh tests/design-system.sh) or from scripts/selftest.sh.
set -u
exec </dev/null
S=$(cd "$(dirname "$0")/../scripts" && pwd)
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
export CLAUDE_PLUGIN_DATA="$T/data"
D=$T/studio; mkdir -p "$D"
sh "$S/project.sh" init "$D" >/dev/null || { echo "FAIL fixture: project.sh init"; exit 1; }
mkdir -p "$D/design/options" "$D/design/reviews/options" "$D/web" "$D/video" "$D/shots"
cp "$S/../templates/design/SYSTEM.md" "$D/design/SYSTEM.md"
today=$(date +%F)
ago() { date -v-"$1"m +%F 2>/dev/null || date -d "$1 months ago" +%F; }
yesterday=$(date -v-1d +%F 2>/dev/null || date -d yesterday +%F)

ev() { printf '{"session_id":"%s","hook_event_name":"%s"%s}' "${SID:-d1}" "$1" "${2:-}"; }
h() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="${2:-$D}" sh "$S/protocol.sh"; }
rc() { h "$1" "${2:-$D}" >/dev/null 2>&1; echo $?; }
turn() { SID=$1; h "$(ev UserPromptSubmit ",\"prompt\":\"x\"")" >/dev/null; sleep 1; }
web() { h "$(ev PostToolUse ",\"tool_name\":\"WebSearch\",\"tool_input\":{\"query\":\"best ${1:-type} 2026\"}")" >/dev/null; }
reviewer() { h "$(ev PostToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: reviewer. Library: none found for refs\"}")" >/dev/null; }
w() { ev PreToolUse ",\"tool_name\":\"${3:-Write}\",\"tool_input\":{\"file_path\":\"$1\",\"content\":\"$2\"}"; }
pw() { ev PostToolUse ",\"tool_name\":\"${3:-Write}\",\"tool_input\":{\"file_path\":\"$1\",\"content\":\"x\"}"; }
stop() { ev Stop ",\"stop_hook_active\":false,\"last_assistant_message\":\"$1\""; }
send() { ev PreToolUse ",\"tool_name\":\"SendUserFile\",\"tool_input\":{\"files\":[\"$1\"],\"status\":\"normal\"}"; }
# prop FILE PIECE RESEARCHED DATE-A DATE-B [DATE-C]: a proposal with 2 or 3 options (links example.com/<piece>-a ...)
prop() { { printf 'Piece: %s\nResearched: %s\nSearches:\n- best %s 2026\nLibrary: none found for %s\n' "$2" "$3" "$2" "$2"
  for x in a:$4 ${5:+b:$5} ${6:+c:$6}; do printf '\n## Option %s: %s one\nLink: https://example.com/%s-%s\nDate: %s\nWhat we take: the %s part\n' "${x%%:*}" "$2" "$2" "${x%%:*}" "${x#*:}" "$2"; done; } > "$1"; }
# orev FILE OPTIONS VERDICT LINE...: a reference review
orev() { f=$1 o=$2 v=$3; shift 3; { printf 'Options: %s\nVerdict: %s\nLinks checked:\n' "$o" "$v"; for l in "$@"; do printf -- '- %s\n' "$l"; done; } > "$f"; }
ok() { CLAUDE_PROJECT_DIR=${2:-$D} sh "$S/track.sh" ok "$D" "design:$1" "${3:-I pick it}"; }

# what is a screen and what is a video
check "a composition (HyperFrames, Remotion) and a rendered video are video; a page is a screen; text is neither" '[ "$(printf "<div data-composition-id=\"main\">" | sh "$S/screens.sh" kind "$D/video/index.html")" = video ] && [ "$(printf "import {Composition} from \"remotion\"" | sh "$S/screens.sh" kind "$D/video/Root.tsx")" = video ] && [ "$(sh "$S/screens.sh" kind "$D/out/final.MP4" </dev/null)" = video ] && [ "$(printf "<div>" | sh "$S/screens.sh" kind "$D/web/app.html")" = screen ] && ! sh "$S/screens.sh" kind "$D/notes.md" </dev/null >/dev/null'

# nothing is built before the owner picks
turn d1
check "screen code waits while the pieces it needs are open, and the block says how a piece closes" 'o=$(h "$(w "$D/web/app.html" "<div>")" 2>&1); [ $? = 2 ] && for t in "typography is open" "components is open" "fresh web search" "2-3 sections" "Date:" "What we take:" "opens every link" "the owner picks" "Nobody else picks" "design:<piece>"; do printf "%s" "$o" | grep -qF "$t" || { echo "missing: $t"; false; }; done'
check "video code waits for tone, rhythm and script too, a render as well" 'o=$(h "$(w "$D/video/index.html" "<div data-composition-id=\\\"main\\\">")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "not done for video" && printf "%s" "$o" | grep -q "tone is open" && printf "%s" "$o" | grep -q "script is open" && [ "$(rc "$(w "$D/video/out.mp4" "x")")" = 2 ]'
check "mockups under design/ are free" '[ "$(rc "$(w "$D/design/mock.html" "<div>")")" = 0 ]'

# the proposal: fresh web research, 2-3 references, each with link, date and what we take
prop "$D/design/options/typography.md" typography "$today" "$(ago 1)" "$(ago 2)"
check "a proposal written in a turn that ran no web search is rejected" 'o=$(h "$(pw "$D/design/options/typography.md")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "this turn ran no web search"'
web weather
check "a web search the proposal does not list (one about something else) does not count as its research" 'o=$(h "$(pw "$D/design/options/typography.md")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "at least one search this turn ran for this piece"'
web typography
cp "$D/design/options/typography.md" "$T/prop.md"
awk '/^- best typography 2026$/ { print "- -v"; print "- anything else"; next } { print }' "$T/prop.md" > "$D/design/options/typography.md"
check "a search listed as an option flag (-v) is read as text, not as an option" '[ "$(rc "$(pw "$D/design/options/typography.md")")" = 2 ]'
cp "$T/prop.md" "$D/design/options/typography.md"
check "after the search it lists, a complete proposal is taken" '[ "$(rc "$(pw "$D/design/options/typography.md")")" = 0 ]'
prop "$D/design/options/x.md" typography "$today" "$(ago 1)"
check "one option is not a choice" 'sh "$S/screens.sh" options "$D/design/options/x.md" | grep -q "2 or 3 sections"'
prop "$D/design/options/x.md" typography "$today" "$(ago 1)" "$(ago 2)" "$(ago 3)"
printf '\n## Option D: four\nLink: https://example.com/d\nDate: %s\nWhat we take: x\n' "$(ago 1)" >> "$D/design/options/x.md"
check "four options are too many" 'sh "$S/screens.sh" options "$D/design/options/x.md" | grep -q "found 4"'
prop "$D/design/options/x.md" x "$today" "$(date +%Y-%m)-00" "$(ago 1)"
check "an impossible date (day 00) is not a date" 'sh "$S/screens.sh" options "$D/design/options/x.md" | grep -q "option 1"'
prop "$D/design/options/x.md" typography "$today" "$(ago 1)" "$(ago 8)"
check "a reference older than 6 months before the research is rejected" 'o=$(h "$(pw "$D/design/options/x.md")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "option 2: dated .*more than 6 months before the research"'
prop "$D/design/options/x.md" typography "$yesterday" "$(ago 1)" "$(ago 2)"
check "a proposal must be researched today when it is written" 'h "$(pw "$D/design/options/x.md")" 2>&1 | grep -q "Researched: today"'
printf 'Piece: typography\nResearched: %s\nSearches:\n- a\n\n## Option A: one\nLink: https://example.com/1\n\n## Option B: two\nDate: %s\nWhat we take: y\n' "$today" "$(ago 1)" > "$D/design/options/x.md"
check "each option needs its link, its date and what we take" 'o=$(sh "$S/screens.sh" options "$D/design/options/x.md"); printf "%s" "$o" | grep -q "option 1: a Date:" && printf "%s" "$o" | grep -q "option 1: a What we take:" && printf "%s" "$o" | grep -q "option 2: one Link:"'
printf 'Piece: typography\nResearched: %s\n\n## Option A: one\nLink: https://example.com/1\nDate: %s\nWhat we take: y\n\n## Option B: two\nLink: https://example.com/1\nDate: %s\nWhat we take: y\n' "$today" "$(ago 1)" "$(ago 1)" > "$D/design/options/x.md"
check "the searches run are listed, and two options never share a link" 'o=$(sh "$S/screens.sh" options "$D/design/options/x.md"); printf "%s" "$o" | grep -q "a Searches: section" && printf "%s" "$o" | grep -q "option 2: its link repeats"'
rm -f "$D/design/options/x.md"
cp "$D/.chief-of-staff" "$T/marker.bak"; chmod u+w "$D/.chief-of-staff"; printf 'refs-max-months: 12\n' >> "$D/.chief-of-staff"
prop "$D/design/options/y.md" typography "$today" "$(ago 1)" "$(ago 9)"
check "the owner can widen the window (refs-max-months in the project settings)" 'sh "$S/screens.sh" options "$D/design/options/y.md"'
cp "$T/marker.bak" "$D/.chief-of-staff"; rm -f "$D/design/options/y.md"
check "a proposal and the design system are not deliverables of the turn (their own gates check them)" '[ "$(rc "$(stop "ok")")" = 0 ]'
turn d2; prop "$D/design/options/colors.md" colors "$today" "$(ago 1)" "$(ago 2)"
check "a proposal a shell command wrote in a turn with no web search is void at the end of the turn" 'o=$(h "$(stop "ok")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "without a web search, so it is void" && grep -q "^Void: " "$D/design/options/colors.md" && sh "$S/screens.sh" options "$D/design/options/colors.md" | grep -q "it is void"'
rm -f "$D/design/options/colors.md"

# the reference review: the reviewer opens every link before the owner sees any
turn d3
printf '<a href="https://example.com/typography-a">A</a>' > "$D/design/opts.html"
check "a page carrying references the reviewer has not cleared is not published or sent" 'o=$(h "$(ev PreToolUse ",\"tool_name\":\"Artifact\",\"tool_input\":{\"file_path\":\"$D/design/opts.html\"}")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "has not cleared (https://example.com/typography-a)" && [ "$(rc "$(send "$D/design/options/typography.md")")" = 2 ]'
check "a path written with JSON escapes is not let through while references wait for review" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Artifact\",\"tool_input\":{\"file_path\":\"$D/design/opts\\u002ehtml\"}")")" = 2 ]'
check "references shown to the owner before their review cannot end the turn" 'o=$(h "$(stop "Option A: https://example.com/typography-a")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "references the independent reviewer has not cleared (https://example.com/typography-a"'
R="$D/design/reviews/options/$today 1000 typography.md"
orev "$R" design/options/typography.md pass "https://example.com/typography-a | status 200 | dated $(ago 1) | keep: top studio"
check "a review that leaves a link unopened is rejected as it is written" 'o=$(h "$(pw "$R")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "Reference review rejected" && printf "%s" "$o" | grep -q "typography-b is not in Links checked"'
orev "$R" design/options/typography.md pass "https://example.com/typography-a | status 200 | keep" "https://example.com/typography-b | status 200 | reject: weak, a template"
check "a pass that rejects a link contradicts itself" 'sh "$S/screens.sh" optreview "$R" | grep -q "Verdict: pass, but https://example.com/typography-b is rejected"'
orev "$R" design/options/typography.md pass "https://example.com/typography-a | status 200 | keep" "https://example.com/typography-b | status 404 | keep"
check "a link that did not open (404) cannot pass" 'sh "$S/screens.sh" optreview "$R" | grep -q "did not open (status 404"'
orev "$R" design/options/typography.md pass "https://example.com/typography-a | status 200 | keep" "https://example.com/typography-b | status 301 | keep"
check "a redirect is not an opened page: the reviewer follows it and gives the final status" 'sh "$S/screens.sh" optreview "$R" | grep -q "did not open (status 301; follow a redirect"'
orev "$R" design/options/typography.md pass "https://example.com/typography-a | keep" "https://example.com/typography-bb | status 200 | keep"
check "each link has its status, and a longer address is not the same link" 'o=$(sh "$S/screens.sh" optreview "$R"); printf "%s" "$o" | grep -q "typography-a: its status" && printf "%s" "$o" | grep -q "typography-b is not in Links checked"'
orev "$R" design/options/typography.md pass "https://example.com/typography-a | status 200 | $(ago 1) | keep: shipped by a top foundry" "https://example.com/typography-b | status 200 | $(ago 2) | keep: current"
check "a review written by the session itself is void at the end of the turn" '[ "$(rc "$(pw "$R")")" = 0 ] && o=$(h "$(stop "ok")" 2>&1); [ $? = 2 ] && grep -q "^Void: " "$R" && sh "$S/screens.sh" unreviewed "$D" | grep -q typography-a'
turn d4; orev "$R" design/options/typography.md pass "https://example.com/typography-a | status 200 | $(ago 1) | keep: shipped by a top foundry" "https://example.com/typography-b | status 200 | $(ago 2) | keep: current"; reviewer
check "a review by the reviewer subagent stands, and the owner may see the references" '[ "$(rc "$(stop "Option A: https://example.com/typography-a")")" = 0 ] && ! grep -q "^Void: " "$R" && [ -z "$(sh "$S/screens.sh" unreviewed "$D")" ]'

# the owner's pick
check "nobody records a pick that the system does not hold yet: no Pick line" 'o=$(ok typography 2>&1); [ $? != 0 ] && printf "%s" "$o" | grep -q "it is open"'
sys() { awk -v p="$1" -v body="$2" 'BEGIN { n = split(body, b, "|") } /^## / { on = (tolower(substr($0, 4)) == p) } on && /^(Status|Options|Pick|Why):/ { next } { print } on && /^For:/ { for (i = 1; i <= n; i++) print b[i] }' "$D/design/SYSTEM.md" > "$T/s.md" && cp "$T/s.md" "$D/design/SYSTEM.md"; }
sys typography "Status: chosen|Options: design/options/typography.md|Pick: https://example.com/elsewhere"
check "a pick that names no reviewed option is refused" 'ok typography 2>&1 | grep -q "a Pick: line with the link of the option the owner picked"'
sys typography "Status: chosen|Options: design/options/typography.md|Pick: Option A, https://example.com/typography-a"
mkdir -p "$D/sub"
check "only the coordinator records the owner.s pick" 'o=$(ok typography "$D/sub" 2>&1); [ $? != 0 ] && printf "%s" "$o" | grep -q "only the coordinator"'
check "a piece marked chosen without the owner.s OK still holds screens" 'h "$(w "$D/web/app.html" "<div>")" 2>&1 | grep -q "typography has no OK from the owner"'
F="$D/design/reviews/options/$(date +%F) 2359 typography.md"; sleep 1
orev "$F" design/options/typography.md fail "https://example.com/typography-a | status 200 | $(ago 1) | keep: current" "https://example.com/typography-b | status 200 | $(ago 2) | reject: weak"
check "a pick whose newest reference review failed is refused" 'o=$(ok typography 2>&1); [ $? != 0 ] && printf "%s" "$o" | grep -q "failed: replace the rejected references"'
rm -f "$F"
check "the hook asks the owner before a pick is recorded" 'h "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sh $S/track.sh ok $D design:typography Option A\"}")" | grep -q "your pick of a design-system piece" && h "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sh $S/track.sh ok $D design:typography Option A\"}")" | grep -q "You are approving piece typography. The pick written in design/SYSTEM.md: Option A, https://example.com/typography-a. The words recorded as yours: option a"'
check "a command that names two pieces, or chains commands, is flagged to the owner instead of described" 'o=$(h "$(ev PreToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo design:colors; sh $S/track.sh ok $D design:typography Option A\"}")"); printf "%s" "$o" | grep -q "cannot read for sure" && ! printf "%s" "$o" | grep -q "You are approving piece"'
check "the coordinator records the owner.s pick; the piece is closed" 'ok typography "$D" "A, the serif" | grep -q "the owner picks design:typography" && sh "$S/track.sh" owned "$D" | grep -q "^design:typography	"'
check "screens still wait for the other pieces" 'o=$(h "$(w "$D/web/app.html" "<div>")" 2>&1); [ $? = 2 ] && ! printf "%s" "$o" | grep -q "typography is" && printf "%s" "$o" | grep -q "colors is open"'
for p in colors components motion; do sys $p "Status: not applicable|Why: a test fixture"; ok $p "$D" "not needed" >/dev/null; done
check "not applicable needs its Why and the owner too, and then screens open" '[ "$(rc "$(w "$D/web/app.html" "<div>")")" = 0 ]'
cp "$D/design/SYSTEM.md" "$T/keep.md"
awk '/^## / { on = (tolower(substr($0, 4)) == "components") } !on' "$T/keep.md" > "$D/design/SYSTEM.md"
check "deleting a piece the screens need holds them again" 'h "$(w "$D/web/app.html" "<div>")" 2>&1 | grep -q "components is missing"'
awk '/^## / { on = (tolower(substr($0, 4)) == "colors") } on && /^For:/ { print "For: print"; next } { print }' "$T/keep.md" > "$D/design/SYSTEM.md"
check "a piece the screens need still counts when its For: line is changed" '[ "$(rc "$(w "$D/web/app.html" "<div>")")" = 2 ]'
cp "$T/keep.md" "$D/design/SYSTEM.md"
check "video still waits for tone, rhythm and script" 'h "$(w "$D/video/index.html" "<div data-composition-id=\\\"m\\\">")" 2>&1 | grep -q "not done for video: tone is open; rhythm is open; script is open"'
awk '/^## / { t = ($0 == "## Typography") } t && /^What we take:$/ { $0 = "What we take: the serif for titles" } { print }' "$D/design/SYSTEM.md" > "$T/s.md"; cp "$T/s.md" "$D/design/SYSTEM.md"
check "a picked piece changed after the owner.s OK holds screens again" 'h "$(w "$D/web/app.html" "<div>")" 2>&1 | grep -q "typography changed after the owner.s OK"'
ok typography "$D" "yes, with the serif for titles" >/dev/null
awk '{ print } /^## Typography/ { t = 1 } t && /^### Applied/ { print "- titles: Serif Display 48/56"; t = 0 }' "$D/design/SYSTEM.md" > "$T/s.md"; cp "$T/s.md" "$D/design/SYSTEM.md"
check "what the specialists write under ### Applied needs no new OK" '[ "$(rc "$(w "$D/web/app.html" "<div>")")" = 0 ]'
echo "- extra" >> "$D/design/options/typography.md"
check "a proposal changed after the owner.s OK holds screens again" 'h "$(w "$D/web/app.html" "<div>")" 2>&1 | grep -q "typography changed after the owner.s OK"'
head -n -1 "$D/design/options/typography.md" > "$T/o.md" 2>/dev/null || sed '$d' "$D/design/options/typography.md" > "$T/o.md"; cp "$T/o.md" "$D/design/options/typography.md"
check "put back as the owner saw it, the OK holds again" '[ "$(rc "$(w "$D/web/app.html" "<div>")")" = 0 ]'
mv "$D/design/SYSTEM.md" "$T/SYSTEM.bak"
check "deleting the design system does not open the gate" 'h "$(w "$D/web/app.html" "<div>")" 2>&1 | grep -q "restore it (git) instead of deleting it"'
mv "$T/SYSTEM.bak" "$D/design/SYSTEM.md"
check "an agent cannot write the owner.s OKs or the plugin.s data" '[ "$(rc "$(w "$D/.owner-ok" "x")")" = 2 ] && [ "$(rc "$(w "$CLAUDE_PLUGIN_DATA/turns/d4/web" "x")")" = 2 ]'

# video: renders and compositions
turn d5; : > "$D/video/out.mp4"
check "a render a shell command wrote while the video pieces are open cannot end the turn quietly" 'o=$(h "$(stop "ok")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "video/out.mp4"'
check "and a video is not sent to the owner before its side-by-side review" 'h "$(send "$D/video/out.mp4")" 2>&1 | grep -q "not cleared to reach the owner"'
for p in tone rhythm script; do sys $p "Status: not applicable|Why: a test fixture"; ok $p "$D" "not needed" >/dev/null; done
check "with every video piece picked, video code opens" '[ "$(rc "$(w "$D/video/index.html" "<div data-composition-id=\\\"m\\\">")")" = 0 ]'
printf -- '---\ntrack: software\nstage: 1\n---\n## Stage 1: Video\n- [ ] cut | Cut | card: rhythm | needs: - | video: video/* | evidence:\n- [ ] review-1 | Review | card: reviewer | needs: cut | evidence:\n' > "$D/TRACK.md"
check "a design item of TRACK.md with video: holds video files too" 'h "$(w "$D/video/index.html" "<div data-composition-id=\\\"m\\\">")" 2>&1 | grep -q "the design item cut in TRACK.md is open" && [ "$(rc "$(w "$D/web/app.html" "<div>")")" = 0 ]'
rm -f "$D/TRACK.md"

# the specialists: fresh research, references, their cards reach every project
check "a design specialist cannot finish without a web search in its turn" 'turn d6; o=$(h "$(ev SubagentStop ",\"stop_hook_active\":false,\"last_assistant_message\":\"Role: tone References: https://example.com ## Never-skip checklist ok\"")" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "fresh web research"'
check "with the search and its references it finishes" 'web tone; [ "$(rc "$(ev SubagentStop ",\"stop_hook_active\":false,\"last_assistant_message\":\"Role: rhythm References: https://example.com ## Never-skip checklist ok\"")")" = 0 ]'
mkdir -p "$D/specialists"; cp "$S/../templates/specialists/designer.md" "$D/specialists/"
check "a card the plugin added reaches a project that keeps its own specialists folder" '[ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: script\\nLibrary: none found for x\"}")")" = 0 ] && [ "$(rc "$(ev PreToolUse ",\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Role card: nobody\\nLibrary: none found for x\"}")")" = 2 ]'
rm -rf "$D/specialists"

# the cards and the skill say the same
C=$S/../templates/specialists
check "the tone, rhythm and script cards exist in the card format" '( for r in tone rhythm script; do f="$C/$r.md"; for s in "^role: $r$" "^## Mission" "^## Method" "^## Never skip" "^## Checked by" "^## Output format" "^## Sources of this method" "shapes what the owner will see or use" "References:" "design/options/"; do grep -q "$s" "$f" || { echo "$r misses $s"; exit 1; }; done; done )'
check "the designer never picks between directions and starts from fresh web research" '! grep -q "then select one" "$C/designer.md" && grep -q "never picks" "$C/designer.md" && grep -q "fresh web search" "$C/designer.md" && grep -q "design/SYSTEM.md" "$C/designer.md"'
check "the reviewer opens every reference link and rejects old, weak or broken ones" 'grep -q "Links checked:" "$C/reviewer.md" && grep -q "design/reviews/options/" "$C/reviewer.md" && grep -qi "old, weak or broken" "$C/reviewer.md"'
check "the specialists skill builds the design system with the owner, piece by piece" 'f="$S/../skills/specialists/SKILL.md"; grep -q "design/SYSTEM.md" "$f" && grep -q "design:<piece>" "$f" && grep -q "2-3" "$f" && grep -qi "fresh web research first" "$f"'
check "ROUTING sends the video pieces to their cards" 'for r in tone rhythm script; do grep -q "\`$r\`" "$S/../templates/ROUTING.md" || exit 1; done'
[ $fail = 0 ] && echo "design system: all passed" || { echo "design system: FAILED"; exit 1; }
