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

6. Handoff não é mais bloqueado: registrar uma decisão em DECISIONS.md (o que o handoff manda fazer) era
   tratado como "entregável" e exigia especialista + revisor no fim do turno. Agora é arquivo de controle,
   como TRACK.md. Economiza 1 bloqueio e 2 subagentes por handoff com decisão.

7. Painel: "Waits on you" (as perguntas que esperam o dono, com a idade) agora vem primeiro, acima dos
   projetos. Antes ficava abaixo dos mapas de trilha de todos os projetos (fora da primeira tela).

8. Setup pergunta uma coisa a menos quando só existe um lugar possível para a biblioteca (computador sem
   Obsidian/iCloud/Dropbox/disco externo): antes perguntava com uma única opção.

9. O skill de especialistas, seguido ao pé da letra, fazia o hook bloquear o revisor 2 vezes (faltavam as
   linhas Library: e Ambition: no brief do revisor). O texto do skill agora inclui essas linhas.

10. Os 8 cartões de especialista (exceto o revisor) não tinham a seção "## Versions" no formato de saída,
    que o hook exige: o especialista que seguia o próprio cartão era bloqueado uma vez por execução. Corrigido.

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

### Round 7 — technical lens (gates without reason; selftest speed)
- Selftest speed examined: per-check timing (131 s total). The 8 slowest checks (24 s) deliberately wait for time
  budgets (cos_limit, gate and lookup cut-offs, lock waits); the rest is spread ~1 s each. No cheap win: no change.
- Gate examined: what marks a turn "substantive" (PostToolUse Write/Edit on .md/.html/.pptx/.docx/.pdf).
- Found: a project's DECISIONS.md was not a control file. The handoff skill (step 3) and the project CLAUDE.md tell
  every session to append decisions there, so a plain handoff (STATE.md + DECISIONS.md) was blocked at Stop:
  "This turn produced a deliverable ... 0 specialist(s) and 0 reviewer(s)". Reproduced in the simulation (rc=2).
  Cost per handoff with a decision: 1 block + 2 subagent runs, for a one-line log entry.
- Changed: projects/<slug>/DECISIONS.md is a control file, exactly like TRACK.md and DELIVERY.md (same path rule:
  only the project's own file, not sub/DECISIONS.md, not a cut path).
- Proof: "updating DECISIONS.md is not a deliverable" failed first; "sub/DECISIONS.md is a real deliverable" added;
  selftest 473/473; simulation handoff Stop rc 2 → 0.
- Blocks per handoff with a decision: 1 → 0.

### Round 7b — reviewer findings on rounds 3-6 (reviewer role card, as a subagent)
- Verdict: pass with minor fixes; no security block weakened; selftest passed.
- Applied: (1) central's backup line covers the library folder too, and pushes to an existing `origin` before
  creating a repo (a retry after a half-done backup no longer fails); (2) the gh message covers "not installed"
  as well as "not signed in"; (3) the guard hint drops "This check is a word list" (it added nothing for a real
  mention) and the message now names .owner-items, which it already protected.
- Left as notes: `library.sh libs` and skills/knowledge say "personal" in a shared workspace, but none is reached
  by a shared-workspace user in practice (reviewer finding 5).
- Proof: selftest 473/473.
- Method log: second reviewer pass in a row that found real defects my own checks missed. Keeping one reviewer
  subagent per batch of user-facing changes (cost ~100k tokens, ~3 min, background while the next round runs).

### Round 8 — user lens (the panel in 5 seconds)
- Examined: panel.py rendered in Chromium (1280x800) on the simulated workspace with one launch project and one
  question waiting on the owner.
- Found: the first screen showed the title, a red dot, the project reasons and a 24-item track map; the question
  itself ("Price at 9 or 19 per month? Recommend 19") was below every project's map, off the first screen.
  "What waits on me?" took a scroll per project (1 project: ~1 screen; 5 projects: ~5 screens).
- Changed: the "Waits on you" section (renamed from "Waiting on the owner": 3 words) comes first, above Projects.
  No data or logic change.
- Proof: new check (section order in the page) failed first, passes after; selftest 474/474; screenshot after
  shows the question as the 4th line of the page.
- Simulation: scrolls to see what waits on the owner, 1 per project → 0.

### Round 9 — technical lens (README promises)
- Examined: README's lists and counts against the repo (skills/, hooks/hooks.json).
- Found: the "Skills:" line under Daily use omitted `ambition`, the skill central runs on every new request
  (an owner reading the README to learn the slash commands never sees /chief-of-staff:ambition); the ECC section
  said "5 skills, 2 shell hooks" — there are 7 skills and 3 hook scripts.
- Changed: README fixed; a check derives both from skills/ and hooks.json, so the README cannot drift again.
- Proof: check failed first ("README Skills line misses ambition"), passes after; selftest 475/475.
- Hook times: unchanged (docs only).

### Round 10 — user lens (setup questions)
- Examined: the setup skill's question block against `setup.sh detect` on a computer with no Obsidian vault,
  iCloud, Dropbox, Google Drive, OneDrive, Box or external disk (this container; typical Linux/WSL, and a Mac
  without those folders).
- Found: detect prints one place ("Inside the workspace"), yet the skill still asked "Where should the company
  library live?" — a question with one real option (AskUserQuestion needs 2-4 options, so the agent either
  invents a second one or the call fails). Not a decision of the owner's.
