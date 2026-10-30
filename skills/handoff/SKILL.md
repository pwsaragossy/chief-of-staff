---
name: handoff
description: Close a session so the next one starts where this one stopped (I-PASS style). Use at the end of any work session in a chief-of-staff project, when the user says "wrap up", "close the session", "handoff", or runs /chief-of-staff:handoff.
---

# Handoff: close so the next session can continue

The next session is a stranger with no memory of this one. Everything it needs is in files.

1. **Update `STATE.md` as a snapshot of now**, not a diary (history lives in git):
   - front matter: `updated` (now, `YYYY-MM-DD HH:MM`: the panel times the handoff from it, not from
     the file date a git pull resets), `next` (the next action in one line), `status`;
   - section 1: severity (green / yellow / red) and one line;
   - section 3: what is true now, one line per fact: `- fact — source — verified: YYYY-MM-DD HH:MM`.
     Never copy a fact that changes on its own (the commit running in production, balances, public
     links and whether they open logged out, deploy state) from the previous STATE.md, a card or memory:
     measure it now and write the new time, or leave it out and say so in section 7;
   - section 4: only what the next session must repeat or avoid;
   - section 5: next actions, each with an owner (a session or a specialist) and its "done" check;
   - section 6: contingencies as "if X, then Y";
   - section 7: what you did not verify. Do not leave it empty by habit; empty means you checked.
   - Clear "Arrival synthesis" back to its placeholder line once its content is reflected above.
2. **Set `dispatch`** in the front matter:
   - `ready` only when the next action needs nobody (no owner decision, no money, no publishing,
     no irreversible step) and fits in one session;
   - `off` otherwise.
3. **Update the card**: the file in `../../board/` whose front matter says `project: <this slug>`: `updated`, `status` (`waiting-owner` if any line waits on
   the owner, else `in-progress`; a finished card is removed and its result goes in STATE.md).
   Keep each question's `(asked ...)` stamp as it is (the hook adds it; it times the oldest question)
   and never rewrite `asked:`. Move done tasks and decided questions to `../../board/archive/` when the
   card passes ~60 lines. Decisions taken this session go in `DECISIONS.md` (one new line each).
4. **Knowledge**: list in STATE.md section 3 the `[[id]]` of each note this session wrote or relied
   on. The hooks have already checked them.
5. **Lesson, at the final handoff only** (STATE.md `status: delivered`): save one lesson for the next
   project in the library, `sh "${CLAUDE_PLUGIN_ROOT}/scripts/library.sh" new howto <slug> "Lesson: <what to
   repeat or avoid>"`, filled in with what happened and its proof file. One line of substance, not a retro.
6. **Commit only the files this session touched**, with a message that says what changed and why.
   A session started by the dispatcher has no shell: skip this step, the dispatcher commits.
