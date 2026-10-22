#!/bin/sh
# The setup skill's two steps, as a script so they are tested.
#   setup.sh detect
#       where the company library could live on this computer, best first. One line per place:
#       "<label><TAB><folder><TAB><why>"; the folder "(workspace)/knowledge" means inside the workspace.
#   setup.sh create <workspace> [--library <folder>] [--backup]
#       creates the workspace; --library puts the library in that folder instead of <workspace>/knowledge;
#       --backup creates private GitHub repos with gh (the workspace, and the library when it is a git repo
#       outside the workspace) and pushes to them.
here=$(cd "$(dirname "$0")" && pwd)
die() { echo "setup: $*" >&2; exit 1; }

case ${1:-} in
detect)
  # an Obsidian vault the owner already uses: the library becomes a folder of it, so the owner reads it
  # where they already read notes (adopt the existing system, never a parallel one). Only a single vault
  # comes first: with several, which one belongs to this company is the owner's call, not a guess
  vaults=$({ find "$HOME" -maxdepth 3 -type d -name .obsidian ! -path "$HOME/Library/*" 2>/dev/null
    find "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents" -maxdepth 2 -type d -name .obsidian 2>/dev/null; } |
    while IFS= read -r o; do v=$(dirname "$o")
      printf 'Obsidian vault "%s"\t%s/Company library\tyou already read your notes there\n' "$(basename "$v")" "$v"; done)
  inside=$(printf 'Inside the workspace\t(workspace)/knowledge\tone folder and one git repo: the simplest backup')
  if [ "$(printf '%s' "$vaults" | grep -c .)" = 1 ]; then printf '%s\n%s\n' "$vaults" "$inside"
  else printf '%s\n' "$inside"; [ -n "$vaults" ] && printf '%s\n' "$vaults"; fi
  d="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
  [ -d "$d" ] && printf 'iCloud Drive\t%s/Company library\tsynced to your other devices; iCloud keeps the versions\n' "$d"
  # sync providers only: CloudStorage also holds network mounts and phones (CloudMounter, MacDroid)
  for d in "$HOME/Dropbox" "$HOME"/Library/CloudStorage/Dropbox* "$HOME"/Library/CloudStorage/GoogleDrive-* "$HOME"/Library/CloudStorage/OneDrive* "$HOME"/Library/CloudStorage/Box*; do
    [ -d "$d" ] && printf '%s\t%s/Company library\tsynced; the provider keeps the versions\n' "$(basename "$d")" "$d"; done
  for d in /Volumes/*; do   # the startup disk is a symlink to /
    [ -d "$d" ] && [ ! -L "$d" ] && [ -w "$d" ] && printf 'Disk "%s"\t%s/Company library\toff this computer; while it is unplugged the library is offline\n' "$(basename "$d")" "$d"; done
  exit 0 ;;
create) ;;
*) die "usage: setup.sh detect | setup.sh create <workspace> [--library <folder>] [--backup]" ;;
esac

W=${2:-}; shift 2 2>/dev/null || die "give the workspace folder"
libdest=; backup=
while [ $# -gt 0 ]; do
  case $1 in --library) libdest=${2:-}; shift 2 || die "--library needs a folder" ;; --backup) backup=1; shift ;; *) die "unknown option $1" ;; esac
done
case $W in /*) ;; *) die "give the workspace as an absolute path" ;; esac
W=${W%/}
[ -f "$W/.chief-of-staff" ] && die "$W is already a workspace"
if [ -d "$W" ] && [ -n "$(ls -A "$W")" ]; then die "$W exists and is not empty: choose a new or empty folder"; fi
[ "$libdest" = "$W/knowledge" ] && libdest=
if [ -n "$libdest" ]; then   # checked before anything is created, so a wrong answer leaves nothing behind
  case $libdest in /*) ;; *) die "give the library folder as an absolute path" ;; esac
  if [ -e "$libdest" ] && [ -n "$(ls -A "$libdest")" ]; then die "$libdest exists and is not empty: choose a new or empty folder"; fi
fi

T="$here/../templates"
mkdir -p "$W/central" "$W/board" "$W/projects" "$W/knowledge/inbox" "$W/knowledge/notes" "$W/knowledge/templates" "$W/specialists" ||
  die "cannot create $W"
for d in board projects knowledge/inbox knowledge/notes; do : > "$W/$d/.gitkeep"; done
cp "$T/central/CLAUDE.md" "$W/central/CLAUDE.md"
cp "$T/ROUTING.md" "$W/ROUTING.md"
cp "$T"/specialists/*.md "$W/specialists/"
cp "$T/knowledge/note.md" "$W/knowledge/templates/note.md"
printf '.dispatch.lock/\n.dispatch.log\n.dispatch-*.out\n.protocol.log\n' > "$W/.gitignore"
git -C "$W" init -q
git -C "$W" config user.name >/dev/null || git -C "$W" config user.name "chief-of-staff"
git -C "$W" config user.email >/dev/null || git -C "$W" config user.email "chief-of-staff@localhost"
printf 'chief-of-staff workspace v0.1\n' > "$W/.chief-of-staff"; chmod 444 "$W/.chief-of-staff"   # last: a failed run can be repeated

if [ -n "$libdest" ]; then
  out=$(CLAUDE_PROJECT_DIR="$W/central" sh "$here/library.sh" offload "$libdest" 2>&1) ||
    die "the workspace is in $W, but the library could not go to $libdest: $out"
  rm -rf "$W"/knowledge.offloaded-*   # the empty library just made; nothing to keep
  echo "Library: $libdest"
else
  echo "Library: $W/knowledge"
fi
git -C "$W" add -A && git -C "$W" commit -qm "chief-of-staff: new workspace"
echo "Workspace: $W"

[ -n "$backup" ] || { echo "Backup: none yet. Add a private git remote to $W and push."; exit 0; }
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "Backup: skipped, GitHub CLI not signed in (gh auth login). Add a private git remote to $W and push."; exit 0
fi
name=$(basename "$W")
if gh repo create "$name" --private --source "$W" --remote origin --push >/dev/null 2>&1; then
  echo "Backup: private GitHub repo $name, pushed."
else
  echo "Backup: could not create the private GitHub repo $name (does it exist already?). Add a private git remote to $W and push."
fi
# the library outside the workspace is its own git repo (not in a synced cloud folder: the provider keeps the versions)
if [ -n "$libdest" ] && [ -d "$libdest/.git" ]; then
  if gh repo create "$name-library" --private --source "$libdest" --remote origin --push >/dev/null 2>&1; then
    echo "Library backup: private GitHub repo $name-library, pushed."
  else
    echo "Library backup: could not create the private GitHub repo $name-library. Add a private git remote to $libdest and push."
  fi
fi
exit 0
