#!/bin/sh
# The whole picture as chat text, readable on a phone (Remote Control): what waits on the owner, what is due in 7
# days, what changed in 24 hours, what is moving, and how much is stopped, across every board folder given.
# Reads the cards' front matter in English or Portuguese (status/project/due/updated or status/projeto/prazo/
# atualizado). Read-only. Usage: sh overview.sh <board folder>...   or   sh overview.sh --all (every registered project
# and every recorded board folder, project.sh board). --rows <board folder>... prints one line per open card instead,
# class<TAB>title<TAB>project<TAB>due<TAB>mtime<TAB>folder (class w waiting, m moving, s stopped; folder from pasta:/folder:),
# which the web panel reads.
rows=0; [ "${1:-}" = --rows ] && { rows=1; shift; }
if [ "${1:-}" = --all ]; then
  # every registered project folder and recorded board folder that still exists, one per line like the lists
  nl='
'; P="$(dirname "$0")/project.sh"
  # a board recorded twice (as a project's board/ and with project.sh board) is read once
  set -f; IFS=$nl; set -- $({ sh "$P" list | sed -n 's/^ok	\(.*\)$/\1\/board/p'; sh "$P" boards | sed -n 's/^ok	//p'; } | awk '!seen[$0]++'); unset IFS; set +f
  [ $# -gt 0 ] || { echo "No projects yet. Run /chief-of-staff:new-project in a folder."; exit 0; }
fi
[ $# -gt 0 ] || { echo "usage: sh overview.sh <board folder>... | --all" >&2; exit 1; }
now=$(date +%s); today=$(date +%F); soon=$(date -v+7d +%F 2>/dev/null || date -d '+7 days' +%F)
for b in "$@"; do
  for f in "$b"/*.md; do [ -f "$f" ] || continue
    # mtime in seconds: BSD stat, then GNU
    m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")
    printf '%s\t%s\n' "$m" "$f"
  done
done | LC_ALL=C awk -F '\t' -v rows="$rows" -v now="$now" -v today="$today" -v soon="$soon" '
  function field(k) { return (k in V) ? V[k] : "" }
  function add(sec, line) { n[sec]++; L[sec, n[sec]] = line }
  {
    f = $2; delete V; title = ""; fm = 0; ln = 0
    while ((getline l < f) > 0) { ln++; sub(/\r$/, "", l)
      if (ln == 1 && l == "---") { fm = 1; continue }
      if (fm) { if (l == "---") { fm = 0; continue } if (match(l, /^[a-z_]+:/)) { k = substr(l, 1, RLENGTH - 1); v = substr(l, RLENGTH + 1); gsub(/\t/, " ", v); sub(/^ +/, "", v); sub(/ +$/, "", v); V[k] = v } continue }
      if (l ~ /^# /) { title = substr(l, 3); break } }
    close(f)
    if (title == "") { title = f; sub(/.*\//, "", title); sub(/\.md$/, "", title) }
    s = tolower(field("status")); p = field("projeto"); if (p == "") p = field("project"); if (p == "") p = "-"
    d = field("prazo"); if (d == "") d = field("due"); d = substr(d, 1, 10)
    if (s ~ /^(encerrado|fechado|done|delivered|closed|arquivado)$/) next
    if (rows) { gsub(/\t/, " ", title); w = field("pasta"); if (w == "") w = field("folder"); gsub(/^"|"$/, "", w)
      print (s ~ /^waiting-owner$/ ? "w" : s ~ /^(parado|paused|blocked|esperando|waiting)$/ ? "s" : "m") "\t" title "\t" p "\t" d "\t" $1 "\t" w; next }
    if (s ~ /^waiting-owner$/) add("w", title " (" p ")")
    else if (s ~ /^(parado|paused|blocked|esperando|waiting)$/) stopped[p]++
    else add("m", title " (" p ", " s ")")
    if (d ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && d <= soon) add("d", d (d < today ? " LATE " : " ") title)
    if (now - $1 < 86400) add("c", title " (" (s == "" ? "-" : s) ")")
  }
  END { if (rows) exit
    split("w|Waiting on you|d|Due in 7 days|c|Changed in 24 hours|m|Moving", S, "|")
    for (i = 1; i < 8; i += 2) { k = S[i]
      printf "%s: %d\n", S[i + 1], n[k]
      for (j = 1; j <= n[k]; j++) print "- " L[k, j] }
    t = ""; for (p in stopped) t = t (t == "" ? "" : ", ") p " " stopped[p]
    print "Stopped: " (t == "" ? "0" : t)
  }'
