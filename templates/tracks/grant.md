---
track: grant
stage: 1
delivery: 4
stale_hours: 48
deputy:
owner_wait_minutes:
deadline:
target:
check:
public_urls:
prod_ref:
---
# Track: grant
For an application judged on paper: a grant, a fund round, an accelerator, a public call, a bounty with a written
submission. Pick it when what goes out is a form the reviewers read. The submission package is a deliverable from
stage 1: it starts as every field of the real form and grows at each stage, so it is never assembled the day before.

## Stage 1: Program, form and package skeleton
Gate: the program's rules, the real form, the review criteria and the deadline are written down, the ask fits the program, and the package holds every field of the real form.
- [ ] blind-spots | Opening checklist from the specialists of every area the project crosses, the owner did not name included: what a senior in each area checks at the start that the owner did not mention, each with why it matters here, the cost of skipping it and the stage it lands in; accepted items are on this map, declined ones are in DECISIONS.md | card: reviewer | needs: - | evidence:
- [ ] rules | Program rules read in full from the program's own pages, each with its link and the date read: who may apply, what is funded and what is not, amounts and caps, payment schedule, IP and licence terms, reporting duties, disqualifiers; for a resubmission, the earlier application and the feedback it got | card: researcher | needs: - | evidence:
- [ ] form | The real application form pulled now, from the live form or the program's own template (link and date): every field in order, with its limit (characters, words, files, links), required or optional, and what the program says it wants there | card: researcher | needs: rules | evidence:
- [ ] criteria | Review criteria with their weights, each mapped to the field of the form that answers it | card: product | needs: rules, form | evidence:
- [ ] deadline | Deadline written as `deadline: YYYY-MM-DD HH:MM` in this file's front matter, in local time or with its offset, and a backward timeline to it with at least 2 days of buffer (default, adjust to the case) | card: product | needs: rules | evidence:
- [ ] ask | The ask in one paragraph: what is asked for, how much, for what result, and why this program, scored against the criteria and the rules' caps | card: finance | needs: rules, criteria | owner: ok | evidence:
- [ ] account | The applicant's account on the program's portal opened now, and every registration or paper it asks of the applicant (company or tax registration, identity checks, team documents), each with how long its approval takes | card: legal | needs: rules | evidence:
- [ ] package-1 | Submission package v1: one file with every field of the form in its order, each with its limit, a first answer, and the open question or missing proof that blocks a full answer | card: product | needs: form, criteria, ask | evidence:
- [ ] review-1 | Independent review of stage 1: verdict and fixes | card: reviewer | needs: blind-spots, rules, form, criteria, deadline, ask, account, package-1 | evidence:

## Stage 2: Proof and full answers
Gate: every claim in the package has its proof, the budget adds up, and every field holds a full answer inside its limit.
- [ ] evidence | Every claim in the package (traction, users, team, prior work, partners, the technology) with its proof: a link, a metric with its source and date, a repository, a letter; a claim without proof is cut or rewritten | card: researcher | needs: package-1 | evidence:
- [ ] budget | Budget and milestones: each line tied to a deliverable and a date, totals equal to the ask, inside the program's caps and payment schedule | card: finance | needs: ask, rules | evidence:
- [ ] technical | The technical description at the depth the reviewers expect: what exists today, what the grant builds, how, and the risks | card: engineer | needs: package-1 | evidence:
- [ ] package-2 | Submission package v2: package v1 with every field answered in full, inside its limit, every claim linked to its proof, budget and milestones in | card: product | needs: package-1, evidence, budget, technical | evidence:
- [ ] review-2 | Independent review of stage 2: verdict and fixes | card: reviewer | needs: evidence, budget, technical, package-2 | evidence:

## Stage 3: Outside read and attachments
Gate: someone who did not write it can explain the project from the package alone, the program's own checks pass, and every attachment is ready.
- [ ] outside-read | Someone who did not write the package reads it alone and explains back in two minutes what is built, for whom, with what money and by when; every place they got wrong is fixed in the package | card: reviewer | needs: package-2 | evidence:
- [ ] prescreen | The package walked field by field against the program's eligibility rules and disqualifiers, and against each review criterion | card: legal | needs: package-2, rules, criteria | evidence:
- [ ] attachments | Every attachment the form asks for (deck, video, documents, links) in the format and size the form requires, each link opened from a logged-out browser | card: designer | needs: package-2 | evidence:
- [ ] package-3 | Submission package v3, the final one: v2 with the fixes of the outside read and the prescreen, ready to paste field by field | card: product | needs: outside-read, prescreen, attachments | evidence:
- [ ] review-3 | Independent review of stage 3: verdict and fixes | card: reviewer | needs: outside-read, prescreen, attachments, package-3 | evidence:

## Stage 4: Submission
Gate: the submission is sent before the deadline, confirmed, and the program's next dates are on the board.
- [ ] review-4 | Independent review before sending: the live form pulled again and compared with the form of stage 1 (a field that changed is fixed in the package), the live form filled from package v3 (saved as a draft where the form allows), each field compared with the package, every link opened from a logged-out browser, verdict and fixes | card: reviewer | needs: package-3, review-3 | evidence:
- [ ] submit | Submission sent at least 1 day before the deadline (default, adjust to the case) from package v3, and the confirmation saved | card: product | needs: review-4 | owner: ok | evidence:
- [ ] after | The program's next dates (answers, interviews, reports, payments) on the project's card, each with what it needs | card: product | needs: submit | evidence:
