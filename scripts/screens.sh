#!/bin/sh
# Screens: no screen is built before its design, and none reaches the owner before an independent review against
# real reference apps. The hooks (protocol.sh) call it; an agent may run "state" to see where the project stands.
#   isui    <file>                0 when the file renders a screen (stdin: the hook input, for the new text)
#   kind    <file>                prints video (a composition or a rendered video), screen, or nothing (stdin as isui)
#   gate    <project_dir> <file> [<kind>]  0 the design is done (or marked not applicable); 1 it is not (prints why);
#                                 3 neither a design system nor a design item of TRACK.md covers the file (the hooks
#                                 only ask for the designer)
#   system  <project_dir> <kind>  0 every piece of design/SYSTEM.md the kind needs holds the owner's OK on its current
#                                 text; 1 + why not; 3 the project keeps no design system
#   piece   <project_dir> <piece> prints the sum the owner's OK freezes (the piece's text and its options file) when
#                                 the piece is ready for the owner's pick; 1 + why not (track.sh ok design:<piece>)
#   options <file>                checks a proposal in design/options/: 2-3 references, each with link, date, what we take
#   optreview <file>              checks a reference review in design/reviews/options/: prints its verdict; 1 + problems
#   unreviewed <project_dir>      the links of proposals with no passing reference review newer than them
#   touch   <project_dir> <file>  records a change of a screen file (its mtime), for the review gate
#   changed <project_dir> <since> [<head>]  screen files changed after the file <since> (ctime), outside design/;
#                                 records them. <head> holds the commit id the turn started from
#   review  <file>                checks a review in design/reviews/: prints its verdict (pass or fail); 1 + problems
#   state   <project_dir>         0 every screen change has a passing review newer than it; 1 + why not
# A design item is a TRACK.md item with id ui-spec or a "screens:" field (path patterns of the product's screens,
# relative to the project folder; without it the item covers every screen file). It is done when closed [x] with an
# evidence file holding a "References:" section with a link (the 1-2 real apps the screens follow) and a "Library:"
# line, or marked [-] with why: (no screens here). Mockups go under design/, which the design gate never holds.
# An item with a "video:" field (path patterns) is the same for video files.
# The design system (design/SYSTEM.md, from templates/design/SYSTEM.md) is the owner's, piece by piece: "## <Piece>"
# sections with For: (screens, video), Status: (open, chosen, not applicable), Options:, Pick:, Why:. A piece closes
# only with the owner's OK, recorded by the coordinator (track.sh ok <project> design:<piece> <words>, which the owner
# approves), and that OK freezes the piece's text up to its "### Applied" part and its options file: any later change
# needs a new OK. Nobody else picks between the references.
. "$(dirname "$0")/lib.sh"

cmd=$1; dir=${2:-}; [ -d "$dir" ] && dir=$(cd "$dir" && pwd -P)
IMG='png|jpe?g|webp|gif'
SYS=design/SYSTEM.md
TK="$(dirname "$0")/track.sh"
US=$(printf '\037')
# a reference is at most this many months older than the research that found it (the owner's setting, else 6)
months() { _m=$(sed -n 's/^refs-max-months: *\([0-9][0-9]*\) *$/\1/p' "$1/.chief-of-staff" 2>/dev/null | head -n 1); echo "${_m:-6}"; }

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

