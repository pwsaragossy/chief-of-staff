#!/bin/sh
# Mutation proof for the guards that stay in chief-of-staff 0.12.0: each mutation removes one guard in a copy of the
# plugin, runs the full selftest there and expects the named test to FAIL. Usage: tests/mutation.sh > log 2>&1
# Exit 0 when every mutation is caught. ONLY=<words of a name> runs that mutation alone.
R=$(cd "$(dirname "$0")/.." && pwd)
caught=0; missed=0
mutate() { # name file test-substring python-old python-new
  [ -n "${ONLY:-}" ] && case $1 in *"$ONLY"*) ;; *) return ;; esac
  t=$(mktemp -d); cp -R "$R/scripts" "$R/templates" "$R/skills" "$R/hooks" "$R/tests" "$R/README.md" "$t/"
  python3 - "$t/$2" "$4" "$5" <<'PY' || { echo "MUTATION NOT APPLIED: $1"; missed=$((missed + 1)); rm -rf "$t"; return; }
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
if s.count(a) != 1: sys.exit("text found %d times" % s.count(a))
open(p, "w").write(s.replace(a, b))
PY
  out=$(sh "$t/scripts/selftest.sh" 2>&1); rm -rf "$t"
  if printf '%s\n' "$out" | grep -F "FAIL $3" >/dev/null; then echo "CAUGHT  $1 -> FAIL $3"; caught=$((caught + 1))
  else echo "MISSED  $1 (expected FAIL $3)"; missed=$((missed + 1)); fi
}
mutate "ask-guard lets any folder ask" scripts/ask-guard.sh "guard blocks a subfolder of the project" \
  'cos_owner "$root" "$dir" && exit 0' 'exit 0'
mutate "track.sh ok from any session" scripts/track.sh "a session that is not the project's coordinator cannot record the owner OK" \
  '[ -n "$_sr" ] && cos_owner "$_sr" "$_s" && [ "$(cd "$_sr" && pwd -P)" = "$(cd "$_dr" 2>/dev/null && pwd -P)" ] ||' 'true ||'
mutate "agents may write .owner-ok" scripts/protocol.sh "agents cannot write the owner OK file" \
  '*/.chief-of-staff/*|*/.owner-ok|*/.owner-items) ;;' '*/.chief-of-staff/*) ;;'
mutate "an owner file the disk folds is trusted" scripts/track.sh "an owner OK the disk only reads as one (a Kelvin K)" \
  'folded=; for _b in .owner-ok .owner-items; do' 'folded=; for _b in ; do'
mutate "an owner OK git tracks is trusted" scripts/track.sh "an owner OK that git tracks, in any letter case" \
  'if [ -n "$wroot" ]; then' 'if false; then'
mutate "a project inside a bigger repository skips the git check" scripts/track.sh "an owner OK that git tracks is not trusted when the project is a subfolder" \
  'while [ -n "$wroot" ] && [ ! -e "$wroot/.git" ]; do wroot=${wroot%/*}; done' '[ -e "$wroot/.git" ] || wroot='
mutate "old layout gets no line" scripts/briefing.sh "a workspace of the old layout gets one line" \
  '{ cos_old "$dir" && echo' '{ false && echo'
mutate "dispatcher runs any folder" scripts/dispatcher.sh "dispatcher refuses a folder that is not a project" \
  'cos_isproj "$root" || { echo "not a chief-of-staff project: $root" >&2; exit 1; }' ':'
mutate "project.sh trust takes any folder" scripts/project.sh "project.sh trust records a project's settings" \
  'cos_isproj "$d" || die "$d is not a project folder"
    cos_cfgsave' 'cos_cfgsave'
mutate "project.sh trust runs without asking" scripts/protocol.sh "the guard asks the owner before project.sh trust" \
  "project\\\\.sh +((init|library|trust)" "project\\\\.sh +((init|library)"
