# chief-of-staff

An AI chief of staff for [Claude Code](https://code.claude.com) and [Grok](https://x.ai): a small company of agents that
works for one owner.

What it gives you:

- **A project is the folder you work in.** No central folder: `/chief-of-staff:new-project` makes the
  conversation's folder a project (opening questions, then a `.chief-of-staff` marker, `board/`, `STATE.md`,
  `DECISIONS.md`), the folder joins the plugin's project list and the conversation becomes its coordinator.
  `/threads` only makes a conversation a coordinator (threads, the Threads pane); it creates no project.
  `/chief-of-staff:setup` picks where the library lives first. The web panel shows one project, or every registered one; the global one adds a Pipeline kanban (idea, validating, building, launched, earning, paused) where you drag a project to its phase (saved in its `STATE.md`, or in `PIPELINE.md` beside a board).
- **Projects that talk to you.** Each project's conversation at its folder's root is its coordinator:
  it asks you its decisions and runs long or parallel work in threads nested under it. Questions that
  waited while you were away sit on a card in `board/`; the coordinator asks them all at once. Threads and
  subfolders do not ask you, except to confirm the origin of an order before an irreversible step.
  Everything runs on this computer. When the coordinator starts a thread, its row in the chat draws as a
  thread card (title, state, a press that opens it), and the Threads pane lists every thread by state.
  Only the coordinator talks to you and writes `DECISIONS.md`; a thread brief that names no specialist
  (`Role card:`, `Library:`) is refused, and every brief opens with the thread rules: no
  Save or Submit in an external form, no push, no deploy, no message sent without your approval.
  Text is reviewed before video or images are rendered, and the coordinator asks where things run
  before it proposes a host.
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
  the project's `.chief-of-staff`, set by the owner) internal work needs one specialist, and the
  reviewer runs only on what goes outside: the submission, the video, the README, messages to judges.
- **A company library (second brain), enforced by hooks.** One note per file in `knowledge/notes/`,
  readable in Obsidian: findings, decisions, how-tos and formats, options, topics. Each note carries
  its origin (project or research) but every project uses every note. Links are inline `[[id]]`;
  backlinks, index and graph are computed on the fly, never stored. A note is checked the moment it
  is saved (format, sources for its confidence, no secrets, no hidden text, third-party text fenced as
  data). When a new note meets a similar one it must say how: the worse is retired, the two are
  merged, or they coexist as valid options. Every prompt brings the notes that bear on it, briefs
  carry a `Library:` line, web research is reminded once per turn to search and save to the library
  (never blocked), and DELIVERY.md cites its sources.
  The library can live on an external disk, a cloud folder or a private repo (`project.sh library <folder>`).
- **Team sync is a separate plugin.** chief-of-staff works for one owner. Team sync left in 0.12.0 and will
  come back as its own plugin; 0.11.5 still has the old shared workspace.
