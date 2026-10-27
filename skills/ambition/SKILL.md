---
name: ambition
description: Turn a request into the version a top professional would deliver, through numbered versions that something outside the model judges. Central runs it on every new request from the owner before new-project or before handing work to a project; every specialist runs it on its own draft. Also when the owner runs /chief-of-staff:ambition or asks to "go further" or "be more ambitious".
---

# Ambition loop with an outside judge

Doing what was asked and stopping is the lazy default. This loop takes the request to what the best
professional in the field would deliver, and lets the world, not the model, judge each step.
Based on Felix Rieseberg, "How to be more ambitious" (altitude, depth, range, an outside judge).

## Rules
1. **Source first.** Read what the request cites (article, link, document, code) before writing.
   State current facts (platform rules, laws where it ships, prices, program requirements) only with
   a source and its date.
2. **Never judge your own work.** Name the outside judge before v1, in this order of preference:
   a command that runs (the project's `check:`), a rule or law with its source, the arithmetic
   (unit economics, cost), real numbers (money in, refunds, users). A fresh-context reviewer is the
   last resort, because it is the same model. The judge measures the **goal behind the goal**
   (Altitude), not only that the work runs: "the page renders" is a test; "a first-time visitor
   signs up in under a minute on a phone" is the judge when the goal is sign-ups.
3. **Numbered versions**, at most 4, each applying one lens and ending with the judge's verdict:
   - **Altitude**: what is the goal behind the goal?
   - **Depth**: what is the rawest material (the data, the code, the primary source) and the tool a
     senior would use on it (a database, a model, a spreadsheet, a benchmark), not prose?
   - **Range**: which specialists DO this work (turn the noun into a verb)? Brief them.
   - **Against yourself**: where does this version break? Say it plainly.
   Every verdict carries its evidence: the command and what it printed, or the file that shows it.
   Stop when the verdict stops improving. A v1 that passes is written as it happened, `v1 passed:
   <what the judge printed>`, never padded with invented failed versions; then check the judge
   measures the goal behind the goal and not something the first draft already met, and raise it
   if it does not. The weakest point you name becomes the next version, unless fixing it grows the
   scope (then it is a question for the owner).
   With a deadline, ship the first working version before the next round; there is no "too small
   to apply" exception: the cheapest loop is one honest judge that measures the goal.
4. **A hard target, with cut gates.** Treat the ambitious target as reasonable, and set a ladder of
   milestones, each with what to do if it fails. The target only comes down with data. The owner's
   own number is theirs: never raise or lower it yourself; offer the ambitious one as an option.
5. **Honest over headline.** Refuse any part that needs a false promise (guaranteed income, a
   "secret", an illegal clause); say why in one or two lines with the source, and deliver the honest
   version that keeps the strength of the hook.
6. **The owner appears only at gates**: sending in their name, signing, accounts, identity checks,
   money, legal decisions. Each gate arrives ready to approve in a minute, through the card. Anything
   that grows the scope beyond the request is one of those questions, never work done.
7. **Execute.** Once a version is viable, produce the assets (the prompt, the plan, the copy, the
   code) instead of handing tasks back to the owner.

## Output
- First line: the conclusion, including "this does not work as asked".
- One line per version: lens, what changed, the outside judge's verdict and its evidence (the command
  output or the file); a v1 that passed is `v1 passed: <what the judge printed>`.
- The final request, plan or prompt in a code block.
- The weakest point still left.
- Sources, with dates.

## Where it runs
- **Central, on a new request**: the final request feeds new-project (STATE.md section 2), and the
  judge becomes the proposal for the project's `target:` and `check:` (the owner approves them). For
  an existing project, the final request and its judge go in the card, as the session's next task.
- **Specialists**: the brief carries `Ambition: <goal behind the goal> | judge: <outside judge>`
  (the hooks block a specialist brief without it and a specialist output without `## Versions`).
  The hooks check that the lines exist; the reviewer checks that each verdict came from the judge.
  The one who briefs sets the judge, not the one who does the work: a worker left to pick its own
  judge picks one its first draft already passes.