# kindof FILE: video (a composition: HyperFrames, Remotion, Motion Canvas; or a rendered video), screen, or nothing
# (stdin: the new text, as isui)
kindof() {
  case $1 in */node_modules/*|*/.git/*|*/__tests__/*|*/tests/*|*/test/*|*.test.*|*.spec.*|*.stories.*) cat >/dev/null; return 1 ;; esac
  case $(printf '%s' "$1" | tr 'A-Z' 'a-z') in *.mp4|*.mov|*.webm|*.m4v|*.mkv) cat >/dev/null; echo video; return 0 ;; esac
  _t=$({ cat; [ -f "$1" ] && head -c 65536 "$1"; } 2>/dev/null)
  case $1 in *.html|*.htm|*.jsx|*.tsx|*.js|*.mjs|*.ts)
    printf '%s' "$_t" | grep -Eq 'data-composition-id|__timelines|from .remotion.|@remotion/|@motion-canvas/|<Composition[ >]' && { echo video; return 0; } ;; esac
  printf '%s' "$_t" | isui "$1" && { echo screen; return 0; }
  return 1; }

# block FILE WORD: the lines of the section WORD (a "Word:" line or a "## Word" heading) up to the next heading or field
# (a known field: an app named "Linear: https://..." inside the section does not end it)
block() { awk -v w="$2" 'BEGIN { w = tolower(w); F = "^[*_]*(verdict|references?|side by side|library|screens|findings|reviewing|reason|answer|options|links checked|piece|researched|searches)[*_ ]*:" }
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

# The design system. secs FILE: one line per "## " piece: id US for US status US options US pick US why (the fields
# above the piece's "### Applied" part, where the specialists write what they derive from the pick)
pid() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-*//; s/-*$//'; }
AWKID='function id(s) { s = tolower(s); gsub(/[^a-z0-9]+/, "-", s); gsub(/^-+|-+$/, "", s); return s }'
secs() { awk "$AWKID"'
  function val(l) { sub(/^[^:]*: */, "", l); gsub(/[`*]/, "", l); sub(/ +$/, "", l); return l }
  function out() { if (n != "") print n "\037" f "\037" st "\037" o "\037" p "\037" w }
  { sub(/\r$/, ""); l = $0; sub(/^[*_ -]+/, "", l); ll = tolower(l) }
  /^## / { out(); n = id(substr($0, 4)); f = st = o = p = w = ""; ap = 0; next }
  /^# / { out(); n = ""; next }
  n == "" { next }
  /^### *[Aa]pplied/ { ap = 1; next }
  ap { next }
  ll ~ /^for[*_ ]*:/ { f = tolower(val(l)); next }
  ll ~ /^status[*_ ]*:/ { st = tolower(val(l)); next }
  ll ~ /^options[*_ ]*:/ { o = val(l); next }
  ll ~ /^pick[*_ ]*:/ { p = val(l); next }
  ll ~ /^why[*_ ]*:/ { w = val(l); next }
  END { out() }' "$1"; }
# ptext FILE PIECE: the piece's text the owner's OK freezes (its heading up to "### Applied" or the next piece)
ptext() { awk -v want="$2" "$AWKID"'{ sub(/\r$/, "") } /^## / { on = (id(substr($0, 4)) == want); ap = 0 } /^# / { on = 0 }
  on && /^### *[Aa]pplied/ { ap = 1 } on && !ap { print }' "$1"; }
psum() { { ptext "$dir/$SYS" "$1"; printf '\037options\n'; [ -n "$2" ] && cat "$dir/$2" 2>/dev/null; } | cos_hsum; }
# okpath REL: a proposal named by a plain relative path in design/options/
okpath() { case $1 in design/options/*.md) case $1 in *..*|*/./*|*//*|*' '*|*'	'*) return 1 ;; esac; return 0 ;; esac; return 1; }
# links FILE: the Link: address of each option of a proposal, in order
links() { awk '{ sub(/\r$/, ""); t = $0; sub(/^[*_ -]+/, "", t); l = tolower(t) } tolower($0) ~ /^##+ *option/ { k++ }
  k > 0 && l ~ /^link[*_ ]*:/ && match(t, /https?:\/\/[^] )>|`"]+/) { print substr(t, RSTART, RLENGTH) }' "$1"; }
D2N='function d2n(s, a) { if (s !~ /^[0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]$/) return -1; split(s, a, "-"); return ((a[1] * 12) + a[2] - 1) * 100 + a[3] }'
# optcheck FILE: a proposal holds 2-3 options from fresh web research, each with its exact link, a date inside the window
# (at most N months before the research), and what this project takes from it
optcheck() { _root=${1%/design/options/*}; awk -v N="$(months "$_root")" -v today="$(date +%F)" "$D2N"'
  function val(l) { sub(/^[^:]*: */, "", l); gsub(/[`*_]/, "", l); return l }
  { sub(/\r$/, ""); l = $0; t = l; sub(/^[*_ -]+/, "", t); ll = tolower(t) }
  ll ~ /^void:/ { vd = 1 }
  tolower(l) ~ /^##+ *option/ { k++; sr = 0; next }
  /^#/ { sr = 0 }
  k == 0 && ll ~ /^piece[*_ ]*:/ { pc = 1 }
  k == 0 && ll ~ /^researched[*_ ]*:/ { r = val(t); sub(/^ */, "", r); sub(/[^0-9-].*/, "", r); rd = r }
  k == 0 && ll ~ /^searches[*_ ]*:/ { sr = 1; if (val(t) ~ /[A-Za-z0-9]/) ns++; next }
  sr && l ~ /^[ ]*([-*+]|[0-9]+[.)]) / && l ~ /[A-Za-z0-9]/ { ns++; next }
  sr && ll ~ /^[a-z ]+:/ { sr = 0 }
  k > 0 && ll ~ /^link[*_ ]*:/ { nl[k]++; if (match(t, /https?:\/\/[^] )>|`"]+/)) ln[k] = substr(t, RSTART, RLENGTH) }
  k > 0 && ll ~ /^date[*_ ]*:/ { d = val(t); sub(/^ */, "", d); sub(/[^0-9-].*/, "", d); dt[k] = d }
  k > 0 && ll ~ /^what we take[*_ ]*:/ { if (val(t) ~ /[A-Za-z]/) tk[k] = 1 }
  END { p = ""; rn = d2n(rd); tn = d2n(today)
    if (vd) p = p "- it is void: research again on the web and write it anew\n"
    if (!pc) p = p "- a Piece: line (the piece of the design system it proposes)\n"
    if (rn < 0) p = p "- a Researched: YYYY-MM-DD line (the day the web research ran)\n"
    else if (rn > tn) p = p "- Researched: " rd " is in the future\n"
    if (ns < 1) p = p "- a Searches: section listing the web searches run for it (fresh research of what the top of the market shipped in the last months; the library and memory never replace it)\n"
    if (k < 2 || k > 3) p = p "- 2 or 3 sections \"## Option <letter>: <name>\" (found " k + 0 ")\n"
    for (i = 1; i <= k; i++) {
      if (nl[i] != 1 || ln[i] == "") p = p "- option " i ": one Link: line with the exact address (the component page, the app screen, the video at its timestamp)\n"
      else if (seen[ln[i]]++) p = p "- option " i ": its link repeats another option\n"
      dn = d2n(dt[i])
      if (dn < 0) p = p "- option " i ": a Date: YYYY-MM-DD line (when the work was published or last updated)\n"
      else if (rn >= 0 && dn > rn) p = p "- option " i ": dated " dt[i] ", after the research (" rd ")\n"
      else if (rn >= 0 && dn < rn - N * 100) p = p "- option " i ": dated " dt[i] ", more than " N " months before the research (" rd "): find what the top of the market shipped recently\n"
      if (!tk[i]) p = p "- option " i ": a What we take: line (what this project takes from it)\n" }
    printf "%s", p; exit (p != "") }' "$1"; }
# optof REVIEW: the proposal a reference review names on its Options: line
optof() { sed -n 's/\r$//; s/^[#*_ -]*[Oo]ptions[*_ ]*: *//p' "$1" | head -n 1 | tr -d '`*' | sed 's/ *$//'; }
# newrev REL: the newest reference review of the proposal REL
newrev() { ls -t "$dir/design/reviews/options/"*.md 2>/dev/null | while IFS= read -r _f; do [ "$(optof "$_f")" = "$1" ] && { printf '%s\n' "$_f"; break; }; done; }
# cleared REL: the proposal's newest reference review passed and is newer than the proposal
cleared() { _rv=$(newrev "$1"); [ -n "$_rv" ] && [ "$_rv" -nt "$dir/$1" ] && [ "$(sh "$0" optreview "$_rv" 2>/dev/null)" = pass ]; }
# system KIND: every piece the kind needs (For: names it) holds the owner's OK on its current text
system() { _k=$1; [ "$_k" = screen ] && _k=screens
  if [ ! -f "$dir/$SYS" ]; then
    # a project that keeps a design system cannot open its gate by deleting the file
    if grep -qs 'design/SYSTEM.md' "$dir/CLAUDE.md" || [ -n "$(sh "$TK" owned "$dir" 2>/dev/null)" ]; then
      echo "design/SYSTEM.md is missing, but this project keeps a design system: restore it (git) instead of deleting it"; return 1; fi
    return 3; fi
  _ok=$(sh "$TK" owned "$dir" 2>/dev/null); _w=; _n=0
  while IFS=$US read -r _p _f _s _o _pk _y; do
    [ -n "$_p" ] || continue
    case $_f in *"$_k"*|*all*|*both*) ;; *) continue ;; esac
    _n=$((_n + 1))
    case $_s in chosen*|not\ applicable*|n/a*|na) ;; *) _w="$_w$_p is open; "; continue ;; esac
    _g=$(printf '%s\n' "$_ok" | awk -F '\t' -v i="design:$_p" '$1 == i { print $2 }')
    if [ -z "$_g" ]; then _w="$_w$_p has no OK from the owner; "
    elif [ "$_g" != "$(psum "$_p" "$_o")" ]; then _w="$_w$_p changed after the owner's OK; "; fi
  done <<EOF
$(secs "$dir/$SYS")
EOF
  [ $_n -gt 0 ] || _w="it names no piece For: $_k; "
  [ -z "$_w" ] && return 0
  printf 'the design system (design/SYSTEM.md) is not done for %s: %s\n' "$_k" "${_w%; }"; return 1; }

log() { cos_cache screens "$dir"; }
mtime() { date -r "$1" +%s 2>/dev/null || date +%s; }

case $cmd in
  isui) isui "$2" ;;
  gate)
    rel=${3#"$dir/"}
    case $rel in */../*|../*|*/./*|./*) ;; design/*) exit 0 ;; esac   # design/../app.html is not a mockup
    k=${4:-}; [ -n "$k" ] || k=$(kindof "$3" </dev/null) || exit 0
    hit=; why=
    # the design system first: the owner's pick, piece by piece
    sw=$(system "$k"); sr=$?
    [ $sr = 3 ] || hit=1; [ $sr = 1 ] && why="$sw. "
    items=; [ -f "$dir/TRACK.md" ] && items=$(awk '{ sub(/\r$/, "") } /^- \[.\] / {
        m = substr($0, 4, 1); k = split(substr($0, 7), f, / \| /); id = f[1]; gsub(/^ +| +$/, "", id); ev = sc = vd = ""; s = v = 0
        for (j = 2; j <= k; j++) { x = f[j]; gsub(/^ +| +$|`/, "", x)
          if (x ~ /^evidence:/) { ev = x; sub(/^evidence: */, "", ev) }
          else if (x ~ /^screens:/) { sc = x; sub(/^screens: */, "", sc); s = 1 }
          else if (x ~ /^video:/) { vd = x; sub(/^video: */, "", vd); v = 1 } }
        if (id == "ui-spec" || s || v) print id "\037" m "\037" ev "\037" sc "\037" vd "\037" s "\037" v }' "$dir/TRACK.md")
    while IFS=$US read -r id m ev sc vd s v; do
      [ -n "$id" ] || continue
      # a screen meets ui-spec and the items with screens:; a video meets the items with video:
      if [ "$k" = video ]; then [ "$v" = 1 ] || continue; sc=$vd
      else [ "$s" = 1 ] || [ "$id" = ui-spec ] || continue; fi
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
  kind) kindof "$2" ;;
  system) system "${3:-screens}" ;;
  piece)
    [ -f "$dir/$SYS" ] || { echo "design/SYSTEM.md does not exist: copy the template (templates/design/SYSTEM.md) first"; exit 1; }
    p=$(pid "${3:-}"); line=$(secs "$dir/$SYS" | awk -F "$US" -v p="$p" '$1 == p')
    [ -n "$p" ] && [ -n "$line" ] || { echo "design/SYSTEM.md has no piece '## ${3:-}'"; exit 1; }
    IFS=$US read -r _p f st o pk y <<EOF
