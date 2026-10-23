---
name: specialists
description: Answer through senior specialists who follow written role cards, then an independent reviewer, instead of as a generalist. Use whenever a deliverable, decision or research crosses an area of expertise (research, product, engineering, money, law, marketing, risk), or the user runs /chief-of-staff:specialists.
---

# Senior specialists with a method, and an independent reviewer

A specialist that only gives an opinion is a generalist with a title. Each one works from its role
card in the workspace `specialists/` folder: what to gather first, the method, the tools and when to
use each, the checks a senior professional never skips, the evidence standard and the output format.

1. **Pick** from the workspace `ROUTING.md` the cards the subject needs, usually one or two plus the
   reviewer. If no card fits, write one in the same format first (`specialists/<role>.md`).
2. **Search the library first** (`knowledge` skill); the prompt hook already lists notes that may
   bear on the request. What it returns goes into every brief, so no specialist redoes research the
   workspace already has.
3. **Brief each specialist as a subagent.** The brief contains, in this order:
   - the line `Role card: <role>` and the full text of that card (the hook blocks a brief without it);
   - the line `Library: [[id]] [[id]] ...` with the notes found, or `Library: none found for <terms>`
     (the hook blocks a brief without it), the question, the files to read, and what to deliver;
   - the line `Ambition: <the goal behind the goal> | judge: <outside judge>` (ambition skill; the
     hook blocks a brief without it), with the instruction "run the ambition lenses on your own draft,
     at most 4 versions, and end with ## Versions: one line per version, the lens and the judge's
     verdict; anything beyond the request goes under Open questions for the owner, not into the work";
   - "research only what is missing; save each new finding with library.sh new and fill its
     Compared: line; cite every note you use as [[id]]; finish with the never-skip checklist of your
     card".
   Run independent specialists in parallel.
4. **Review.** A separate subagent with `Role card: reviewer` (and that card's text) receives the
   specialists' role cards and their full outputs, not your summary. It checks every never-skip item,
   attacks the premises, recomputes the numbers and returns a verdict.
5. **Merge**: fix what the reviewer proved; record what stays open in STATE.md section 7. Only then
   does anything go to the owner, through the card if it needs a decision.

Limits: the reviewer is the same model with a different brief. Where the law or real money requires
a licensed human, the specialists prepare and a human signs.