mutate "a background launch is not credited" scripts/protocol.sh "the turn that applies a background report is credited" \
  "*'\"status\":\"async_launched\"'*|*'\"status\": \"async_launched\"'*|" ""
mutate "screen code is written before its design" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'why=$(sh "$SC" gate "$root" "$sfp" "$sk") || [ $? != 1 ] || {' 'why=; true || {'
mutate "a design item closed with a stub opens screen code" scripts/screens.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'x) w=$(refs "$ev") || why=' 'x) w=$(true) || why='
mutate "design/../ passes as a mockup" scripts/screens.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'case $rel in */../*|../*|*/./*|./*) ;; design/*) exit 0 ;; esac' 'case $rel in design/*) exit 0 ;; esac'
mutate "a screen is shown before its review" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'why=$(sh "$SC" state "$root") && exit 0' 'exit 0'
mutate "opening a screen in the owner's browser is not held" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'why=$(sh "$SC" state "$root") || { echo "Blocked by chief-of-staff: this opens a screen' 'why=$(true) || { echo "Blocked by chief-of-staff: this opens a screen'
mutate "empty or repeated screenshots pass as a side by side" scripts/screens.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'do cksum < "$i"; done | sort -u' 'do echo "$i$RANDOM"; done | sort -u'
mutate "a review of an older picture clears a newer screen" scripts/screens.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  '[ -n "$fresh" ] && exit 0' 'exit 0'
mutate "a review the session wrote itself stands" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'if [ -n "$rv" ] && [ "$reviewers" -lt 1 ]' 'if false'
mutate "screen code written by a shell command goes unseen" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'chg=$(cos_limit 1 sh "$SC" changed "$root" "$st/start" "$st/head") || chg=' 'chg='
mutate "a screen not cleared lets go on the second stop" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  '[ -n "$sgaps" ] && [ "$(count screenpush)" -lt 2 ] && {' 'false && {'
mutate "a drawing or a pdf is sent before the review" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  '*.avif\"*|*.svg\"*|*.pdf\"*|' ''
mutate "a drawing or a pdf opens in the owner's viewer before the review" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  '(png|jpe?g|webp|gif|avif|svg|pdf|mp4|mov|webm|m4v|mkv)([^a-z0-9]|$)|$(printf' '(png|jpe?g|webp|gif|avif|mp4|mov|webm|m4v|mkv)([^a-z0-9]|$)|$(printf'
mutate "an answer pointing at a pdf ends before the review" scripts/protocol.sh "screens: no screen code before its design, no screen to the owner before its side-by-side review" \
  'gif|avif|svg|pdf|mp4|mov|webm|m4v|mkv)([^a-z0-9]|$)|screenshot' 'gif|avif|svg|mp4|mov|webm|m4v|mkv)([^a-z0-9]|$)|screenshot'
DS="design system: the owner picks each piece from 2-3 recent references the reviewer opened before screens or videos are built"
mutate "an open design-system piece lets screen code through" scripts/screens.sh "$DS" \
  '[ $sr = 1 ] && why="$sw. "' ':'
mutate "a piece counts as picked without the owner's OK" scripts/screens.sh "$DS" \
  'if [ -z "$_g" ]; then _w="$_w$_p has no OK from the owner; "' 'if false; then :'
mutate "a piece changed after the owner's OK still counts" scripts/screens.sh "$DS" \
  'elif [ "$_g" != "$(psum "$_p" "$_o")" ]; then' 'elif false; then'
mutate "a proposal needs no web search in its turn" scripts/protocol.sh "$DS" \
  'if [ ! -f "$st/web" ]; then p="${p:+$p' 'if false; then p="${p:+$p'
mutate "an old reference passes" scripts/screens.sh "$DS" \
  'else if (rn >= 0 && dn < rn - N * 100)' 'else if (0)'
mutate "one option is a choice" scripts/screens.sh "$DS" \
  'if (k < 2 || k > 3)' 'if (0)'
