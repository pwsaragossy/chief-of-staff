#!/bin/sh
# Screens: no screen is built before its design, and none reaches the owner before an independent review against
# real reference apps. The hooks (protocol.sh) call it; an agent may run "state" to see where the project stands.
#   isui    <file>                0 when the file renders a screen (stdin: the hook input, for the new text)
#   gate    <project_dir> <file>  0 the design is done (or marked not applicable); 1 it is not (prints why);
#                                 3 no design item of TRACK.md covers the file (the hooks only ask for the designer)
#   touch   <project_dir> <file>  records a change of a screen file (its mtime), for the review gate
#   changed <project_dir> <since> [<head>]  screen files changed after the file <since> (ctime), outside design/;
#                                 records them. <head> holds the commit id the turn started from
#   review  <file>                checks a review in design/reviews/: prints its verdict (pass or fail); 1 + problems
#   state   <project_dir>         0 every screen change has a passing review newer than it; 1 + why not
# A design item is a TRACK.md item with id ui-spec or a "screens:" field (path patterns of the product's screens,
# relative to the project folder; without it the item covers every screen file). It is done when closed [x] with an
# evidence file holding a "References:" section with a link (the 1-2 real apps the screens follow) and a "Library:"
# line, or marked [-] with why: (no screens here). Mockups go under design/, which the design gate never holds.
. "$(dirname "$0")/lib.sh"

cmd=$1; dir=${2:-}; [ -d "$dir" ] && dir=$(cd "$dir" && pwd -P)
IMG='png|jpe?g|webp|gif'

