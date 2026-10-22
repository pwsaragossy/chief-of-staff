# chief-of-staff

An AI chief of staff for [Claude Code](https://code.claude.com): a small company of agents that
works for one owner. Version 0.1.

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
  cannot end without at least one specialist and the reviewer.
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
- **A routing table** (`ROUTING.md`) so nobody has to remember whom to call.
- **A local panel**: green, yellow or red per project with the reason, a live map of each track
  (stages, deliverables by state, prerequisites, the delivery line, items added since opening), decisions
  waiting on the owner, the last turns, and a box to drop files or links into the knowledge inbox.
- **An optional dispatcher** that starts the next session on its own. Off by default.

## Install

```sh
claude plugin marketplace add <owner>/chief-of-staff
claude plugin install chief-of-staff@chief-of-staff
```

Replace `<owner>` with the GitHub account that hosts the repository. For a private repository,
Claude Code clones with your existing git credentials
(`gh auth login` then `gh auth setup-git`). Inside Claude Code you can use
`/plugin marketplace add` and `/plugin install` instead.

Then open Claude Code in any folder and run `/chief-of-staff:setup`. It looks at your computer first,
then asks up to four questions in one block, each with a recommendation: where the workspace goes
(default `~/chief-of-staff`); where the company library goes (inside the workspace, your Obsidian
vault, iCloud Drive, Dropbox, Google Drive, OneDrive or an external disk); when the GitHub CLI is
signed in, whether to back up to private GitHub repositories; and whether to join a team library
(paste its git link). Then it creates:

```
<workspace>/
  .chief-of-staff        marker the hooks look for
  central/CLAUDE.md      the one door to the owner
  board/                 one card per open item (status, project, owner, due)
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
  specialists, the reviewer or the track gate, or a dispatcher alert;
- **yellow**: a decision waiting on the owner, no handoff for longer than the track's
  `stale_hours` (3 h for a hackathon, 48 h otherwise), or paused;
- **green**: none of these.

Files or links dropped in the import box land in the library's `inbox/` (the panel warns when one
looks like it holds a key or token); central turns them into library notes with the `knowledge`
skill. The Library section shows the notes as a graph (green active, yellow past review, grey
retired, red ring with problems; the 300 most linked when there are more), with the notes that have
problems, broken links, notes past their review date and possible duplicates nobody compared.

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
- An offloaded library: no automatic sync; Windows paths are not supported; in iCloud, keep the
  folder downloaded on the computer (placeholder files are not seen).

## Check

```sh
sh scripts/selftest.sh
claude plugin validate .
```
