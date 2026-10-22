#!/bin/sh
# Track gates. A project's TRACK.md lists the minimum deliverables per stage (templates/tracks/).
#   check  <project_dir>  one problem per line, exit 1 if any (the Stop hook blocks on these)
#   brief  <project_dir>  one line for the session briefing: stage, what is open now, what waits
#   status <project_dir>  "stage<US>stages<US>closed<US>total" for health.sh
# Item line: - [ ] id | deliverable | card: role | needs: a, b | evidence: path   ([x] done, [-] n/a + why:)
# No TRACK.md: silent, exit 0 (old projects keep working).
. "$(dirname "$0")/lib.sh"

cmd=$1; dir=$2; t="$dir/TRACK.md"
if [ ! -f "$t" ]; then # a project made from the template names TRACK.md in its CLAUDE.md: deleting the file must not open the gate
  [ "$cmd" = check ] && grep -qs 'TRACK.md' "$dir/CLAUDE.md" 2>/dev/null && { echo "TRACK.md is missing, but this project's CLAUDE.md requires it: restore it (git) instead of deleting it"; exit 1; }
  exit 0
fi
US=$(printf '\037')
rawstage=$(fm_get "$t" stage); cur=$rawstage; case $cur in ''|*[!0-9]*) cur=1 ;; esac
state=$(fm_get "$dir/STATE.md" status | tr 'A-Z' 'a-z')