# isui FILE: by extension; a script or native source counts when it uses a UI framework (new text or file on disk)
isui() {
  case $1 in */node_modules/*|*/.git/*|*/dist/*|*/build/*|*/__tests__/*|*/tests/*|*/test/*|*.test.*|*.spec.*|*.stories.*) return 1 ;; esac
  case $1 in
    *.html|*.htm|*.css|*.scss|*.sass|*.less|*.jsx|*.tsx|*.vue|*.svelte|*.astro) return 0 ;;
    *.swift|*.kt|*.dart|*.js|*.mjs|*.ts) ;;
    *) return 1 ;; esac
  { cat; [ -f "$1" ] && head -c 65536 "$1"; } 2>/dev/null |
    grep -Eq 'import (SwiftUI|UIKit|AppKit)|some View|: View \{|@Composable|package:flutter|extends (StatelessWidget|StatefulWidget)|from .(react|vue|svelte|lit).|ReactDOM|innerHTML|document\.createElement|customElements\.define'
}

# block FILE WORD: the lines of the section WORD (a "Word:" line or a "## Word" heading) up to the next heading or field
# (a known field: an app named "Linear: https://..." inside the section does not end it)
block() { awk -v w="$2" 'BEGIN { w = tolower(w); F = "^[*_]*(verdict|references?|side by side|library|screens|findings|reviewing|reason|answer)[*_ ]*:" }
  { l = tolower($0); sub(/\r$/, "", l) }
  on && (l ~ /^#/ || l ~ F) { on = 0 }
  l ~ "^[#*_ ]*" w "[*_ ]*:?" { t = l; sub("^[#*_ ]*" w "[*_ ]*:?", "", t); if (t == "" || t ~ /^[ *_:]/) { on = 1; print; next } }
  on { print }' "$1"; }

# refs FILE_OR_DIR: the design evidence names a reference app with a link, and the library
# (one regular file inside the project, by a plain relative path: an empty evidence: or a folder proves nothing)
refs() { case $1 in ''|/*|../*|*/../*|*/..|./*|*/./*) echo "its evidence is not a file of the project named by a plain relative path"; return 1 ;; esac
  _f=$dir/$1
  [ -f "$_f" ] || { echo "its evidence file $1 is missing"; return 1; }
  _r=0
  block "$_f" 'references?' | grep -Eq 'https?://' ||
    { echo "its evidence ${_f#"$dir/"} has no 'References:' section with a link (the 1-2 real apps the screens follow)"; _r=1; }
  grep -Eqi '^[#*_ ]*library[*_ ]*:?' "$_f" || { echo "its evidence ${_f#"$dir/"} has no 'Library:' line (what the library holds on these screens, or none found for <terms>)"; _r=1; }
  return $_r; }

# shots REVIEW DIR ROOT: the screenshots its side by side names that exist, as absolute paths (a markdown link or a
# backticked path may hold spaces; a bare path may not)
shots() { _b=$(block "$1" 'side by side')
  { printf '%s\n' "$_b" | grep -oE "\\([^)]+\\.($IMG)\\)" | sed 's/^(//; s/)$//'
    printf '%s\n' "$_b" | grep -oE "\`[^\`]+\\.($IMG)\`" | tr -d '\`'
    printf '%s\n' "$_b" | grep -oE "[^][ ()\`\"<>|]+\\.($IMG)"; } 2>/dev/null |
  while IFS= read -r _i; do for _c in "$_i" "$2/$_i" "$3/$_i"; do
    case $_c in (/*) [ -s "$_c" ] && { printf '%s\n' "$_c"; break; } ;; esac; done; done; }

log() { cos_cache screens "$dir"; }
mtime() { date -r "$1" +%s 2>/dev/null || date +%s; }

case $cmd in
  isui) isui "$2" ;;
  gate)
    rel=${3#"$dir/"}; [ -f "$dir/TRACK.md" ] || exit 3
    case $rel in */../*|../*|*/./*|./*) ;; design/*) exit 0 ;; esac   # design/../app.html is not a mockup
    US=$(printf '\037'); hit=; why=
    items=$(awk '{ sub(/\r$/, "") } /^- \[.\] / {
        m = substr($0, 4, 1); k = split(substr($0, 7), f, / \| /); id = f[1]; gsub(/^ +| +$/, "", id); ev = sc = ""; s = 0
        for (j = 2; j <= k; j++) { v = f[j]; gsub(/^ +| +$|`/, "", v)
          if (v ~ /^evidence:/) { ev = v; sub(/^evidence: */, "", ev) }
          else if (v ~ /^screens:/) { sc = v; sub(/^screens: */, "", sc); s = 1 } }
        if (id == "ui-spec" || s) print id "\037" m "\037" ev "\037" sc }' "$dir/TRACK.md")
    [ -n "$items" ] || exit 3
    while IFS=$US read -r id m ev sc; do
      if [ -n "$sc" ]; then in=; set -f
        for p in $(printf '%s' "$sc" | tr ',' ' '); do case $rel in $p) in=1 ;; esac; done; set +f
        [ -n "$in" ] || continue; fi
      hit=1
      case $m in
        -) ;;
        x) w=$(refs "$ev") || why="${why}$id is closed, but $(printf '%s' "$w" | tr '\n' ';' | sed 's/;$//; s/;/; and /g'). "  ;;
        *) why="${why}the design item $id in TRACK.md is open. " ;;
      esac
    done <<EOF
