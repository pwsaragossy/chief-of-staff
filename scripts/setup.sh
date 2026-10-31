#!/bin/sh
# The setup skill's two steps, as a script so they are tested.
#   setup.sh detect
#       where the company library could live on this computer, best first. One line per place:
#       "<label><TAB><folder><TAB><why>"; the folder "(workspace)/knowledge" means inside the workspace.
#   setup.sh create <workspace> [--library <folder>] [--join <git-url>] [--backup]
#       creates the workspace; --library puts the personal library in that folder instead of
#       <workspace>/knowledge; --join connects a team library (library.sh join: an empty repo starts one);
#       --backup creates private GitHub repos with gh (the workspace, and the library when it is a git repo
#       outside the workspace) and pushes to them.
#   setup.sh create <workspace> --share <git-url> --member <name>
#       a workspace the whole team shares (one board, every project): pushed to <git-url>, an empty private
#       repo the teammates can write to. Its library is the team's; nothing personal goes in it.
#   setup.sh join <workspace> <git-url> --member <name>
#       a teammate's copy of a shared workspace. Board, projects and library sync at every session start and turn end.
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
create|join) ;;
*) die "usage: setup.sh detect | setup.sh create <workspace> [--library <folder>] [--join <git-url>] [--backup] [--share <git-url> --member <name>] | setup.sh join <workspace> <git-url> --member <name>" ;;
esac

cmd=$1; W=${2:-}; shift 2 2>/dev/null || die "give the workspace folder"
url=; [ "$cmd" = join ] && { url=${1:-}; shift 2>/dev/null || die "join needs the shared workspace's git link"; }
libdest=; backup=; join=; share=; member=
while [ $# -gt 0 ]; do
  case $1 in --library) libdest=${2:-}; shift 2 || die "--library needs a folder" ;; --join) join=${2:-}; shift 2 || die "--join needs a git link" ;;
    --share) share=${2:-}; shift 2 || die "--share needs a git link" ;; --member) member=${2:-}; shift 2 || die "--member needs your name" ;;
    --backup) backup=1; shift ;; *) die "unknown option $1" ;; esac
