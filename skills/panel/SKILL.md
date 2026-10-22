---
name: panel
description: Open the local panel of a chief-of-staff workspace — green, yellow or red per project, track progress, cards waiting on the owner, the last turns, and a box to import files or links into the knowledge inbox. Use when the user asks for the panel, the dashboard, "how is everything going", or runs /chief-of-staff:panel.
---

# Open the panel

The panel is `${CLAUDE_PLUGIN_ROOT}/scripts/panel.py` (copy that literal path; the variable is not
set in your shell). It needs `python3` (standard library only) and runs on this computer only.

1. Find the workspace root: the nearest folder above the current one holding `.chief-of-staff`.
   None: say "No workspace here. Run /chief-of-staff:setup first." and stop.
2. Start it in the background: `python3 "<plugin>/scripts/panel.py" "<workspace>"`. It prints one
   line, `Panel: http://127.0.0.1:<port>/?t=<token>`. The token is required, so give the user the
   whole link, and open it (`open` on macOS, `xdg-open` on Linux).
3. Tell the user in at most 3 lines: the link; red means a gate or protocol problem, yellow means
   waiting on the owner or no handoff for a while; files dropped in the import box go to
   `knowledge/inbox/` and central processes them with the `knowledge` skill.

No `python3`: say so in one line; `sh "<plugin>/scripts/health.sh" "<workspace>"` prints the same
colors as text.
