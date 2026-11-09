#!/bin/sh
# Mutation proof for the guards that stay in chief-of-staff 0.12.0: each mutation removes one guard in a copy of the
# plugin, runs the full selftest there and expects the named test to FAIL. Usage: tests/mutation.sh > log 2>&1
# Exit 0 when every mutation is caught. ONLY=<words of a name> runs that mutation alone.
R=$(cd "$(dirname "$0")/.." && pwd)
caught=0; missed=0
mutate() { # name file test-substring python-old python-new
  [ -n "${ONLY:-}" ] && case $1 in *"$ONLY"*) ;; *) return ;; esac
  t=$(mktemp -d); cp -R "$R/scripts" "$R/templates" "$R/skills" "$R/hooks" "$R/README.md" "$t/"
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
echo "caught=$caught missed=$missed"; [ "$missed" = 0 ]
