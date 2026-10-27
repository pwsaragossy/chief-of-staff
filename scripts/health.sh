#!/bin/sh
# Health of each project, the one source for the panel and the briefing.
#   health.sh [dir]        one line per project, fields split by \037:
#     slug color reason stage stages closed total delivery delivered baseline baseline_delivery deadline member
#     target check runs   (runs: "first value -> last value" from .check-runs)
#     (deadline: seconds since 1970, empty when TRACK.md sets none)
#   health.sh cards [dir]  one line per board card, fields split by \037:
#     C name project status member color waited limit due due_left questions deputy size   (questions split by \036;
#     waited: minutes since its oldest open question was asked; due_left: minutes to the due date, negative when past;
#     deputy: who to escalate to, set when a late question meets a deadline under 3 h; size: set when the card is too long)
# red    = track gate problem, STATE says red, a protocol violation in the last 24 h, a dispatcher ALERT,
#          a question waiting on the owner longer than owner_wait_minutes (TRACK.md, default 60),
#          the deadline (TRACK.md) less than 2 h away or past with the delivery open,
#          a late question less than 3 h before the deadline (escalate to the track's deputy:)
# yellow = a card waiting on the owner, a card past its due date, the deadline less than 6 h away,
#          no handoff (STATE.md updated:) for longer than stale_hours, status paused, the last check run failed,
#          the target met on the very first run (not a hard target), a card too long to read,
#          a public_urls link closed to a logged-out visitor, production not serving the prod_ref commit,
#          a delivery that points at a file outside the workspace
# green  = none of the above
. "$(dirname "$0")/lib.sh"

mode=projects; [ "${1:-}" = cards ] && { mode=cards; shift; }
root=$(cos_root "${1:-$PWD}") || { echo "health.sh: no chief-of-staff workspace at ${1:-$PWD}" >&2; exit 2; }
US=$(printf '\037'); RS=$(printf '\036')
now=$(date +%s)
clean() { tr -d '\000-\037' | cut -c1-200; }

cards() {
  # one pass over the board (cos_board); values come back without control characters, at most 200 characters
  cos_board "$root" | while IFS=$US read -r c cm cp cs ca dr nq nu sp nl nb lg q; do
    t="$root/projects/$(printf '%s' "$cp" | tr -cd 'A-Za-z0-9._-')/TRACK.md"
    lim=$(fm_get "$t" owner_wait_minutes); case $lim in ''|*[!0-9]*) lim=60 ;; esac
    col=green; w=; esc=
    if [ "$cs" = waiting-owner ]; then
      # timed from the oldest open question: its (asked ...) stamp or asked:, else the file date
      a=$(cos_epoch "$ca")
      while IFS= read -r x; do x=$(cos_epoch "$x"); [ -n "$x" ] && { [ -z "$a" ] || [ "$x" -lt "$a" ]; } && a=$x; done <<EOS
