#!/bin/sh
# The library: the company's second brain. One note per file in <library>/notes/, readable in Obsidian;
# links are inline [[id]]; index, backlinks and graph are computed on the fly (library.awk), never stored.
# Usage (inside a project folder):
#   library.sh search <terms...>                best notes first, with their neighbours
#   library.sh new <type> <origin> <title...>   make a note skeleton; prints its path and the similar notes
#   library.sh similar <title...>               active notes whose title shares 2+ words with this one
#   library.sh check <file...>                  the save gate for these notes (exit 2 on problems)
#   library.sh gate <file...>                   the turn-end gate: also links, Compared: and retirements
#   library.sh index                            refresh the turn-end gate's index (the prompt hook runs it in the background)
#   library.sh doctor [--count]                 every problem in the library, and duplicates never compared
#   library.sh retire <old> <new|-> <reason>    retire the worse note; <new> = the note that replaces or merges it
#   library.sh backlinks <id>                   notes that link to <id>
#   library.sh graph                            tab-separated nodes and edges, for the panel
#   library.sh brief [project]                  counts for the session briefing
#   library.sh where                            the library folder and whether it is reachable
#   library.sh libs                             every library: name, folder, state, notes, last sync, this session's (*)
# Before the command, --lib personal names the library outright (the only one: project.sh library sets where it lives).
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

die() { echo "library: $*" >&2; exit 1; }
usage() { sed -n '4,21p' "$0" | sed 's/^# //' >&2; exit 1; }
dir=${CLAUDE_PROJECT_DIR:-$PWD}
root=$(cos_root "$dir") || die "not inside a chief-of-staff project folder"
name=; [ "${1:-}" = --lib ] && { name=${2:-}; shift 2 || usage; }
mine=$(cos_libname "$root" "$dir")   # the session's own library
setlib() { name=$1; lib=$(cos_libpath "$root" "$name"); state=$?; kind=personal; }
setlib "${name:-$mine}"
today=$(date +%F)
idre='^[a-z0-9][a-z0-9-]\{1,79\}$'

offline() {
  case $state in
    1) if [ -s "$(cos_data)/library" ]; then echo "Library offline: $lib is not reachable (external disk unplugged?). Work continues without it; plug it in, or the owner picks another folder with project.sh library <folder>."
       else echo "No library yet: /chief-of-staff:setup picks where it lives. Work continues without it."; fi ;;
    2) echo "Library error: $lib exists but has no .library-id file or notes/ (an empty mount point, or a wrong path in $(cos_data)/library). Do not write notes there." ;;
    3) echo "Library error: the library path in $(cos_data)/library must be one absolute path (project.sh library <folder> sets it)." ;;
    4) echo "Library error: there is no library '$name' here (the only library is personal)." ;;
  esac
}
need_online() { [ $state = 0 ] || { offline >&2; exit 1; }; }
notes() { set -- "$lib/notes/"*.md; [ -e "$1" ]; }   # the glob alone: ls would stat every note (slow on WSL drives)
# the ids of the other libraries, "id<TAB>library", so a link across libraries is seen (library.awk EXTF)
ext() {
  [ -n "${EXTF:-}" ] && rm -f "$EXTF"
  EXTF=$(mktemp "${TMPDIR:-/tmp}/cos-ext.XXXXXX") || return 0; trap 'rm -f "$EXTF"' EXIT
  # ids come from the per-library cache (cos_ids): no stat per note of every other library at each gate
  cos_ids "$lib" > "$EXTF.own"
  cos_libs "$root" | while IFS="$(printf '\t')" read -r n p; do
    [ "$n" = "$name" ] && continue
    cos_ids "$p" | awk -v n="$n" -v own="$EXTF.own" 'BEGIN { while ((getline l < own) > 0) O[l] = 1 } $0 != "" && !($0 in O) { print $0 "\t" n }'
  done > "$EXTF"; rm -f "$EXTF.own"
  export EXTF
}
run() { # MODE [awk -v assignments...] -- runs library.awk over every note
  m=$1; shift
  notes || { [ "$m" = brief ] && echo "Library '$name': empty (0 notes)."; return 0; }
  case $m in gate|doctor|graph) ext ;; esac
  LC_ALL=C TODAY=$today awk -v MODE="$m" -v TODAY="$today" -v LIBNAME="$name" -v LIBKIND="$kind" "$@" -f "$here/library.awk" "$lib/notes/"*.md
}
# the turn-end gate reads only the notes changed since its last run and the targets; the facts of the others
# (ids, states, titles, Compared:) come from a per-library index on this computer, so its time follows the turn's
# notes, not the library's size. One find (a stat per note, no read) says what changed; ctime, so mv or touch -t count
igate() {
  notes || return 0
  ext; k=$(cos_cache noteidx "$lib"); mkdir -p "${k%/*}"
  : > "$EXTF.t0"   # taken before the scan: a note changed while the gate runs is read again next time
  printf '%s\n' "$lib/notes/"*.md | grep -v '^$' > "$EXTF.all"
  # COS_SINCE (protocol.sh, personal library): the turn's start, after which every changed note is a target; an
  # index taken after it needs no scan
  { [ -f "$k" ] && { [ -z "${COS_SINCE:-}" ] || [ ! "$k" -nt "$COS_SINCE" ]; } && find "$lib/notes" -name '*.md' -type f -cnewer "$k" 2>/dev/null
    printf '%s\n' "$TARGETS"; } > "$EXTF.new"
  trap 'rm -f "$EXTF" "$EXTF.t0" "$EXTF.all" "$EXTF.new" "$k.$$"' EXIT
  LC_ALL=C TODAY=$today IDXF=$k IDXOUT=$k.$$ ALLF=$EXTF.all NEWF=$EXTF.new awk -v MODE=gate -v TODAY="$today" -v LIBNAME="$name" -v LIBKIND="$kind" -f "$here/library.awk"
  r=$?; [ -s "$k.$$" ] && touch -r "$EXTF.t0" "$k.$$" && mv -f "$k.$$" "$k"
  return $r
}
translit() { # fixed table, byte for byte, so ids do not depend on iconv or the locale
  LC_ALL=C sed 's/Á/a/g; s/À/a/g; s/Â/a/g; s/Ã/a/g; s/Ä/a/g; s/á/a/g; s/à/a/g; s/â/a/g; s/ã/a/g; s/ä/a/g; s/É/e/g; s/È/e/g; s/Ê/e/g; s/Ë/e/g; s/é/e/g; s/è/e/g; s/ê/e/g; s/ë/e/g; s/Í/i/g; s/Ì/i/g; s/Î/i/g; s/Ï/i/g; s/í/i/g; s/ì/i/g; s/î/i/g; s/ï/i/g; s/Ó/o/g; s/Ò/o/g; s/Ô/o/g; s/Õ/o/g; s/Ö/o/g; s/ó/o/g; s/ò/o/g; s/ô/o/g; s/õ/o/g; s/ö/o/g; s/Ú/u/g; s/Ù/u/g; s/Û/u/g; s/Ü/u/g; s/ú/u/g; s/ù/u/g; s/û/u/g; s/ü/u/g; s/Ç/c/g; s/ç/c/g; s/Ñ/n/g; s/ñ/n/g'
}
plus6m() { date -v+6m +%F 2>/dev/null || date -d '+6 months' +%F; }

