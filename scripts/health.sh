#!/bin/sh
# Health of each project, the one source for the panel and the briefing.
#   health.sh [dir]        one line per project, fields split by \037:
#     slug color reason stage stages closed total delivery delivered baseline baseline_delivery deadline member
#     (deadline: seconds since 1970, empty when TRACK.md sets none)
#   health.sh cards [dir]  one line per board card, fields split by \037:
#     C name project status member color waited limit due due_left questions   (questions split by \036;
#     waited: minutes the card has waited on the owner; due_left: minutes to the due date, negative when past)
# red    = track gate problem, STATE says red, a protocol violation in the last 24 h, a dispatcher ALERT,
#          a question waiting on the owner longer than owner_wait_minutes (TRACK.md, default 60),
#          the deadline (TRACK.md) less than 2 h away or past with the delivery open
# yellow = a card waiting on the owner, a card past its due date, the deadline less than 6 h away,
#          STATE.md unchanged for longer than stale_hours, status paused
# green  = none of the above
. "$(dirname "$0")/lib.sh"

mode=projects; [ "${1:-}" = cards ] && { mode=cards; shift; }
root=$(cos_root "${1:-$PWD}") || { echo "health.sh: no chief-of-staff workspace at ${1:-$PWD}" >&2; exit 2; }
US=$(printf '\037'); RS=$(printf '\036')
now=$(date +%s)
clean() { tr -d '\000-\037' | cut -c1-200; }

cards() {
  for c in "$root"/board/*.md; do
    [ -f "$c" ] || continue
    cp=$(fm_get "$c" project | clean); cs=$(fm_get "$c" status | clean)
    lim=$(fm_get "$root/projects/$(printf '%s' "$cp" | tr -cd 'A-Za-z0-9._-')/TRACK.md" owner_wait_minutes); case $lim in ''|*[!0-9]*) lim=60 ;; esac
    col=green; w=
    if [ "$cs" = waiting-owner ]; then
      # timed from asked: (the Stop hook stamps it), else from the file date
      a=$(cos_epoch "$(fm_get "$c" asked)"); [ -n "$a" ] || a=$(stat -c %Y "$c" 2>/dev/null || stat -f %m "$c")
      w=$(( (now - a) / 60 )); [ "$w" -ge 0 ] || w=0
      col=yellow; [ "$w" -ge "$lim" ] && col=red
    fi
    dr=$(fm_get "$c" due | clean); de=$(cos_epoch "$dr"); dl=
    [ -n "$de" ] && { dl=$(( (de - now) / 60 )); [ "$dl" -lt 0 ] && [ $col = green ] && col=yellow; }
    q=$(cos_questions "$c" | awk 'NR > 1 { printf "\036" } { printf "%s", $0 }')
    printf 'C%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$US" "$(basename "$c" .md | clean)" "$US" "$cp" "$US" "$cs" "$US" "$(fm_get "$c" member | clean)" \
      "$US" "$col" "$US" "$w" "$US" "$lim" "$US" "$dr" "$US" "$dl" "$US" "$q"
  done
}
[ $mode = cards ] && { cards; exit 0; }
allcards=$(cards)

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

  st=$(sh "$(dirname "$0")/track.sh" status "$d")
  [ -n "$st" ] || st="$US$US$US$US$US$US$US"
  tot=$(printf '%s' "$st" | cut -d "$US" -f4); dl=$(printf '%s' "$st" | cut -d "$US" -f5); dv=$(printf '%s' "$st" | cut -d "$US" -f6)
  bl=$(printf '%s' "$st" | cut -d "$US" -f7); bd=$(printf '%s' "$st" | cut -d "$US" -f8)
  status=$(fm_get "$s" status | tr 'A-Z' 'a-z')
  # quiet = STATE.md says delivered AND the track agrees (all items up to the line closed); a bare word is not enough
  quiet=; case $status in delivered|done) [ "$dv" = 1 ] && quiet=1 ;; esac

  dlv=$(fm_get "$d/TRACK.md" deadline | clean); dle=
  if [ -n "$dlv" ]; then
    dle=$(cos_epoch "$dlv")
    if [ -z "$dle" ]; then yellow "deadline '$dlv' in TRACK.md is not a date: write YYYY-MM-DD HH:MM in local time"
    elif [ "$dv" != 1 ]; then
      left=$(( (dle - now) / 60 ))
      if [ "$dle" -le "$now" ]; then red "deadline passed $(cos_ago $(( (now - dle) / 60 ))) ago and the delivery is open"
      elif [ "$left" -lt 120 ]; then red "deadline in $(cos_ago "$left") and the delivery is open"
      elif [ "$left" -lt 360 ]; then yellow "deadline in $(cos_ago "$left")"; fi
    fi
  fi
  while IFS=$US read -r k cn cp cs cm cc cw cl cd cdl cq; do
    [ "$k" = C ] && [ "$cp" = "$p" ] || continue
    if [ "$cs" = waiting-owner ]; then
      if [ "$cc" = red ]; then red "a question has waited on the owner for $(cos_ago "$cw") (limit $cl min): $cn"
      else yellow "waiting on the owner for $(cos_ago "$cw"): $cn"; fi
    fi
    [ -n "$cdl" ] && [ "$cdl" -lt 0 ] && yellow "card past its due date $cd: $cn"
  done <<EOC
$allcards
EOC
  [ -n "$bl" ] && [ "${tot:-0}" -lt "$bl" ] && yellow "$((bl - tot)) items removed from the track since opening ($bl at opening, $tot now)"
  [ -n "$bd" ] && [ "$bd" != "$dl" ] && yellow "delivery line moved from stage $bd to stage $dl since opening"
  h=$(fm_get "$d/TRACK.md" stale_hours); case $h in ''|*[!0-9]*) h=48 ;; esac
  [ -z "$quiet" ] && [ -n "$(find "$s" -mmin +$((h * 60)) 2>/dev/null)" ] && yellow "no handoff for more than $h h"
  [ "$status" = paused ] && yellow "paused"
  if [ -n "$quiet" ]; then on="delivered: the original request is done"; else on="on track"; fi
  [ -n "$color" ] || { color=green; reason=$on; }
  printf '%s\037%s\037%s\037%s\037%s\037%s\n' "$p" "$color" "$(printf '%s' "$reason" | clean)" "$st" "$dle" "$(fm_get "$s" member | clean)"
done
