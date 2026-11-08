---
name: setup
description: First use of chief of staff on this computer - pick where the company library (its second brain) lives, then open the first project. Use when the user says "set up chief of staff", "create my workspace", or runs /chief-of-staff:setup.
---

# Set up chief of staff

A project is the folder the owner works in; the plugin only keeps, in its
own data folder, the list of project folders and where the library lives. `setup.sh` and `project.sh`
are `${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh` and `.../project.sh`; that variable is resolved in this
text only, not in your shell, so copy the literal paths into your commands. The owner answers once, by
clicking; you do everything else.

1. Look before asking, and say nothing yet: `sh setup.sh detect` prints the places where the library
   could live, best first: `<label> TAB <folder> TAB <why>`.
2. Ask ONE AskUserQuestion: "Where should the company library (its second brain) live?" Options: the
   first lines of `detect`, at most 4, in its order (it puts an Obsidian vault first only when there is
   exactly one; with several, which vault belongs to this company is the owner's pick); label = the
   label, description = the folder and the why. The first is the recommendation, marked "(Recommended)".
   With a single place, do not ask: use it and say so in step 4.
3. Run, with the absolute path (expand `~` yourself): `sh project.sh library "/absolute/library folder"`.
   An existing library is kept as it is; an empty or new folder becomes one. It refuses a folder that
   holds other files: ask again.
4. Tell the owner in at most 3 lines where the library is, that every conversation in any folder now
   searches and saves to it, and that each project is the folder it lives in.
5. Run the `new-project` skill in this conversation's folder when the owner wants a project now; it
   ends by making this folder a project (the light way, without the opening questions, is `/threads`).

In cloud sessions (Claude Code on the web) the plugin hooks do not run.
