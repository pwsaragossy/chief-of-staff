---
name: new-project
description: Open a new project with the fixed playbook (opening questions, coherence check, registration, start with gates). Use in the central session when the owner says "new project", "I'm starting X", "what do we need for X?", or runs /chief-of-staff:new-project.
---

# Open a new project (the playbook)

Run this from `central/` only: central is the one session that asks the owner, and the only one that
creates projects.

## 1. Opening: one round of questions, as buttons, recommendation first
Ask them together, in as few rounds as the question tool allows (it takes at most 4 per call, so
this is two calls back to back). Offer likely answers as options; free text goes through "Other".
1. **What** is it, in one sentence?
2. **Kind**: real project, experiment, or a test of the method? (A test stays a test: no real
   accounts, money, or legal steps.) And which track: hackathon, software, brand, launch or
   research (the files in `${CLAUDE_PLUGIN_ROOT}/templates/tracks/`); recommend the one that fits.
3. **Success**: what result, by when?
4. **Investment**: hours per week and money the owner accepts to spend.
5. **Stop criterion**: what number or event makes us stop or change course?
6. **Library** — only when `sh "${CLAUDE_PLUGIN_ROOT}/scripts/library.sh" libs` lists a team library:
   is this project personal or a team's? Recommend personal unless the owner named the team. A team
   project writes to and searches that team's library only, so nothing personal reaches the team.

Decide yourself anything technical, legal, or that follows from the answers. Only ask what is
irreversible or touches the owner's values, money, or criteria.

## 2. Coherence check, before any specialist
Write down whether the success criteria fit together and fit the investment (example of a misfit:
"first revenue in 30 days" with "zero manual hours"). If they do not fit, say so in one line and ask
the owner to pick, in the same round of buttons if possible.

## 3. Registration
1. Check for an existing project with the same subject or a similar name in `../projects/` and in
   the central table. If one exists, stop and say so.
2. Create `../projects/<slug>/` with `CLAUDE.md` and `STATE.md` from
   `${CLAUDE_PLUGIN_ROOT}/templates/project/` (copy the literal path shown here), filling the
   `{{...}}` fields from the answers. Put the answers in STATE.md section 2.
   Copy the chosen track to `../projects/<slug>/TRACK.md`. Set `delivery:` to the stage that
   delivers what the owner asked for (the success answer): that is the planned end. Then run
   `sh "${CLAUDE_PLUGIN_ROOT}/scripts/track.sh" baseline ../projects/<slug>` once, which records how
   many items the map had at opening, so the panel shows how much was added later. When the project
   has a deadline, write it in TRACK.md as `deadline: YYYY-MM-DD HH:MM` in local time: the panel
   counts down, turns yellow under 6 hours and red under 2 hours while the delivery is open. If an item truly cannot apply, mark it
   `[-]` with `why:` instead of deleting it, so the reviewer sees it.
   For a team project, from its folder: `CLAUDE_PROJECT_DIR=<absolute path of ../projects/<slug>> sh
   "${CLAUDE_PLUGIN_ROOT}/scripts/library.sh" use <team>` (the owner confirms; never write `.library` by hand).
3. Create the card `../board/<Project name>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/board/card.md`,
   with `owner` set to the project session (for example `session-<slug>`), never the owner.
   In a shared workspace (`shared: yes` in `.chief-of-staff`), set `member:` in the card and in
   STATE.md to this person's name (`git config cos.member`), so the team board shows whose it is.
4. Add one line to the project table in `central/CLAUDE.md` (not in a shared workspace: there the
   briefing and the panel list every project, and a shared table would clash between teammates).
5. Commit only these files.

## 4. Start
The stages and their minimum deliverables are in TRACK.md; a hook stops any session that moves
`stage:` forward, or sets STATE.md to done, while an item of an earlier stage is open or lacks its
proof file. Add project-specific deliverables to TRACK.md in the same format. At each gate the
decision is one of: continue, stop, pause, redo. Then tell the owner which folder to open next.
