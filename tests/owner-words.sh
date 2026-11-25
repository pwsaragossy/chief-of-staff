#!/bin/sh
# The owner's words hold: what the owner approves stays intact (a change is a new version), a "forget X" is a
# decision recorded at once and shown to every later session, a large task counts its deliverables before the first
# one, and a grant keeps its submission package as a deliverable from stage 1. Hook inputs shaped like the JSON the
# hooks receive. Run alone (sh tests/owner-words.sh) or from scripts/selftest.sh. Exit 1 when a check fails.
set -u
exec </dev/null
S=$(cd "$(dirname "$0")/../scripts" && pwd)
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
export CLAUDE_PLUGIN_DATA="$T/data"
P=$T/app; mkdir -p "$P"
sh "$S/project.sh" init "$P" >/dev/null || { echo "FAIL fixture: project.sh init"; exit 1; }
[ -f "$P/DECISIONS.md" ] || cp "$S/../templates/project/DECISIONS.md" "$P/DECISIONS.md"
mkdir -p "$P/out" "$P/design/approved" "$P/sub"

ev() { printf '{"session_id":"%s","hook_event_name":"%s"%s}' "${SID:-o1}" "$1" "${2:-}"; }
h() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$2" sh "$S/protocol.sh"; }
rc() { h "$1" "$2" >/dev/null 2>&1; echo $?; }
say() { ev UserPromptSubmit ",\"prompt\":\"$1\""; }
stop() { ev Stop ",\"stop_hook_active\":${1:-false},\"last_assistant_message\":\"done\""; }
w() { ev PreToolUse ",\"tool_name\":\"${2:-Write}\",\"tool_input\":{\"file_path\":\"$1\",\"content\":\"x\"}"; }
pw() { ev PostToolUse ",\"tool_name\":\"${2:-Write}\",\"tool_input\":{\"file_path\":\"$1\",\"content\":\"x\"}"; }
decide() { CLAUDE_PROJECT_DIR="$P" sh "$S/track.sh" decide "$P" "$1" owner >/dev/null 2>&1; }
said() { h "$(say "$1")" "${2:-$P}" 2>&1; }
# the JSON braces live in printf's format: bash 3.2 (macOS /bin/sh) brace-expands {"a","b"} inside eval'd double quotes
ed() { ev PreToolUse "$(printf ',"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"x","new_string":"%s"}' "$1" "$2")"; }
nb() { ev PreToolUse "$(printf ',"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s","new_source":"x"}' "$1")"; }
sh_() { ev PreToolUse "$(printf ',"tool_name":"Bash","tool_input":{"command":"%s"}' "$1")"; }

