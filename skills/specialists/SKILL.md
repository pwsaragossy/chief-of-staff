---
name: specialists
description: Answer through senior specialists who follow written role cards, then an independent reviewer, instead of as a generalist. Use whenever a deliverable, decision or research crosses an area of expertise (research, product, engineering, money, law, marketing, risk), or the user runs /chief-of-staff:specialists.
---

# Senior specialists with a method, and an independent reviewer

A specialist that only gives an opinion is a generalist with a title. Each one works from its role
card in the project's `specialists/` folder (else the plugin's templates): what to gather first, the method, the tools and when to
use each, the checks a senior professional never skips, the evidence standard and the output format.

1. **Pick** from the project's `ROUTING.md` (else the plugin's) the cards the subject needs, usually one or two plus the
   reviewer. If no card fits, write one in the same format first (`specialists/<role>.md`).
2. **Search the library first** (`knowledge` skill); the prompt hook already lists notes that may
   bear on the request. What it returns goes into every brief, so no specialist redoes research the
   project already has. Design work is the exception: a design-system piece, a screen or a video starts with fresh
   web research of the last months (below), which the library and memory never replace.
3. **Brief each specialist as a subagent.** The brief contains, in this order:
   - the line `Role card: <role>` or `Role card: <project>/specialists/<role>.md` (the role name is
     enough; a path may hold spaces; the hook blocks a brief without it) and "read your role card first and follow it". Do not paste the card: at 8-12 KB
     each, pasted cards crowd the task out of the brief, and the subagent reads the file itself;
   - the line `Owner said:` followed by every constraint, correction and fact the owner gave in this
     conversation, quoted word for word ("no CISBRA or CAMACOL in the video", "the letter comes from
     CISBRA, not from us", "only remove the sales part"), or `Owner said: nothing beyond the request`.
     Your summary is not enough: the owner's corrections that reached no brief came back as errors;
   - the line `Library: [[id]] [[id]] ...` with the notes found, or `Library: none found for <terms>`
     (the hook blocks a brief without it), the question, the files to read, and what to deliver;
   - the instruction "do only what this brief asks and check it with an outside judge (a command
     that runs, a source, the arithmetic). Before you build, list the decisions the work depends on;
     the ones that shape what the owner will see or use (what gets built, reuse or rebuild, its look
     and format, its scope, what a sample is) are questions for the owner, not choices for you: end
     with them under Open questions for the owner, with anything beyond the brief as options, and
     build nothing on them";
   - "research only what is missing; save each new finding with library.sh new and fill its
     Compared: line; cite every note you use as [[id]]; finish with the never-skip checklist of your
     card".
   Run independent specialists in parallel.
4. **Review.** A separate subagent with `Role card: <project>/specialists/reviewer.md` receives the
   paths of the specialists' role cards and their full outputs (or the files they wrote), not your
   summary, and the same `Owner said:` and `Library:` lines the specialists got (the hook blocks a reviewer brief
   without `Library:`; the reviewer checks each citation against those notes, and that no choice
   that shapes what the owner sees was made without the owner's words); it reads each card itself. It checks every never-skip item,
   attacks the premises, recomputes the numbers and returns a verdict.
   In hackathon pace (`pace: fast` in the project's `.chief-of-staff`, set by the owner) skip this
   step for internal work (plans, code, cards, research for the team); run it on what goes outside:
   the submission, the video, the README, messages to judges, partners or users.
5. **Merge**: fix what the reviewer proved; record what stays open in STATE.md section 7. Only then
   does anything go to the owner, through the card if it needs a decision.

## The design system, built with the owner piece by piece

Every project that shows the owner a screen or a video keeps a design system in `design/SYSTEM.md` (copy the
plugin's `templates/design/SYSTEM.md` at the start of the project). Its pieces: typography, colors, components and
motion (screens), and tone, rhythm and script (video). Nothing on a screen or in a video is built before the owner
picks the pieces it needs; the hooks block screen and video code until then (mockups under `design/` are free).

For each open piece, at the start of the project:
1. **Fresh web research first.** Brief the piece's specialist (`designer` for typography, colors, components and
   motion; `tone`, `rhythm`, `script` for the video pieces) to search the web for what the top of the market shipped
   in the last months (the project's window, `refs-max-months` in its settings, default 6). The library and memory
   never replace that search; a proposal written in a turn with no web search is void.
2. **2-3 concrete references.** The specialist writes `design/options/<piece>.md` from the plugin's
   `templates/design/options.md`: per option the exact link (the component's page on its gallery, the screen of a real
   app, the video at its timestamp), its date, who made it, what we take and what we leave. The specialist never
   picks between them.
3. **The reviewer opens every link** and writes `design/reviews/options/<YYYY-MM-DD HHMM> <piece>.md` (Options:,
   Verdict:, Links checked: with status and date per link). An old, weak or broken reference is rejected and
   replaced; the owner sees only options whose review passed (the turn-end hook stops an answer that shows links not
   yet cleared).
4. **The owner picks.** The coordinator shows the options as cards (what each looks or sounds like, the link, what we
   take), one piece per question, recommendation marked but never decided. With the owner's answer it writes
   `Status: chosen`, `Options:` and `Pick:` (the picked link) in the piece, then records the owner's OK:
   `sh "${CLAUDE_PLUGIN_ROOT}/scripts/track.sh" ok <project folder> design:<piece> <the owner's words>`, which the
   owner approves. A piece that does not apply is `Status: not applicable` with `Why:`, and needs the owner's OK too.
5. **Applied.** The specialist writes what follows from the pick under the piece's `### Applied` (exact values,
   tokens, rules). The OK froze the piece above that line and its proposal; changing them needs a new pick.

After that, screens and videos follow the design system without asking the owner again. When a new screen or video
needs something the system does not cover (a chart style, a new kind of video), add it as a new piece (`## <Piece>`,
`For:`, `Status: open`) and run the five steps for that piece only. Where things stand:
`sh "${CLAUDE_PLUGIN_ROOT}/scripts/screens.sh" system <project folder> screens|video`.

Limits: the reviewer is the same model with a different brief. Where the law or real money requires
a licensed human, the specialists prepare and a human signs. The hooks check that each reference has a link, a date
inside the window and a reviewer's line, not that the reviewer really opened it: the reviewer's card is what holds
that.