$(printf '%s' "$sp" | tr '\036' '\n')
EOS
      [ -n "$a" ] || a=$(stat -c %Y "$c" 2>/dev/null || stat -f %m "$c")
      w=$(( (now - a) / 60 )); [ "$w" -ge 0 ] || w=0
      col=yellow; [ "$w" -ge "$lim" ] && col=red
      # past its limit less than 3 h before the deadline (or after it): the owner is out of reach, so the
      # question goes to the deputy the track names (deputy:), who decides in the owner's place
      if [ $col = red ]; then dp=$(fm_get "$t" deputy | clean); de=$(cos_epoch "$(fm_get "$t" deadline)")
        [ -n "$dp" ] && [ -n "$de" ] && [ $((de - now)) -lt 10800 ] && esc=$dp; fi
    fi
    de=$(cos_epoch "$dr"); dl=
    [ -n "$de" ] && { dl=$(( (de - now) / 60 )); [ "$dl" -lt 0 ] && [ $col = green ] && col=yellow; }
    # a card past ~60 lines, 15 KB or with lines over 300 characters is read by every session: it buries the questions
    big=; { [ "$nl" -gt 60 ] || [ "$nb" -gt 15000 ] || [ "$lg" -gt 0 ]; } && big="$nl lines, $((nb / 1024)) KB, $lg lines over 300 characters"
    n=${c##*/}; n=${n%.md}
    printf 'C%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$US" "$(printf '%s' "$n" | clean)" "$US" "$cp" "$US" "$cs" "$US" "$cm" \
      "$US" "$col" "$US" "$w" "$US" "$lim" "$US" "$dr" "$US" "$dl" "$US" "$q" "$US" "$esc" "$US" "$big"
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
  tg=$(fm_get "$d/TRACK.md" target | clean); ck=$(fm_get "$d/TRACK.md" check | clean); runs=
  if [ -s "$d/.check-runs" ]; then   # rc 0 met, 1 not met; other codes (timeout, error) are not a measurement
    fr=$(awk -F '\t' '$2 == 0 || $2 == 1 { print $2 "\t" $3; exit }' "$d/.check-runs"); lr=$(tail -n 1 "$d/.check-runs" | cut -f2,3)
    lv=$(printf '%s' "$lr" | cut -f2 | clean); [ -n "$fr" ] && runs="$(printf '%s' "$fr" | cut -f2 | clean) -> $lv"
    [ "${lr%%	*}" = 1 ] && yellow "check fails: $lv (target: $tg)"
    [ "${fr%%	*}" = 0 ] && yellow "target met on the first run: not a hard target, raise it with the owner"
  fi
  while IFS=$US read -r k cn cp cs cm cc cw cl cd cdl cq cesc cbig; do
    [ "$k" = C ] && [ "$cp" = "$p" ] || continue
    if [ "$cs" = waiting-owner ]; then
      if [ -n "$cesc" ]; then red "a question has waited $(cos_ago "$cw") with the deadline under 3 h: escalate it to the deputy, $cesc: $cn"
      elif [ "$cc" = red ]; then red "a question has waited on the owner for $(cos_ago "$cw") (limit $cl min): $cn"
      else yellow "waiting on the owner for $(cos_ago "$cw"): $cn"; fi
    fi
    [ -n "$cdl" ] && [ "$cdl" -lt 0 ] && yellow "card past its due date $cd: $cn"
    [ -n "$cbig" ] && yellow "card too long to read ($cbig): move what is done to board/archive/: $cn"
  done <<EOC
$allcards
EOC
  [ -n "$bl" ] && [ "${tot:-0}" -lt "$bl" ] && yellow "$((bl - tot)) items removed from the track since opening ($bl at opening, $tot now)"
  [ -n "$bd" ] && [ "$bd" != "$dl" ] && yellow "delivery line moved from stage $bd to stage $dl since opening"
  h=$(fm_get "$d/TRACK.md" stale_hours); case $h in ''|*[!0-9]*) h=48 ;; esac
  # the handoff time is updated: in the front matter; the file date only when it is missing (a git pull or
  # checkout sets the file date to now, so a teammate's stale STATE.md looked fresh)
  ue=$(cos_epoch "$(fm_get "$s" updated)"); old=
  if [ -n "$ue" ]; then [ $((now - ue)) -gt $((h * 3600)) ] && old=1; else old=$(find "$s" -mmin +$((h * 60)) 2>/dev/null); fi
  [ -z "$quiet" ] && [ -n "$old" ] && yellow "no handoff for more than $h h"
  [ "$status" = paused ] && yellow "paused"
  # what goes outside, seen as a stranger would (only here, for the panel and health.sh, never in a hook):
  # public_urls: opened without credentials; prod_ref: <url> <commit> serves that commit. Cached 10 min
  net() { _c=$(cos_cache net "$1"); [ -n "$(find "$_c" -mmin -10 2>/dev/null)" ] || { mkdir -p "${_c%/*}"
      _b=$(curl -q -s -L --max-time 4 -o "$_c.body" -w '%{http_code}' -- "$1" 2>/dev/null); _r=$?
      { printf '%s %s\n' "$_r" "${_b:-000}"; head -c 4096 "$_c.body" 2>/dev/null; } > "$_c"; rm -f "$_c.body"; }
    cat "$_c"; }
  netok() { set -- $(head -n 1); [ "$1" = 0 ] && { [ "$2" = 000 ] || [ "$2" -lt 400 ]; }; }
  if command -v curl >/dev/null 2>&1; then
    for u in $(fm_get "$d/TRACK.md" public_urls | clean | tr ',' ' ' | cut -d' ' -f1-6); do
      net "$u" | netok || { yellow "a public link does not open for a logged-out visitor: $u ($(net "$u" | head -n 1 | cut -d' ' -f2))"; break; }
    done
    set -- $(fm_get "$d/TRACK.md" prod_ref | clean)
    if [ $# -ge 2 ]; then pc=$(printf '%s' "$2" | cut -c1-7)
      if ! net "$1" | netok; then yellow "production does not answer: $1"
      elif ! net "$1" | sed 1d | grep -qF -- "$pc"; then yellow "production does not serve the expected commit $pc ($1)"; fi
    fi
  fi
  # a delivery that points at a file outside the workspace: teammates and the reviewer cannot open it
  xo=$( { cat "$d/DELIVERY.md"; awk 'NR == 1 && /^---/ { f = 1; next } f && /^---/ { f = 0; next } !f' "$d/TRACK.md"; } 2>/dev/null | grep -oE '(^|[ (`"'"'"'])(~|/[A-Za-z0-9._-]+)(/[A-Za-z0-9._-]+)+' |
    sed 's/^[ (`"'"'"']//' | while IFS= read -r x; do case $x in "$root"/*|/usr/*|/bin/*|/dev/*|/etc/*|/opt/*) ;; *) printf '%s\n' "$x" ;; esac; done | head -n 1)
  [ -n "$xo" ] && yellow "the delivery points outside the workspace ($xo): copy the file into the project folder"
  if [ -n "$quiet" ]; then on="delivered: the original request is done"; else on="on track"; fi
  [ -n "$color" ] || { color=green; reason=$on; }
  printf '%s\037%s\037%s\037%s\037%s\037%s\n' "$p" "$color" "$(printf '%s' "$reason" | clean)" "$st" "$dle" "$(fm_get "$s" member | clean)$US$tg$US$ck$US$runs"
done
