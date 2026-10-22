---
name: setup
description: Create a chief-of-staff workspace (central, board, projects, knowledge base) in a folder the owner chooses. Use when the user says "set up chief of staff", "create my workspace", or runs /chief-of-staff:setup.
---

# Set up a chief-of-staff workspace

Templates live in `${CLAUDE_PLUGIN_ROOT}/templates`. That variable is resolved in this text only, not
in your shell, so copy the literal path shown here into your commands.

1. Ask for one thing only: the workspace folder (default: `chief-of-staff` in the home folder).
   Expand `~` to the absolute path yourself before using it.
   - If it holds a `.chief-of-staff` file, stop: the workspace exists; say so and list its projects.
   - If it exists and is not empty, stop and ask for an empty or new folder. Never set up over
     existing files.
2. Create the layout and copy the templates (the marker is written last, so a failed run can be
   repeated):

   ```sh
   W="/absolute/path/to/workspace"; T="${CLAUDE_PLUGIN_ROOT}/templates"
   mkdir -p "$W/central" "$W/board" "$W/projects" "$W/knowledge/inbox" "$W/knowledge/notes" "$W/knowledge/topics" "$W/knowledge/templates"
   for d in board projects knowledge/inbox knowledge/notes knowledge/topics; do : > "$W/$d/.gitkeep"; done
   cp "$T/central/CLAUDE.md" "$W/central/CLAUDE.md"
   cp "$T/ROUTING.md" "$W/ROUTING.md"
   cp "$T/knowledge/note.md" "$W/knowledge/templates/note.md"
   printf '.dispatch.lock/\n.dispatch.log\n.dispatch-*.out\n' > "$W/.gitignore"
   git -C "$W" init -q
   git -C "$W" config user.name >/dev/null || git -C "$W" config user.name "chief-of-staff"
   git -C "$W" config user.email >/dev/null || git -C "$W" config user.email "chief-of-staff@localhost"
   printf 'chief-of-staff workspace v0.1\n' > "$W/.chief-of-staff"
   git -C "$W" add -A && git -C "$W" commit -qm "chief-of-staff: new workspace"
   ```

3. Tell the user, in at most 5 lines:
   - open Claude Code in `<workspace>/central` to talk to the chief of staff; start new projects there;
   - each project gets its own folder in `projects/`, and its own conversation is opened there;
   - only `central` asks them questions; the other sessions write cards in `board/`;
   - the workspace is a git repo with **no backup yet**: add a private remote and push to it
     (the dispatcher refuses to run without a remote);
   - in cloud sessions (Claude Code on the web) the plugin hooks do not run; the rules still hold
     through the CLAUDE.md files only if the workspace is the repository of that session.