$line
EOF
    e=
    case $st in
      chosen*)
        if ! okpath "$o"; then e="$e- an Options: line naming its proposal by a plain path, design/options/<piece>.md
"
        elif [ ! -f "$dir/$o" ]; then e="$e- its proposal $o does not exist
"
        else
          q=$(optcheck "$dir/$o") || e="$e- its proposal $o is not complete:
$q
"
          # the research is at most a month old when the owner picks
          rd=$(sed -n 's/\r$//; s/^[*_ -]*[Rr]esearched[*_ ]*: *\([0-9-]*\).*/\1/p' "$dir/$o" | head -n 1)
          awk -v rd="$rd" -v today="$(date +%F)" "$D2N"' BEGIN { r = d2n(rd); exit !(r >= 0 && r >= d2n(today) - 100) }' ||
            e="$e- its research ($rd) is more than a month old: research again before the owner picks
"
          hp=; for u in $(links "$dir/$o"); do case $pk in *"$u"*) hp=1 ;; esac; done
          [ -n "$hp" ] || e="$e- a Pick: line with the link of the option the owner picked
"
          rv=$(newrev "$o")
          if [ -z "$rv" ]; then e="$e- a reference review of $o by the independent reviewer in design/reviews/options/
"
          elif ! v=$(sh "$0" optreview "$rv"); then e="$e- its reference review ${rv#"$dir/"} is not complete:
