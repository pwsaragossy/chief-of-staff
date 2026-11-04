# Projects pane — design

Surface: the desktop app's pane (`$.ui.open`), elements Box, Text, Button, Link, Markdown. English UI like panel.py.

Flow:
1. Pane opens (central start, or `/chief-of-staff:projects`). Title "Projects".
2. List: "Central" row, then one row per project: name · status · "next: …" (dim). Delivered/paused projects under a dim "Done (n)" row.
3. Press a row → project page: header name + Back; Goal line; "New chat" button; Memory (status, updated, next, last 5 decisions); Chats (title, last activity; press = show it); Instructions (first 30 lines of CLAUDE.md as Markdown).
4. New chat → button reads "Opening…" → session starts in projects/<slug>, filed in group "<slug>", shown in the main pane. On failure the page shows the error and what to do.

States:
- Not in a workspace and none remembered: "No workspace" + "Open a chat in your chief-of-staff folder once."
- No projects: "No projects" + "Ask central for one."
- No chats: "No chats yet".
- Opening: button label "Opening…", disabled for a second press.
- Error: "Couldn't open the chat: <reason>. Try again, or open the folder from New session."

Copy limits: buttons 1-2 words; one help line at most.
Accessibility: every button has its own key and a label; text only, no colour-only status.
