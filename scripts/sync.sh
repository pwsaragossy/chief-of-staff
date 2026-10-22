#!/bin/sh
# Team library sync. The hooks run it in the background; it never waits for a password (GIT_TERMINAL_PROMPT=0).
#   sync.sh pull <library>                          at session start: fast-forward to the team's latest notes
#   sync.sh push <library> <session> <workspace> [file...]   after a turn whose notes passed the gate: commit only
#                                                   those files (paths inside the library), rebase, push.
#                                                   A conflict is undone and becomes a card in <workspace>/board/
#                                                   owned by that session (never the owner).
# The last result is one line in <library>/.git/cos-sync, shown by the briefing and by library.sh libs.
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true
# ssh reads the terminal for a passphrase or a new host key: in the background it must fail instead
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3"
cmd=${1:-}; q=${2:-}
[ -d "$q/.git" ] || exit 0
say() { printf '%s %s\n' "$(date '+%F %T')" "$*" > "$q/.git/cos-sync"; }
# one sync at a time per library; a lock older than 10 minutes was left by a killed sync
lk="$q/.git/cos-sync.lock"
# a lock whose sync is gone (killed, power cut) is stale: its pid no longer runs
[ -d "$lk" ] && ! kill -0 "$(cat "$lk/pid" 2>/dev/null || echo none)" 2>/dev/null && rm -f "$lk/pid" && rmdir "$lk" 2>/dev/null
mkdir "$lk" 2>/dev/null || { say "sync busy (another sync runs); the next turn retries"; exit 0; }
echo $$ > "$lk/pid"; trap 'rm -f "$lk/pid"; rmdir "$lk"' EXIT
first() { printf '%s' "$1" | tr -d '\000-\037' | cut -c1-160; }
g() { git -C "$q" -c core.symlinks=false "$@"; }   # a symlink a teammate pushed stays a plain file

case $cmd in
  pull)
    g rev-parse -q --verify '@{u}' >/dev/null || { say "nothing to pull yet: the team library was never pushed"; exit 0; }
    if e=$(g pull -q --ff-only 2>&1); then say "pulled ok"
    elif [ -n "$(g log --oneline '@{u}..' 2>/dev/null)" ]; then say "local notes not pushed yet; the next push merges the team's"
    else say "pull failed: $(first "$e")"; fi ;;
  push)
    s=${3:-central} w=${4:-}
    g config user.name >/dev/null || g config user.name chief-of-staff
    g config user.email >/dev/null || g config user.email chief-of-staff@localhost
    if [ $# -ge 4 ]; then shift 4; else shift $#; fi
    [ $# -gt 0 ] && g add -A -- "$@"   # only what the gate passed: anything else stays local
    g diff --cached --quiet || g commit -qm "notes from $s"
    if ! g rev-parse -q --verify '@{u}' >/dev/null; then   # the first push failed at join: push now, nothing to merge
      if e=$(g push -q -u origin HEAD 2>&1); then say "pushed ok"; else say "push failed: $(first "$e")"; fi; exit 0
    fi
    # files the gate held back stay uncommitted: autostash keeps them out of the way of the rebase
    if ! e=$(g pull -q --rebase --autostash 2>&1); then
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
