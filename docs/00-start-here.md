# Start here

CodeArena is specified, not implemented. If you are about to scaffold a framework, read the two build manuals and follow them. Do not pick a different stack, a fifth round, or a different scoring formula in a feature branch.

## Who should read what

| You are building | Read in this order |
| --- | --- |
| Either half, on day one | This file, `01-product.md`, `02-decisions.md` |
| The match itself | `04-match-engine.md`, `07-realtime.md`, `contracts/constants.json` |
| The judge | `05-judge-and-sandbox.md`, `11-security.md` |
| HTTP handlers | `06-http-api.md`, `contracts/openapi.yaml`, `08-data-model.md` |
| The website | `09-frontend.md`, then `06` and `07` |
| The server | `10-backend.md`, then `04`, `05`, `06`, `07`, `08` |
| Deploying it | `12-infrastructure.md`, `deploy/env.example` |
| Planning the semester | `14-delivery.md` |
| Proving it works | `13-testing.md` |

## Rules that are easy to “simplify” and must not be simplified

- Both players receive the same problems, the same option order, and the same starter code.
- The browser does not score the opponent and does not decide a verdict.
- A sample run never changes the score and never counts as a wrong attempt.
- Hidden test input and expected output never enter the sandbox and never appear in an API response.
- Round 2 and round 3 are four-option questions. They are not free-text and they are not code edits.
- Quick Match changes rating. A lobby never changes rating.
- Opponent source code and the opponent’s chosen option are not sent until the match is `final`.
- One container runs one submission and is then destroyed.

## Repository boundaries

```text
parent codearena          rules and contracts
frontend submodule         React screens, Monaco, socket client, no rules
backend submodule          HTTP, WebSocket, match transaction, judge, rating write
```

Shared TypeScript types are generated from `contracts/openapi.yaml` into each child repo when that child is scaffolded. They are committed in the child and must match the parent file. The parent script `scripts/check-contracts.ps1` is the check to add in CI once both children vendor a copy. Until then, a reviewer diffs them by hand.

## Academic source

The product flow is the flowchart on slide 9 of `DOC-20261027-WA0002.pptx`. The abstract, objectives, and methodology slides supply the non-functional requirements: API-first, REST plus WebSockets, isolated execution, hidden tests, rating, history, and fair winner rules. Slides 7 and 8 still carry an old header (“VIII Semester, Department of ISE, 2021–2022”). That header is a template leftover. The title slide is the identity that counts: V Semester, CSE, RNSIT, 2026–2027.
