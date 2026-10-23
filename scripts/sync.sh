#!/bin/sh
# Team sync of a team library, or of a whole shared workspace (<library> = the workspace root). The hooks run it
# in the background; it never waits for a password (GIT_TERMINAL_PROMPT=0).
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
# a push waits for a pull that holds the lock (the last turn of a session must still go out); a pull does not wait
n=0; while ! mkdir "$lk" 2>/dev/null; do
  n=$((n + 1)); [ "$cmd" = push ] && [ $n -lt 30 ] || { say "sync busy (another sync runs); the next turn retries"; exit 0; }; sleep 1
done
echo $$ > "$lk/pid"; trap 'rm -f "$lk/pid"; rmdir "$lk"' EXIT
first() { printf '%s' "$1" | tr -d '\000-\037' | cut -c1-160; }
g() { git -C "$q" -c core.symlinks=false "$@"; }   # a symlink a teammate pushed stays a plain file
# settings, hooks and git rules run code on this computer: a change to them from the remote is never taken
# (letter case ignored: macOS reads .CLAUDE/ as .claude/; a remote whose changes cannot be listed is refused too)
incoming_bad() {
  # fail closed: with no common history git cannot list what changed, and an empty list would pass
  g merge-base HEAD '@{u}' >/dev/null 2>&1 || { echo "changes that cannot be listed"; return; }
  g diff -z --name-only HEAD...'@{u}' 2>/dev/null | tr '\0' '\n' | grep -Ei '(^|/)(\.claude/|\.mcp\.json$|\.gitattributes$|\.gitignore$|\.chief-of-staff$|\.owner-ok$|\.owner-items$)' | head -n 3 | tr '\n' ' '
}
refused() { say "pull refused: the remote changes settings that run code here ($1); ask the teammate to remove that change"; }

case $cmd in
  pull)
    g rev-parse -q --verify '@{u}' >/dev/null || { say "nothing to pull yet: the team copy was never pushed"; exit 0; }
    if ! e=$(g fetch -q 2>&1); then say "pull failed: $(first "$e")"; exit 0; fi
    bad=$(incoming_bad)
    if [ -n "$bad" ]; then refused "$bad"
    elif e=$(g merge -q --ff-only '@{u}' 2>&1); then say "pulled ok"
    elif [ -n "$(g log --oneline '@{u}..' 2>/dev/null)" ]; then say "local notes not pushed yet; the next push merges the team's"
    else say "pull failed: $(first "$e")"; fi ;;
  push)
    s=${3:-central} w=${4:-}
    g config user.name >/dev/null || g config user.name chief-of-staff
    g config user.email >/dev/null || g config user.email chief-of-staff@localhost
    if [ $# -ge 4 ]; then shift 4; else shift $#; fi
    # what leaves is one commit: the last shared state plus exactly the gated files, as they were gated. Commits
    # made by hand in this folder are folded in, so their content never leaves unless the gate saw it
    # (the index goes back too, so a file a hand commit carried, and the gate did not list, stays here)
    b=$(g merge-base HEAD '@{u}' 2>/dev/null || g rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1)
    [ -n "$b" ] && g reset -q "$b"
    if [ $# -gt 0 ] && ! e=$(g --literal-pathspecs add -A -- "$@" 2>&1); then   # only what the gate passed
      g reset -q; say "push failed: $(first "$e")"; exit 1; fi
    g diff --cached --quiet || g commit -qm "update from $s"
    if ! g rev-parse -q --verify '@{u}' >/dev/null; then   # the first push failed at join: push now, nothing to merge
      if e=$(g push -q -u origin HEAD 2>&1); then say "pushed ok"; else say "push failed: $(first "$e")"; fi; exit 0
    fi
    # files the gate held back stay uncommitted: autostash keeps them out of the way of the rebase
    if ! e=$(g fetch -q 2>&1); then say "push failed: $(first "$e")"; exit 1; fi
    bad=$(incoming_bad); [ -n "$bad" ] && { refused "$bad"; exit 1; }
    if ! e=$(g rebase -q --autostash '@{u}' 2>&1); then
      if g rebase --abort 2>/dev/null; then   # a real conflict: same note changed here and by a teammate
        n=$(basename "$q"); say "conflict: a teammate changed the same files; card in board/"
        c="$w/board/Sync conflict - $n.md"
        if [ -n "$w" ] && [ -d "$w/board" ] && [ ! -f "$c" ]; then
          d=$(date +%F)
          cat > "$c" <<CARD
---
tags:
  - board
status: in-progress
project: $s
owner: session-$s
member: $(git -C "$q" config cos.member 2>/dev/null | tr -d '\000-\037')
due:
since: $d
updated: $d
---

# Sync conflict - $n

Files saved here clash with a teammate's change to the same files in $q.
Nothing was lost: your changes are committed locally, the team's are on the remote.

To do (this session, not the owner):
1. git -C "$q" pull --rebase
2. For each conflicting file, keep both changes. For a library note, apply the library rule: keep the
   better version and retire the worse one (library.sh retire), or merge both into one note. Never
   drop a teammate's change to win the conflict.
3. git -C "$q" add <the files> && git -C "$q" rebase --continue
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