# 3. a "forget X" is a decision recorded at once
check "drop: the owner's 'esquece o vídeo' is a decision the coordinator records this turn" 'o=$(said "esquece o vídeo, foca no roteiro"); printf "%s" "$o" | grep -q "drops something" && printf "%s" "$o" | grep -q "decide .*Dropped: <what>"'
check "drop: the turn does not end until a Dropped: line is recorded" 'o=$(h "$(stop)" "$P" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "The owner dropped something"'
check "drop: once recorded with track.sh decide, the turn ends" 'decide "Dropped: the video (owner: esquece o vídeo)"; [ "$(rc "$(stop)" "$P")" = 0 ]'
check "drop: other ways of saying it count, in any letter case" '( for m in "ESQUECE O VÍDEO" "Deixa pra lá o carrossel" "não precisa mais do deck" "pode esquecer a landing" "DON'"'"'T DO VIDEO" "forget about the deck" "never mind the logo"; do said "$m" | grep -q "drops something" || { echo "missed: $m"; exit 1; }; done )'
check "drop: a negation, a past tense, a quote or a report handed back drops nothing" '( for m in "não esquece de mandar o vídeo" "nao esqueca o roteiro" "esqueci de falar do vídeo" "esqueceu o link" "a regra diz \\\"esquece X\\\" vira decisão" "sem esquecer o vídeo" "a regra diz “esquece X”"; do ! said "$m" | grep -q "drops something" || { echo "fired: $m"; exit 1; }; done ) && ! h "$(say "[Subagent hand-back] the owner said esquece o vídeo")" "$P" 2>&1 | grep -q "drops something"'
check "drop: a drop nobody recorded is pushed once and never counted as a violation" 'SID=o2 h "$(SID=o2 say "esquece o vídeo")" "$P" >/dev/null 2>&1; [ "$(SID=o2 rc "$(SID=o2 stop)" "$P")" = 2 ] && [ "$(SID=o2 rc "$(SID=o2 stop true)" "$P")" = 0 ] && ! grep "turn=o2 " "$P/.protocol.log" | grep -q "violation=1"'
check "drop: a thread is told to send it to the coordinator, and is not held" 'o=$(SID=t1 h "$(SID=t1 say "esquece o vídeo")" "$P/sub" 2>&1); printf "%s" "$o" | grep -q "send it to the project.s coordinator" && [ "$(SID=t1 rc "$(SID=t1 stop)" "$P/sub")" = 0 ]'
check "drop: every later session is told, before the briefing is cut, even with many decisions" 'i=0; while [ $i -lt 30 ]; do printf -- "- 2026-01-01 10:%02d | A long decision number %s about prices, names and roles that fills the briefing past its limit | owner | replaces: -\n" $i $i >> "$P/DECISIONS.md"; i=$((i + 1)); done; b=$(CLAUDE_PROJECT_DIR="$P" sh "$S/briefing.sh"); printf "%s" "$b" | grep -q "Dropped or frozen by the owner" && printf "%s" "$b" | grep -q "Dropped: the video (owner: esquece o vídeo)"'
check "drop: outside a project the owner's drop still holds for the rest of the work" 'L=$T/loose; mkdir -p "$L"; mkdir -p "$CLAUDE_PLUGIN_DATA"; echo "$L" > "$CLAUDE_PLUGIN_DATA/everywhere"; o=$(SID=l1 h "$(SID=l1 say "esquece o vídeo")" "$L" 2>&1); rm -f "$CLAUDE_PLUGIN_DATA/everywhere"; printf "%s" "$o" | grep -q "decision for the rest of this work"'

