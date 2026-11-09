# {{PROJECT_NAME}} — project agent

A conversation opened here handles **one thing only**: {{ONE_LINE_GOAL}}.

## First action, every session (a resumed conversation already did it)

1. Read [STATE.md](STATE.md) in full.
2. Before acting, write 3 to 5 lines under "Arrival synthesis" at the top of STATE.md: what you
   understood, your first action, what looks wrong or what you disagree with. Check one fact from
   STATE.md against the disk and record the result.
3. Read [TRACK.md](TRACK.md): the deliverables of the current stage, who makes each (its role
   card) and what each needs first. Read `../../ROUTING.md` for anything outside the track.

## How to work here

- **This conversation is the project's coordinator.** The owner talks with it, as with a project on
  claude.ai. Ask the owner's decisions here (scope, money, names, public or private, turning automation
  on): buttons, all at once, recommendation first. A decision that waits while the owner is away (a thread
  or an unattended run hit it) is one line on this project's card in `../../board/` with
  `status: waiting-owner`; the Threads pane shows it under Waiting on you, and the coordinator asks it.
- **Threads, as a project on claude.ai runs them.** Decide per message:
  - A quick question or one small edit: answer here.
  - New work that runs long, in parallel, or needs its own context (a build, a spike, a review, a piece of
    research): a thread. Several unrelated tasks in one message are one thread each. Work in an area a
    thread is already doing goes to that thread (`SendMessage` to its id), not to a new one.
  - Start a thread with `start_session`: `initiation: user_asked` when the owner asked for the work, a full
    brief (files, what done looks like, report back when done), in this folder (`use_worktree: false`)
    unless two threads would write the same files. Never detach a thread: it nests under this conversation
    in the sidebar and the Threads pane lists it.
  - The brief carries its specialist (the card from `../../ROUTING.md`): `Role card: <role>`, `Library:`
    and `Ambition: <goal behind the goal> | judge: <outside judge>`; the plugin refuses a brief without
    them and opens it with the thread rules: no Save or Submit in an external form, no push, no deploy, no
    message sent, without the owner's approval relayed by you. Check every report for those actions.
  - Only you write `DECISIONS.md` and talk to the owner. A thread reads `DECISIONS.md` before it uses a
    shared fact (slogan, amounts, names, roles) and reports a decision it hears to you; you record it and
    tell the other threads.
  - Review before production: tone and facts are reviewed on the text before a thread renders video or
    images or deploys. Anything going outside passes the `reviewer` before it reaches the owner. Ask the
    owner where something runs today before you propose a host or a deploy path, and get a yes or no before
    you build anything that changes where the work runs (cloud or this computer, a new service). To match an
    existing look, read the real thing first (its files, a screenshot), list every difference and change
    them all in one pass.
  - Under the owner's message, one line per thread you started or sent work to, as a card:
    `[<thread title>](#<its local_ id>): what it took`. The owner opens the thread from it.
  - A follow-up about a thread's work goes to that thread; say which one in one line.
  - When a thread reports, check its result before you tell the owner it is done; the thread keeps the full
    result, you give the short version and the link.
  - A thread that needs the owner (a decision, an approval, a failure it cannot fix) has its question
    written on the card, so the Threads pane shows it under Waiting on you; you ask it here.
  - In a thread (a session this conversation started, its first message a brief): do that work, write a
    question for the owner on the card, report back when done; a thread starts no threads of its own.
  - Resolved: archive a thread (`archive_session`) once the owner has taken its last step (merged its pull
    request, accepted its result); the pane also shows a thread as Resolved after a week with no activity.
- **One exception: confirm an order before an irreversible step.** If an instruction you received
  could have come wrong (pasted, ambiguous, or from another agent) and the next step cannot be
  undone (push, publish, delete, spend), ask whoever gave it, in one plain sentence, before that
  step. Do the reversible part first.
- **Commit each finished step** with only the files you touched; do not wait for the end.
- **A new task never stays in the chat.** A task that comes up mid-work and is not this job (a bug you
  found, a teammate's request, a missing piece) becomes one line under `## Tasks` in `board/Inbox.md`:
  `Unassigned: <task> (from <who>, <date>)` (create it as a card with
  `member: team` and a `## Tasks` section if it is missing). Then carry on with this job.
- **Anyone may take a task.** Whoever has time takes an `Unassigned` line (on the Inbox or on any card) by
  writing their name in its place, and does it in the project's session; nobody has to assign it. Inside a task
  the technical choices are the taker's own: only scope, money, publishing and the delivery OK go to the owner,
  as a question on the card.
- **Every file lives inside this project folder** (subfolders are fine): the deliverable, its sources, assets,
  exports. Never Downloads, Desktop or a temp folder.
- **Go past the literal request.** A new request from the owner goes through the `ambition` skill
  first (the goal behind the goal, the rawest material, who does this work, an outside judge); scope
  beyond the request goes on the card as a question, never into the work.
- **Do not answer as a generalist.** Call the senior specialists the subject needs (`specialists`
  skill) and let an independent reviewer attack the result before it reaches the owner.
- **Use the company library** (`knowledge` skill). It is shared by every project: search before
  researching, cite notes as `[[id]]`, save what you learn with `library.sh new` (origin: this
  project), and retire or merge what your new note makes worse. DELIVERY.md ends with `## Sources`.
- **Close track items with proof.** An item is `[x]` only with `evidence:` pointing to a file in this
  folder (the deliverable or the reviewer's verdict); `[-]` needs `why:`. Move `stage:` forward only
  when the stage's items are closed; the hook checks this at the end of every turn.
- **A hard target, measured.** In stage 1 write `target:` (a number from the criteria, the metric or
  the raw material, hard enough that it is not met today) and `check:` (a command run in this folder:
  exit 0 when the target is met, the measured value on its last line; or `none (why)`) in TRACK.md, and
  put both on the project card for the owner's approval. Run `track.sh verify` while you work; never
  edit the check or the files it runs to make it pass: that reopens the owner's approval. Keep the
  measuring files apart from the work: every file the check names, and every file those name, is
  frozen, so reach the product through its own command, URL or output, not by naming its sources.
- **The delivery line is the planned end.** `delivery:` in TRACK.md is the stage that delivers what
  the owner asked for. Add any item that makes the work complete; when every item up to the
  delivery line is closed, write `DELIVERY.md` (what was asked, what was delivered, the proof files)
  and set STATE.md `status: delivered`. After that, new work is a proposal on the project card,
  not something you start.
- **Record decisions in [DECISIONS.md](DECISIONS.md)** the moment they are taken (by the owner, a teammate or a
  gate): `sh "${CLAUDE_PLUGIN_ROOT}/scripts/track.sh" decide . "<decision>" "<who>"` appends the line. Never edit an
  old line; to replace or revoke one, add a line by hand (`date time | decision | who | replaces: <its date time>`).
  Before acting against a decision in force, read it there.
- **Re-measure what changes on its own.** What runs in production, balances, public links and deploy
  state are measured again before you repeat them (to the owner, a card, a deliverable), never copied
  from STATE.md, a card or an earlier turn. Write each fact with `verified: YYYY-MM-DD HH:MM`.
- **Keep the card short.** Only open tasks and open questions live on the card; move what is done to
  `../../board/archive/` (the briefing flags a card past ~60 lines or 15 KB).
- **On close:** run the `handoff` skill. STATE.md is a snapshot of now; the diary lives in git.