done
case $W in /*) ;; *) die "give the workspace as an absolute path" ;; esac
W=${W%/}
[ -f "$W/.chief-of-staff" ] && die "$W is already a workspace"
# a Windows drive seen from WSL (drvfs): every file read there is about 70 times slower than in the Linux home,
# and the hooks run on each prompt and tool call
case $W in /mnt/[a-z]/*) echo "Warning: $W is on a Windows drive seen from WSL, where the hooks are about 70 times slower. Prefer a folder in the Linux home (~/chief-of-staff); Windows apps reach it at \\\\wsl\$\\<distro>\\home." ;; esac
if [ -d "$W" ] && [ -n "$(ls -A "$W")" ]; then die "$W exists and is not empty: choose a new or empty folder"; fi
member=$(printf '%s' "$member" | tr -d '\000-\037' | cut -c1-60)
if [ -n "$share" ] || [ "$cmd" = join ]; then
  [ -n "$member" ] || die "a shared workspace needs --member <your name>: the board shows whose each project is"
  [ -z "$libdest$join$backup" ] || die "a shared workspace keeps its library inside and is backed up by the team repo: drop --library, --join and --backup"
fi
export GIT_TERMINAL_PROMPT=0
ignore() { # what never leaves this computer: logs, locks, raw imports, secrets and build output
  printf '.dispatch.lock/\n.dispatch.log\n.dispatch-*.out\n.protocol.log\n' > "$W/.gitignore"
  [ -n "$share" ] && printf 'knowledge/inbox/*\n!knowledge/inbox/.gitkeep\n.env\n.env.*\n*.pem\n*.key\n*.p12\nnode_modules/\n.DS_Store\n' >> "$W/.gitignore"
}
if [ "$cmd" = join ]; then
  tmp="$W.cos-join-$$"   # cloned aside, so a wrong link leaves nothing where the workspace goes
  git clone -q -c core.symlinks=false "$url" "$tmp" 2>&1 | head -n 3 >&2
  if [ ! -f "$tmp/.chief-of-staff" ] || ! grep -qx 'shared: yes' "$tmp/.chief-of-staff"; then
    rm -rf "$tmp"; die "$url is not a shared chief-of-staff workspace (no 'shared: yes' marker, or no access); nothing was created"
  fi
  # what sync.sh pull refuses, refused at join too: settings and hooks that run code here, a marker inside a folder
  # (it would split the workspace and switch its gates off) and an owner's OK, which never comes from the team
  bad=$(git -C "$tmp" ls-files 2>/dev/null | grep -Ei '(^|/)(\.claude/|\.mcp\.json$|\.gitattributes$|\.owner-ok$|\.owner-items$)|/\.chief-of-staff$|/\.gitignore$' | head -n 3 | tr '\n' ' ')
  if [ -n "$bad" ]; then rm -rf "$tmp"; die "$url holds files that would run code or stand in for the owner here ($bad): ask the teammate who added them to remove them; nothing was created"; fi
  # the marker keeps only what makes it a shared workspace: pace, library and team lines are this computer's to set
  # (sync.sh pull refuses any later change to it), so the team repo cannot set them for the joiner
  ign=$(sed -n '2,$p' "$tmp/.chief-of-staff" | grep -vx 'shared: yes' | tr -d '\000-\037' | cut -c1-80 | head -n 3 | tr '\n' ';' | sed 's/;$//; s/;/; /g')
  printf 'chief-of-staff workspace v0.1\nshared: yes\n' > "$tmp/.chief-of-staff"
  { [ ! -d "$W" ] || rmdir "$W"; } && mv "$tmp" "$W" || { rm -rf "$tmp"; die "cannot create $W"; }
  chmod 444 "$W/.chief-of-staff"
  [ -n "$ign" ] && echo "Ignored from the team's marker: $ign (set on this computer only, by its owner)"
  git -C "$W" config core.symlinks false
  git -C "$W" config cos.member "$member"
  git -C "$W" config user.name >/dev/null || git -C "$W" config user.name "$member"
  git -C "$W" config user.email >/dev/null || git -C "$W" config user.email "chief-of-staff@localhost"
  echo "Workspace: $W (shared, you are $member)"
  echo "Library: $W/knowledge (the team's)"
  exit 0
fi
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
ignore
git -C "$W" init -q
git -C "$W" config user.name >/dev/null || git -C "$W" config user.name "chief-of-staff"
git -C "$W" config user.email >/dev/null || git -C "$W" config user.email "chief-of-staff@localhost"
{ printf 'chief-of-staff workspace v0.1\n'; [ -n "$share" ] && printf 'shared: yes\n'; } > "$W/.chief-of-staff"; chmod 444 "$W/.chief-of-staff"   # last: a failed run can be repeated

if [ -n "$libdest" ]; then
  out=$(CLAUDE_PROJECT_DIR="$W/central" sh "$here/library.sh" offload "$libdest" 2>&1) ||
    die "the workspace is in $W, but the library could not go to $libdest: $out"
  rm -rf "$W"/knowledge.offloaded-*   # the empty library just made; nothing to keep
  echo "Library: $libdest"
else
  echo "Library: $W/knowledge"
fi
if [ -n "$join" ]; then   # a failed join leaves the workspace usable: the owner can join later from central
  CLAUDE_PROJECT_DIR="$W/central" sh "$here/library.sh" join "$join" 2>&1 | sed 's/^library: //; s/^/Team library: /' | head -n 3
fi
git -C "$W" add -A && git -C "$W" commit -qm "chief-of-staff: new workspace"
echo "Workspace: $W"
if [ -n "$share" ]; then
  git -C "$W" config cos.member "$member"; git -C "$W" config core.symlinks false
  git -C "$W" remote add origin "$share"
  if e=$(git -C "$W" push -q -u origin HEAD 2>&1); then echo "Shared: pushed to $share; teammates join with setup.sh join <folder> $share --member <name>"
  else echo "Shared: the first push to $share failed ($(printf '%s' "$e" | head -n 1 | cut -c1-160)); the first turn that ends retries it"; fi
  exit 0
fi

[ -n "$backup" ] || { echo "Backup: none yet: the workspace is only on this computer. Ask central to back it up to a private GitHub repo when you want one."; exit 0; }
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "Backup: not done, the GitHub tool (gh) is not installed or not signed in on this computer. Install it and run gh auth login, then ask central to back it up."; exit 0
fi
name=$(basename "$W")
if gh repo create "$name" --private --source "$W" --remote origin --push >/dev/null 2>&1; then
  echo "Backup: private GitHub repo $name, pushed."
else
  echo "Backup: not done, the private GitHub repo $name could not be created (one with that name may exist). Ask central to back it up under another name."
fi
# the library outside the workspace is its own git repo (not in a synced cloud folder: the provider keeps the versions)
if [ -n "$libdest" ] && [ -d "$libdest/.git" ]; then
  if gh repo create "$name-library" --private --source "$libdest" --remote origin --push >/dev/null 2>&1; then
    echo "Library backup: private GitHub repo $name-library, pushed."
  else
    echo "Library backup: not done, the private GitHub repo $name-library could not be created. Ask central to back up $libdest under another name."
  fi
fi
exit 0