- **Built for deadlines.** A project's `TRACK.md` can carry `deadline: YYYY-MM-DD HH:MM`: the panel
  counts down, yellow under 6 hours, red under 2 hours while the delivery is open. A question waiting
  on the owner turns red after `owner_wait_minutes` (60 by default, 20 in the hackathon track), with
  its age shown. Each question line carries the time it was asked (`- (asked 2026-10-25 18:00 -0300) ...`,
  stamped by the turn-end hook), and the card is timed from its oldest open question, so rewriting `asked:`
  or adding a newer question never makes an old one look young. With `deputy: <name>` in TRACK.md, a
  question past its limit less than 3 hours before the deadline is escalated to the deputy. The panel and
  the briefing show the questions themselves. Items marked `owner: ok`
  (the hackathon's scope freeze and submission) close only with the owner's OK, which the coordinator records
  with `track.sh ok` and the owner approves.
- **Ambition proposes, the owner decides.** Every new task goes through the `ambition` skill (a question is answered at once, without it):
  the goal behind the goal, the rawest material, who does this work, and an outside judge. The bigger
  version a top professional would deliver reaches the owner as an option with its cost and a
  recommendation; nothing past the request is built without the owner's answer.
- **The owner decides what they will see.** Before building, every session lists the decisions the
  work depends on. The ones that shape what the owner will see or use (what gets built, reuse or
  rebuild, its look and format, its scope, what a sample is) go to the owner, and nothing is built on
  them before the answer. A thread asks through the coordinator, which never answers for the owner,
  and a line in `DECISIONS.md` records only the owner's own words in quotes, with the time.
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
- **A decision log and facts with a time.** Each project keeps `DECISIONS.md`, one line per decision
  (`date time | decision | who | replaces`); a later line replaces or revokes an earlier one, and the
  briefing shows the decisions in force. A decision may say `guard: <term>`: a `git push` whose commits
  change that term asks first. STATE.md facts carry `verified: <date time>`; the briefing flags the ones
  older than the track's `stale_hours`, and the handoff never copies a fact that changes on its own
  (production commit, balances, public links, deploy state) without measuring it again.
- **What goes outside, seen as a stranger.** Optional `public_urls:` (opened without credentials) and
  `prod_ref: <url> <commit>` (production serves that commit) in TRACK.md are checked by `health.sh` and the
  panel, never by a hook, at most every 10 minutes; a DELIVERY.md or TRACK.md that points at a file
  outside the project folder is flagged too.
- **A routing table** (`ROUTING.md`) so nobody has to remember whom to call.
- **A local panel**: green, yellow or red per project with the reason, a live map of each track
  (stages, deliverables by state, prerequisites, the delivery line, items added since opening), decisions
  waiting on the owner with their questions and how long they have waited, the deadline countdown, the
  last 24 hours in three counts (turns, protocol breaks, rejected notes), and a box to
  drop files or links into the knowledge inbox.
- **An optional dispatcher** that starts the next session on its own. Off by default.

## Install

```sh
claude plugin marketplace add pwsaragossy/chief-of-staff
claude plugin install chief-of-staff@chief-of-staff
```

The repository is public, so installing needs no GitHub account or access. Inside Claude Code,
`/plugin marketplace add pwsaragossy/chief-of-staff` and `/plugin install chief-of-staff@chief-of-staff`
do the same. Update later with both commands, then restart Claude Code (the first only refreshes the
marketplace; the installed copy stays on its old version until the second):

```sh
claude plugin marketplace update chief-of-staff
claude plugin update chief-of-staff@chief-of-staff
```

With a local marketplace (a clone added by path), run `git pull` in the clone first.

Grok Build loads the same plugin. Add the marketplace, install it, and trust it (hooks stay off until you do):

```sh
grok plugin marketplace add pwsaragossy/chief-of-staff
grok plugin install chief-of-staff --trust
```

Update later with `grok plugin marketplace update` and `grok plugin update chief-of-staff`. Then open Grok in any folder and run `/chief-of-staff:setup`. `${CLAUDE_PLUGIN_ROOT}` and `${GROK_PLUGIN_ROOT}` are the plugin folder. Slash commands fill them. Export `CLAUDE_PLUGIN_DATA` from `${GROK_PLUGIN_DATA}` before a script when the shell does not already have it.

What reaches Grok, and what does not:

- Session start uses `new` and `load` (Claude's `startup`, `resume`, `clear` and `compact` never match). The briefing is a `systemMessage`. Grok drops plain SessionStart text, and it drops an allowing UserPromptSubmit, so the per-prompt protocol text is not injected. The stop and pre-tool gates still run.
- Tool names are translated before the gates (`web_search`, `web_fetch`, `open_page`, `spawn_subagent`, `search_replace`, `write`, `run_terminal_command`, `read_file`, `ask_user_question`, and the Cursor names). Research stays a reminder, not a block, the same as on Claude since 0.12.11.
- `PostCompact` resets the turn the way a compaction does. It does not ask for a new session. Grok does not show that hook's `systemMessage`, and it drops the next prompt's protocol text, so after a compaction the model is not briefed again. The stop and pre-tool gates still run. Rotation left in 0.12.11.
- `hooks/projects.tsx` is Claude's module runtime (the Threads pane). On Grok the shell ask-guard still blocks `ask_user_question` outside the coordinator.
- The dispatcher runs `grok -p` when `COS_ENGINE=grok`, when `CLAUDE_BIN` is grok, or when `claude` is not on PATH. The unattended run gets read and edit tools only (`--max-turns 40` stands in for the dollar budget, which Grok does not take).
- `sh scripts/check.sh` uses `grok plugin validate` when the claude CLI is absent. `claude plugin test` (the `projects.tsx` module) still needs claude.

Then open Claude Code in any folder and run `/chief-of-staff:setup`. It looks at your computer first,
asks one question: where the company library goes (your Obsidian vault, iCloud Drive, Dropbox, Google
Drive, OneDrive or an external disk). A project folder then holds:

```
<project folder>/
  .chief-of-staff        marker the hooks look for (kind: project)
  board/                 one card per open item (status, owner, member, due, asked)
  STATE.md               the snapshot the next conversation starts from
  DECISIONS.md           the decisions in force, one line each
  TRACK.md               the stages and gates, when the project has a track
  specialists/           optional: role cards of its own (else the plugin's)
```

The plugin's data folder keeps `projects` (one registered folder per line) and `library` (the library's
path). The older workspace layout (`central/`, `projects/<slug>/`) was removed in 0.12.0: the briefing of
such a folder says so, and `/chief-of-staff:new-project` in each project's own folder starts it again
(copy its STATE.md, TRACK.md and board card across).

## Upgrading from 0.5 to 0.11

Update as in [Install](#install), then:

- **Old workspace layout.** A workspace of the layout removed in 0.12.0 (`central/`, `projects/<slug>/`)
  is no longer read: its briefing says so in one line, and `project.sh` refuses to register it. For
  each project, open its own folder, run `/chief-of-staff:new-project`, and copy across its `STATE.md`,
  `TRACK.md` and board cards.
- **Library.** `/chief-of-staff:setup` asks for one library. Point it at your existing library folder
  (the one with `.library-id` and `notes/`): it is kept as it is.
- **Team sync.** Shared projects, team libraries and their commands were removed in 0.12.0 (`setup.sh create`/`join`, `sync.sh`, `library.sh join`/`leave`/`use`).
  A folder that was shared says so once in its briefing, and nothing is sent to or pulled from the team.
  If your team still works that way, stay on 0.11.5 (commit `27a3db1`) until the team plugin ships.
- **Rollback.** Install 0.11.5, or restore single files with `git checkout 7f56dbf -- <path>` (as in the
  0.12.0 release notes).

## Upgrading from 0.4.x

Nothing to migrate by hand for project folders:

- Cards with the old single `asked:` keep their age: at the first turn end, their open questions are
  stamped with that `asked:` time, and new ones with their own time.
- `Role card: <role>` still works; a brief may now give the card's path instead, and nobody pastes the card.
- `DECISIONS.md` is optional in old projects (copy `templates/project/DECISIONS.md` to start one); new
  projects get it.
- `deputy:`, `public_urls:` and `prod_ref:` in TRACK.md are optional; without them nothing changes.

## Daily use

1. Open a conversation in the project's folder. The first time, run `/chief-of-staff:new-project` (opening
   questions and a track; it makes the folder a project). Later conversations there are its
   coordinator from the start: the briefing shows where it stopped, the decisions and what waits on you.
2. Long or parallel work runs as threads the coordinator starts; the Threads pane lists them.
3. `/chief-of-staff:panel` in a project shows that project; anywhere else, every project.
4. Close every session with `/chief-of-staff:handoff`.

Skills: `setup`, `new-project`, `ambition`, `handoff`, `specialists`, `knowledge`, `panel`.

## Panel

On a phone, or with no project, `scripts/overview.sh <board folder>...` prints the whole picture as chat
text: what waits on you, due in 7 days, changed in 24 hours, moving, stopped (English or Portuguese card fields).

`/chief-of-staff:panel` starts `scripts/panel.py` (needs `python3`, standard library only) and opens
a link like `http://127.0.0.1:<port>/?t=<token>`. It listens on this computer only and refuses any
request without the token. Colors come from `scripts/health.sh`; `health.sh text <project folder>` prints them
without the panel: a verdict first ("All fine" or how many questions wait on you), one line per project,
then your questions with their age:

- **red**: a track gate problem, STATE.md says red, a turn in the last 24 h ended without the
  specialists, the reviewer or the track gate, a dispatcher alert, a question waiting on the owner
  past `owner_wait_minutes` (escalate to the `deputy:` when the deadline is under 3 hours), or the
  deadline less than 2 hours away (or past) with the delivery open;
- **yellow**: a decision waiting on the owner, a card past its `due:` date, the deadline less than
  6 hours away, no handoff (STATE.md `updated:`, not the file date) for longer than the track's
  `stale_hours` (3 h for a hackathon, 48 h otherwise), paused, the last check run failed, the target met on
  the very first run, a card over ~60 lines or 15 KB, a `public_urls:` link closed to a logged-out visitor,
  production not serving the `prod_ref:` commit, or a delivery that points outside the project folder;
- **green**: none of these.

Each project lists every reason, red ones first (more than 3 fold under "more reasons"), the
`public_urls:` and `prod_ref:` results as a logged-out visitor sees them, and the last 5 decisions in
force from `DECISIONS.md`. Each question waiting on the owner shows how long ago it was asked, a card
past its limit near the deadline names the `deputy:` who decides, and a card too long to read says so.

Files or links dropped in the import box land in the library's `inbox/` (the panel warns when one
looks like it holds a key or token); the coordinator turns them into library notes with the `knowledge`
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

