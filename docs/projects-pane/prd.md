# Projects pane — PRD

Problem: the owner (Pedro, solo founder) wants the app's Projects tab behaviour for chief-of-staff projects, but that tab only runs on claude.ai's cloud; today a local project conversation has to be opened by picking the right folder by hand, and its conversations sit loose in the sidebar.

Why now: Pedro runs projects (dock-folders) from central and opens their conversations every day; each wrong-folder start loses the briefing.

In:
- A "Projects" pane beside the conversation, listing the workspace's projects (status, next action, last update), central first.
- A project's page: its goal, its instructions (CLAUDE.md), its memory (STATE.md next/status, the last decisions), its conversations.
- "New chat": starts a local session in the project's folder, files it in a sidebar group named after the project, and shows it.
- Opening one of the project's conversations from the pane.
- `/chief-of-staff:projects` opens the pane; central opens it at start.

Not in:
- Creating a project from the pane (stays in central's new-project playbook).
- Editing instructions or memory from the pane (they are files the agents keep).
- Cloud sessions, routines, sharing.
- Changing the app's own Projects tab.

Done when: one press on "New chat" opens a local conversation whose folder is the project's, filed in the project's sidebar group, and whose briefing says "agent of project '<slug>'" — checked through list_sessions (cwd, group) and that session's events.

Risks: the mod API is early access and moves between releases; start_session from a plugin is untested until the build; a hooks.json with both shell hooks and a module may not load (fallback: ship the pane as its own plugin in the same marketplace).
