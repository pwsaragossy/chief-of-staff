---
name: setup
description: Create a chief-of-staff workspace (central, board, projects) and the company library, its second brain, in the places the owner picks from one block of questions. Use when the user says "set up chief of staff", "create my workspace", or runs /chief-of-staff:setup.
---

# Set up a chief-of-staff workspace

`setup.sh` is `${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh`; that variable is resolved in this text only, not
in your shell, so copy the literal path into your commands. The owner answers once, by clicking; you do
everything else.

1. Look before asking, and say nothing yet:
   ```sh
   sh setup.sh detect
   gh auth status >/dev/null 2>&1 && echo gh-ok
   ```
   `detect` prints the places where the library could live, best first: `<label> TAB <folder> TAB <why>`.
   If `~/chief-of-staff` exists and holds a `.chief-of-staff` file, stop: the workspace exists; say so and
   list its projects.

2. Ask everything in ONE AskUserQuestion call, with these questions (the first option of each is the
   recommendation, marked "(Recommended)"; the owner can always type another answer):
   - **Workspace** — "Where should the workspace live?" Options: `~/chief-of-staff`, and
     `~/Documents/chief-of-staff`. Description: the central conversation, the board and one folder per
     project.
   - **Library** — "Where should the company library (its second brain) live?" Options: the first lines
     of `detect`, at most 4, in its order (it puts an Obsidian vault first only when there is exactly
     one; with several, which vault belongs to this company is the owner's pick). Label = the label, description = the folder and the why.
   - **Backup** — only when `gh-ok` was printed: "Back up to private GitHub repositories?" Options:
     "Yes, private repos (Recommended)" (description: creates private repos on your GitHub account and
     pushes; nothing is public) and "Not now".
   - **Team** — "Join a team library (shared knowledge with a team)?" Options: "Not now (Recommended)"
     (description: your library stays personal; join a team later from central) and "I have the link"
     (description: choose Other and paste the team library's git link; an empty private repo starts a
     new team library). The personal library stays private either way.

3. Run, with the absolute paths (expand `~` yourself; the inside-the-workspace answer means no
   `--library`; add `--backup` only on yes; add `--join <link>` when a link was given):
   ```sh
   sh setup.sh create "/absolute/workspace" --library "/absolute/library folder" --join "<team git link>" --backup
   ```
   It refuses a folder that is not empty and creates nothing then: ask again for that answer only.

4. Tell the owner, in at most 5 lines:
   - open Claude Code in `<workspace>/central` to talk to the chief of staff; start new projects there;
   - each project gets its own folder in `projects/`, and its own conversation is opened there;
   - only `central` asks them questions; the other sessions write cards in `board/`;
   - where the library is, the `Team library:` and `Backup:` lines of `create` as they were printed;
   - in cloud sessions (Claude Code on the web) the plugin hooks do not run; the rules still hold
     through the CLAUDE.md files only if the workspace is the repository of that session.
