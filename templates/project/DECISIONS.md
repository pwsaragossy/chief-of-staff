# {{PROJECT_NAME}} — decisions

One line per decision, newest at the bottom. A line is never edited or deleted: a new line replaces it.
The briefing shows the decisions in force at every session start.

`- YYYY-MM-DD HH:MM | decision | who decided | replaces: <date and time of the line it replaces, or ->`

- To withdraw a decision without a new one: `- <now> | revoked: <why> | who | replaces: <its date and time>`.
  `replaces:` names a minute, so it lifts every line of that minute: when two lines share one, write the one
  that stays again in a new line before you revoke the other.
- `Dropped: <what> (owner: <their words>)`: something the owner dropped. No session proposes it or works on it
  again unless the owner asks; the briefing lists it at every session start.
- `Frozen: <what> (owner: <their words>; freeze: <file or folder>, <file or folder>)`: something the owner
  approved. The hooks block an edit of those paths (relative to the project); a change is a new version in a
  new file. To change the approved file itself, a new line revokes the freeze first.
- Add `guard: <term>` inside a decision (a word, a file name, a setting) and a `git push` from this project
  whose commits change that term asks the person at the keyboard first.

## Log