Every hook does nothing outside a project folder, so the plugin does not affect your other projects.
Opt-in for the rest of your folders: list them in `everywhere` inside the plugin's data folder
(`~/.claude/plugins/data/chief-of-staff-chief-of-staff/everywhere`, one absolute path per line, `/` for all).
There the specialists gate runs with the plugin's own role cards; no library, board or
track, and turns are logged to `protocol.log` in the same data folder.
A second opt-in, `knowledge-mcp` in the same data folder, holds the path of a knowledge-mcp `server.py`: at each new
session, in any folder, the briefing lists the knowledge bases its `discover` found and never offered, and the session
asks the owner once which to add (each answer is recorded by its id, a no too, and never asked again). Each base is
shown in one session only, answered or not (`kb-offered` in the data folder; delete it to be asked again).

- `SessionStart` prints a factual briefing (at most 2000 characters): cards waiting on the owner,
  the project's status and next action, the library's counts and the project's latest notes.
- `PreToolUse` on `AskUserQuestion` blocks button questions in any session that is not a project's coordinator.
- `PreToolUse` on `Bash` approves by itself the plugin's own read-only commands, the ones the hooks already
  run on their own: one call of `library.sh` (`search`, `similar`, `check`, `gate`, `doctor`, `backlinks`,
  `brief`, `where`, `libs`) or `track.sh` (`check`, `brief`, `status`, `items`) at the plugin's own path, with no
  shell syntax and paths only inside the project folder. Anything else asks as usual; your own deny and ask rules still
  apply over it, and plan mode is not bypassed. Every git command the scripts run refuses a folder that only looks
  like a repository (a teammate could commit one) and ignores `core.fsmonitor`.
