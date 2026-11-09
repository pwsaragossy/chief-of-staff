#!/bin/sh
# The setup skill's first step, as a script so it is tested (project.sh does the rest).
#   setup.sh detect
#       where the company library could live on this computer, best first. One line per place:
#       "<label><TAB><folder><TAB><why>"; every folder is absolute (project.sh library takes it as is).
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
  inside=$(printf 'On this computer\t%s/Company library\tone plain folder in your home; back it up with git or Time Machine' "$HOME")
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
*) die "usage: setup.sh detect (project.sh library <folder> records the choice; project.sh init <folder> opens a project)" ;;
esac