mutate "a reference review may leave a link out" scripts/screens.sh "$DS" \
  '[ -n "$l" ] || { e="$e- $u is not in Links checked' 'true || { e="$e- $u is not in Links checked'
mutate "a pass may keep a rejected link" scripts/screens.sh "$DS" \
  '[ "$v" = pass ] && { [ "$r" = reject ]' 'false && { [ "$r" = reject ]'
mutate "references reach the owner before their review" scripts/protocol.sh "$DS" \
  '[ -n "$ul" ] && sgaps=' 'false && sgaps='
mutate "a pick is recorded without a passing reference review" scripts/screens.sh "$DS" \
  'elif [ "$v" != pass ]; then e="$e- its reference review' 'elif false; then e="$e- its reference review'
mutate "deleting the design system opens the gate" scripts/screens.sh "$DS" \
  'if grep -qs '"'"'design/SYSTEM.md'"'"' "$dir/CLAUDE.md" ||' 'if false &&'
mutate "a design specialist finishes without a web search" scripts/protocol.sh "$DS" \
  '[ -f "$st/web" ] || { echo "Design work starts' 'true || { echo "Design work starts'
mutate "a proposal written with no web search stays valid" scripts/protocol.sh "$DS" \
  'if [ ! -f "$st/web" ]; then op=' 'if false; then op='
mutate "a render is not seen as video" scripts/screens.sh "$DS" \
  '*.mp4|*.mov|*.webm|*.m4v|*.mkv) cat >/dev/null; echo video' '*.nothing) cat >/dev/null; echo video'
mutate "agents may write the plugin's data" scripts/protocol.sh "$DS" \
  'case $rp in "$(real "$DATA")"/*|' 'case $rp in /nonexistent/*|'
mutate "a piece deleted from the design system stops counting" scripts/screens.sh "$DS" \
  '*) _w="$_w$_r is missing' '*) _w="$_w'
mutate "a proposal counts any web search, not one it names" scripts/protocol.sh "$DS" \
  'grep -qxF -e "$q" -- "$st/webq" 2>/dev/null &&' 'true &&'
mutate "the owner approves a pick without seeing it" scripts/protocol.sh "$DS" \
  '[ -n "$dp" ] && printf '"'"' You are approving piece' 'false && printf '"'"' You are approving piece'
mutate "a page carrying unreviewed references is published" scripts/protocol.sh "$DS" \
  'for u in $ul; do grep -qF "$u" "$f" 2>/dev/null || continue' 'for u in $ul; do continue'
mutate "an impossible date passes" scripts/screens.sh "$DS" \
  'if (a[2] < 1 || a[2] > 12 || a[3] < 1 || a[3] > 31) return -1;' ''
mutate "a redirect passes as an opened link" scripts/screens.sh "$DS" \
  'case $sc in 2??) false' 'case $sc in [23]??) false'
mutate "a new screen in a project with no design system goes through" scripts/screens.sh "$DS" \
  'isnew "$3" && { hit=1;' 'false && { hit=1;'
mutate "the current option's From: may name no file" scripts/screens.sh "$DS" \
  'else if ((getline x < (root "/" fr[i])) < 0) p = p' 'else if (0) p = p'
mutate "two current options pass" scripts/screens.sh "$DS" \
  'if (nc > 1) p = p' 'if (0) p = p'
mutate "the current option alone needs no fresh reference" scripts/screens.sh "$DS" \
  'if (k >= 2 && k - nc < 1) p = p' 'if (0) p = p'
OW="the owner's words hold: approved work stays intact, a drop is recorded at once, a large task counts its deliverables, a grant keeps its package from stage 1"
mutate "a file the owner approved is written over" scripts/protocol.sh "$OW" \
  '[ -n "$hz" ] && { echo "Blocked by chief-of-staff: ${afp##*/} holds work' 'false && { echo "Blocked by chief-of-staff: ${afp##*/} holds work'
