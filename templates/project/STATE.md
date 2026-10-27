---
status: in-progress
updated: {{DATE}}
next: {{NEXT_ACTION}}
dispatch: off
member:
---

# {{PROJECT_NAME}} — state

## Arrival synthesis
(the next session writes here before acting: what it understood, first action, what looks wrong, one fact checked against the disk)

## 1. State in one line
{{SEVERITY}}. One sentence: where the project is and whether it is on track.
(green = on track · yellow = watch · red = blocked or off track)

## 2. Intent (what counts as "done")
- What the owner wants, in their words:
- "Done" for the current stage:
- Stop criterion (written at the start; when it is hit, the project goes to the gate):

## 3. What is true now
One fact per line, `- fact — source (file, link, command) — verified: YYYY-MM-DD HH:MM`. Nothing inferred goes
here without saying so. Facts that change on their own (what runs in production, balances, public links, deploy
state) are measured again before they are copied forward; the briefing flags those older than `stale_hours`.

## 4. What was done and how
Only what the next session needs to repeat or avoid. History lives in git.

## 5. Next actions
1. **Owner of the step (a session or a specialist):** action, and how you know it is done.

## 6. If X, then Y
- If something needs the owner, it becomes a line on the card with `status: waiting-owner`. Do not ask.

## 7. What I did not verify
-
