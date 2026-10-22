# Routing table

Who to call for what, so the owner never has to remember. A session reads this before picking the
next step. Each specialist works from a role card in `specialists/<role>.md`: its method, its
tools and when to use each, and what it never skips. Edit cards and rows freely: they are yours.

| when the next step is about | role card | reviewer attacks with |
|---|---|---|
| research, facts, market, competitors, "is this true?" | `researcher` | `reviewer` |
| product, users, UX, what to build and in what order | `product` | `reviewer` |
| code, architecture, tooling, build vs buy | `engineer` | `reviewer` + `security` when data or access is involved |
| money: price, cost, revenue, cash, tax exposure | `finance` | `reviewer` |
| law, contracts, IP, privacy, regulation | `legal` (AI prepares, a licensed human signs) | `reviewer` |
| marketing, positioning, channels, launch | `marketing` | `reviewer` |
| risk, security, privacy, operational failure | `security` | `reviewer` |
| opening a new project | `new-project` skill (from `central/`) | coherence check of the success criteria |
| something the owner sent to study (link, video, file) | `knowledge` skill | — |
| closing a session | `handoff` skill | the next session's arrival synthesis |
| a decision only the owner can make | a line on the project card, `status: waiting-owner` | — |

Rules (the hooks enforce the first three):
- Every subagent brief names its card (`Role card: <role>`) and carries the card's text; a search or
  file-reading helper says `Role card: utility`.
- A specialist's output ends with its never-skip checklist, each item done or not applicable (why).
- A deliverable, a cross-area decision or research ends only after a specialist and the reviewer.
- The person who does the work is never the person who judges it. The reviewer is the same model
  with a different brief: it catches incoherence, not authority.
- Need a role with no card? Write the card first, in the same format, then call it.