case ${1:-} in
  search)
    [ $# -ge 2 ] || usage; shift; a=
    [ "$1" = --auto ] && { a=1; shift; }
    all=; [ "${1:-}" = --all ] && { all=1; shift; }
    [ $# -ge 1 ] || usage
    if [ -z "$all" ]; then [ $state = 0 ] || { offline; exit 0; }; Q=$* run search -v AUTO="$a"; exit 0; fi
    # every library; the session's first, the others each under a line that says where they come from
    own=$name
    { echo "$own"; cos_libs "$root" | cut -f1 | grep -vx "$own"; } | while IFS= read -r n; do
      setlib "$n"
      if [ "$n" = "$own" ]; then echo "== Library '$n' (this session's)"
      else echo "== Library '$n', not this session's ('$own'): use it to learn, but do not copy its content into '$own' notes or deliverables unless the owner agrees (it may be private, or another team's)."; fi
      if [ $state = 0 ]; then Q=$* run search; else offline; fi
    done ;;
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
      o=$(cos_libof "$root" "$f"); [ -n "$o" ] && setlib "${o%%	*}"
      ext
      LC_ALL=C awk -v MODE=check -v TODAY="$today" -v LIBNAME="$name" -v LIBKIND="$kind" -f "$here/library.awk" "$f" || rc=2
    done
    exit $rc ;;
  gate)
    [ $# -ge 2 ] || usage; shift
    o=$(cos_libof "$root" "$1"); [ -n "$o" ] && setlib "${o%%	*}"   # the library of the files (protocol.sh passes one library at a time)
    [ $state = 0 ] || exit 0
    for f in "$@"; do [ -f "$f" ] && [ ! -s "$f" ] && { echo "notes/$(basename "$f"): is empty: write the note or delete the file"; exit 2; }; done
    TARGETS=$(printf '%s\n' "$@") igate ;;
  index)
    [ $state = 0 ] || exit 0
    TARGETS= igate >/dev/null; exit 0 ;;
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
  brief) [ $state = 0 ] || { offline; exit 0; }; echo "Library of this session: '$name' ($lib)."; run brief -v PROJ="${2:-}" ;;
  where) echo "$lib"; offline; exit $state ;;
  libs)
    cos_libs "$root" | while IFS="$(printf '\t')" read -r n p; do
      setlib "$n"; c=$(ls "$lib/notes/" 2>/dev/null | grep -c '\.md$')
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$lib" "$state" "$c" "-" "$([ "$n" = "$mine" ] && echo '*')"
    done ;;
  *) usage ;;
esac