$items
EOF
    [ -n "$hit" ] || exit 3
    [ -z "$why" ] && exit 0
    printf '%s\n' "${why% }"; exit 1 ;;
  touch)
    [ -n "$dir" ] && [ -n "${3:-}" ] || exit 1
    l=$(log); mkdir -p "${l%/*}"; printf '%s\t%s\n' "$(mtime "$3")" "$3" >> "$l"
    [ "$(wc -l < "$l")" -gt 400 ] && { tail -n 200 "$l" > "$l.$$" && mv -f "$l.$$" "$l"; }
    exit 0 ;;
  changed)
    [ -f "${3:-}" ] || exit 0
    # a file put back as it was when the turn started (git checkout) is no change: only while HEAD is still the commit
    # the turn started from (a commit made this turn can carry the new screen code)
    h0=$(cat "${4:-/nonexistent}" 2>/dev/null); hn=$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)
    find "$dir" \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .venv -o -name venv -o \
      -name __pycache__ -o -name .next -o -name Pods -o -name DerivedData -o -path "$dir/design" -o -name tests -o -name test \) -prune -o \
      -type f -cnewer "$3" \( -name '*.html' -o -name '*.htm' -o -name '*.css' -o -name '*.scss' -o -name '*.sass' -o -name '*.less' \
      -o -name '*.jsx' -o -name '*.tsx' -o -name '*.vue' -o -name '*.svelte' -o -name '*.astro' -o -name '*.swift' -o -name '*.kt' \
      -o -name '*.dart' -o -name '*.js' -o -name '*.mjs' -o -name '*.ts' \) -print 2>/dev/null | head -n 200 |
    while IFS= read -r f; do isui "$f" </dev/null || continue
      [ -n "$h0" ] && [ "$h0" = "$hn" ] && git -C "$dir" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 &&
        git -C "$dir" diff --quiet HEAD -- "$f" 2>/dev/null && continue
      printf '%s\n' "$f"; sh "$0" touch "$dir" "$f"; done ;;
  review)
    f=$2; [ -f "$f" ] || { echo "no such file"; exit 1; }; d=${f%/*}; root=${d%/design/reviews*}; p=
    v=$(sed -n 's/\r$//; s/^[#*_ ]*[Vv]erdict[*_ ]*: *[*_]*\([A-Za-z]*\).*/\1/p' "$f" | head -n 1 | tr 'A-Z' 'a-z')
    case $v in pass|fail) ;; *) p="$p- a 'Verdict: pass' or 'Verdict: fail' line
" ;; esac
    grep -qi '^void:' "$f" && p="$p- it is void: $(grep -i '^void:' "$f" | head -n 1 | cut -c7-)
"
    block "$f" 'references?' | grep -Eq 'https?://' || p="$p- a 'References:' section with the link of each reference app the designer named
"
    # the side by side: at least two saved screenshots that exist (this screen and the reference), by path
    # distinct by content: one picture named twice, or two empty files, is no comparison
    n=$(shots "$f" "$d" "$root" | while IFS= read -r i; do cksum < "$i"; done | sort -u | wc -l | tr -d ' ')
    [ "${n:-0}" -ge 2 ] || p="$p- a 'Side by side:' section naming at least two different saved screenshots that exist: this screen and the reference app (found $n)
"
    [ -z "$p" ] && { echo "$v"; exit 0; }
    printf '%s' "$p"; exit 1 ;;
  state)
    l=$(log); last=0; lf=
    [ -f "$l" ] && { last=$(awk -F '\t' '$1 + 0 >= m { m = $1 + 0; f = $2 } END { print m + 0 }' "$l"); lf=$(awk -F '\t' '$1 + 0 >= m { m = $1 + 0; f = $2 } END { print f }' "$l"); }
    r=$(ls -t "$dir/design/reviews/"*.md 2>/dev/null | head -n 1)
    if [ -z "$r" ]; then
      [ "$last" -gt 0 ] || exit 0
      echo "${lf#"$dir/"} changed and design/reviews/ holds no review of the screens"; exit 1; fi
    rel=${r#"$dir/"}
    v=$(sh "$0" review "$r") || { echo "the newest review, $rel, is not complete:"; printf '%s\n' "$v"; exit 1; }
    [ "$v" = fail ] && { echo "the newest review, $rel, failed: fix the screen and review it again"; exit 1; }
    # the review is newer than every change (same second counts as after), and one of its screenshots, this screen's
    # own, was taken after the last change: a review of an older picture does not clear a newer screen
    if [ "$last" -lt "$(mtime "$r")" ]; then
      d=${r%/*}; fresh=$(shots "$r" "$d" "$dir" | while IFS= read -r i; do [ "$(mtime "$i")" -ge "$last" ] && echo y; done | head -n 1)
      [ -n "$fresh" ] && exit 0
      echo "the newest passing review, $rel, has no screenshot taken after the last change of ${lf#"$dir/"}"; exit 1; fi
    echo "${lf#"$dir/"} changed after the newest passing review, $rel"; exit 1 ;;
  *) echo "usage: screens.sh isui|gate|touch|changed|review|state ..." >&2; exit 2 ;;
esac