- `scripts/protocol.sh` (UserPromptSubmit, PreToolUse, PostToolUse, SubagentStop, Stop) states
  the protocol in full at the first prompt of a session and after a compaction or restart (nothing on
  the other prompts) and enforces it: a subagent brief must name an existing role card by its path
  (`Role card: <project>/specialists/<role>.md`, which the subagent reads itself, or `Role card:
  utility` for a helper; an Explore, web-fetch or claude-code-guide subagent is a helper by its type); a
  turn that only edits a file this session already put through specialists and the reviewer is not a new deliverable
  (a Write, or an edit of DECISIONS.md, still is); a .md inside a code repository (git plus a build or test
  manifest at its top: a skill, a template, docs/) is code, not a deliverable, except its README and DECISIONS.md; a specialist cannot finish without its never-skip checklist, and its brief needs a `Library:` line; web research gets one reminder per turn to search
  the library (`scripts/library.sh search`) and save what it found, never a block; a note is checked on save and at the end of the turn (links,
  `Compared:`, retirements, notes written by shell commands too); agents cannot edit the project's
  marker;
  a substantive turn (a deliverable file or a long answer) cannot end without a
  specialist and the reviewer; research alone is not substantive. Each push happens once per
  turn. Every turn is logged to `<project>/.protocol.log`, the adherence record.
