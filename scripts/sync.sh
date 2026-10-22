#!/bin/sh
# Team library sync. The hooks run it in the background; it never waits for a password (GIT_TERMINAL_PROMPT=0).
#   sync.sh pull <library>                          at session start: fast-forward to the team's latest notes
#   sync.sh push <library> <session> <workspace>    after a turn whose notes passed the gate: commit, rebase, push.
#                                                   A conflict is undone and becomes a card in <workspace>/board/
#                                                   owned by that session (never the owner).
# The last result is one line in <library>/.git/cos-sync, shown by the briefing and by library.sh libs.
export GIT_TERMINAL_PROMPT=0
cmd=${1:-}; q=${2:-}
[ -d "$q/.git" ] || exit 0
lk="$q/.git/cos-sync.lock"; mkdir "$lk" 2>/dev/null || exit 0   # one sync at a time per library
trap 'rmdir "$lk"' EXIT
say() { printf '%s %s\n' "$(date '+%F %T')" "$*" > "$q/.git/cos-sync"; }
first() { printf '%s' "$1" | tr -d '\000-\037' | cut -c1-160; }
g() { git -C "$q" "$@"; }

case $cmd in
  pull)
    if e=$(g pull -q --ff-only 2>&1); then say "pulled ok"; else say "pull failed: $(first "$e")"; fi ;;
  push)
    s=${3:-central} w=${4:-}
    g config user.name >/dev/null || g config user.name chief-of-staff
    g config user.email >/dev/null || g config user.email chief-of-staff@localhost
    g add -A -- notes templates
    g diff --cached --quiet || g commit -qm "notes from $s"
    if ! e=$(g pull -q --rebase 2>&1); then
      if g rebase --abort 2>/dev/null; then   # a real conflict: same note changed here and by a teammate
        n=$(basename "$q"); say "conflict: a teammate changed the same notes; card in board/"
        c="$w/board/Library conflict - $n.md"
        if [ -n "$w" ] && [ -d "$w/board" ] && [ ! -f "$c" ]; then
          d=$(date +%F)
          cat > "$c" <<CARD
---
tags:
  - board
status: in-progress
project: $s
owner: session-$s
due:
since: $d
updated: $d
---

# Library conflict - $n

Notes saved here clash with a teammate's change to the same notes in the team library $n ($q).
Nothing was lost: your notes are committed locally, the team's are on the remote.

To do (this session, not the owner):
1. git -C "$q" pull --rebase
2. For each conflicting note, apply the library rule: keep the better version and retire the worse one
   (library.sh retire), or merge both into one note. Never drop a teammate's note to win the conflict.
3. git -C "$q" add notes && git -C "$q" rebase --continue
4. sh "$(cd "$(dirname "$0")" && pwd)/sync.sh" push "$q" $s "$w", then delete this card.
CARD
        fi
        exit 1
      fi
      say "pull failed: $(first "$e")"; exit 1   # offline or no access: the commit waits for the next turn
    fi
    if e=$(g push -q 2>&1); then say "pushed ok"; else say "push failed: $(first "$e")"; fi ;;
  *) echo "usage: sync.sh pull <library> | sync.sh push <library> <session> <workspace>" >&2; exit 1 ;;
esac