- Changed: the skill asks Library only when detect printed two or more places; otherwise it says where the
  library went in the final summary (it can still move later: library.sh offload).
- Proof: check failed first, passes after; selftest 476/476.
- Simulation: questions in setup on such a computer, gh not signed in: 3 → 2 (Workspace, Team).

### Round 11 — technical lens (false blocks: skill vs hook)
- Examined: the PreToolUse Agent gate against the specialists skill, followed literally.
- Found: step 4 told the agent to brief the reviewer with its role card and the specialists' outputs; the hook
  requires a `Library:` line and an `Ambition: ... | judge: ...` line for every role card, the reviewer included.
  Reproduced: brief as written → block (Library); add Library → block (Ambition). 2 blocks per reviewer run.
  The hook is right (the reviewer checks each verdict against the judge and each citation against the notes),
  so the skill text was wrong; the guard is unchanged.
- Changed: specialists SKILL.md step 4 tells to pass the same Library and Ambition lines, and why.
- Proof: check failed first, passes after; selftest 477/477.
- Blocks per reviewer run when the skill is followed literally: 2 → 0.

### Round 12 — user lens (the specialist agent as a user)
- Examined: what a specialist subagent is told to output (its role card's "Output format") against what the
  SubagentStop hook requires (`## Never-skip checklist`, and `## Versions` with evidence when it is not the reviewer).
- Found: all 8 non-reviewer cards' output formats had no `## Versions`. The brief asks for it (specialists skill
  step 3), but the card is the format the subagent copies; one that follows its card is blocked once per run
  ("Your brief carries an Ambition line: add a '## Versions' section...") and spends a second turn.
- Changed: each of the 8 cards' output formats has a `## Versions` block (v<n> lens - verdict - evidence; "v1 passed:").
  Hook unchanged.
- Proof: check failed first ("no Versions in designer.md"), passes after; the marketing card's own template fed to
  the SubagentStop hook exits 0; selftest 478/478.
- Blocks per specialist run that follows its card: 1 → 0.
- Pattern noticed (rounds 11-12): the hooks' requirements live in protocol.sh and the instructions live in skills
  and cards; they drifted apart twice. Both checks now tie them together in the selftest.

### Round 13 — technical lens (instructions vs hooks: notes, delivery) — no change
- Examined: `library.sh new` + the note template + the save check (`library.sh check`, `gate`): a fresh note fails
  with 3 clear messages (each placeholder line, the Compared: entry); filled as the template says, it passes both.
  DELIVERY.md: the gate's `## Sources` rule matches the project CLAUDE.md and the knowledge skill.
- Found: nothing with evidence. No change.

### Round 14 — user lens (team conflicts; tracks) — no change
- Examined: sync.sh's conflict card (addressed to the session, says nothing was lost and the 4 steps); all 5 track
  templates copied fresh pass `track.sh check` and brief cleanly; every `card:` a track names exists in
  templates/specialists/; ROUTING.md names the same cards.
- Found: nothing with evidence. No change. Next rounds move to other areas (panel text, dispatcher, knowledge skill).

## Ideas (no evidence of friction yet; not built)
- A CI job on GitHub Actions (macos-latest runs /bin/sh = bash 3.2; ubuntu dash) running `sh scripts/selftest.sh`
  on every push to a branch, and a run with TMPDIR containing a space. v0.5.1 was a bash 3.2 parse error that a
  macOS runner would have caught. Not built: adding CI is an owner decision (Actions minutes, repo settings).