- Screens (`scripts/screens.sh`, called by `protocol.sh`), in a project folder. **No screen code before its
  design**: a Write or Edit of a file that renders a screen (html, css, jsx, tsx, vue, svelte, astro; swift, kotlin,
  dart, js or ts that use a UI framework; not tests) is blocked while the project's design item is not done. A design
  item is a TRACK.md item with id `ui-spec` or a `screens:` field (path patterns of the product's screens, so a deck
  is not held; an item with a `video:` field holds video files the same way); it is done when closed with evidence that holds a `References:` section (1-2
  real apps, with links) and a `Library:` line, or marked not applicable with `why:`. The block tells the agent to
  run the designer: fresh web research first, 1-2 real reference apps, then the design, with mockups under `design/`, which is
  never held. Screen code a shell command wrote is caught at the end of the turn (pushed once). A project with no
  design item is not held: once per turn it is told what a screen needs. **No screen to the owner before its
  review**: every change of a screen file is recorded; an `Artifact` publish, a `SendUserFile` of a page, a
  picture, a drawing (svg) or a pdf, and a shell `open` of any of them or of a local server are blocked until the newest review in `design/reviews/`
  says `Verdict: pass`, is newer than every change and holds a screenshot taken after the last change. An answer
  that points at a screen (a localhost address, a page, a picture, a drawing, a pdf) is pushed at the end of the turn, and that push
  holds the second stop too, twice at most. A review is rejected on save without `Verdict:`, a `References:` section
  with links and a `Side by side:` section naming two different, non-empty saved screenshots (this screen and the
  reference); one written in a turn that ran no reviewer subagent is made void. Paths are compared as the disk
  resolves them (`..`, symlinks, letter case), and a design item's evidence is one file of the project named by a
  plain relative path. A designer subagent cannot finish without a `References:` section.
  `sh scripts/screens.sh state <project>` says where the project stands.
- The design system (`design/SYSTEM.md`, from `templates/design/SYSTEM.md`), in a project folder that keeps one.
  **The owner picks every piece before anything is built on it**: typography, colors, components and motion for
  screens; tone, rhythm and script (with typography, colors and motion) for video. Screen code and video code (a
  HyperFrames, Remotion or Motion Canvas composition, or a rendered mp4, mov, webm, m4v or mkv) are blocked while a
  piece they need is open or its text changed after the owner's OK; mockups under `design/` are free. A piece closes
  in four steps the hooks hold: (1) its specialist (`designer`, or the new `tone`, `rhythm` and `script` cards) writes
  `design/options/<piece>.md` with 2-3 references, each with its exact link, a date at most `refs-max-months` (the
  project's setting, default 6) before the research, and what we take; the proposal is rejected on save without a
  web search in the same turn that its `Searches:` list names exactly, or with today's date missing, and voided at the end of a turn that ran none; (2) the
  reviewer writes `design/reviews/options/<YYYY-MM-DD HHMM> <piece>.md` with every link, its HTTP status and keep or
  reject (a pass keeps every link, each with a 2xx status after redirects; a review written with no reviewer subagent is void); an answer that shows the
  owner links not yet cleared is pushed back, and a page or file carrying them is not published or sent; (3) the owner picks, and only the coordinator records it with
  `track.sh ok <project> design:<piece> <words>`, which the owner approves, after `screens.sh piece` confirms the
  proposal, its passing review newer than it, a `Pick:` naming one of its links and research under a month old;
  (4) the OK freezes the piece above its `### Applied` part and its proposal (a sha256): any change needs a new OK.
  Each kind always needs its own pieces, so deleting one from the file or changing its `For:` line holds the gate
  again. Deleting `design/SYSTEM.md` does not open the gate in a project whose CLAUDE.md names it or that holds an OK on
  a piece. A designer, tone, rhythm or script subagent cannot finish without `References:` and a web search in its
  turn. A role card the plugin ships reaches a project that keeps its own `specialists/` folder (the project's card
  wins when both exist). Agents write nothing in the plugin's data folder. A project with no design system yet (one
  that started before it) is not locked as it stands: edits of its existing screen and video files go on, with a
  notice once per turn, and its first new screen or video (a file not on disk or not in the last commit; without git, every file already
  on disk counts as existing) waits while the
  design system is proposed to the owner, with what the project already uses as one option per piece
  (`## Option A (current)` with `From:` its file, no link or date) beside 1-2 fresh references. The owner may turn it
  off for a project with `design-system: off` in its settings; then only TRACK.md design items hold its screens. `sh scripts/screens.sh system <project>
  screens|video` says where it stands.
