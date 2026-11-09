# Decisions and ambiguities

The deck is clear about the product shape and silent about most of the engineering. Every item below is something a teammate could reasonably have built differently. Resolved items are the rules. Do not reopen one inside a feature pull request. Reopen it with a pull request that edits this file and the contracts together.

Open items need the team or the guide before someone spends money or sends invites. They do not block writing the client and the server.

## Resolved from the deck

### The match is four short rounds, not one long problem

The methodology slide can be read as “both players write a full solution to one problem.” The flowchart on the architecture slide is more specific and wins: four rounds, two of them edited code, two of them chosen answers. A blank-editor “classic duel” mode is not in this build.

### Rounds 2 and 3 are multiple choice

The flowchart says “Choose Answer” for Predict Output and Find Logical Error, and “Edit Code” for the other two rounds. Choice rounds have exactly four options. Free-text prediction is rejected because the slide says choose, and because free text creates unfair grading (spaces, case, `6` versus `6.0`).

### Languages are C, C++, Python, and JavaScript

The flowchart lists those four. Java is not a v1 language. JavaScript means a Node.js stdin/stdout program, not browser DOM code. Problems must say that in the prompt.

### Battle entry is Quick Match, Create Lobby, or Join Lobby

The flowchart lists those three and then language and difficulty. “Topic” appears in the methodology slide and does not appear in the flowchart. Players do not pick a topic. Setters may still describe a topic inside `promptMd`. There is no topic column and no topic filter.

### The client is replaceable

The objectives call the system headless and API-first, with REST for request/response work and WebSockets for live events. Mutations go through REST so they can be retried safely. The socket is how the server pushes state. This split is what lets a future terminal client play without scraping the website.

## Resolved because the deck was silent

These are assumptions. They are binding until this file changes.

