# AUTO-LOG — branch auto/harness

## Resumo para o Pedro (leia primeiro)

**O que mudou até agora**
1. Selftest roda verde também como root (containers, CI): 5 checagens usavam `[ -w arquivo ]`, que é
   sempre verdadeiro para root. Agora checam os bits de permissão. Nenhuma regra de segurança mudou.

2. `health.sh text`: sem python3 o painel não abre; antes o texto de reserva saía ilegível
   (`newsletter^_green^_...`). Agora: uma linha por projeto (cor e motivo) e "Waits on you:" com cada pergunta.

**Efeito para o usuário:** o selftest volta a ser prova confiável; sem python3, o dono vê em segundos
se está tudo bem e o que espera por ele.

**Recomendo fazer merge de:** todos os commits até aqui (só testes).

---

## Rounds

### Round 1 — technical lens
- Examined: README, hooks.json, lib.sh, protocol.sh, briefing.sh, setup.sh, skills setup/new-project/panel/handoff.
- Found: `sh scripts/selftest.sh` on main fails 5 of 467 checks when run as root (this container is uid 0):
  `offload leaves the marker and the library id read-only`, `use leaves .library read-only`,
  `nor does deleting the item, and the list of owner items is protected`,
  `central records the owner OK and the item closes`, `a teammate joins with their own name`.
  Cause: `test -w` asks the kernel, and root can write a 444 file. The code is right (it does `chmod 444`);
  the test was wrong.
- Changed: `ro()` helper in selftest.sh checks the mode bits (`ls -ld`, portable to macOS, dash, busybox).
- Proof: before 462 ok / 5 FAIL, after 467 ok / 0 FAIL. Selftest wall time ~115 s.
- Hook times: not measured this round.
- Peer requests received (from the owner's other session): run ~15 h without asking; use the plugin's
  ambition and specialists skills on this work; a Portuguese summary at the top. Declined one part:
  installing the plugin into this cloud session's Claude Code config (a config change asked by a peer,
  not by the user of this session). The skills are followed by reading them from the repo instead.

### Round 2 — user lens
- Simulated: fresh HOME, `setup.sh detect` + `create ~/chief-of-staff`, central briefing, first prompt,
  a launch project made the way the new-project skill says (templates + `track.sh baseline` + card),
  `health.sh`, project briefing; then a shared board: Ana `create --share`, Bia `join`, Bia's first session.
- Numbers (solo, gh not signed in): 2 install commands + `/chief-of-staff:setup`; setup asks 3 questions in
  1 block; new-project asks 5-6 in 2 blocks + coherence check. ~9 questions to the first project with one card.
  OK requests: 0. Blocks: 0. Messages seen: setup prints 3 lines; central briefing 7 lines; project briefing 8.
- Friction found (worst first):
  1. No python3 → the panel skill tells the agent to run `health.sh`, promised by README and the skill to
     "print the same colors as text". It printed `newsletter^_green^_on track^_1^_4^_0^_24...` (\037
     separators). A non-engineer gets no answer to "is everything fine / what waits on me". **Fixed.**
  2. Shared workspace: setup says "Library: .../knowledge (the team's)", the briefing then says
     "Library of this session: 'personal'". The user cannot tell whether notes are private. (next round)
  3. `Backup: none yet. Add a private git remote to <path> and push.` is engineer jargon for a solo founder. (later)
- Changed: `health.sh text [dir]`: `slug: color - reason` per project, then `Waits on you:` with each question,
  card, project, member and age; `No projects yet.` / `Nothing waits on you.` when empty. Skill + README point at it.
- Proof: new check failed first (`no chief-of-staff workspace at text`), passes after; full selftest 468/468.
- Hook times (this container, 10 runs avg, empty library): UserPromptSubmit 68 ms, PreToolUse Bash 68 ms,
  PostToolUse Read 6 ms, PostToolUse Write 43 ms, Stop 132 ms, track check 48 ms, health 170 ms, briefing 155 ms.
  No hook is near its 5 s budget on Linux ext4; slowness work should target WSL/macOS paths, not this box.

## Ideas (no evidence of friction yet; not built)