- The same Stop hook runs `scripts/track.sh check` in a project session: a stage below `stage:` with
  an open item, an item marked done whose proof file does not exist or whose prerequisites are
  open, a not-applicable item without a reason, a reviewer item marked not applicable, a stage
  without a reviewer item, STATE.md set to done or delivered with open items, or a reached delivery
  line without `DELIVERY.md` and `status: delivered`. The briefing lists what is open
  now in the current stage.

## The dispatcher (off by default)

`scripts/dispatcher.sh <project folder>` runs `claude -p` (or `grok -p` with `COS_ENGINE=grok`) in each project whose `STATE.md` says
`status: in-progress` and `dispatch: ready`. The `handoff` skill sets `ready` only when the next
action needs nobody. Guard rails:

- refuses to run if the project's git repo has no remote, unless `COS_ALLOW_NO_BACKUP=1`. The
  sessions cannot push; set `COS_PUSH=1` for the dispatcher to push after its runs, or push yourself;
- at most `COS_MAX_RUNS_PER_DAY` runs (default 3), `COS_MAX_BUDGET_USD` per run (default 2),
  `COS_RUN_TIMEOUT` seconds per run (default 1800); one dispatcher at a time, a stale lock is
  taken over;
- the unattended session gets read and edit tools only, with no shell at all (so no git, no
  Keychain, no push), cannot ask questions, and cannot edit `CLAUDE.md`, `.claude/`, `.git/`, `.gitattributes` or the
  dispatcher's own files (deny rules anchored to the project folder's absolute path);
- the dispatcher itself commits after each run, with git hooks and other code-running git config
  switched off; if `.git/config` or `.git/hooks` changed anyway, it stops and commits or pushes nothing;
- every run is logged in `<project>/.dispatch.log`, output in `.dispatch-<slug>.out`;
- a run that ends without a handoff, times out, or is interrupted is parked (`dispatch: off`)
  instead of looping.

Schedulers start with a short PATH, so give the absolute path of the CLI (`command -v claude`).
On macOS, fill in `templates/dispatcher/com.chief-of-staff.dispatcher.plist`. On Linux, a cron line:
`0 */2 * * * CLAUDE_BIN=/abs/path/claude /bin/sh /path/to/scripts/dispatcher.sh /path/to/project`.

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
  its hook runtime. This package follows the same idea by default: 7 skills, 3 hook scripts that do
  nothing outside a project folder unless you opt in, and the dispatcher off.
- **Security scan.** ECC's AgentShield (`npx ecc-agentshield scan`, separate MIT package) scans
  `CLAUDE.md`, settings, MCP servers, hooks and agents for risky configuration. We do not bundle it.
  It is a useful check before turning the dispatcher on. For this repository we scan for secrets
  with gitleaks before each push.

What is ours, with no equivalent found in ECC:

- only each project's coordinator asks the owner, enforced by hooks (`ask-guard`, and a thread check in the module);
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