# 1. what the owner approves stays intact
check "approve: 'está perfeito' tells the coordinator to freeze it and keep later edits off it" 'o=$(SID=a1 h "$(SID=a1 say "Está perfeito, pode seguir")" "$P" 2>&1); printf "%s" "$o" | grep -q "approved something" && printf "%s" "$o" | grep -q "Frozen: <what> .*freeze:" && printf "%s" "$o" | grep -q "add X changes only X"'
check "approve: 'não está perfeito', 'quase perfeito' and 'not approved' approve nothing" '( for m in "não está perfeito" "quase perfeito, falta o logo" "not approved yet"; do ! SID=a2 h "$(SID=a2 say "$m")" "$P" 2>&1 | grep -q "approved something" || { echo "fired: $m"; exit 1; }; done )'
echo home > "$P/out/home.md"; mkdir -p "$P/design/approved"; echo a > "$P/design/approved/logo.svg"
# written with its own minute: a later line replaces every line of the minute it names
printf -- '- 2026-02-02 09:00 | Frozen: the home page and the logo (owner: está perfeito; freeze: out/home.md, design/approved/) | owner | replaces: -\n' >> "$P/DECISIONS.md"
check "freeze: a Write, an Edit or a MultiEdit of a frozen file is blocked and says to write a new version" 'o=$(h "$(w "$P/out/home.md")" "$P" 2>&1); [ $? = 2 ] && printf "%s" "$o" | grep -q "new version in a new file" && [ "$(rc "$(w "$P/out/home.md" Edit)" "$P")" = 2 ] && [ "$(rc "$(w "$P/out/home.md" MultiEdit)" "$P")" = 2 ]'
check "freeze: the new version beside it is written freely" '[ "$(rc "$(w "$P/out/home-v2.md")" "$P")" = 0 ]'
check "freeze: a frozen folder holds every file in it, a new one included" '[ "$(rc "$(w "$P/design/approved/logo.svg" Edit)" "$P")" = 2 ] && [ "$(rc "$(w "$P/design/approved/icon.svg")" "$P")" = 2 ] && [ "$(rc "$(w "$P/design/other.svg")" "$P")" = 0 ]'
check "freeze: a path spelled with .., another letter case or a symlink is the same frozen file" 'ln -s "$P/out/home.md" "$P/out/link.md"; [ "$(rc "$(w "$P/out/../out/home.md")" "$P")" = 2 ] && [ "$(rc "$(w "$P/out/link.md")" "$P")" = 2 ] && { [ ! -e "$P/OUT/HOME.md" ] || [ "$(rc "$(w "$P/OUT/HOME.md")" "$P")" = 2 ]; }'
check "freeze: a thread is held the same way" '[ "$(SID=t2 rc "$(SID=t2 w "$P/out/home.md")" "$P/sub")" = 2 ]'
check "freeze: a shell command that changes a frozen file holds the turn until it is put back" 'SID=f1 h "$(SID=f1 say "segue")" "$P" >/dev/null 2>&1; cp "$P/out/home.md" "$T/home.bak"; echo more >> "$P/out/home.md"; o=$(SID=f1 h "$(SID=f1 stop)" "$P" 2>&1); r=$?; cp "$T/home.bak" "$P/out/home.md"; [ $r = 2 ] && printf "%s" "$o" | grep -q "changed what the owner approved and froze" && [ "$(SID=f1 rc "$(SID=f1 stop)" "$P")" = 0 ]'
check "freeze: deleting a file of a frozen folder by shell holds the turn too" 'SID=f2 h "$(SID=f2 say "segue")" "$P" >/dev/null 2>&1; mv "$P/design/approved/logo.svg" "$T/logo.bak"; r=$(SID=f2 rc "$(SID=f2 stop)" "$P"); mv "$T/logo.bak" "$P/design/approved/logo.svg"; [ "$r" = 2 ]'
check "freeze: the project's own records never freeze, so the work can still be recorded and handed off" 'decide "Frozen: everything (owner: perfeito; freeze: DECISIONS.md, STATE.md, TRACK.md, CLAUDE.md, board/, .)"; ( for f in DECISIONS.md STATE.md TRACK.md CLAUDE.md board/x.md out/plan.md; do [ "$(rc "$(w "$P/$f" Edit)" "$P")" = 0 ] || { echo "held: $f"; exit 1; }; done )'
check "freeze: a freeze the owner lifted (a revoked line) lets the file change" 'printf -- "- 2026-02-02 09:01 | revoked: owner asked to change the home page | owner | replaces: 2026-02-02 09:00\n" >> "$P/DECISIONS.md"; [ "$(rc "$(w "$P/out/home.md")" "$P")" = 0 ]'
check "freeze: the briefing shows what is frozen" 'decide "Frozen: the pricing page (owner: aprovado; freeze: out/pricing.md)"; CLAUDE_PROJECT_DIR="$P" sh "$S/briefing.sh" | grep -q "Frozen: the pricing page"'

