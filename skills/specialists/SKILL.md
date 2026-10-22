---
name: specialists
description: Answer through senior specialists and an independent reviewer instead of as a generalist. Use whenever a decision or deliverable crosses an area of expertise (research, product, engineering, money, law, marketing, risk), or the user runs /chief-of-staff:specialists.
---

# Senior specialists and an independent reviewer

A generalist agreeing with a generalist owner produces "more or less" answers. Delegate.

1. **Pick** from the workspace `ROUTING.md` the specialists the subject needs. If none fits, define
   one: title, seniority, what they would check first. Keep it to the few the question needs.
2. **Brief each specialist as a subagent**, with the full mission: the question, the files to read,
   what to deliver, and the format below. Run independent specialists in parallel.
3. **Format every specialist writes** (saved to a file in the project, not only in chat):
   - one-line answer first;
   - each claim marked **[FACT]** (with its source: link, file, command output) or **[INFERENCE]**;
   - what would change the conclusion;
   - what they did not check.
4. **Independent review**: a separate subagent, who did not do the work, attacks it. Its brief is to
   attack the premises, not just the structure: wrong assumptions, contradictions between
   specialists, missing costs, what the owner would have to do by hand. Give it the specialists'
   files, not your summary.
5. **Merge**: fix what the reviewer proved; record what stays open in STATE.md section 7. Only then
   does anything go to the owner, through the card if it needs a decision.

Limits: the reviewer is the same model with a different brief. Where the law or real money requires
a licensed human, the specialists prepare and a human signs.