- **Grok** injects the session briefing only as a `systemMessage`, and drops UserPromptSubmit stdout, so the model does not see the per-prompt protocol text. A compaction's `PostCompact` briefing is not shown either. The gates still block. A Grok transcript is not Claude's, so the token half of an old rotation check would not have fired. That check is gone. `hooks/projects.tsx` does not run, so the Threads pane is Claude Code only.
- **Cloud sessions** (Claude Code on the web) do not load plugins installed on your machine, so
  neither hook runs there. The rules still reach a cloud session only through the `CLAUDE.md` files,
  and only if the project folder is that session's repository.
- The ask guard stops button questions only. A question written as plain text is not blocked; the
  `CLAUDE.md` rules are what prevent it.
- The ask guard has been tested by script, not yet in an interactive session.
- The reviewer is the same model with a different brief. It catches incoherence, not authority.
- "Substantive" is a heuristic (deliverable file or an answer over 6000 characters,
  measured on the answer itself). Until v0.4.7 it was the whole hook input over 2500 bytes, which a
  2-3 KB status report crossed and forced specialists on every turn. A short answer to a real decision
  is not forced through specialists.
- The prompt's unasked library lookup leaves out notes past `review_by` and weak matches (score under
  1.5), lists high and medium notes first, then low ones (the default of a new note) labelled "low
  confidence — verify before citing", and shows each note's matching line; `library.sh search`
  run by the agent shows everything. A lookup that took 2 s or more is skipped until a note is added.
