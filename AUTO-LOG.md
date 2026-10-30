# AUTO-LOG — branch auto/harness

## Resumo para o Pedro (leia primeiro)

**O que mudou até agora**
1. Selftest roda verde também como root (containers, CI): 5 checagens usavam `[ -w arquivo ]`, que é
   sempre verdadeiro para root. Agora checam os bits de permissão. Nenhuma regra de segurança mudou.

2. `health.sh text`: sem python3 o painel não abre; antes o texto de reserva saía ilegível
   (`newsletter^_green^_...`). Agora: primeira linha é o veredito ("All fine" ou "3 questions wait on you.
   Projects: 1 red."), depois uma linha por projeto e só as perguntas desta pessoa, cada uma com a própria idade.

3. Mensagem de bloqueio mais clara: quando o guarda bloqueia um comando só porque ele *menciona* um arquivo
   protegido (ex.: mensagem de commit com ".library"), a mensagem agora diz para reescrever sem o nome.
   O bloqueio continua igual (segurança intacta); o agente só não fica tentando às cegas.

4. Workspace compartilhado: o briefing chamava a biblioteca do time de 'personal' (o setup dizia "the team's").
   Agora diz "the team's (shared workspace)": ninguém pensa que as notas são privadas.

5. Mensagens de backup do setup sem jargão: em vez de "Add a private git remote and push", diz que o
   workspace está só neste computador e para pedir ao central um backup privado no GitHub (o central sabe o comando).

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

### Round 2b — reviewer findings on health.sh text (specialists skill, reviewer role card)
- Reviewer verdict: fix needed. Real bugs: (1) in a shared workspace "Waits on you" listed teammates'
  questions (briefing.sh filters by member, text mode did not); (2) every question showed the card's oldest
  wait, not its own age (field 14 ignored); (3) a waiting card with no questions section vanished;
  (4) no first-line verdict, so "is everything fine?" still needed a scan.
- Changed: verdict first line; member filter like briefing.sh; per-question age "asked N ago"; bare card shows
  "open the card"; `-F "$US"` like the rest of the repo. Tests extended (shared + 2 ages + bare + other member;
  and an all-green case); they failed first, pass now. Full selftest 469/469.
- Method note (skills used on this work): the ambition judge I picked (one card, one question at 0 min) was one
  my v1 already passed: exactly the failure the ambition skill warns about ("a worker left to pick its own judge
  picks one its first draft already passes"). The independent reviewer caught it. Lesson kept: for a change I
  judge myself, the selftest case must include the shared-workspace and multi-item variants.

### Round 3 — technical lens (false guard blocks)
- Examined: PreToolUse Bash guard with 30 commands an agent commonly runs in a project session (git add/commit/
  push/log, cat/sed/grep/find/diff, cp/mv, python/node/npm, echo >> TRACK.md, track.sh verify/check,
  library.sh search/new, reading .owner-ok and the marker). Probe script: scratchpad probe.sh.
- Found: 29/30 pass with no block and no ask. 1 block: `git commit -m "docs: explain the .library file"`.
  Kept on purpose: the guard is a word list, `git commit` can write, and telling a mention from a write would
  need a shell parser (fail closed wins). The friction was the message: it explained the protected files but
  not that a mere mention triggers it, so an agent would retry the same command.
- Changed: Bash blocks on a protected name add one sentence: "This check is a word list: if the command only
  mentions one of these names (a commit message, an echo), rephrase it without the name." Write/Edit unchanged.
- Proof: new check failed first, passes after; selftest 470/470.
- Hook times: unchanged (message only).

### Round 4 — user lens (second member joins)
- Examined: Bia's first central session after `setup.sh join` (simulation from round 2).
- Found: setup printed `Library: .../knowledge (the team's)`; the briefing then printed
  `Library of this session: 'personal' (...)` and `Library 'personal': empty (0 notes).` A teammate reads that
  their notes are private when every note goes to the whole team: the most expensive misunderstanding a shared
  workspace can cause. 1 confusing message of 7 in Bia's first briefing.
- Changed: library.sh shows the shared workspace's library as "the team's (shared workspace)" in the two
  person-facing lines. The internal name stays `personal` (all gates, sync and paths unchanged).
- Proof: new check failed first, passes after; selftest 471/471.
- Simulation after: Bia's briefing has 0 messages that say personal; confusing messages 1 → 0.

### Round 5 — technical lens (environments)
- Examined: full selftest (a) with TMPDIR holding a space, so every workspace path has a space (a folder in
  "My Drive" or "Google Drive"); (b) with `sh` resolved to `bash --posix` (macOS /bin/sh is bash; only bash 5
  exists here, not 3.2); (c) default dash.
- Found: (a) 3 FAIL, all in the public_urls/prod_ref checks: the test wrote `file://<path with space>` as the URL;
  public_urls is a space-separated list and a URL holds no raw space, so the test was wrong, not health.sh.
  (b) 471/471. (c) 471/471.
- Changed: the test percent-encodes the path (`%20`).
- Proof: (a) 468 → 471/471 with a spaced TMPDIR; default run 471/471.
- Not testable here: bash 3.2 itself (macOS), busybox ash, WSL drvfs. Idea below.

### Round 6 — user lens (setup's last words)
- Examined: every line `setup.sh create` prints to a solo founder (round 2 simulation, gh not signed in).
- Found: 1 of 3 lines was jargon with no next step: `Backup: none yet. Add a private git remote to <path> and push.`
  Same in 3 other backup messages. A non-engineer stops there (moment of "what do I do now?": 1).
- Changed: 4 messages in setup.sh say what happened and what to do ("ask central to back it up"); central's
  CLAUDE.md gets the one command for that (private repo only). Tests lock the new wording and forbid "git remote".
- Proof: 2 tightened checks failed first, pass after; selftest 471/471.
- Simulation after: "don't know what to do" moments in setup output 1 → 0.

## Ideas (no evidence of friction yet; not built)
- A CI job on GitHub Actions (macos-latest runs /bin/sh = bash 3.2; ubuntu dash) running `sh scripts/selftest.sh`
  on every push to a branch, and a run with TMPDIR containing a space. v0.5.1 was a bash 3.2 parse error that a
  macOS runner would have caught. Not built: adding CI is an owner decision (Actions minutes, repo settings).
