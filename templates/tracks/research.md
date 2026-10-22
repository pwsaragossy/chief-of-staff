---
track: research
stage: 1
stale_hours: 48
---
# Track: research
For answering a question that a decision depends on. Pick it when the answer must be sourced, graded and triangulated, not just recalled.

## Stage 1: Question and decision
Gate: the question is answerable, the decision it unlocks is named, and the standard for a sufficient answer is set before searching.
- [ ] question | Research question stated so that evidence could prove it wrong, with scope, time window and geography | card: researcher | needs: - | evidence:
- [ ] decision | The decision this research unlocks, who decides, by when, and which answers would change it | card: product | needs: - | evidence:
- [ ] answer-standard | Standard for a sufficient answer: required evidence types, minimum number of independent sources, acceptable confidence | card: researcher | needs: question, decision | evidence:
- [ ] prior-work | Library and workspace searched for existing findings, with results listed or none found | card: researcher | needs: question | evidence:
- [ ] review-1 | Independent review of stage 1: verdict and fixes | card: reviewer | needs: question, decision, answer-standard, prior-work | evidence:
## Stage 2: Sources
Gate: sources are chosen to disagree with each other if the hypothesis is wrong, and each is graded.
- [ ] source-plan | Source plan covering at least 3 independent source types (for example primary data, official documents, expert or user interviews), with the reason for each | card: researcher | needs: answer-standard | evidence:
- [ ] search-log | Search log: queries, databases or sites, dates, counts of results, and what was excluded and why | card: researcher | needs: source-plan | evidence:
- [ ] source-grades | Each source graded for type, date, independence, method and conflict of interest, with the grade written next to it | card: researcher | needs: search-log | evidence:
- [ ] primary-data | At least 3 primary observations (interviews, measurements, documents read in full) with dates and sample size | card: researcher | needs: source-plan | evidence:
- [ ] review-2 | Independent review of stage 2: verdict and fixes | card: reviewer | needs: source-plan, search-log, source-grades, primary-data | evidence:
## Stage 3: Triangulation
Gate: each key claim is supported by independent sources, and contradictions are explained, not dropped.
- [ ] claim-table | Table of key claims with supporting and opposing evidence, source grade, and independence of sources for each | card: researcher | needs: source-grades, primary-data | evidence:
- [ ] contradictions | Contradictions between sources listed with the likely cause (method, date, sample, interest) and which side is weighted | card: researcher | needs: claim-table | evidence:
- [ ] gaps | Gaps and untested assumptions listed, with what each would cost to close | card: researcher | needs: claim-table | evidence:
- [ ] fact-check | Numbers, quotes and dates in the claim table re-checked against the original source, not a summary of it, by someone other than the author of the table | card: researcher | needs: claim-table | evidence:
- [ ] review-3 | Independent review of stage 3: verdict and fixes | card: reviewer | needs: claim-table, contradictions, gaps, fact-check | evidence:
## Stage 4: Synthesis
Gate: the answer, its confidence and what would change it are written for the decision owner, and the findings are saved.
- [ ] findings | Findings stated as the answer to the question, each marked fact or inference, with confidence level and the reason | card: researcher | needs: claim-table, contradictions, gaps | evidence:
- [ ] recommendation | Recommendation for the named decision, the alternative rejected, and what result would flip it | card: product | needs: findings, decision | evidence:
- [ ] limits | Limits section: what was not checked, sources not reached, risks of bias in the method | card: researcher | needs: findings | evidence:
- [ ] library-entry | Findings saved to the workspace library with sources, dates and confidence so they are found next time | card: researcher | needs: findings, limits | evidence:
- [ ] review-4 | Independent review of stage 4: verdict and fixes | card: reviewer | needs: findings, recommendation, limits, library-entry | evidence:
