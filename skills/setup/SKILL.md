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
   git config --global user.name || id -F 2>/dev/null
   ```
   `detect` prints the places where the library could live, best first: `<label> TAB <folder> TAB <why>`.
   If `~/chief-of-staff` exists and holds a `.chief-of-staff` file, stop: the workspace exists; say so and
   list its projects.

2. Ask everything in ONE AskUserQuestion call, with these questions (the first option of each is the
   recommendation, marked "(Recommended)"; the owner can always type another answer):
   - **Workspace** — "Where should the workspace live?" Options: `~/chief-of-staff`, and
     `~/Documents/chief-of-staff`. Description: the central conversation, the board and one folder per
     project.
   - **Library** — only when `detect` printed two or more places (with one, the library goes inside the
     workspace: say so in step 4, do not ask): "Where should the company library (its second brain)
     live?" Options: the first lines of `detect`, at most 4, in its order (it puts an Obsidian vault first only when there is exactly
     one; with several, which vault belongs to this company is the owner's pick). Label = the label, description = the folder and the why.
   - **Backup** — only when `gh-ok` was printed: "Back up to private GitHub repositories?" Options:
     "Yes, private repos (Recommended)" (description: creates private repos on your GitHub account and
     pushes; nothing is public) and "Not now".
   - **Team** — "Work with a team?" Options:
     - "Just me (Recommended)" — your library and board stay personal; a team can be added later.
     - "Share a library" — choose Other and paste the team library's git link (an empty private repo
       starts one): shared knowledge, your board stays yours.
     - "One board for the team" — choose Other and paste an empty private repo link that every teammate
       can write to: the whole workspace (board, projects, library) is the team's, and everyone sees
       what everyone is working on. Nothing personal goes in it; keep a separate personal workspace.
     - "Join my team's board" — choose Other and paste the link a teammate shared.

3. Run, with the absolute paths (expand `~` yourself; the inside-the-workspace answer means no
   `--library`; add `--backup` only on yes; add `--join <link>` when a link was given):
   ```sh
   sh setup.sh create "/absolute/workspace" --library "/absolute/library folder" --join "<team git link>" --backup
   ```
   It refuses a folder that is not empty and creates nothing then: ask again for that answer only.
   For "One board for the team" or "Join my team's board" the library and backup answers do not apply
   (the library lives inside, the team repo is the backup); the member name is the one step 1 printed
   (ask for it only when it printed nothing):
   ```sh
   sh setup.sh create "/absolute/workspace" --share "<empty repo link>" --member "<name>"
   sh setup.sh join "/absolute/workspace" "<shared workspace link>" --member "<name>"
   ```

4. Tell the owner, in at most 5 lines:
   - open Claude Code in `<workspace>/central` to talk to the chief of staff; start new projects there;
   - each project gets its own folder in `projects/`, and its own conversation is opened there;
   - only `central` asks them questions; the other sessions write cards in `board/`;
   - where the library is, the `Team library:`, `Shared:` and `Backup:` lines of `create` as they were printed;
   - with one board for the team: every turn end sends the board, the projects and the checked notes to
     the team, every session start brings the teammates' changes, and each central asks only its own
     member's questions; the panel shows everyone's projects;
   - in cloud sessions (Claude Code on the web) the plugin hooks do not run; the rules still hold
     through the CLAUDE.md files only if the workspace is the repository of that session.
