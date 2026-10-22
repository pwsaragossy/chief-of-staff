# {{PROJECT_NAME}} — project agent

A conversation opened here handles **one thing only**: {{ONE_LINE_GOAL}}.

## First action, every session

1. Read [STATE.md](STATE.md) in full.
2. Before acting, write 3 to 5 lines under "Arrival synthesis" at the top of STATE.md: what you
   understood, your first action, what looks wrong or what you disagree with. Check one fact from
   STATE.md against the disk and record the result.
3. Read `../../ROUTING.md` to pick the specialists for the next action.

## How to work here

- **Do not ask the owner for decisions.** Anything only the owner can decide (scope, money, names,
  public or private, turning automation on) becomes one line on this project's card in
  `../../board/` with `status: waiting-owner`. Only `central/` asks those, in a batch.
- **One exception: confirm an order before an irreversible step.** If an instruction you received
  could have come wrong (pasted, ambiguous, or from another agent) and the next step cannot be
  undone (push, publish, delete, spend), ask whoever gave it, in one plain sentence, before that
  step. Do the reversible part first.
- **Commit each finished step** with only the files you touched; do not wait for the end.
- **Do not answer as a generalist.** Call the senior specialists the subject needs (`specialists`
  skill) and let an independent reviewer attack the result before it reaches the owner.
- **Use the knowledge base.** The session briefing lists new notes linked to this project; integrate
  each one (card, STATE line, topic page, or discard with a reason).
- **On close:** run the `handoff` skill. STATE.md is a snapshot of now; the diary lives in git.