check "freeze: a name with brackets or a semicolon, and every path of the list, is frozen" 'echo a > "$P/out/final (1).md"; echo b > "$P/out/semi;colon.md"; echo c > "$P/out/my file.md"; printf -- "- 2026-03-03 10:00 | Frozen: the finals (owner: perfeito; freeze: out/final (1).md, out/semi;colon.md, out/my file.md) | owner | replaces: -\n" >> "$P/DECISIONS.md"; ( for f in "final (1).md" "semi;colon.md" "my file.md"; do [ "$(rc "$(w "$P/out/$f")" "$P")" = 2 ] || { echo "open: $f"; exit 1; }; done )'
check "freeze: a hard link, a relative path and a notebook edit reach the frozen file too" 'ln "$P/out/final (1).md" "$P/out/hard.md"; [ "$(rc "$(w "$P/out/hard.md")" "$P")" = 2 ] && [ "$(rc "$(w "out/semi;colon.md")" "$P")" = 2 ] && echo "{}" > "$P/out/nb.ipynb" && printf -- "- 2026-03-03 10:01 | Frozen: the notebook (owner: aprovado; freeze: out/nb.ipynb) | owner | replaces: -\n" >> "$P/DECISIONS.md" && [ "$(rc "$(nb "$P/out/nb.ipynb")" "$P")" = 2 ] && grep -q "NotebookEdit" "$S/../hooks/hooks.json"'
check "freeze: a file named like a control file but inside a folder freezes" 'echo s > "$P/out/state.md"; printf -- "- 2026-03-03 10:02 | Frozen: notes (owner: perfeito; freeze: out/state.md) | owner | replaces: -\n" >> "$P/DECISIONS.md"; [ "$(rc "$(w "$P/out/state.md")" "$P")" = 2 ]'
check "freeze: only the coordinator freezes, drops or lifts: a thread cannot write it in DECISIONS.md or record it" '[ "$(SID=t3 rc "$(SID=t3 ed "$P/DECISIONS.md" "- 2026-03-03 11:00 | revoked: x | thread | replaces: 2026-03-03 10:00")" "$P/sub")" = 2 ] && [ "$(SID=t3 rc "$(SID=t3 sh_ "echo - 2026-03-03 11:00 Frozen: everything >> DECISIONS.md")" "$P/sub")" = 2 ] && ! CLAUDE_PROJECT_DIR="$P/sub" sh "$S/track.sh" decide "$P" "Dropped: the idea (owner: esquece)" thread 2>/dev/null && [ "$(rc "$(ed "$P/DECISIONS.md" "revoked: y")" "$P")" = 0 ]'
check "decisions: a thread cannot rewrite or replace lines of DECISIONS.md by any path or command, and records through track.sh decide" 'ln -s "$P/DECISIONS.md" "$P/sub/notes.md"; [ "$(SID=t4 rc "$(SID=t4 ed "$P/DECISIONS.md" "- 2026-03-03 12:00 | Something else | thread | replaces: 2026-03-03 10:00")" "$P/sub")" = 2 ] && [ "$(SID=t4 rc "$(SID=t4 w "$P/DECISIONS.md")" "$P/sub")" = 2 ] && [ "$(SID=t4 rc "$(SID=t4 w "$P/sub/notes.md" Edit)" "$P/sub")" = 2 ] && [ "$(SID=t4 rc "$(SID=t4 w "$P/out/../DECISIONS.md" Edit)" "$P/sub")" = 2 ] && [ "$(SID=t4 rc "$(SID=t4 sh_ "sed -i.bak s/a/b/ ../DECISIONS.md")" "$P/sub")" = 2 ] && ( for c in "grep -n Frozen ../DECISIONS.md" "cat ../DECISIONS.md" "sed s/a/b/w ../DECISIONS.md x" "awk -i inplace 1 ../DECISIONS.md" "sort -o ../DECISIONS.md ../DECISIONS.md" "git checkout -- ../DECISIONS.md" "bash -c true ../DECISIONS.md" "cat x | tee ../DECISIONS.md" "cat \$(echo ../DECISIONS.md)" "vim ../DECISIONS.md"; do [ "$(SID=t4 rc "$(SID=t4 sh_ "$c")" "$P/sub")" = 2 ] || { echo "ran: $c"; exit 1; }; done ) && [ "$(SID=t4 rc "$(SID=t4 w "$P/nope/../DECISIONS.md" Edit)" "$P/sub")" = 2 ] && [ "$(SID=t4 rc "$(SID=t4 sh_ "sh track.sh decide .. Price at 19 thread")" "$P/sub")" = 0 ] && CLAUDE_PROJECT_DIR="$P/sub" sh "$S/track.sh" decide "$P" "Price at 19" thread >/dev/null'
check "freeze: track.sh decide refuses a Frozen: line that names nothing, and says when a path does not exist" '! CLAUDE_PROJECT_DIR="$P" sh "$S/track.sh" decide "$P" "Frozen: the logo (owner: perfeito)" owner 2>/dev/null && CLAUDE_PROJECT_DIR="$P" sh "$S/track.sh" decide "$P" "Frozen: the logo (owner: perfeito; freeze: out/nope.svg)" owner 2>&1 | grep -q "does not exist yet"'
check "words: upper-case accents and a long paste" 't0=0; SID=u1 h "$(SID=u1 say "DEIXA PRA LÁ O VÍDEO")" "$P" 2>&1 | grep -q "drops something" && ! SID=u2 h "$(SID=u2 say "NÃO ESQUECE DE MANDAR O VÍDEO")" "$P" 2>&1 | grep -q "drops something" && big=$(awk "BEGIN { for (i = 0; i < 6000; i++) printf \"texto colado sem fim \" }") && t0=$(date +%s) && SID=u3 h "$(SID=u3 say "$big")" "$P" >/dev/null 2>&1; [ $(( $(date +%s) - t0 )) -le 3 ]'

