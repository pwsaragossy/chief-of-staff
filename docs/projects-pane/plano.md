# Projects pane — plan

Where: a hooks module in the chief-of-staff plugin: `hooks/projects.tsx`, named by `hooks/hooks.json` under `modules` next to the shell hooks; contract in `types/index.d.ts`, named in plugin.json. If the engine refuses both kinds in one hooks.json, ship it as plugin `chief-of-staff-projects` in the same marketplace.

Reuse: workspace root = nearest folder with `.chief-of-staff` (as lib.sh cos_root); front matter read like fm_get; DECISIONS.md lines like cos_decisions (tab separated? read the file format first).

Data: `$.store` keeps the last workspace root seen (so the pane works from any session). `$.state` atoms: view (list | project slug), busy flag, last error. Nothing migrates: new keys.

App calls ($.mcp.call): ccd_session_mgmt.list_sessions (chats by cwd), ccd_sidebar.list_groups/create_group/move_sessions, ccd_session.start_session (user_asked, fresh, cwd, use_worktree false), ccd_window.open_session_in focus.

Tests: `hooks/projects.test.tsx` with `claude plugin test`: list built from a fake workspace; New chat calls start_session with the project's cwd and files it in the group (mcp mocked); error state. Real check: press New chat on dock-folders in this app, then list_sessions + list_events for the new session (the "Done when").

Way back: remove the `modules` line from hooks.json (shell hooks untouched); `git revert` the commit.

Stop list: none (local plugin files; no push, no release until Pedro asks).