# S<US>stage<US>name  and  I<US>stage<US>mark<US>id<US>card<US>needs<US>evidence<US>why
rows=$(awk '
  { sub(/\r$/, "") }
  /^## Stage [0-9]+:/ { s = $3; sub(/:$/, "", s); n = $0; sub(/^## Stage [0-9]+: */, "", n); print "S\037" s "\037" n; next }
  /^- \[.\] / {
    m = substr($0, 4, 1); k = split(substr($0, 7), f, / \| /)
    id = f[1]; gsub(/^ +| +$/, "", id); card = needs = ev = why = ""
    for (j = 2; j <= k; j++) { v = f[j]; gsub(/^ +| +$|`/, "", v)
      if (v ~ /^card:/) { card = v; sub(/^card: */, "", card) }
      else if (v ~ /^needs:/) { needs = v; sub(/^needs: */, "", needs) }
      else if (v ~ /^evidence:/) { ev = v; sub(/^evidence: */, "", ev) }
      else if (v ~ /^why:/) { why = v; sub(/^why: */, "", why) } }
    print "I\037" (s == "" ? 0 : s) "\037" m "\037" id "\037" card "\037" needs "\037" ev "\037" why
  }' "$t")

mark_of() { printf '%s\n' "$rows" | awk -F "$US" -v i="$1" '$1 == "I" && $4 == i { print ($3 == " " ? "o" : $3); exit }'; }
open_needs() { # ids in $1 (comma list) that are not closed
  for n in $(printf '%s' "$1" | tr ',' ' '); do
    [ "$n" = - ] && continue
    case $(mark_of "$n") in x|-) ;; *) printf '%s, ' "$n" ;; esac
  done
}
stages=$(printf '%s\n' "$rows" | grep -c "^S$US")
sname=$(printf '%s\n' "$rows" | awk -F "$US" -v c="$cur" '$1 == "S" && $2 == c { print $3; exit }')

check() {
  case $rawstage in ''|*[!0-9]*|0) echo "stage: in the TRACK.md front matter must be a whole number from 1 to $stages (found '$rawstage')" ;; esac
  [ "$cur" -gt "$stages" ] && echo "stage: $cur in TRACK.md, but the track has $stages stages"
  # lines that look like an item, a stage or a comment but would not be parsed: they would silently drop out of the gate
  awk '{ sub(/\r$/, "") }
    /<!--|-->/ { print "line " NR ": HTML comments hide items from the gate; delete the item with a [-] and why: instead"; next }
    /^[ \t]*[-*+][ \t]*\[.?\]/ && !/^- \[.\] / { print "line " NR ": not a valid item (write exactly: - [ ] id | deliverable | card: role | needs: ids | evidence:)" }
    /^#+[ \t]*[Ss]tage/ && !/^## Stage [0-9]+:/ { print "line " NR ": not a valid stage header (write exactly: ## Stage N: Name)" }' "$t"
  # structure: sequential stages, unique ids, a role on every item, needs that exist, point back and have no loop, one proof file per item
  printf '%s\n' "$rows" | awk -F "$US" '
    $1 == "S" { ns++; if ($2 != ns) print "stage headers must be numbered 1, 2, 3 in order: found Stage " $2 " where Stage " ns " was expected" }
    $1 == "I" { n++; id[n] = $4; nd[n] = $6
      if ($2 == 0) print "item " $4 " is before the first stage header"
      if ($4 !~ /^[A-Za-z0-9_-]+$/) print "item id \"" $4 "\" must use only letters, digits, - and _"
      else if ($4 in at) print "item id " $4 " appears twice"
      else { at[$4] = n; st[$4] = $2 }
      if ($5 == "") print $4 " has no card: (the role that makes it)"
      if ($3 == "x" && $7 != "") { if ($7 in ev) print $4 " and " ev[$7] " share the proof file " $7 ": each item needs its own"; else ev[$7] = $4 } }
    END { for (i = 1; i <= n; i++) { k = split(nd[i], a, /, */)
        for (j = 1; j <= k; j++) { m = a[j]; if (m == "" || m == "-") continue
          if (m == id[i]) print id[i] " needs itself"
          else if (!(m in at)) print id[i] " needs " m ", which is not an item of the track"
          else if (st[m] > st[id[i]]) print id[i] " (stage " st[id[i]] ") needs " m " from the later stage " st[m] ": needs must point back" } }
      do { ch = 0; for (i = 1; i <= n; i++) if (!dn[i]) { ok = 1; k = split(nd[i], a, /, */)
          for (j = 1; j <= k; j++) if ((a[j] in at) && !dn[at[a[j]]]) ok = 0
          if (ok) { dn[i] = 1; ch = 1 } } } while (ch)
      for (i = 1; i <= n; i++) if (!dn[i]) l = l (l ? ", " : "") id[i]
      if (l != "") print "these items wait on each other in a loop, so none can close: " l }'
  # every stage needs a reviewer item, so no stage passes on the word of the agent that did the work
  printf '%s\n' "$rows" | awk -F "$US" '$1 == "S" { s[$2] = 1 } $1 == "I" && $5 == "reviewer" { r[$2] = 1 }
    END { for (k in s) if (!(k in r)) print "stage " k " has no item with card: reviewer" }'
  printf '%s\n' "$rows" | while IFS=$US read -r kind s m id card needs ev why; do
    [ "$kind" = I ] || continue
    case $m in
      ' ') [ "$s" -lt "$cur" ] && echo "stage $s is behind the current stage $cur, but $id is open"
           [ "$state" = done ] && echo "STATE.md status is done, but $id is open" ;;
      x)   if [ -z "$ev" ]; then echo "$id is marked done without evidence: (the path of its proof file)"
           else case $ev in
             /*|*..*|TRACK.md|STATE.md|CLAUDE.md|./TRACK.md|./STATE.md|./CLAUDE.md) echo "$id: evidence $ev must be a proof file inside the project folder, not a control file or a path outside" ;;
             *) if [ ! -e "$dir/$ev" ] && [ -e "$dir/${ev%% *}" ]; then echo "$id: evidence must be the file path alone (found \"$ev\"); write evidence: ${ev%% *} and put any note in that file"
                elif [ ! -e "$dir/$ev" ]; then echo "$id is marked done, but its evidence $ev does not exist"
                elif [ -L "$dir/$ev" ] || [ ! -f "$dir/$ev" ]; then echo "$id: evidence $ev must be a regular file, not a folder or a link"
                elif [ ! -s "$dir/$ev" ]; then echo "$id: evidence $ev is empty"; fi ;;
           esac; fi
           for n in $(printf '%s' "$needs" | tr ',' ' '); do
             [ "$n" = - ] && continue
             case $(mark_of "$n") in
               x|-) ;;
               '') ;;
               *) echo "$id is marked done, but it needs $n, which is open" ;;
             esac
           done ;;
      -)   [ -n "$why" ] || echo "$id is marked not applicable without why: (the reason)"
           [ "$card" = reviewer ] && echo "$id is a reviewer item and cannot be marked not applicable: the independent reviewer closes it with a verdict file that judges every [-] of the stage" ;;
      *)   echo "$id has the mark [$m]: use [ ] open, [x] done or [-] not applicable" ;;
    esac
  done
}

case $cmd in
  check)
    p=$(check); [ -z "$p" ] && exit 0
    printf '%s\n' "$p"; exit 1 ;;
  status)
    printf '%s\n' "$rows" | awk -F "$US" -v c="$cur" -v n="$stages" '
      $1 == "I" { t++; if ($3 == "x" || $3 == "-") d++ } END { printf "%s\037%s\037%d\037%d\n", c, n, d, t }' ;;
  brief)
    now=; wait=
    while IFS=$US read -r kind s m id card needs ev why; do
      [ "$kind" = I ] && [ "$s" = "$cur" ] && [ "$m" = ' ' ] || continue
      o=$(open_needs "$needs")
      if [ -z "$o" ]; then now="$now${now:+, }$id ($card)"; else wait="$wait${wait:+; }$id needs ${o%, }"; fi
    done <<EOF
$rows
EOF
    if [ -z "$now" ]; then now="none, the stage can pass its gate"; [ -n "$wait" ] && now="nothing until the prerequisites below are closed"; fi
    printf 'Track %s, stage %s of %s (%s). Open now: %s.%s\n' "$(fm_get "$t" track)" "$cur" "$stages" "$sname" \
      "$now" "${wait:+ Waiting on prerequisites: $wait.}" ;;
  *) echo "usage: track.sh check|brief|status <project_dir>" >&2; exit 2 ;;
esac
