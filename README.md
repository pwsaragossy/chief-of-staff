# chief-of-staff

An AI chief of staff for [Claude Code](https://code.claude.com): a small company of agents that
works for one owner, or for a team. Version 0.4.7.

What it gives you:

- **One door to the owner.** Only the `central` session asks you for decisions. Project sessions
  write them on a card in `board/` and keep working; central asks them all at once. The one
  exception: any session may confirm the origin of an order before an irreversible step.
- **A fixed project playbook with tracks.** Opening questions, a coherence check of the success
  criteria, then a track for the kind of project (hackathon, software, brand, launch, research):
  stages of minimum deliverables, each naming the specialist who makes it, what it needs first and
  the file that proves it. A hook stops any session that moves past a stage with an open item, a
  missing proof file, or no reviewer verdict. Each track has a delivery line, the stage that
  delivers what the owner asked for: when it closes, the session must write `DELIVERY.md` and mark
  the project delivered, and further ideas become proposals instead of an endless loop.
- **Standard handoffs.** Every project has a `STATE.md` in one format (adapted from the I-PASS
  clinical handoff). The next session writes an arrival synthesis and checks one fact before acting.
- **Specialists with a written method, and an independent reviewer, enforced by hooks.** Nine
  role cards (`specialists/`: researcher, product, engineer, designer, finance, legal, marketing,
  security, reviewer) say what each senior specialist gathers first, its method, its toolbox and when to use
  each tool, what it never skips, its evidence standard and output format. A substantive turn
  cannot end without at least one specialist and the reviewer. In hackathon pace (`pace: fast` in
  the workspace's `.chief-of-staff`, set by the owner) internal work needs one specialist, and the
  reviewer runs only on what goes outside: the submission, the video, the README, messages to judges.
- **A company library (second brain), enforced by hooks.** One note per file in `knowledge/notes/`,
  readable in Obsidian: findings, decisions, how-tos and formats, options, topics. Each note carries
  its origin (project or research) but every project uses every note. Links are inline `[[id]]`;
  backlinks, index and graph are computed on the fly, never stored. A note is checked the moment it
  is saved (format, sources for its confidence, no secrets, no hidden text, third-party text fenced as
  data). When a new note meets a similar one it must say how: the worse is retired, the two are
  merged, or they coexist as valid options. Every prompt brings the notes that bear on it, briefs
  carry a `Library:` line, web search waits for a library search, and DELIVERY.md cites its sources.
  The library can live on an external disk, a cloud folder or a private repo (`library.sh offload`).
- **Team libraries, kept apart from yours.** Join a team's library by its git link, at setup or later
  from central (`library.sh join <link>`; an empty private repo starts one); leave it with
  `library.sh leave`. Each project picks one library (`library.sh use <team>`, asked in
  `new-project`); central and the other projects use your personal library. A session searches and
  writes only its own library (`search --all` shows the others, labelled); a team note cannot link
  a personal note or another team's, and a personal note that links a team note gets a warning.
  Team notes are pulled at session start and pushed after a turn whose notes pass the checks; a
  conflict with a teammate becomes a card for that project's session. Join, leave and use ask you
  first; settings changed any other way stop the turn until you confirm them (`library.sh trust`).
- **One board for the whole team.** A workspace can be shared: one teammate creates it on an empty
  private git repo (`setup.sh create <folder> --share <link> --member <name>`), the others join it
  (`setup.sh join <folder> <link> --member <name>`). Every turn end sends the board, the projects and
  the library notes that passed the checks to the team; every session start brings the teammates'
  changes. Each card and project says whose it is (`member:`), each person's central asks only their
  own questions, each dispatcher runs only its own projects, and the panel shows everyone's work.
  Files that look like they hold a key or token stay on the computer, and the turn says so.
- **Built for deadlines.** A project's `TRACK.md` can carry `deadline: YYYY-MM-DD HH:MM`: the panel
  counts down, yellow under 6 hours, red under 2 hours while the delivery is open. A question waiting
  on the owner turns red after `owner_wait_minutes` (60 by default, 20 in the hackathon track), with
  its age shown. The panel and the briefing show the questions themselves. Items marked `owner: ok`
  (the hackathon's scope freeze and submission) close only with the owner's OK, which central records
  with `track.sh ok` and the owner approves.
- **Past the literal request (ambition loop).** Every new request goes through the `ambition` skill:
  the goal behind the goal, the rawest material, who does this work, and an outside judge that
  measures that goal, in at most 4 numbered versions. Whoever briefs sets the judge: every specialist
  brief carries `Ambition: <goal> | judge: <what measures it>`, and a specialist cannot finish
  without its `## Versions`. Scope beyond the request is a question for the owner, never work.
  In our test (same vague task, haiku as the worker, a timing check it never saw): 1 pass in 8 runs
  as asked; 0 in 5 when the worker ran the loop alone (it picked a judge its first draft passed);
  3 in 3 when a central on sonnet wrote the brief and the judge first.
- **A hard target and a judge that is not the model.** Every track carries `target:` (a number, taken
  from the criteria, the metric or the raw material) and `check:` (a command that measures it: exit 0
  when met, the value on its last line; or `none (why)`). A project cannot leave stage 1 until both are
  written and the owner approved them; the approval freezes the target, the command, the files the
  command names and the files those name in turn, so a later change goes back to the owner. A pass
  counts only for the check the owner approved last. `track.sh verify` runs the check any time.
  The owner's delivery OK runs it again in front of the owner: a pass is recorded with its value, a
  fail needs the owner's waiver, recorded with the failing value. The panel shows the target and the
  first and latest values; a failing check, or a target already met on the first run, is yellow.
  Why: models grade their own work; a measured number does not. In our test the same model got the
  same task as a plain prompt and as a prompt with a target and a check: 11.1 s and a failing check
  without them, 1.43 s and a passing one with them (target under 3 s). That measured the prompt, the
  idea this feature builds into every track.
- **A routing table** (`ROUTING.md`) so nobody has to remember whom to call.
- **A local panel**: green, yellow or red per project with the reason, a live map of each track
  (stages, deliverables by state, prerequisites, the delivery line, items added since opening), decisions
  waiting on the owner with their questions and how long they have waited, the deadline countdown, the
  last 24 hours in three counts (turns, protocol breaks, rejected notes), the sync state, and a box to
  drop files or links into the knowledge inbox.
- **An optional dispatcher** that starts the next session on its own. Off by default.

## Install

```sh
claude plugin marketplace add pwsaragossy/chief-of-staff
claude plugin install chief-of-staff@chief-of-staff
```

The repository is private: each person needs read access to it on GitHub, and Claude Code clones
with their own git credentials (`gh auth login`, then `gh auth setup-git`). Inside Claude Code,
`/plugin marketplace add pwsaragossy/chief-of-staff` and `/plugin install chief-of-staff@chief-of-staff`
do the same. Update later with `claude plugin marketplace update chief-of-staff`.

Then open Claude Code in any folder and run `/chief-of-staff:setup`. It looks at your computer first,
then asks up to four questions in one block, each with a recommendation: where the workspace goes
(default `~/chief-of-staff`); where the company library goes (inside the workspace, your Obsidian
vault, iCloud Drive, Dropbox, Google Drive, OneDrive or an external disk); when the GitHub CLI is
signed in, whether to back up to private GitHub repositories; and whether to work with a team (just
you, a shared library, one board for the whole team, or join a teammate's board). Then it creates:

```
<workspace>/
  .chief-of-staff        marker the hooks look for
  central/CLAUDE.md      the one door to the owner
  board/                 one card per open item (status, project, owner, member, due, asked)
  projects/<slug>/       CLAUDE.md + STATE.md + TRACK.md per project
  knowledge/             inbox/, notes/, templates/ (or the folder you picked; move later: library.sh offload)
  libraries/<team>/      one git clone per team library you joined (ignored by the workspace repo)
  specialists/           one role card per specialist (edit freely)
  ROUTING.md             who to call for what
```

## Daily use

1. Open Claude Code in `<workspace>/central`. It briefs you in at most 5 lines and asks whatever
   is waiting on you, as buttons.
2. To start something, tell central. It runs `/chief-of-staff:new-project`.
3. To work on a project, open Claude Code in `projects/<slug>`. The briefing shows the next action.
4. Close every session with `/chief-of-staff:handoff`.

Skills: `setup`, `new-project`, `handoff`, `specialists`, `knowledge`, `panel`.

## Panel

`/chief-of-staff:panel` starts `scripts/panel.py` (needs `python3`, standard library only) and opens
a link like `http://127.0.0.1:<port>/?t=<token>`. It listens on this computer only and refuses any
request without the token. Colors come from `scripts/health.sh`, which also works as text:

- **red**: a track gate problem, STATE.md says red, a turn in the last 24 h ended without the
  specialists, the reviewer or the track gate, a dispatcher alert, a question waiting on the owner
  past `owner_wait_minutes`, or the deadline less than 2 hours away (or past) with the delivery open;
- **yellow**: a decision waiting on the owner, a card past its `due:` date, the deadline less than
  6 hours away, no handoff for longer than the track's `stale_hours` (3 h for a hackathon, 48 h
  otherwise), paused, the last check run failed, or the target was met on the very first run;
- **green**: none of these.

Files or links dropped in the import box land in the library's `inbox/` (the panel warns when one
looks like it holds a key or token); central turns them into library notes with the `knowledge`
skill. The Library section shows the notes as an interactive graph, drawn on a canvas with no outside
code (it works offline): color by type (finding, decision, howto, option; topics are squares), size
by links, a dashed yellow ring past the review date, an outline only when retired, a red dot with
problems; the 500 most linked when there are more. Zoom with the wheel, a pinch or the buttons, drag
the background to pan, drag a note to pin it (double-click releases it), Fit to see everything.
Pointing at a note lights it and its neighbours; clicking opens its detail (type, state, origin,
confidence, updated, review_by, its problems in words, links out and backlinks, which navigate).
Search by title or id (Enter jumps to the first match), filter by type (the legend), origin, only
with problems or without retired notes. The keyboard works too (Tab, arrows, Enter, Esc, + - 0), a
list of the same notes sits under the graph for screen readers, and reduced motion lays it out in
one step. The 30 s refresh keeps the view, the selection and the positions. Below it: the notes with
problems, broken links, notes past their review date and possible duplicates nobody compared.
In the track map, an item waiting on a prerequisite is grey with a dashed border, a prerequisite in
the same stage shows as "↳ id", and pointing at an item outlines what it needs and what needs it.

## Hooks

Every hook does nothing outside a workspace, so the plugin does not affect your other projects.

- `SessionStart` prints a factual briefing (at most 2000 characters): cards waiting on the owner,
  the project's status and next action, the library's counts and the project's latest notes.
- `PreToolUse` on `AskUserQuestion` blocks button questions in any session that is not `central/`.
- `scripts/protocol.sh` (UserPromptSubmit, PreToolUse, PostToolUse, SubagentStop, Stop) restates
  the protocol every turn and enforces it: a subagent brief must name an existing role card
  (`Role card: <role>`, or `Role card: utility` for a helper); a specialist cannot finish without
  its never-skip checklist and needs a `Library:` line; web search waits for a library search
  (`scripts/library.sh search`); a note is checked on save and at the end of the turn (links,
  `Compared:`, retirements, notes written by shell commands too); agents cannot edit the workspace
  marker;
  a substantive turn (a deliverable file, web research, or a long answer) cannot end without a
  specialist and the reviewer, nor research end without a saved note. Each push happens once per
  turn. Every turn is logged to `<workspace>/.protocol.log`, the adherence record.
- The same Stop hook runs `scripts/track.sh check` in a project session: a stage below `stage:` with
  an open item, an item marked done whose proof file does not exist or whose prerequisites are
  open, a not-applicable item without a reason, a reviewer item marked not applicable, a stage
  without a reviewer item, STATE.md set to done or delivered with open items, or a reached delivery
  line without `DELIVERY.md` and `status: delivered`. The briefing lists what is open
  now in the current stage.

## The dispatcher (off by default)

`scripts/dispatcher.sh <workspace>` runs `claude -p` in each project whose `STATE.md` says
`status: in-progress` and `dispatch: ready`. The `handoff` skill sets `ready` only when the next
action needs nobody. Guard rails:

- refuses to run if the workspace git repo has no remote, unless `COS_ALLOW_NO_BACKUP=1`. The
  sessions cannot push; set `COS_PUSH=1` for the dispatcher to push after its runs, or push yourself;
- at most `COS_MAX_RUNS_PER_DAY` runs (default 3), `COS_MAX_BUDGET_USD` per run (default 2),
  `COS_RUN_TIMEOUT` seconds per run (default 1800); one dispatcher at a time, a stale lock is
  taken over;
- the unattended session gets read and edit tools only, with no shell at all (so no git, no
  Keychain, no push), cannot ask questions, and cannot edit `CLAUDE.md`, `.claude/`, `.git/`, `.gitattributes` or the
  dispatcher's own files (deny rules anchored to the workspace's absolute path);
- the dispatcher itself commits after each run, with git hooks and other code-running git config
  switched off; if `.git/config` or `.git/hooks` changed anyway, it stops and commits or pushes nothing;
- every run is logged in `<workspace>/.dispatch.log`, output in `.dispatch-<slug>.out`;
- a run that ends without a handoff, times out, or is interrupted is parked (`dispatch: off`)
  instead of looping.

Schedulers start with a short PATH, so give the absolute path of the CLI (`command -v claude`).
On macOS, fill in `templates/dispatcher/com.chief-of-staff.dispatcher.plist`. On Linux, a cron line:
`0 */2 * * * CLAUDE_BIN=/abs/path/claude /bin/sh /path/to/scripts/dispatcher.sh /path/to/workspace`.

## Relation to Everything Claude Code (ECC)

[ECC](https://github.com/affaan-m/everything-claude-code) (MIT, v2.2.3 checked on 2026-10-22) is a
large general toolkit: 71 agents, 311 skills, Node.js hooks. We compared it piece by piece; it
fully replaces none of ours, so nothing here was cut. No ECC code is copied into this package.

What we reference or reuse as an idea:

- **Session summary hooks.** ECC's `scripts/hooks/session-end.js` runs on every Stop event and asks
  `claude -p` to summarize the transcript into `~/.claude/session-data/`; `session-start.js` injects
  the latest summary (up to 8000 characters). We keep a deliberate handoff instead: the `handoff`
  skill writes a fixed-format `STATE.md` inside the project folder, readable by any session and
  versioned in git, with no extra model call per response. The two can coexist; if you run both,
  every session start gets two briefings.
- **Minimal profile.** ECC's `minimal` install profile (`manifests/install-profiles.json`) leaves out
  its hook runtime. This package follows the same idea by default: 5 skills, 2 shell hooks that do
  nothing outside a workspace, and the dispatcher off.
- **Security scan.** ECC's AgentShield (`npx ecc-agentshield scan`, separate MIT package) scans
  `CLAUDE.md`, settings, MCP servers, hooks and agents for risky configuration. We do not bundle it.
  It is a useful check before turning the dispatcher on. For this repository we scan for secrets
  with gitleaks before each push.

What is ours, with no equivalent found in ECC:

- one door to the owner, enforced by a hook (`ask-guard`);
- a project playbook with a coherence check of the success criteria and gates;
- a per-project state snapshot with an arrival synthesis by the next session;
- an unattended dispatcher with a run ceiling, budget, timeout, no shell, and git hook checks;
- specialists who work from written role cards and are checked by hooks, attacked by an
  independent reviewer (ECC's `santa-method` and `council` skills are the closest, for code and
  content review, and they are skills the model may not call);
- a company library checked by hooks on every save, where the worse of two conflicting notes is
  retired or the two are merged, and valid alternatives coexist;
- a routing table of whom to call for what.

## Known limits

- **Cloud sessions** (Claude Code on the web) do not load plugins installed on your machine, so
  neither hook runs there. The rules still reach a cloud session only through the `CLAUDE.md` files,
  and only if the workspace is that session's repository.
- The ask guard stops button questions only. A question written as plain text is not blocked; the
  `CLAUDE.md` rules are what prevent it.
- The ask guard has been tested by script, not yet in an interactive session.
- The reviewer is the same model with a different brief. It catches incoherence, not authority.
- "Substantive" is a heuristic (deliverable file, web research, or an answer over about 2500
  characters). A short answer to a real decision is not forced through specialists.
- The hooks check that specialists and the reviewer ran, not that they were good.
- A track gate checks that a proof file exists, not what it says. An agent can still write a
  thin file; the stage's reviewer item, which can never be skipped, is where that is caught.
- The role cards' sources were checked once by a reviewer on 2026-10-22; a few dates and versions
  (RICE post, Nielsen heuristics revision, EDPB guideline versions) are left without a year on
  purpose. Thresholds marked "default, adjust to the case" are conventions, not standards.
- The dispatcher's guard rails rely on Claude Code permission rules; they are not a sandbox. For a
  stronger boundary, run the dispatcher inside a container or a separate user account.
- Library search is lexical (BM25F over titles, aliases, tags and body). A duplicate written with a
  different title, or in another language, is found only by the reviewer, not by the hooks.
  Semantic search would be an optional adapter, worth it past about 5,000 notes.
- A note's truth, and whether "the worse" was really retired, are judged by the reviewer; the hooks
  check that the decision was made and recorded.
- Notes written by shell commands are caught when the command names the library path; other
  bypasses are caught by `library.sh doctor` and the panel, not by the turn gate.
- Team libraries: the hooks block links and writes across libraries, but not an agent retyping
  personal content in its own words into a team note; the reviewer and the team read what is shared.
  Confirmation for join, leave and use matches the command text, so a renamed copy of library.sh
  is not seen, and neither is a protected file name (`.chief-of-staff`, `.library`) built inside a
  shell variable; those files are read-only on disk.
- A shared workspace is the team's: nothing personal belongs in it, and it takes no personal or other
  team library. The hooks do not stop an agent that reads a personal workspace elsewhere on the disk
  and retypes it there; keep the two apart. The key check is a list of known token shapes (cloud keys,
  GitHub tokens, private keys, Stellar secret seeds), not a full secret scanner. The member name is
  local git config, set at join, not an identity check. A conflict (two people changing the same
  card) is undone and becomes a card; it is not merged automatically.
- The owner's OK (`.owner-ok`) is protected like the library settings: written only through
  `track.sh ok`, which asks the owner (in a run with nobody watching, the ask is refused), an item that
  needs it cannot be marked not applicable, and removing its mark or its line after opening is caught
  (the list of those items is written once at opening, read-only, in `.owner-items`). The shell check
  is a word list, not a shell interpreter: it knows common globs (`.o*`, `*-items`), but an agent that
  builds the file name in a shell variable, or with a glob or shell option it does not know, is not
  seen. Then the reviewer and the owner's own read of `.owner-ok` are the last line.
- Ambition: the hooks check that the `Ambition:` line and `## Versions` exist, not that the judge is
  a good one; the reviewer checks that, and it is the same model.
- Target and check: the check runs a shell command written in TRACK.md, so only a session or central
  on your computer runs it (never a hook), never for a teammate's project in a shared workspace, and
  only a command the owner approved on this computer (the approval lives in `.owner-ok`, which never
  syncs; in a shared workspace one that git tracks, in any letter case, came from the team repo: it is
  moved aside and not trusted). A commit this computer did not make that changes the project after the
  approval (a pull by the plugin or by hand) stops the check until the owner approves again.
  The check is only as hard as its inputs. The freeze covers the files the command names and the files
  those name, not what the check reaches without naming it: a test suite run by `npm test` or `pytest`,
  or data the agent writes. Prefer a check that measures the product from outside (its command, its
  URL, a fixed input), and read the frozen file list `track.sh ok <p> check` prints. A timing check can
  be flaky on a busy laptop; the owner's waiver (`waive: <reason>`) exists for that.
  `.check-runs` (the history the panel shows, run by the agent) is not protected: the approval and the delivery result
  live in `.owner-ok`, like the other owner OKs.
- Times: write `deadline:` with its offset (`2026-10-25 18:00 -0300`) when teammates are in other
  time zones; question times are stamped with the offset already. In a shared workspace, files over
  20 MB, nested git repositories, settings (`.claude/`, `.mcp.json`, `.gitignore`, `.gitattributes`)
  and files that look like they hold a key stay on the computer: a key stops the turn until it is
  moved to `.env`, the rest is listed in the next briefing; a change to
  settings coming from the team is refused at pull. A file name with a line break stops the push
  until it is renamed.
- An offloaded library: no automatic sync; Windows paths are not supported; in iCloud, keep the
  folder downloaded on the computer (placeholder files are not seen).

## Check

```sh
sh scripts/selftest.sh
claude plugin validate .
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