| Topic | Decision | Why |
| --- | --- | --- |
| Stack | TypeScript on both sides. Next.js on the web. NestJS for the API and the worker. PostgreSQL 16. Redis 7. Prisma. BullMQ. pnpm. Node 22. | One language for a four-person CSE team. NestJS module boundaries match the backend manual. PostgreSQL is the source of truth for rating, which must not live only in a cache. |
| One rating number | Every player has a single Elo rating, starting at 1200, floor 100. | The result screen says “rating changes,” singular. Separate ratings per language are a later product. |
| Quick Match rated, lobby unrated | No switch on the lobby. | A rated private room is an invitation to farm a friend. |
| Same-pair cap | The 4th rated match between the same two accounts inside 24 hours is forced unrated. | Same reason, for people who avoid lobbies and queue together. |
| Difficulty caps | Rating ≥ 1600 cannot queue rated Easy. Rating ≥ 2000 cannot queue rated Easy or Medium. | Otherwise the Easy queue is a farm. Numbers are in `constants.json`. |
| No Ready button | Countdown starts when the opponent is present. | The flowchart’s “Both Players Ready (Countdown)” is a state, not a second confirmation step. |
| Timers | Syntax 90s, predict 40s, logic 50s, fix 180s. Same on every difficulty. | The deck has no times. Keeping timers constant makes the rating mean one thing. Difficulty changes which problems are drawn, not the clock. |
| Intermission | 5 seconds between rounds. The correct choice and the explanation are shown then. Opponent code is not. | Both players are already done for that round, so revealing the choice cannot be abused. Five seconds is long enough to read one sentence. |
| Sample run versus submit | Run executes sample tests only, is rate-limited, and does not affect score or the wrong-attempt count. Submit is the graded action. | The methodology slide says players may test. Charging a test as a penalty would punish the behavior we want. |
| Clock does not pause on disconnect | 15 seconds without a heartbeat marks the player disconnected. They then have 30 seconds to reconnect. The round timer keeps moving. | Pausing lets a player stall when they are losing. The future-work slide’s “robust recovery” means surviving deploys and in-flight jobs, which the judge reconciler covers. It does not mean a paused clock. |
| Early void | If both players have zero submissions and the match is still inside the first 15 seconds of round 1, a forfeit voids the match and does not touch rating. | A misclick or a crashed tab in the first moments should not move a rating. |
| Forfeit after that | The remaining player wins if the forfeiting player’s total is lower or the totals are equal. If the forfeiting player is strictly ahead, the match still completes on the clock with the absent player scoring 0 on later rounds, and the normal comparison decides the winner. | An absent player who is already behind should not be able to freeze a loss. An absent player who is ahead should not automatically lose a match they were winning if the other player never catches up. |
| Opponent code | Hidden until `status = final`. Then both players can read each other’s best round-1 and round-4 submission. | Learning from the opponent is the point of the result screen. Seeing it during the round is copying. |
| Hidden tests | The API may say “failed hidden test 2 of 5.” It never returns that test’s input or expected output. | Returning the input turns the hidden suite into a public suite after one submission. |
| Same option order | Options are not shuffled differently per player. The stored order is the shown order. | Both players must see the same problem. A per-player shuffle makes disputes unreadable. |
| Rematch | Opens an unrated lobby. It does not requeue a rated match. | Matches the “play again → dashboard” arrow for ranked play, and still provides the rematch button from the methodology slide. |
| Email verification | Off unless `REQUIRE_EMAIL_VERIFICATION=true`. Password reset exists in both modes. | A panel demo on a college network should not depend on an inbox. Production turns the flag on. |
| College SSO | Not in v1. Email and password only. | The deck says signup and login. It does not name Google or a VTU identity provider. |
| Same campus NAT | Same public IP does not force a match unrated. | The whole class shares an address. The pair cap handles farming better than an IP check. |
| Problem source | Original problems only. | Importing public judge problems creates a copyright and an academic-integrity problem. |
| Reuse of containers | Never. One submission, one container, then delete. Images may be pre-pulled. | A reused container is a channel between two students’ programs. |
| Where grade time is measured | At HTTP receive, not at container exit. | Otherwise a slow worker lowers the player’s score. |
| Rounding | Scores and Elo use half-away-from-zero. The function is specified in the match engine. JavaScript `Math.round` is not used, because it is asymmetric on negative Elo deltas. | Two implementations must move rating by the same integer. |
| Modular monolith | One backend repo, two processes: `api` and `worker`. Not four microservices. | Four students cannot operate a distributed system. The process split is only the one that isolation requires: the judge must be able to die without taking login down, and it must not share a network namespace with the API. |
| Nested repos | This repo holds the contracts. `frontend` and `backend` are Git submodules. | That is the requested shape: one main repository with two repositories inside it. |
| Private GitHub | All three repositories are private. | The team can grant access. The problem bank and any future secret are not world-readable by default. |
| Deployment target | One Ubuntu VPS running Docker Compose, with Caddy for TLS. Kubernetes is a scale path, not the setup this team runs. | A production design that the team will not operate is fiction. The scale path is still written down in the infrastructure doc. |

## Open

These do not have a safe default that we should pretend is a product decision.

| Topic | What is blocked | What is not blocked |
| --- | --- | --- |
| Teammate GitHub logins | Inviting Srujan, Sujan, and Tejas | Building from a local clone |
| Domain name and who pays for the VPS | Pointing DNS and opening a bill | Writing the app and running the data-plane compose file locally |
| Which SMTP provider | Sending real reset mail in production | `MAIL_MODE=log`, which prints the link on the API |
| Whether the panel demo must ship before Quick Match exists | Nothing technical. The delivery plan already puts a lobby demo earlier than the public queue. | — |
| License | Adding a `LICENSE` file | Private development. There is no license until the team picks one. MIT is the recommendation if the work later becomes public. |

## Explicitly rejected readings

- “Headless” does not mean there is no website. It means the website does not own the rules. The deck still requires a web client.
- “Execution progress” on the objectives slide is the opponent panel: solving, submitted, correct, wrong, and tests passed out of tests total. It is not a live stream of the opponent’s keystrokes.
- Slides 7 and 8 heading “Department of ISE, 2021–2022” is not the project identity.
- A microservice per concern (auth service, rating service, problem service, gateway) is rejected for v1. Module boundaries inside one API process are required so a split stays possible later.
- Socket.IO is rejected. The wire protocol is a small JSON text protocol over a normal WebSocket, documented in `07-realtime.md`, so a non-JavaScript client can speak it.
- GraphQL is rejected. The contract is the OpenAPI file plus the WebSocket document.