mutate "a frozen file changed by a shell command goes unseen" scripts/protocol.sh "$OW" \
  '[ "$(fsum "$z")" = "$s" ] ||' 'true ||'
mutate "a frozen folder holds only its own path" scripts/protocol.sh "$OW" \
  'case $rpf in ("$z"|"$z"/*) printf' 'case $rpf in ("$z") printf'
mutate "the owner's approval passes without a word" scripts/protocol.sh "$OW" \
  'print "approve\t" substr(s' 'print "approvx\t" substr(s'
mutate "the first deliverable is made before the list is counted" scripts/protocol.sh "$OW" \
  'if [ -n "${dl:-}" ] && [ -z "${nd:-}" ]' 'if false && [ -z "${nd:-}" ]'
mutate "a drop the owner said ends the turn unrecorded" scripts/protocol.sh "$OW" \
  'if [ -n "$project" ] && [ -f "$st/drop" ] &&' 'if false && [ -f "$st/drop" ] &&'
mutate "a negated word counts as a drop or an approval" scripts/protocol.sh "$OW" \
  'gsub(/(n(\303\243|\303\203|a)o|sem|nunca' 'if (0) gsub(/(n(\303\243|\303\203|a)o|sem|nunca'
mutate "a later session is not told what the owner dropped" scripts/briefing.sh "$OW" \
  '[ -n "$df" ] && { out "Dropped or frozen' 'false && { out "Dropped or frozen'
mutate "the grant package is built from scratch at each stage" templates/tracks/grant.md "$OW" \
  '| needs: package-1, evidence, budget, technical |' '| needs: evidence, budget, technical |'
mutate "the grant form is read late" templates/tracks/grant.md "$OW" \
  '- [ ] form | The real application form pulled now' '- [ ] form | The application form'
mutate "a hard link to a frozen file is written over" scripts/protocol.sh "$OW" \
  'if [ -z "$hz" ] && [ -f "$afp" ] &&' 'if false &&'
mutate "a thread lifts a freeze in DECISIONS.md" scripts/protocol.sh "$OW" \
  '[ -n "$dhit" ] && { echo "Blocked by chief-of-staff: DECISIONS.md is written' 'false && { echo "Blocked by chief-of-staff: DECISIONS.md is written'
mutate "a freeze path stops at a bracket" scripts/lib.sh "$OW" \
  "s/; *[A-Za-z]+:.*//; s/\\) *\$//" "s/[;)].*//"
mutate "a thread writes DECISIONS.md with a shell command" scripts/protocol.sh "$OW" \
  'if [ -n "$project" ] && ! isowner && printf '"'"'%s'"'"' "$lc" | grep -q '"'"'decisions\.md'"'"' &&' 'if false &&'
mutate "a thread chains a write after a git add of DECISIONS.md" scripts/protocol.sh "$OW" \
  "grep -Eq '^ *git +(add|commit|status)( [^;&|<>\`\$]*)?\$'" "grep -Eq '^ *git +(add|commit|status)( .*)?\$'"
mutate "a brief is read as the owner speaking" scripts/protocol.sh "$OW" \
  "*'<ci-monitor-event>'*|*'Role card:'*) ow= ;;" "*'<ci-monitor-event>'*) ow= ;;"
mutate "an engineering 'drop the' counts as a drop" scripts/protocol.sh "$OW" \
  'drop (it|that|this)|scrap' 'drop (it|that|this|the)|scrap'
mutate "two decisions in one minute go unflagged" scripts/track.sh "$OW" \
  'grep -q "^- $_now |" "$f" &&' 'false &&'
mutate "the grant portal account waits for the last day" templates/tracks/grant.md "$OW" \
  "- [ ] account | The applicant's account on the program's portal opened now" "- [ ] account | The applicant's account on the program's portal"
echo "caught=$caught missed=$missed"; [ "$missed" = 0 ]
