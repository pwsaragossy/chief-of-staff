#!/bin/sh
# The library: what the workspace already knows, kept as one note per item in knowledge/notes/.
# Notes link to each other (`links:`), which makes them a graph; a newer note can replace an
# older one (`supersedes:`), and the older one is deleted (git keeps it).
#
# Usage (from anywhere inside a workspace):
#   library.sh search <term> [term...]   notes that match, best first, plus the notes they link to
#   library.sh replace <old-id> <new-id> delete the old note and point every reference to the new one
. "$(dirname "$0")/lib.sh"

root=$(cos_root "${CLAUDE_PROJECT_DIR:-$PWD}") || { echo "not inside a chief-of-staff workspace" >&2; exit 1; }
dir="$root/knowledge/notes"
usage() { sed -n '6,8p' "$0" | sed 's/^# //' >&2; exit 1; }
ids() { fm_get "$1" "$2" | tr -d '[] ' | tr ',' '\n' | sed '/^$/d'; }   # list field -> one id per line

case ${1:-} in
  search)
    [ $# -ge 2 ] || usage
    shift
    hits=$(for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      n=0
      for t in "$@"; do grep -qi -- "$t" "$f" && n=$((n + 1)); done
      [ $n -gt 0 ] && printf '%s %s\n' "$n" "$f"
    done | sort -rn | head -n 10)
    if [ -z "$hits" ]; then
      echo "Library: nothing on '$*' in $dir. Research is needed; save each finding there as a note, linked to related notes."
      exit 0
    fi
    echo "Library: notes on '$*' (read them before any web search; cite them by path):"
    printf '%s\n' "$hits" | while read -r n f; do
      echo "- $f  [$n/$# terms, confidence $(fm_get "$f" confidence)]"
      grep -i -m 2 -- "$1" "$f" | cut -c1-160 | sed 's/^/    /'
      for l in $(ids "$f" links); do
        [ -f "$dir/$l.md" ] && echo "    linked: $dir/$l.md" || echo "    linked: $l (missing: fix or remove the link)"
      done
    done
    ;;
  replace)
    [ $# -eq 3 ] || usage
    old=$2 new=$3
    [ -f "$dir/$old.md" ] || { echo "no note $old" >&2; exit 1; }
    [ -f "$dir/$new.md" ] || { echo "no note $new: write the new note first" >&2; exit 1; }
    # Point every reference in the workspace (links, cards, STATE files) to the new note.
    grep -rl --include='*.md' -- "$old" "$root" 2>/dev/null | while read -r f; do
      case $f in "$dir/$old.md"|"$dir/$new.md") continue ;; esac
      sed "s/$old/$new/g" "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
    done
    links=$(ids "$dir/$new.md" links | grep -vx -- "$old" | tr '\n' ',' | sed 's/,/, /g; s/, $//')
    fm_set "$dir/$new.md" links "[$links]"
    s=$(ids "$dir/$new.md" supersedes | tr '\n' ',' | sed 's/,/, /g; s/, $//')
    fm_set "$dir/$new.md" supersedes "[${s:+$s, }$old]"
    rm "$dir/$old.md"
    echo "Replaced $old with $new: references updated, $old deleted (git history keeps it)."
    ;;
  *) usage ;;
esac
