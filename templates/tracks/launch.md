---
track: launch
stage: 1
delivery: 4
stale_hours: 48
deputy:
target:
check:
public_urls:
prod_ref:
---
# Track: launch
For taking an offer, product or feature to market. Pick it when there is something to release publicly and the result must be measured.

## Stage 1: Goal and positioning
Gate: the goal is a number with a date, the first segment is chosen, and the economics can support the plan.
- [ ] goal | Launch goal as a number with a date and the funnel it implies (reach, click, lead, trial, paid) | card: marketing | needs: - | evidence:
- [ ] segment | One first segment with trigger event, pain, buying role and explicit exclusions, with at least 3 primary sources | card: researcher | needs: - | evidence:
- [ ] positioning | Positioning statement naming the real alternative, including doing nothing | card: marketing | needs: goal, segment | evidence:
- [ ] unit-economics | Price, gross margin, allowed acquisition cost and payback period, with a low case and a base case | card: finance | needs: goal | evidence:
- [ ] jurisdictions | Countries of seller and target buyers listed, with the advertising, endorsement, privacy and consent rules that apply to each | card: legal | needs: segment | evidence:
- [ ] review-1 | Independent review of stage 1: verdict and fixes | card: reviewer | needs: goal, segment, positioning, unit-economics, jurisdictions | evidence:
## Stage 2: Channels and measurement
Gate: one or two channels are chosen with budget caps and stop rules, and tracking is defined before spend.
- [ ] messaging | Messaging hierarchy: one core promise, 3 supporting claims each with proof or flagged no proof yet, objection answers | card: marketing | needs: positioning | evidence:
- [ ] channels | Channel ranking with fit, cost, learning speed and volume ceiling; at most 2 chosen for the first test | card: marketing | needs: messaging, unit-economics | evidence:
- [ ] funnel-math | Funnel math at low, base and high conversion rates with required traffic and acquisition cost against the allowed cost | card: finance | needs: channels, unit-economics | evidence:
- [ ] test-plan | Test plan per channel with budget cap, duration, minimum sample, success threshold and stop rule written before launch | card: marketing | needs: channels, funnel-math | evidence:
- [ ] tracking | Tracking spec: events, UTM convention, consent handling, and the single place where each number is read | card: engineer | needs: test-plan | evidence:
- [ ] review-2 | Independent review of stage 2: verdict and fixes | card: reviewer | needs: messaging, channels, funnel-math, test-plan, tracking | evidence:
## Stage 3: Assets and claims
Gate: every public claim is proven or removed, and assets work on the channels chosen.
- [ ] landing | Landing page with one primary action, mobile layout, accessible contrast and labels, and a working tracking event | card: designer | needs: messaging, tracking | evidence:
- [ ] channel-assets | Assets in the exact formats each chosen channel requires (copy, images, video, email), with message matching the landing page | card: marketing | needs: messaging, channels | evidence:
- [ ] claims-check | Every claim, price, testimonial and comparison checked against proof and the rules in the listed jurisdictions; unproven claims removed | card: legal | needs: channel-assets, landing, jurisdictions | evidence:
- [ ] privacy-consent | Privacy notice, consent for tracking and email, unsubscribe path, and data handling checked for the listed jurisdictions | card: legal | needs: tracking, landing | evidence:
- [ ] load-check | Landing page and sign-up or purchase flow tested end to end, including the payment or lead path and a load or rate check | card: engineer | needs: landing, tracking | evidence:
- [ ] review-3 | Independent review of stage 3: verdict and fixes | card: reviewer | needs: landing, channel-assets, claims-check, privacy-consent, load-check | evidence:
## Stage 4: Launch and measure
Gate: the launch ran to plan, results are read against the pre-set thresholds, and the next decision is written.
- [ ] runbook | Launch runbook: timeline, owners, go and no-go criteria, rollback or pause steps, support coverage during the first 48 hours | card: marketing | needs: test-plan, load-check | evidence:
- [ ] go-no-go | Go or no-go check against the runbook criteria with every blocking item closed | card: product | needs: runbook, claims-check, privacy-consent | evidence:
- [ ] launch-log | Launch log: what went live, when and where, with links and timestamps, and every deviation from the runbook | card: marketing | needs: go-no-go | evidence:
- [ ] dashboard | Single report of the funnel numbers against the goal, updated from the tracking spec | card: engineer | needs: tracking | evidence:
- [ ] readout | Results readout against the pre-set thresholds and minimum sample: scale, change or cut, with the range when the sample is small | card: marketing | needs: launch-log, dashboard | evidence:
- [ ] review-4 | Independent review of stage 4: verdict and fixes | card: reviewer | needs: runbook, go-no-go, launch-log, dashboard, readout | evidence:
