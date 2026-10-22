---
track: software
stage: 1
delivery: 4
stale_hours: 48
---
# Track: software
For building a product or a significant feature that real users will run. Pick it when the work has users, data or money at stake and will be released and maintained.

## Stage 1: Problem and requirements
Gate: the problem is evidenced, scope in and out is written, and success has a number, a date and a kill criterion.
- [ ] problem | Problem statement for a named user in behavioral terms, with at least one behavioral evidence item and the current alternative with its cost | card: product | needs: - | evidence:
- [ ] user-evidence | At least 5 primary-source observations or interviews about past behavior, with dates and counts | card: researcher | needs: - | evidence:
- [ ] requirements | Requirements with acceptance criteria, scope in and scope out, one-page spec | card: product | needs: problem, user-evidence | evidence:
- [ ] success-metric | Success metric with baseline, target, date and kill criterion | card: product | needs: problem | evidence:
- [ ] data-classes | Data the product will handle classified (personal, financial, health, none) with the jurisdictions of users and provider | card: legal | needs: requirements | evidence:
- [ ] review-1 | Independent review of stage 1: verdict and fixes | card: reviewer | needs: problem, user-evidence, requirements, success-metric, data-classes | evidence:
## Stage 2: Design and architecture
Gate: flows, states, architecture and threats are documented before code that depends on them is written.
- [ ] flows | Core user flow diagram with entry, primary action, success, error and exit paths | card: designer | needs: requirements | evidence:
- [ ] ui-spec | Screens with empty, loading, error and first-use states, using existing components, with measured contrast ratios against WCAG 2.2 AA | card: designer | needs: flows | evidence:
- [ ] architecture | Architecture note: components, data model, external services, build-versus-buy choices, the main risk and how it is tested early | card: engineer | needs: requirements | evidence:
- [ ] threat-model | Threat model of assets, entry points, trust boundaries and abuse cases, with a mitigation or accepted risk for each | card: security | needs: architecture, data-classes | evidence:
- [ ] estimate | Effort estimate by the people who will build it, with the riskiest piece spiked first | card: engineer | needs: architecture | evidence:
- [ ] review-2 | Independent review of stage 2: verdict and fixes | card: reviewer | needs: flows, ui-spec, architecture, threat-model, estimate | evidence:
## Stage 3: Build and verify
Gate: acceptance criteria pass in tests, security and accessibility checks are done, and legal terms match what the product does.
- [ ] test-plan | Test plan mapping every acceptance criterion to a test, including failure paths and one end-to-end test of the main flow | card: engineer | needs: requirements, architecture | evidence:
- [ ] implementation | Implementation passing the test plan in CI, with test output saved as evidence | card: engineer | needs: test-plan, ui-spec | evidence:
- [ ] security-checks | Dependency vulnerability scan, secrets scan, authentication and authorization checks on every entry point from the threat model | card: security | needs: implementation, threat-model | evidence:
- [ ] a11y-audit | Accessibility audit of the built screens against WCAG 2.2 AA: keyboard path, focus, contrast, target size, labels | card: designer | needs: implementation | evidence:
- [ ] terms-privacy | Terms of service and privacy notice that match the data actually collected, checked for the jurisdictions in data-classes | card: legal | needs: data-classes, implementation | evidence:
- [ ] review-3 | Independent review of stage 3: verdict and fixes | card: reviewer | needs: test-plan, implementation, security-checks, a11y-audit, terms-privacy | evidence:
## Stage 4: Release and operate
Gate: release is reversible, monitored, and the first measurement of the success metric is scheduled.
- [ ] release-plan | Release plan with environments, migration steps, staged rollout, and a rollback tested at least once | card: engineer | needs: implementation | evidence:
- [ ] monitoring | Error tracking, uptime check and one alert per critical flow, with a named person receiving it | card: engineer | needs: release-plan | evidence:
- [ ] backup-restore | Backup of user data with a restore performed once and timed | card: engineer | needs: release-plan | evidence:
- [ ] released | Production release done per the plan, with version, time and the result of a smoke test of the main flow | card: engineer | needs: release-plan, monitoring, backup-restore | evidence:
- [ ] release-notes | Release notes and user-facing announcement with no claim the product cannot prove | card: marketing | needs: released | evidence:
- [ ] metric-readout | Date set to read the success metric against baseline and kill criterion, with the query or report that produces it | card: product | needs: success-metric, monitoring | evidence:
- [ ] review-4 | Independent review of stage 4: verdict and fixes | card: reviewer | needs: release-plan, monitoring, backup-restore, released, release-notes, metric-readout | evidence:
