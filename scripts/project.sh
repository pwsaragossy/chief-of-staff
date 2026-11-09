#!/bin/sh
# Projects are the folders the owner creates; there is no central folder.
#   project.sh init <dir>       make <dir> a project: marker (kind: project), board/Inbox.md, STATE.md, DECISIONS.md,
#                               only when it has no marker yet; then register it in <plugin data>/projects (once)
#   project.sh library <dir>    the owner's one library: an existing library, or a new one in an empty folder;
#                               recorded in <plugin data>/library (setup asks the owner where)
#   project.sh trust <dir>      the owner read <dir>/.chief-of-staff and confirms its settings as they are now
#   project.sh list             each registered folder, "ok<TAB>path" or "missing<TAB>path"
#   project.sh board <dir>      a board folder the global panel also reads (an existing system's own cards, such as a
#                               second brain's board/), recorded once in <plugin data>/boards; nothing is written in <dir>
#   project.sh boards           each recorded board folder, "ok<TAB>path" or "missing<TAB>path"
# The list and the library setting are read-only on disk and protected by the hooks: only this script writes them,
# from new-project and setup (/threads makes a coordinator, never a project). A thread never runs it (hooks/projects.tsx).
set -u
. "$(dirname "$0")/lib.sh"
die() { echo "project.sh: $*" >&2; exit 1; }
D=$(cos_data); T="$(dirname "$0")/../templates"
# rewrite a read-only file of the plugin's data folder in one step
put() { mkdir -p "$D" && { [ -f "$D/$1" ] && chmod u+w "$D/$1"; cat > "$D/$1.tmp.$$" && mv -f "$D/$1.tmp.$$" "$D/$1"; chmod 444 "$D/$1"; }; }
abs() { case $1 in /*) [ -d "$1" ] || die "$1 is not a folder"; (cd "$1" && pwd -P) ;; *) die "give the folder as an absolute path" ;; esac; }

case ${1:-} in
  init)
    [ $# = 2 ] || die "usage: project.sh init <folder>"
    d=$(abs "$2") || exit 1
    # a folder inside a project or a workspace (a subfolder, a worktree of a thread) is part of it, never its own
    # project: otherwise a thread could register its own worktree and become a coordinator
    a=${d%/*}; while [ -n "$a" ]; do [ -f "$a/.chief-of-staff" ] && die "$d is inside $a, which is already a project or workspace"; a=${a%/*}; done
    if [ ! -f "$d/.chief-of-staff" ]; then
      n=${d##*/}; now=$(date '+%F %H:%M')
      mkdir -p "$d/board" || die "cannot write in $d"
      [ -f "$d/board/Inbox.md" ] || sed "s/{{DATE}}/$(date +%F)/g; s/^owner: central$/owner: coordinator/" "$T/board/Inbox.md" > "$d/board/Inbox.md"
      [ -f "$d/STATE.md" ] || sed -e "s/{{PROJECT_NAME}}/$n/" -e "s/{{DATE}}/$now/" -e "s/{{NEXT_ACTION}}/the owner's first request/" "$T/project/STATE.md" > "$d/STATE.md"
      [ -f "$d/DECISIONS.md" ] || sed "s/{{PROJECT_NAME}}/$n/" "$T/project/DECISIONS.md" > "$d/DECISIONS.md"
      printf 'chief-of-staff project v0.1\nkind: project\n' > "$d/.chief-of-staff"; chmod 444 "$d/.chief-of-staff"   # last: a failed run can be repeated
      echo "Project: $d (new)"
    else
      cos_isproj "$d" || die "$d is a workspace of the old layout (central/, projects/<slug>), removed in 0.12.0: make each project's own folder a project instead"
      echo "Project: $d"
    fi
    # ponytail: two inits at the same instant can both append; readers (panel, overview) drop repeated lines
    grep -Fxq "$d" "$D/projects" 2>/dev/null || { { cat "$D/projects" 2>/dev/null; printf '%s\n' "$d"; } | put projects; } || die "cannot write $D/projects"
    ;;
  library)
    [ $# = 2 ] || die "usage: project.sh library <folder>"
    case $2 in /*) ;; *) die "give the library folder as an absolute path" ;; esac
    l=$2
    if [ -f "$l/.library-id" ] && [ -d "$l/notes" ]; then echo "Library: $l (existing)"
    elif [ -e "$l" ] && [ -n "$(ls -A "$l" 2>/dev/null)" ]; then die "$l is not empty and is not a library: choose a new or empty folder, or an existing library"
    else
      mkdir -p "$l/notes" "$l/inbox" "$l/templates" || die "cannot create $l"
      cp "$T/knowledge/note.md" "$l/templates/note.md"
      od -An -N8 -tx1 /dev/urandom | tr -d ' \n' > "$l/.library-id"; chmod 444 "$l/.library-id"
      echo "Library: $l (new)"
    fi
    printf '%s\n' "$l" | put library || die "cannot write $D/library"
    ;;
  trust)
    [ $# = 2 ] || die "usage: project.sh trust <project folder>"
    d=$(abs "$2") || exit 1
    cos_isproj "$d" || die "$d is not a project folder"
    cos_cfgsave "$d" && echo "Recorded the settings of $d as they are now."
    ;;
  board)
    [ $# = 2 ] || die "usage: project.sh board <folder>"
    d=$(abs "$2") || exit 1
    grep -Fxq "$d" "$D/boards" 2>/dev/null || { { cat "$D/boards" 2>/dev/null; printf '%s\n' "$d"; } | put boards; } || die "cannot write $D/boards"
    echo "Board: $d"
    ;;
  list|boards)
    [ "$1" = list ] && f=projects || f=boards
    awk '!seen[$0]++' "$D/$f" 2>/dev/null | while IFS= read -r p; do
      [ -n "$p" ] || continue; if [ -d "$p" ]; then printf 'ok\t%s\n' "$p"; else printf 'missing\t%s\n' "$p"; fi; done
    ;;
  *) die "usage: project.sh init <folder> | library <folder> | trust <folder> | list | board <folder> | boards" ;;
esac
