#!/bin/sh
# The library: the company's second brain. One note per file in <library>/notes/, readable in Obsidian;
# links are inline [[id]]; index, backlinks and graph are computed on the fly (library.awk), never stored.
# Usage (inside a workspace):
#   library.sh search <terms...>                best notes first, with their neighbours
#   library.sh new <type> <origin> <title...>   make a note skeleton; prints its path and the similar notes
#   library.sh similar <title...>               active notes whose title shares 2+ words with this one
#   library.sh check <file...>                  the save gate for these notes (exit 2 on problems)
#   library.sh gate <file...>                   the turn-end gate: also links, Compared: and retirements
#   library.sh doctor [--count]                 every problem in the library, and duplicates never compared
#   library.sh retire <old> <new|-> <reason>    retire the worse note; <new> = the note that replaces or merges it
#   library.sh backlinks <id>                   notes that link to <id>
#   library.sh graph                            tab-separated nodes and edges, for the panel
#   library.sh brief [project]                  counts for the session briefing
#   library.sh where                            the library folder and whether it is reachable
#   library.sh offload <folder> [--remote <git-url>]   move the library (central session only)
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

die() { echo "library: $*" >&2; exit 1; }
usage() { sed -n '4,16p' "$0" | sed 's/^# //' >&2; exit 1; }
root=$(cos_root "${CLAUDE_PROJECT_DIR:-$PWD}") || die "not inside a chief-of-staff workspace"
lib=$(cos_lib "$root"); state=$?
today=$(date +%F)
idre='^[a-z0-9][a-z0-9-]\{1,79\}$'

offline() {
  case $state in
    1) echo "Library offline: $lib is not reachable (external disk unplugged?). Work continues without it; plug it in, or move the library back with library.sh offload $root/knowledge from central." ;;
    2) echo "Library error: $lib exists but has no .library-id file (an empty mount point, or a wrong path in $root/.chief-of-staff). Do not write notes there." ;;
    3) echo "Library error: the library: line in $root/.chief-of-staff must be one absolute path." ;;
  esac
}
need_online() { [ $state = 0 ] || { offline >&2; exit 1; }; }
notes() { ls "$lib/notes/"*.md >/dev/null 2>&1; }
run() { # MODE [awk -v assignments...] -- runs library.awk over every note
  m=$1; shift
  notes || { [ "$m" = brief ] && echo "Library: empty (0 notes)."; return 0; }
  LC_ALL=C TODAY=$today awk -v MODE="$m" -v TODAY="$today" "$@" -f "$here/library.awk" "$lib/notes/"*.md
}
translit() { # fixed table, byte for byte, so ids do not depend on iconv or the locale
  LC_ALL=C sed 's/Á/a/g; s/À/a/g; s/Â/a/g; s/Ã/a/g; s/Ä/a/g; s/á/a/g; s/à/a/g; s/â/a/g; s/ã/a/g; s/ä/a/g; s/É/e/g; s/È/e/g; s/Ê/e/g; s/Ë/e/g; s/é/e/g; s/è/e/g; s/ê/e/g; s/ë/e/g; s/Í/i/g; s/Ì/i/g; s/Î/i/g; s/Ï/i/g; s/í/i/g; s/ì/i/g; s/î/i/g; s/ï/i/g; s/Ó/o/g; s/Ò/o/g; s/Ô/o/g; s/Õ/o/g; s/Ö/o/g; s/ó/o/g; s/ò/o/g; s/ô/o/g; s/õ/o/g; s/ö/o/g; s/Ú/u/g; s/Ù/u/g; s/Û/u/g; s/Ü/u/g; s/ú/u/g; s/ù/u/g; s/û/u/g; s/ü/u/g; s/Ç/c/g; s/ç/c/g; s/Ñ/n/g; s/ñ/n/g'
}
plus6m() { date -v+6m +%F 2>/dev/null || date -d '+6 months' +%F; }