$v
"
          elif [ "$v" != pass ]; then e="$e- its reference review ${rv#"$dir/"} failed: replace the rejected references and review again
"
          elif ! [ "$rv" -nt "$dir/$o" ]; then e="$e- $o changed after its reference review: review it again
"; fi
        fi ;;
      not\ applicable*|n/a*|na) [ -n "$y" ] || e="$e- a Why: line (why this piece does not apply)
"; o= ;;
      *) e="$e- it is open (Status: chosen once the owner picks, or not applicable with Why:)
" ;;
    esac
    [ -n "$e" ] && { printf '%s' "$e"; exit 1; }
    psum "$p" "$o" ;;
  options) optcheck "$2" ;;
  optreview)
    f=$2; [ -f "$f" ] || { echo "no such file"; exit 1; }; root=${f%/design/reviews/options/*}; e=
    v=$(sed -n 's/\r$//; s/^[#*_ ]*[Vv]erdict[*_ ]*: *[*_]*\([A-Za-z]*\).*/\1/p' "$f" | head -n 1 | tr 'A-Z' 'a-z')
    case $v in pass|fail) ;; *) e="$e- a 'Verdict: pass' or 'Verdict: fail' line
" ;; esac
    grep -qi '^void:' "$f" && e="$e- it is void: $(grep -i '^void:' "$f" | head -n 1 | cut -c7-)
