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
   project already has.
3. **Brief each specialist as a subagent.** On Grok that tool is `spawn_subagent`. The brief lines are the same. A read-only helper is `Role card: utility`. The brief contains, in this order:
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

Limits: the reviewer is the same model with a different brief. Where the law or real money requires
a licensed human, the specialists prepare and a human signs.
