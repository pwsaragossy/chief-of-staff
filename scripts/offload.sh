#!/bin/sh
# Move the library to another folder: an external disk or SSD, a synced cloud folder (iCloud Drive,
# Dropbox, Google Drive, OneDrive), or a folder that is (or becomes) its own git repo with a private
# remote. Moving it back is the same command with <workspace>/knowledge.
#   offload.sh offload <folder> [--remote <git-url>]      (called as library.sh offload ...)
# Runs only from central, the session that talks to the owner. Copies, verifies every file by checksum,
# then points the workspace marker at the new folder. Nothing is deleted: the old folder is renamed
# (inside the workspace) or left in place (elsewhere), for the owner to remove once happy.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
die() { echo "offload: $*" >&2; exit 1; }

shift   # "offload"
dest=${1:-}; remote=
[ "${2:-}" = --remote ] && remote=${3:-}
[ -n "$dest" ] || die "usage: library.sh offload <folder> [--remote <git-url>]"
dir=${CLAUDE_PROJECT_DIR:-$PWD}
root=$(cos_root "$dir") || die "not inside a chief-of-staff workspace"
case ${dir#"$root"} in /central|/central/*) ;; *) die "only central moves the library, after the owner agrees (this session is in ${dir#"$root"/})" ;; esac
lib=$(cos_lib "$root"); [ $? = 0 ] || die "the current library ($lib) is not reachable: plug the disk in first"
[ "$(printf '%s' "$dest$remote" | tr -d '\000-\037\177')" = "$dest$remote" ] || die "the folder and the URL must be one line, without control characters"
case $remote in -*) die "the git URL must not start with -" ;; esac
case $dest in /*) ;; *) die "give an absolute folder path" ;; esac
case $dest in */../*|*/..|*/./*) die "the path must not contain . or .. parts" ;; esac
dest=${dest%/}
[ "$dest" = "$lib" ] && die "the library is already at $dest"
case $dest/ in "$lib"/*) die "$dest is inside the current library" ;; esac
[ "$dest" != "$root/knowledge" ] && case $dest/ in "$root"/*) die "$dest is inside the workspace: offload moves the library out of it (or back to $root/knowledge)" ;; esac
if [ -e "$dest" ]; then [ -d "$dest" ] && [ -z "$(ls -A "$dest")" ] || die "$dest exists and is not empty: choose a new or empty folder"; fi
case $dest in
  *"/Mobile Documents/"*|*/CloudStorage/*|*/Dropbox/*|*/Dropbox|*"/Google Drive/"*|*/OneDrive*) cloud=1 ;;
  *) cloud= ;;
esac
# ponytail: iCloud "Desktop & Documents" syncs ~/Desktop and ~/Documents in place; its folders inside
# iCloud Drive are the sign it is on
case $dest in "$HOME"/Desktop/*|"$HOME"/Documents/*)
  [ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents" ] && cloud=1 ;; esac
up=$(dirname "$dest"); while [ ! -d "$up" ]; do up=$(dirname "$up"); done
outer=$(git -C "$up" rev-parse --show-toplevel 2>/dev/null)
[ -n "$remote" ] && [ -n "$outer" ] && die "$dest is inside the git repo $outer, which versions it: back that repo up instead of --remote"
[ -n "$remote" ] && [ -n "$cloud" ] && die "a git repo inside a synced cloud folder gets corrupted by the sync: use a plain folder for --remote"
if [ -n "$remote" ]; then
  # nothing secret leaves this computer: every note passes the secret check first
  s=$(cd "$root/central" && sh "$here/library.sh" doctor | grep "looks like a secret")
  [ -z "$s" ] || die "notes hold what looks like a key or token; replace it with <REDACTED> first:
$s"
fi

mkdir -p "$dest" || die "cannot create $dest (is the disk mounted and writable?)"
cp -R "$lib/." "$dest/" || die "copy to $dest failed; nothing changed (the old library is untouched)"
sums() { (cd "$1" && find . -type f ! -path './.git/*' ! -name .library-id -exec cksum {} + | sort); }
[ "$(sums "$lib")" = "$(sums "$dest")" ] || die "the copy in $dest differs from the library; nothing changed. Delete $dest and run again"
n=$(find "$dest/notes" -name '*.md' -type f | wc -l | tr -d ' ')

home=$root/knowledge
[ "$dest" = "$home" ] && rm -rf "${dest:?}/.git"   # back inside the workspace repo: no repo inside the repo
if [ "$dest" != "$home" ]; then
  [ -f "$dest/.library-id" ] || { od -An -N8 -tx1 /dev/urandom | tr -d ' \n' > "$dest/.library-id"; chmod 444 "$dest/.library-id"; }
  # a folder inside another repo (an Obsidian vault kept in git) is versioned by that repo: no repo inside it
  if [ -z "$cloud" ] && [ -z "$(git -C "$dest" rev-parse --show-toplevel 2>/dev/null)" ]; then
    # the inbox holds the owner's raw files, waiting to be processed: it never goes to a remote
    { grep -qx 'inbox/' "$dest/.gitignore" 2>/dev/null || echo 'inbox/' >> "$dest/.gitignore"; }
    git -C "$dest" init -q && git -C "$dest" add -A && git -C "$dest" -c user.name=chief-of-staff -c user.email=chief-of-staff@localhost commit -qm "library: moved here from $lib" ||
      die "the copy is in $dest, but git init failed there; the workspace still uses $lib"
  fi
fi
# point the workspace at the new folder (the marker keeps its other lines)
m=$root/.chief-of-staff
grep -v '^library:' "$m" > "$m.tmp.$$" || : > "$m.tmp.$$"
[ "$dest" = "$home" ] || printf 'library: %s\n' "$dest" >> "$m.tmp.$$"
chmod 444 "$m.tmp.$$"; mv -f "$m.tmp.$$" "$m"   # read-only: agents do not edit it by accident

cos_cfgsave "$root"
old=
if [ "$lib" = "$home" ]; then
  old=$root/knowledge.offloaded-$(date +%Y%m%d-%H%M%S)
  mv "$lib" "$old" && { grep -qx 'knowledge.offloaded-*/' "$root/.gitignore" 2>/dev/null || echo 'knowledge.offloaded-*/' >> "$root/.gitignore"; }
fi
echo "Library moved to $dest: $n notes, every file verified by checksum."
[ -n "$cloud" ] && echo "It is a synced cloud folder: the provider keeps the versions (no git there). Keep the folder set to stay downloaded on this computer."
if [ -n "$remote" ]; then
  git -C "$dest" remote add origin "$remote" 2>/dev/null || git -C "$dest" remote set-url origin "$remote"
  if e=$(git -C "$dest" push -q -u origin HEAD 2>&1); then echo "Pushed to $remote."
  else echo "Push to $remote failed: $(printf '%s' "$e" | head -n 3 | tr '\n' ' ')(the library works locally; push again with git -C $dest push -u origin HEAD)"; fi
fi
if [ -n "$old" ]; then echo "The old copy is in $old (ignored by git); delete it once you are happy. Commit the workspace: knowledge/ now lives outside it."
else echo "The old copy stays in $lib; delete it once you are happy."; fi
[ "$dest" = "$home" ] && echo "The library is back inside the workspace: commit knowledge/."
exit 0