- The decision guard reads the diff of the repository the hook runs in (the session's folder), not one
  a command reaches with `cd` or `-C`; it is a reminder that asks, not a lock. It compares with the
  branch's upstream, else the same branch on `origin`, else `origin/HEAD` (or `origin/main`, `origin/master`)
  for a new branch pushed with `-u`; with none of them it asks, since what the push changes is unknown.
- The hooks keep inside Claude Code's limits (5 s, 10 s for the briefing): each slow step (the prompt's
  library lookup, the turn-end note and track checks, the briefing's board and library reads) has its own
  budget. A lookup cut short is skipped until a note is added; a turn-end check cut short blocks the turn
  once and says what to run, and is logged as `slow=`,
  not as a violation; the briefing says what it could not read.
- The near-duplicate file notice compares names only, among files with the same extension (letter case,
  separators and a final s ignored), and never blocks: it asks the agent to check whether one duplicates the other.
- The hooks check that specialists and the reviewer ran, not that they were good.
- The design-system gates check that each reference has a link, a date inside the window and a line in the
  reviewer's file with its status, not that the reviewer opened it or that the work is the best: the reviewer's card
  holds that. The web search they require is one the proposal names, run in the same turn, not proof it found the best work.
  An answer that describes the options without their links is not caught. A video is known
  by its composition markers or its file extension; a video made another way is held only by a `video:` item.
- The screen gates know a screen file by its extension (and, for scripts and native code, by a UI framework in its
  text), and a shown screen by the tool (`Artifact`, `SendUserFile`) or by words in the answer. A screen opened in
  the browser pane to check one's own work (`preview_start`) is not blocked: that is how the builder and the
  reviewer see it, and the owner can see that pane. Pointing the owner at a screen in the answer is pushed at most
  three times per turn, not locked. A shell command that writes screen code is caught at the end of the turn, not
  before. The review gate checks the review's form and its times, not its judgement: the newest passing review clears
  every screen of the project, and a design item's evidence is checked for references and the library, not for
  quality. A screen changed in the same second as its review counts as changed after it.
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
- Confirmation for init, library and trust matches the command text, so a renamed copy of project.sh
  is not seen, and neither is a protected file name (`.chief-of-staff`, `.library-id`) built inside a
  shell variable; those files are read-only on disk.
- The owner's OK (`.owner-ok`) is protected like the library settings: written only through
  `track.sh ok`, which asks the owner (in a run with nobody watching, the ask is refused), an item that
  needs it cannot be marked not applicable, and removing its mark or its line after opening is caught
  (the list of those items is written once at opening, read-only, in `.owner-items`). The shell check
  is a word list, not a shell interpreter: it knows common globs (`.o*`, `*-items`), but an agent that
  builds the file name in a shell variable, or with a glob or shell option it does not know, is not
  seen. Then the reviewer and the owner's own read of `.owner-ok` are the last line.
- Owner decisions: no hook can tell which choice shapes what the owner sees; the protocol, the
  coordinator and the reviewer ask for it, and they are the same model.
- Target and check: the check runs a shell command written in TRACK.md, so only a session or the coordinator
  on your computer runs it (never a hook), and only a command the owner approved on this computer (the
  approval lives in `.owner-ok`, which is local: one that git tracks, in any letter case, came through git
  and not from this computer's owner, so it is moved aside to `.owner-ok.from-git` and not trusted).
  The check is only as hard as its inputs. The freeze covers the files the command names and the files
  those name, not what the check reaches without naming it: a test suite run by `npm test` or `pytest`,
  or data the agent writes. Prefer a check that measures the product from outside (its command, its
  URL, a fixed input), and read the frozen file list `track.sh ok <p> check` prints. A timing check can
  be flaky on a busy laptop; the owner's waiver (`waive: <reason>`) exists for that.
  `.check-runs` (the history the panel shows, run by the agent) is not protected: the approval and the delivery result
  live in `.owner-ok`, like the other owner OKs.
- Times: write `deadline:` with its offset (`2026-10-25 18:00 -0300`) when people are in other
  time zones; question times are stamped with the offset already.
- The project root is the nearest folder with a `.chief-of-staff` marker. A marker that arrives in a subfolder
  (a hand `git pull`, or an agent building the name in a variable) makes that subfolder look like a project of its
  own, and its track gate and guarded-push ask stop. A
  forged owner OK stays untrusted (the guards read every marker above), but nothing else catches it: keep project
  repositories without a marker, and look at `git status` after a pull by hand.
- A library outside the project (disk, cloud folder): no automatic sync; Windows paths are not supported; in iCloud, keep the
  folder downloaded on the computer (placeholder files are not seen).

## Pitfalls for maintainers

- **WSL drives.** A project under `/mnt/c` (drvfs) reads files about 70 times slower than the Linux
  home; every hook pays it. `setup.sh` warns; prefer `~/chief-of-staff`. Run the selftest from a copy on
  ext4 too (`/tmp`), or it takes many minutes.
- **No fork per item in hooks.** The hooks run on every prompt and tool call: one `awk` over the board
  (`cos_board`), note ids from a cache keyed by the `notes/` folder's mtime (`cos_ids`), no `dirname`
  loop, and Read/Grep/Glob leave before any setup unless they name a library.
- **The turn-end gate reads the turn's notes, not the library.** `library.sh gate` keeps an index of
  each note's id, state, type, title words and `Compared:` (`noteidx-*` in the plugin data folder) and
  reads only the targets and the notes whose ctime is newer than the index (one `find`, a stat per note);
  for the personal library the Stop hook passes the turn's start (`COS_SINCE`), so an index refreshed
  after it (the prompt hook runs `library.sh index` in the background) needs no scan at all. A check that
  needs another note's facts must add them to the index (`saveidx`/`loadidx` in `library.awk`). Never `ls`
  the notes in a hook: `ls` stats every file (1.8 s for 300 notes on `/mnt/c`); test the glob instead.
- **Background children hold pipes.** A `sleep` left by a killed watcher kept the dispatcher's output
  open for up to `COS_RUN_TIMEOUT`; watchers poll instead.
- **Hook stdin.** `briefing.sh` reads its hook input only when stdin is not a terminal; tests feed it
  `/dev/null`.

## Check

```sh
sh scripts/check.sh
```

It always runs `claude plugin validate .` and the module tests (`claude plugin test .`, seconds), and the
full `scripts/selftest.sh` (about 6 minutes) only when something it reads changed since the last release:
`scripts/`, `templates/`, `skills/`, `hooks/hooks.json` or this README. `ALL=1` runs it anyway. The version
lives only in `.claude-plugin/plugin.json`.

## License

Apache License 2.0. See [LICENSE](LICENSE).

Contributors: Pedro Wakigawa Saragossy, Leo Schlanger ([@leo-schlanger](https://github.com/leo-schlanger)).