case ${1:-} in
  search)
    [ $# -ge 2 ] || usage; shift; a=
    [ "$1" = --auto ] && { a=1; shift; }
    [ $state = 0 ] || { offline; exit 0; }
    Q=$* run search -v AUTO="$a" ;;
  similar)
    [ $# -ge 2 ] || usage; shift; need_online
    Q=$* run similar ;;
  new)
    [ $# -ge 4 ] || usage; need_online
    type=$2 origin=$3; shift 3; title=$(printf '%s' "$*" | tr -d '\000-\037' | tr '"' "'" | cut -c1-200)
    case $type in finding|decision|howto|option|topic) ;; *) die "type must be finding, decision, howto, option or topic" ;; esac
    printf '%s' "$origin" | grep -Eq '^(central|research:[a-z0-9][a-z0-9-]*|[a-z0-9][a-z0-9-]*)$' || die "origin must be the project slug, research:<slug> or central"
    slug=$(printf '%s' "$title" | translit | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//' | cut -d- -f1-6 | cut -c1-50 | sed 's/-*$//')
    [ ${#slug} -ge 2 ] || slug=note
    id=$slug-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')
    file=$lib/notes/$id.md
    rb=; case $type in finding|howto|option) rb=$(plus6m) ;; esac
    ID=$id TITLE=$title TYPE=$type ORIGIN=$origin DATE=$today RB=$rb TOKEN=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n') awk '{
        gsub(/\{\{ID\}\}/, ENVIRON["ID"]); gsub(/\{\{TYPE\}\}/, ENVIRON["TYPE"]); gsub(/\{\{ORIGIN\}\}/, ENVIRON["ORIGIN"])
        gsub(/\{\{DATE\}\}/, ENVIRON["DATE"]); gsub(/\{\{REVIEW_BY\}\}/, ENVIRON["RB"]); gsub(/\{\{TOKEN\}\}/, ENVIRON["TOKEN"])
        while ((i = index($0, "{{TITLE}}"))) $0 = substr($0, 1, i - 1) ENVIRON["TITLE"] substr($0, i + 9)
        print }' "$here/../templates/knowledge/note.md" > "$file.tmp.$$" || die "cannot write in $lib/notes"
    ( set -C; cat "$file.tmp.$$" > "$file" ) 2>/dev/null || { rm -f "$file.tmp.$$"; die "$file exists: run new again"; }
    rm -f "$file.tmp.$$"
    echo "Created $file"
    echo "Fill every {{...}}, keep the claim in your own words, and link related notes inline as [[id]]."
    sim=$(Q=$title run similar | grep -v "^\[\[$id\]\]")
    if [ -n "$sim" ]; then echo "Similar notes: name each on the Compared: line (replaces, merged, or coexists (reason)):"; printf '%s\n' "$sim"
    else echo "No similar note: write 'Compared: none similar'."; fi ;;
  check)
    [ $# -ge 2 ] || usage; shift
    rc=0
    for f in "$@"; do
      [ -f "$f" ] || continue
      [ -s "$f" ] || { echo "notes/$(basename "$f"): is empty: write the note (library.sh new makes a skeleton)"; rc=2; continue; }
      LC_ALL=C awk -v MODE=check -v TODAY="$today" -f "$here/library.awk" "$f" || rc=2
    done
    exit $rc ;;
  gate)
    [ $# -ge 2 ] || usage; shift; [ $state = 0 ] || exit 0
    for f in "$@"; do [ -f "$f" ] && [ ! -s "$f" ] && { echo "notes/$(basename "$f"): is empty: write the note or delete the file"; exit 2; }; done
    T=$(printf '%s\n' "$@") ; TARGETS=$T run gate ;;
  doctor)
    [ $state = 0 ] || { offline; exit 0; }
    if [ "${2:-}" = --count ]; then run doctor -v COUNT=1; else run doctor; fi
    ls -A "$lib/notes" 2>/dev/null | grep -q '\.icloud$' && echo "warning: some notes are iCloud placeholders not downloaded to this computer; checks may miss them (Finder: Download Now)"
    exit 0 ;;
  retire)
    [ $# -ge 4 ] || usage; need_online
    old=$2 new=$3; shift 3; reason=$(printf '%s' "$*" | tr -d '\000-\037' | tr '"' "'" | cut -c1-200)
    printf '%s\n' "$old" | grep -q "$idre" || die "bad id: $old"
    [ -f "$lib/notes/$old.md" ] || die "no note $old in $lib/notes"
    if [ "$new" != - ]; then
      printf '%s\n' "$new" | grep -q "$idre" || die "bad id: $new"
      [ -f "$lib/notes/$new.md" ] || die "no note $new: write the better (or merged) note first"
      fm_set "$lib/notes/$old.md" superseded_by "$new"
    fi
    fm_set "$lib/notes/$old.md" status retired
    fm_set "$lib/notes/$old.md" retired_reason "\"$reason\""
    fm_set "$lib/notes/$old.md" updated "$today"
    echo "Retired [[$old]]$( [ "$new" = - ] || echo " (replaced by [[$new]])" ): it stays in place, so links still resolve; search shows it only as replaced." ;;
  backlinks)
    [ $# -eq 2 ] || usage; need_online; run backlinks -v ID="$2" ;;
  graph) need_online; run graph ;;
  brief) [ $state = 0 ] || { offline; exit 0; }; run brief -v PROJ="${2:-}" ;;
  where) echo "$lib"; offline; exit $state ;;
  offload) sh "$here/offload.sh" "$@" ;;
  *) usage ;;
esac
