#!/bin/sh
# The library: the company's second brain. One note per file in <library>/notes/, readable in Obsidian;
# links are inline [[id]]; index, backlinks and graph are computed on the fly (library.awk), never stored.
# Usage (inside a workspace):
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
#   library.sh offload <folder> [--remote <git-url>]   move the personal library (central session only)
#   library.sh libs                             every library: name, folder, state, notes, last sync, this session's (*)
#   library.sh use <personal|team>              from a project folder: the library this project writes to and searches
#   library.sh join <git-url> [<name>]          connect a team library (central only; an empty repo becomes one)
#   library.sh leave <name>                     disconnect a team library (central only)
#   library.sh trust                            the owner confirms the library settings as they are (central only)
# Before the command, --lib <name> picks another library than the session's (personal, or a team's).
# A session uses its project's library (projects/<p>/.library names a team; none = personal); central uses personal.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

die() { echo "library: $*" >&2; exit 1; }
usage() { sed -n '4,25p' "$0" | sed 's/^# //' >&2; exit 1; }
dir=${CLAUDE_PROJECT_DIR:-$PWD}
root=$(cos_root "$dir") || die "not inside a chief-of-staff workspace"
name=; [ "${1:-}" = --lib ] && { name=${2:-}; shift 2 || usage; }
mine=$(cos_libname "$root" "$dir")   # the session's own library
setlib() { name=$1; lib=$(cos_libpath "$root" "$name"); state=$?; kind=team; [ "$name" = personal ] && kind=personal; }
# what a person reads: a shared workspace's own library (knowledge/) is the team's, though its name stays personal
label() { if [ "$name" = personal ] && cos_shared "$root"; then printf "the team's (shared workspace)"; else printf "'%s'" "$name"; fi; }
setlib "${name:-$mine}"
# a shared workspace is the team's: its knowledge/ is already the team library, and nothing personal joins it
case ${1:-} in join|use|offload) cos_shared "$root" && die "this workspace is shared with the team: its library (knowledge/) is already the team's, so it takes no other library. Personal notes belong in a personal workspace." ;; esac
central_only() { case ${dir#"$root"} in /central|/central/*) ;; *) die "only central $1, after the owner agrees (this session is in ${dir#"$root"/})" ;; esac; }
today=$(date +%F)
idre='^[a-z0-9][a-z0-9-]\{1,79\}$'

offline() {
  case $state in
    1) echo "Library offline: $lib is not reachable (external disk unplugged?). Work continues without it; plug it in, or move the library back with library.sh offload $root/knowledge from central." ;;
    2) if [ "$name" != personal ]; then echo "Library error: the team library '$name' is missing or damaged at $lib. From central: library.sh leave $name, then library.sh join <its git link> $name again; or this project goes back to the personal library (library.sh use personal)."
       else echo "Library error: $lib exists but has no .library-id file (an empty mount point, or a wrong path in $root/.chief-of-staff). Do not write notes there."; fi ;;
    3) echo "Library error: the library: line in $root/.chief-of-staff must be one absolute path." ;;
    4) echo "Library error: this session uses the library '$name', which is not connected (library.sh libs lists them; central connects one with library.sh join)." ;;
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
  notes || { [ "$m" = brief ] && echo "Library $(label): empty (0 notes)."; return 0; }
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
  brief) [ $state = 0 ] || { offline; exit 0; }; echo "Library of this session: $(label) ($lib)."; run brief -v PROJ="${2:-}" ;;
  where) echo "$lib"; offline; exit $state ;;
  offload) [ "$name" = personal ] || die "offload moves the personal library; a team library lives in its git repo"; sh "$here/offload.sh" "$@" ;;
  libs)
    cos_libs "$root" | while IFS="$(printf '\t')" read -r n p; do
      setlib "$n"; c=$(ls "$lib/notes/" 2>/dev/null | grep -c '\.md$')
      sy=$(head -n 1 "$lib/.git/cos-sync" 2>/dev/null | tr -d '\000-\037' | cut -c1-120)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$lib" "$state" "$c" "${sy:--}" "$([ "$n" = "$mine" ] && echo '*')"
    done ;;
  use)
    [ $# -eq 2 ] || usage
    case ${dir#"$root"/} in projects/?*) p=${dir#"$root"/projects/}; p=${p%%/*} ;; *) die "run it from a project folder (projects/<name>)" ;; esac
    setlib "$2"; [ $state = 4 ] && die "no library named '$2' (library.sh libs lists them)"
    f=$root/projects/$p/.library; [ -f "$f" ] && chmod u+w "$f"
    if [ "$2" = personal ]; then rm -f "$f"; else printf '%s\n' "$2" > "$f"; chmod 444 "$f"; fi
    cos_cfgsave "$root"
    echo "Project '$p' now writes to and searches the library '$2' ($lib). Other libraries only through search --all, with a warning." ;;
  join)
    [ $# -ge 2 ] || usage; central_only "connects a team library"
    url=$2
    [ "$(printf '%s' "$url${3:-}" | tr -d '\000-\037\177')" = "$url${3:-}" ] || die "the URL and the name must be one line, without control characters"
    case $url in -*) die "the git URL must not start with -" ;; esac
    n=${3:-$(basename "$url" .git | tr 'A-Z_' 'a-z-' | tr -cd 'a-z0-9-')}
    printf '%s\n' "$n" | grep -q '^[a-z0-9][a-z0-9-]\{0,39\}$' || die "name the library: lowercase letters, digits and dashes (library.sh join <url> <name>)"
    [ "$n" = personal ] && die "personal is your own library: pick another name"
    setlib "$n"; [ $state = 4 ] || die "a library named '$n' is already connected"
    p=$root/libraries/$n; [ -e "$p" ] && die "$p exists: remove it or pick another name"
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10" git clone -q -c core.symlinks=false -- "$url" "$p" 2>"$root/.join.err" || { e=$(head -n 3 "$root/.join.err" | tr '\n' ' '); rm -f "$root/.join.err"; rm -rf "${p:?}"; die "could not clone $url: $e(check the link and your access to it)"; }
    rm -f "$root/.join.err"
    if [ ! -f "$p/.library-id" ]; then
      if [ -n "$(ls -A "$p" | grep -vx .git)" ]; then rm -rf "${p:?}"; die "$url holds files but is not a chief-of-staff library: use an empty repo, or one another member joined first"; fi
      # an empty repo: this member starts the team library
      mkdir -p "$p/notes" "$p/templates" "$p/inbox"; : > "$p/notes/.gitkeep"
      cp "$here/../templates/knowledge/note.md" "$p/templates/note.md"
      printf 'inbox/\n' > "$p/.gitignore"
      od -An -N8 -tx1 /dev/urandom | tr -d ' \n' > "$p/.library-id"
      git -C "$p" add -A && git -C "$p" -c user.name=chief-of-staff -c user.email=chief-of-staff@localhost commit -qm "library: started" || die "could not start the library in $p"
      GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10" git -C "$p" push -q -u origin HEAD 2>/dev/null || echo "Note: the first push to $url failed; it is retried after the first note saved in a project of this team."
    fi
    mkdir -p "$p/inbox"; chmod 444 "$p/.library-id" 2>/dev/null
    grep -qx 'libraries/' "$root/.gitignore" 2>/dev/null || echo 'libraries/' >> "$root/.gitignore"
    m=$root/.chief-of-staff; chmod u+w "$m"; printf 'team: %s %s\n' "$n" "$p" >> "$m"; chmod 444 "$m"
    cos_cfgsave "$root"
    echo "Connected the team library '$n' ($p, $(ls "$p/notes" | grep -c '\.md$') notes) from $url."
    echo "A project uses it with: library.sh use $n (from the project folder). It syncs at session start and after each turn that saved notes in it." ;;
  trust)   # the owner checked library.sh libs and confirms the settings as they are now
    [ $# -eq 1 ] || usage; central_only "records the library settings"
    cos_cfgsave "$root"; echo "Recorded the library settings as they are now; library.sh libs lists them." ;;
  leave)
    [ $# -eq 2 ] || usage; central_only "disconnects a team library"
    [ "$2" = personal ] && die "the personal library cannot be left"
    setlib "$2"; [ $state = 4 ] && die "no library named '$2'"
    u=$(for f in "$root"/projects/*/.library; do [ -f "$f" ] && [ "$(head -n 1 "$f" | tr -cd 'a-z0-9-')" = "$2" ] && printf '%s\n' "$f"; done | sed 's|.*/projects/||; s|/.library$||' | tr '\n' ' ')
    [ -z "$u" ] || die "projects still use '$2': $u. Close them, or switch each to another library (library.sh use, from the project folder, with the owner's OK)"
    if [ -d "$lib/.git" ]; then
      # never pushed (no upstream) counts as not pushed: the team would lose every note
      [ -z "$(git -C "$lib" status --porcelain -- notes templates)" ] && git -C "$lib" rev-parse -q --verify '@{u}' >/dev/null &&
        [ -z "$(git -C "$lib" log --oneline '@{u}..' 2>/dev/null)" ] ||
        die "'$2' has notes not pushed to the team yet: run sh $here/sync.sh push \"$lib\" and leave again"
    fi
    m=$root/.chief-of-staff; chmod u+w "$m"; grep -v "^team: $2 " "$m" > "$m.tmp.$$"; chmod 444 "$m.tmp.$$"; mv -f "$m.tmp.$$" "$m"
    old=; case $lib in "$root"/libraries/*) old=$lib.left-$(date +%Y%m%d-%H%M%S); mv "$lib" "$old" ;; esac
    cos_cfgsave "$root"
    echo "Disconnected '$2': it no longer appears in search. Notes that link it now show broken links (library.sh doctor)."
    [ -n "$old" ] && echo "The local copy is in $old (ignored by git); delete it once you are sure." ;;
  *) usage ;;
esac
