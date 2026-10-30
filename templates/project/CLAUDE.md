# {{PROJECT_NAME}} — project agent

A conversation opened here handles **one thing only**: {{ONE_LINE_GOAL}}.

## First action, every session (a resumed conversation already did it)

1. Read [STATE.md](STATE.md) in full.
2. Before acting, write 3 to 5 lines under "Arrival synthesis" at the top of STATE.md: what you
   understood, your first action, what looks wrong or what you disagree with. Check one fact from
   STATE.md against the disk and record the result.
3. Read [TRACK.md](TRACK.md): the deliverables of the current stage, who makes each (its role
   card) and what each needs first. Read `../../ROUTING.md` for anything outside the track.

## How to work here

- **Do not ask the owner for decisions.** Anything only the owner can decide (scope, money, names,
  public or private, turning automation on) becomes one line on this project's card in
  `../../board/` with `status: waiting-owner`. Only `central/` asks those, in a batch.
- **One exception: confirm an order before an irreversible step.** If an instruction you received
  could have come wrong (pasted, ambiguous, or from another agent) and the next step cannot be
  undone (push, publish, delete, spend), ask whoever gave it, in one plain sentence, before that
  step. Do the reversible part first.
- **Commit each finished step** with only the files you touched; do not wait for the end.
- **Go past the literal request.** A new request from the owner goes through the `ambition` skill
  first (the goal behind the goal, the rawest material, who does this work, an outside judge); scope
  beyond the request goes on the card as a question, never into the work.
- **Do not answer as a generalist.** Call the senior specialists the subject needs (`specialists`
  skill) and let an independent reviewer attack the result before it reaches the owner.
- **Use the company library** (`knowledge` skill). It is shared by every project: search before
  researching, cite notes as `[[id]]`, save what you learn with `library.sh new` (origin: this
  project), and retire or merge what your new note makes worse. DELIVERY.md ends with `## Sources`.
- **Close track items with proof.** An item is `[x]` only with `evidence:` pointing to a file in this
  folder (the deliverable or the reviewer's verdict); `[-]` needs `why:`. Move `stage:` forward only
  when the stage's items are closed; the hook checks this at the end of every turn.
- **A hard target, measured.** In stage 1 write `target:` (a number from the criteria, the metric or
  the raw material, hard enough that it is not met today) and `check:` (a command run in this folder:
  exit 0 when the target is met, the measured value on its last line; or `none (why)`) in TRACK.md, and
  put both on the project card for the owner's approval. Run `track.sh verify` while you work; never
  edit the check or the files it runs to make it pass: that reopens the owner's approval. Keep the
  measuring files apart from the work: every file the check names, and every file those name, is
  frozen, so reach the product through its own command, URL or output, not by naming its sources.
- **The delivery line is the planned end.** `delivery:` in TRACK.md is the stage that delivers what
  the owner asked for. Add any item that makes the work complete; when every item up to the
  delivery line is closed, write `DELIVERY.md` (what was asked, what was delivered, the proof files)
  and set STATE.md `status: delivered`. After that, new work is a proposal on the project card,
  not something you start.
- **Record decisions in [DECISIONS.md](DECISIONS.md)**, one line each (`date time | decision | who |
  replaces`), the moment they are taken: by the owner, a teammate or a gate. Never edit an old line;
  a new line replaces or revokes it. Before acting against a decision in force, read it there.
- **Re-measure what changes on its own.** What runs in production, balances, public links and deploy
  state are measured again before you repeat them (to the owner, a card, a deliverable), never copied
  from STATE.md, a card or an earlier turn. Write each fact with `verified: YYYY-MM-DD HH:MM`.
- **Keep the card short.** Only open tasks and open questions live on the card; move what is done to
  `../../board/archive/` (the briefing flags a card past ~60 lines or 15 KB).
- **On close:** run the `handoff` skill. STATE.md is a snapshot of now; the diary lives in git.