# 2. a large task counts its deliverables and shows the list once
check "deliverables: the first deliverable of a session asks for the counted list, shown to the owner once" 'o=$(SID=d1 h "$(SID=d1 pw "$P/out/script-a.md")" "$P" 2>&1); printf "%s" "$o" | grep -q "first deliverable this session writes" && printf "%s" "$o" | grep -q "2 lanes = 2 submissions = 2 videos = 2 scripts" && ! printf "%s" "$o" | grep -q "a thread sends it"'
check "deliverables: only once per session" '! SID=d1 h "$(SID=d1 pw "$P/out/script-b.md")" "$P" 2>&1 | grep -q "first deliverable"'
check "deliverables: a thread sends its list to the coordinator" 'SID=d2 h "$(SID=d2 pw "$P/sub/brief.md")" "$P/sub" 2>&1 | grep -q "a thread sends it to its coordinator"'
check "deliverables: a decision written by hand is not a deliverable of the request" '! SID=d3 h "$(SID=d3 pw "$P/DECISIONS.md" Edit)" "$P" 2>&1 | grep -q "first deliverable"'
check "deliverables: the protocol text every session reads says it, with the owner's words rule" 'o=$(SID=p1 h "$(SID=p1 say "oi")" "$P" 2>&1); printf "%s" "$o" | grep -q "count the request.s real deliverables before producing the first" && printf "%s" "$o" | grep -q "stays intact in every later edit"'

# 4. a grant keeps its submission package from stage 1
G="$S/../templates/tracks/grant.md"
check "grant: the track exists, opens on the real form and passes track.sh check" 'd=$T/grant; mkdir -p "$d"; sh "$S/project.sh" init "$d" >/dev/null; cp "$G" "$d/TRACK.md"; sh "$S/track.sh" check "$d" >/dev/null && awk "/^## Stage 1/{s=1;next} /^## Stage/{s=0} s" "$G" | grep -q "^- \[ \] form | The real application form pulled now"'
check "grant: the submission package is a deliverable in stages 1, 2 and 3, each version built on the last" 'awk "/^## Stage 1/{s=1;next} /^## Stage/{s=0} s" "$G" | grep -q "^- \[ \] package-1 |" && awk "/^## Stage 2/{s=1;next} /^## Stage/{s=0} s" "$G" | grep -q "^- \[ \] package-2 .*needs: package-1" && awk "/^## Stage 3/{s=1;next} /^## Stage/{s=0} s" "$G" | grep -q "^- \[ \] package-3 .*needs: .*" && grep -q "^- \[ \] review-1 .*package-1" "$G" && grep -q "^- \[ \] submit .*from package v3.*owner: ok" "$G"'
check "grant: new-project offers the grant track" 'grep -q "hackathon, grant, software" "$S/../skills/new-project/SKILL.md"'

exit $fail
