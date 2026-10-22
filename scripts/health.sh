#!/bin/sh
# Health of each project, the one source for the panel. One line per project, fields split by \037:
#   slug  color  reason  stage  stages  closed  total
# red    = track gate problem, STATE says red, a protocol violation in the last 24 h, a dispatcher ALERT
# yellow = a card waiting on the owner, STATE.md unchanged for longer than stale_hours, status paused
# green  = none of the above
. "$(dirname "$0")/lib.sh"

root=$(cos_root "${1:-$PWD}") || { echo "health.sh: no chief-of-staff workspace at ${1:-$PWD}" >&2; exit 2; }
US=$(printf '\037')
now=$(date +%s)
clean() { tr -d '\000-\037' | cut -c1-200; }

for s in "$root"/projects/*/STATE.md; do
  [ -f "$s" ] || continue
  d=$(dirname "$s"); p=$(basename "$d")
  color=; reason=
  red() { [ -n "$color" ] && [ "$color" != yellow ] || { color=red; reason=$1; }; }
  yellow() { [ -n "$color" ] || { color=yellow; reason=$1; }; }

  gap=$(sh "$(dirname "$0")/track.sh" check "$d" | head -n 1)
  [ -n "$gap" ] && red "track: $gap"
  sev=$(awk '/^## 1\./ { on = 1; next } on && NF { print tolower($1); exit }' "$s" | tr -cd 'a-z')
  [ "$sev" = red ] && red "STATE.md says red"
  # a violation counts unless a later line of the same session complied (the agent fixed it after the push)
  [ -f "$root/.protocol.log" ] && awk -v p="project=$p" -v c=$((now - 86400)) '
      index($0, " " p " ") {
        t = 0; for (i = 1; i <= NF; i++) { if ($i ~ /^t=/) t = substr($i, 3) + 0; if ($i ~ /^turn=/) id = $i }
        if (/violation=1/ && t >= c) bad[id] = 1
        else if (/violation=0/ && !/specialists=0 reviewers=0/) delete bad[id] }
      END { for (k in bad) f = 1; exit !f }' "$root/.protocol.log" && red "a turn ended without the specialists, the reviewer or the track gate"
  [ -f "$root/.dispatch.log" ] && awk -v p="$p" 'index($0, "ALERT") && (index($0, " " p ";") || index($0, " " p ",")) { f = 1 } END { exit !f }' "$root/.dispatch.log" && red "dispatcher ALERT: read .dispatch.log, then delete the ALERT line to clear it"

  for c in "$root"/board/*.md; do
    [ -f "$c" ] && [ "$(fm_get "$c" status)" = waiting-owner ] && [ "$(fm_get "$c" project)" = "$p" ] && { yellow "waiting on the owner: $(basename "$c" .md)"; break; }
  done
  h=$(fm_get "$d/TRACK.md" stale_hours); case $h in ''|*[!0-9]*) h=48 ;; esac
  [ -n "$(find "$s" -mmin +$((h * 60)) 2>/dev/null)" ] && yellow "no handoff for more than $h h"
  [ "$(fm_get "$s" status)" = paused ] && yellow "paused"

  st=$(sh "$(dirname "$0")/track.sh" status "$d")
  [ -n "$st" ] || st="$US$US$US"
  [ -n "$color" ] || { color=green; reason="on track"; }
  printf '%s\037%s\037%s\037%s\n' "$p" "$color" "$(printf '%s' "$reason" | clean)" "$st"
done