"
    o=$(optof "$f")
    if ! okpath "$o" || [ ! -f "$root/$o" ]; then e="$e- an Options: line naming the proposal it checked (design/options/<piece>.md)
"
    else
      sec=$(block "$f" 'links checked')
      [ -n "$sec" ] || e="$e- a 'Links checked:' section, one line per link: the link, status <the HTTP code seen>, the date on the page, keep or reject and why
"
      for u in $(links "$root/$o"); do
        l=$(printf '%s\n' "$sec" | awk -v u="$u" '{ i = index($0, u); if (i) { c = substr($0, i + length(u), 1); if (c == "" || c ~ /[] |)>`,;]/) { print; exit } } }')
        [ -n "$l" ] || { e="$e- $u is not in Links checked: open it and give its status
"; continue; }
        lc=$(printf '%s' "$l" | tr 'A-Z' 'a-z'); sc=$(printf '%s' "$lc" | grep -Eo 'status *:? *[0-9]{3}' | grep -Eo '[0-9]{3}' | head -n 1)
        [ -n "$sc" ] || e="$e- $u: its status (the HTTP code seen when it was opened)
"
        case $lc in *reject*) r=reject ;; *keep*) r=keep ;; *) r=; e="$e- $u: keep or reject, and why
" ;; esac
        [ "$v" = pass ] && { [ "$r" = reject ] || case $sc in [23]??) false ;; *) true ;; esac; } &&
          e="$e- Verdict: pass, but $u is rejected or did not open (status ${sc:-none}): a pass keeps every link
"
      done
    fi
    [ -n "$e" ] && { printf '%s' "$e"; exit 1; }
    echo "$v" ;;
  unreviewed)
    for f in "$dir"/design/options/*.md; do [ -f "$f" ] || continue; r=${f#"$dir/"}
      cleared "$r" || links "$f"; done ;;
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
      -o -name '*.dart' -o -name '*.js' -o -name '*.mjs' -o -name '*.ts' -o -iname '*.mp4' -o -iname '*.mov' -o -iname '*.webm' \
      -o -iname '*.m4v' -o -iname '*.mkv' \) -print 2>/dev/null | head -n 200 |
    while IFS= read -r f; do kindof "$f" </dev/null >/dev/null || continue
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
  *) echo "usage: screens.sh isui|kind|gate|system|piece|options|optreview|unreviewed|touch|changed|review|state ..." >&2; exit 2 ;;
esac
