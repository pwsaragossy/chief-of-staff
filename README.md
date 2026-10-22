# chief-of-staff

An AI chief of staff for [Claude Code](https://code.claude.com): a small company of agents that
works for one owner. Version 0.1.

What it gives you:

- **One door to the owner.** Only the `central` session asks you for decisions. Project sessions
  write them on a card in `board/` and keep working; central asks them all at once. The one
  exception: any session may confirm the origin of an order before an irreversible step.
- **A fixed project playbook.** Opening questions, a coherence check of the success criteria,
  registration, stages with gates (continue, stop, pause, redo).
- **Standard handoffs.** Every project has a `STATE.md` in one format (adapted from the I-PASS
  clinical handoff). The next session writes an arrival synthesis and checks one fact before acting.
- **Specialists and an independent reviewer.** No generalist answers: senior specialists as
  subagents, each claim marked FACT or INFERENCE, and someone who did not do the work attacks it.
- **A knowledge base that gets used.** What you send to study becomes a note linked to a project;
  the project briefing lists it until the project session integrates or discards it.
- **A routing table** (`ROUTING.md`) so nobody has to remember whom to call.
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

Then open Claude Code in any folder and run `/chief-of-staff:setup`. It asks where to create the
workspace (default `~/chief-of-staff`) and creates:

```
<workspace>/
  .chief-of-staff        marker the hooks look for
  central/CLAUDE.md      the one door to the owner
  board/                 one card per open item (status, project, owner, due)
  projects/<slug>/       CLAUDE.md + STATE.md per project
  knowledge/             inbox/, notes/, topics/, templates/
  ROUTING.md             who to call for what
```

## Daily use

1. Open Claude Code in `<workspace>/central`. It briefs you in at most 5 lines and asks whatever
   is waiting on you, as buttons.
2. To start something, tell central. It runs `/chief-of-staff:new-project`.
3. To work on a project, open Claude Code in `projects/<slug>`. The briefing shows the next action.
4. Close every session with `/chief-of-staff:handoff`.

Skills: `setup`, `new-project`, `handoff`, `specialists`, `knowledge`.

## Hooks

Both hooks do nothing outside a workspace, so the plugin does not affect your other projects.

- `SessionStart` prints a factual briefing (at most 2000 characters): cards waiting on the owner,
  the project's status and next action, new knowledge notes to integrate.
- `PreToolUse` on `AskUserQuestion` blocks button questions in any session that is not `central/`.

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
  Keychain, no push), cannot ask questions, and cannot edit `CLAUDE.md`, `.claude/`, `.git/` or the
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
- specialists who mark each claim FACT or INFERENCE, attacked by an independent reviewer
  (ECC's `santa-method` and `council` skills are the closest, for code and content review);
- a knowledge base where each note is linked to a project and must be integrated or discarded;
- a routing table of whom to call for what.

## Known limits

- **Cloud sessions** (Claude Code on the web) do not load plugins installed on your machine, so
  neither hook runs there. The rules still reach a cloud session only through the `CLAUDE.md` files,
  and only if the workspace is that session's repository.
- The ask guard stops button questions only. A question written as plain text is not blocked; the
  `CLAUDE.md` rules are what prevent it.
- The ask guard has been tested by script, not yet in an interactive session.
- The reviewer is the same model with a different brief. It catches incoherence, not authority.
- The dispatcher's guard rails rely on Claude Code permission rules; they are not a sandbox. For a
  stronger boundary, run the dispatcher inside a container or a separate user account.
- Notes still `new` after 21 days are to be discarded by the project session (a rule in the
  `knowledge` skill); no script enforces it yet.

## Check

```sh
sh scripts/selftest.sh
claude plugin validate .
```
