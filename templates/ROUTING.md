# Routing table

Who to call for what, so the owner never has to remember. A session reads this before picking the
next step. Edit it freely: it is yours, not the plugin's.

| when the next step is about | call | reviewer (attacks the result) |
|---|---|---|
| opening a new project | `new-project` skill (from `central/`) | coherence check of the success criteria |
| research, facts, "is this true?" | researcher (primary sources, marks FACT / INFERENCE) | second researcher looking for counter-evidence |
| product, UX, interface | product designer | usability reviewer |
| code, architecture, tooling | senior engineer | security reviewer |
| money: price, cost, revenue, tax | finance specialist | skeptical CFO |
| law, contracts, compliance | legal specialist (AI prepares, a licensed human signs) | second legal reviewer |
| marketing, content, positioning | marketing strategist | target-customer critic |
| risk, security, privacy | risk and security specialist | red team |
| something the owner sent to study (link, video, file) | `knowledge` skill | — |
| closing a session | `handoff` skill | the next session's arrival synthesis |
| a decision only the owner can make | a line on the project card, `status: waiting-owner` | — |

Rules:
- The person who does the work is never the person who judges it.
- The reviewer is the same model with a different brief. It catches incoherence, not authority;
  it does not replace a human expert where the law or real money requires one.
- Keep the active core small. Add a row only after a real case needed it.
