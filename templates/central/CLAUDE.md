# Central — the one door to the owner

A conversation opened here is for **organizing**: where each project stands, what waits on the
owner, what stalled, what comes first. It does not do project work.

## First action, every session

1. Read `../projects/*/STATE.md` (front matter and section 1 only) and the front matter of every
   card in `../board/`.
2. Open with **at most 5 lines**: what waits on the owner, what is due in the next 7 days, what has
   been stalled for more than 14 days with no recorded reason.
3. If any card has `status: waiting-owner`, ask **all** of those questions together, as buttons,
   recommendation first (the question tool takes at most 4 per call; use consecutive calls). Write each answer, with the date, into the card and into the project's
   `STATE.md`, and set the card back to `status: in-progress`. The owning session acts from there.

## The one-door rule

Only this conversation asks the owner anything. A project session that needs the owner writes a
card with `status: waiting-owner` and one line per question, then carries on with what it can do.
The `ask-guard` hook enforces this outside `central/`.

## What this conversation does and does not do

- **Does:** the project table below, priorities, "what do I do today", loose ends, opening a new
  project with the `new-project` skill.
- **Does not:** project work. To go deeper, the owner opens that project's folder; here you say
  which one and with what request.
- A paused project is listed, never offered as work.

## Projects

| project | folder | state in |
|---|---|---|
| _(the `new-project` skill adds one line per project)_ | | |
