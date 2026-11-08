---
name: panel
description: Open the panel — in the chat (overview.sh, also on a phone) or the local web panel — of this project folder or of every registered project: green, yellow or red per project, track progress, cards waiting on the owner with their questions, the deadline countdown, the last 24 hours in three counts, and a box to import files or links into the knowledge inbox. Use when the user asks for the panel, the dashboard, "how is everything going", or runs /chief-of-staff:panel.
---

# Open the panel

The panel is `${CLAUDE_PLUGIN_ROOT}/scripts/panel.py` (copy that literal path; the variable is not
set in your shell). It needs `python3` (standard library only) and runs on this computer only.

0. The owner on a phone (Remote Control): the chat is the panel, since the web panel listens on this
   computer only. Run `sh "<plugin>/scripts/overview.sh" --all` (every registered project), or with
   board folders as arguments when a folder's `CLAUDE.md` names boards of its own (folders of cards with
   `status:` front matter). Give its lines in the owner's language, in the same order, nothing added:
   waiting on the owner, due in 7 days, changed in 24 hours, moving, stopped. Then stop.
1. Which panel: inside a project folder (the nearest folder above holding `.chief-of-staff`), that
   project; anywhere else, every registered project (`--all`).
2. Start it in the background: `python3 "<plugin>/scripts/panel.py" "<project folder>"` or
   `python3 "<plugin>/scripts/panel.py" --all`. It prints one line, `Panel: http://127.0.0.1:<port>/?t=<token>`.
   The token is required: open the whole link in the app's built-in browser, or with `open` on macOS
   (`xdg-open` on Linux), and give it to the owner.
3. Tell the owner in at most 3 lines: the link; red means a gate or protocol problem, yellow means
   waiting on the owner or no handoff for a while, grey means a registered folder that is gone; files
   dropped in the import box go to the library's `inbox/` and are processed with the `knowledge` skill.

No `python3`: say so in one line, run `sh "<plugin>/scripts/health.sh" text "<project folder>"` for each
folder that `sh "<plugin>/scripts/project.sh" list` prints as ok, and show its lines as they are.
