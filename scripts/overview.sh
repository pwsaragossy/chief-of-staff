#!/bin/sh
# The whole picture as chat text, readable on a phone (Remote Control): what waits on the owner, what is due in 7
# days, what changed in 24 hours, what is moving, and how much is stopped, across every board folder given.
# Reads the cards' front matter in English or Portuguese (status/project/due/updated or status/projeto/prazo/
# atualizado). Read-only. Usage: sh overview.sh <board folder>...
[ $# -gt 0 ] || { echo "usage: sh overview.sh <board folder>..." >&2; exit 1; }
now=$(date +%s); today=$(date +%F); soon=$(date -v+7d +%F 2>/dev/null || date -d '+7 days' +%F)
for b in "$@"; do
  for f in "$b"/*.md; do [ -f "$f" ] || continue
    # mtime in seconds: BSD stat, then GNU
    m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")
    printf '%s\t%s\n' "$m" "$f"
  done
done | LC_ALL=C awk -F '\t' -v now="$now" -v today="$today" -v soon="$soon" '
  function field(k) { return (k in V) ? V[k] : "" }
  function add(sec, line) { n[sec]++; L[sec, n[sec]] = line }
  {
    f = $2; delete V; title = ""; fm = 0; ln = 0
    while ((getline l < f) > 0) { ln++; sub(/\r$/, "", l)
      if (ln == 1 && l == "---") { fm = 1; continue }
      if (fm) { if (l == "---") { fm = 0; continue } if (match(l, /^[a-z_]+:/)) { k = substr(l, 1, RLENGTH - 1); v = substr(l, RLENGTH + 1); sub(/^ +/, "", v); sub(/ +$/, "", v); V[k] = v } continue }
      if (l ~ /^# /) { title = substr(l, 3); break } }
    close(f)
    if (title == "") { title = f; sub(/.*\//, "", title); sub(/\.md$/, "", title) }
    s = tolower(field("status")); p = field("projeto"); if (p == "") p = field("project"); if (p == "") p = "-"
    d = field("prazo"); if (d == "") d = field("due"); d = substr(d, 1, 10)
    if (s ~ /^(encerrado|fechado|done|delivered|closed|arquivado)$/) next
    if (s ~ /^(aguardando-pedro|waiting-owner)$/) add("w", title " (" p ")")
    else if (s ~ /^(parado|paused|blocked|esperando|waiting)$/) stopped[p]++
    else add("m", title " (" p ", " s ")")
    if (d ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && d <= soon) add("d", d (d < today ? " LATE " : " ") title)
    if (now - $1 < 86400) add("c", title " (" (s == "" ? "-" : s) ")")
  }
  END {
    split("w|Waiting on you|d|Due in 7 days|c|Changed in 24 hours|m|Moving", S, "|")
    for (i = 1; i < 8; i += 2) { k = S[i]
      printf "%s: %d\n", S[i + 1], n[k]
      for (j = 1; j <= n[k]; j++) print "- " L[k, j] }
    t = ""; for (p in stopped) t = t (t == "" ? "" : ", ") p " " stopped[p]
    print "Stopped: " (t == "" ? "0" : t)
  }'
