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
| design: brand identity, logo, interface, deck | `designer` | `reviewer` |
| risk, security, privacy, operational failure | `security` | `reviewer` |
| opening a new project | `new-project` skill (from `central/`), which copies a track to TRACK.md | coherence check of the success criteria |
| the next deliverable of a project | the role card named on its line in TRACK.md | the stage's `review-<n>` item |
| how everything is going | `panel` skill (green, yellow, red per project) | — |
| something the owner sent to study (link, video, file); anything learned worth keeping | `knowledge` skill | — |
| move the library to a disk, cloud folder or private repo | `knowledge` skill, from central, after the owner agrees | — |
| closing a session | `handoff` skill | the next session's arrival synthesis |
| a decision only the owner can make | a line on the project card, `status: waiting-owner` | — |

Rules (the hooks enforce the first three):
- Every subagent brief names its card by path (`Role card: <workspace>/specialists/<role>.md`, read by
  the subagent itself, never pasted), a `Library:` line and an `Ambition: <goal behind the goal> |
  judge: <outside judge>` line; a search or file-reading helper says `Role card: utility`.
- A specialist's output ends with `## Versions` (ambition skill), each verdict with its evidence (the
  command output or the file; `v1 passed: <what the judge printed>` is a complete line), and its
  never-skip checklist, each item done or not applicable (why).
- A deliverable, a cross-area decision or research ends only after a specialist and the reviewer.
- The person who does the work is never the person who judges it. The reviewer is the same model
  with a different brief: it catches incoherence, not authority.
- Need a role with no card? Write the card first, in the same format, then call it.
