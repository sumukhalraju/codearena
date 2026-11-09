# Testing

The production bar is a small set of tests that lock the rules, plus one browser flow that plays a real lobby match. A large snapshot suite that breaks on copy changes is not the goal.

## Domain unit tests (backend, required before any match is called done)

In `packages/domain`, with no database:

- The worked score table in `04-match-engine.md`, every cell.
- `t = 0` yields 100. `t = T` yields 30. A correct code round with enough penalties yields 1, not 0 or a negative.
- Half-away-from-zero: `0.5 → 1`, `-0.5 → -1`, `76.666 → 77`, `53.333 → 53`.
- Elo worked example: 1200 vs 1200, win, K = 40, deltas `+20` and `-20`.
- Elo floor: a player at 100 who loses stays at 100, and the winner still gains their unclipped delta.
- K selection follows the match engine order. Fewer than 10 rated matches uses 40, including a player whose rating is already 2000. Once `rated_matches` is at least 10, a rating of 2000 or more uses 10, and everyone else uses 20. The match that takes the player from 9 to 10 rated matches still used 40. The next one does not.
- Output compare: trailing newline does not matter, trailing spaces do not matter, leading spaces do, `6` is not `6.0`, CRLF equals LF.
- A choice grade does not call the penalty function.

## Integration tests (backend, Testcontainers)

PostgreSQL and Redis, real migrations, no Docker language containers yet. The sandbox port is a fake that returns a scripted verdict.

- Signup, login, refresh rotation, reuse of a revoked refresh token revokes the family.
- Two users create a lobby, the second join produces a match in `countdown`, both projections of round 1 contain the same starter code, and neither projection contains `correctOptionId` or a hidden input.
- A choice submit with the right id writes the score from the formula and the wrong id writes 0. A second choice submit returns `409`.
- A scripted `accepted` on a code round after one scripted `wrong_answer` produces the penalty.
- A scripted `internal_error` does not reduce `submissionsRemaining`.
- Double delivery of the same judge result does not double the score.
- Finalize writes two `rating_events` and moves `users.rating` for a rated match, and writes neither for a lobby match.
- Non-participant `GET /matches/{id}` is 404.
- Idempotency: same key and same body replays the response. Same key and different body is 409.

## Sandbox tests (backend, on a runner that has Docker)

These are slower. Run them on main and nightly, and on pull requests that touch `sandbox/` or `apps/worker/src/judge`.

- A Python program that prints stdin passes a fixture and returns `accepted`.
- A Python program that sleeps 30 seconds against a 1 second limit returns `time_limit` and the container is gone afterward (`docker ps` does not show `ca-`).
- A fork bomb hits `pids-limit` or the wall clock and does not survive the test process. The assertion is “the worker function returned and no `ca-` container remains,” not “the host feels fine.”
- A program that opens a TCP socket fails to connect and the verdict is `runtime_error` or a passed test if the program handles the error and still prints the right answer. The assertion that matters: the container’s network mode is `none`. Inspect the container config in a test that starts a short `sleep` and runs `docker inspect`.
- Compile error returns stderr to the owner DTO and an empty stderr field on the opponent progress event.
- Seccomp fixture: read stdin, write stdout, `accepted`.

## Contract tests

When both children exist as code, Schemathesis or an equivalent run against a locally booted API using `contracts/openapi.yaml`. Any 500 or any response that violates the schema fails CI. This starts in the milestone that declares the API complete, not on day one.

## Frontend tests

Vitest:

- Clock helper, including a server time ahead of the client and behind it.
- Reducer: applying `match.snapshot` replaces state. Applying `submission.result` for a different match id does not.

Playwright, two browser contexts, against a real local API and a fake or real judge:

1. Sign up two users.
2. User A creates a Python easy lobby.
3. User B joins with the code.
4. Both see the countdown and then the same round title.
5. On a choice round, A clicks the correct option and B clicks a wrong one. The intermission shows both scores and the explanation.
6. The test can skip code execution by using a problem pack of four problems where rounds 1 and 4 are included and the fake judge is scripted, if the suite is the one without Docker. The suite that runs in the release pipeline uses the real Python image for round 4 with the sample pack’s fix problem. One of the two users submits a correct sum and the other submits `print(0)`.
7. The result page shows a winner and, for this lobby, the word Unrated.

Also cover: refresh on `/match/{id}` during round 4 stays on round 4. A third user opening the match URL sees not found.

## What not to automate yet

- Load tests as a gate. A k6 script that queues 20 users is useful later and is not a merge requirement.
- Visual pixel diffs.
- Testing C, C++, and JavaScript images on every pull request. Python runs every time the sandbox job runs. The other three run nightly so a broken `g++` image is caught within a day.

## Definition of done for a rule change

A change to scoring, pairing, forfeit, or the snapshot fields updates the parent contracts and docs, updates the domain or integration test that names the old behavior, and only then changes the app. A pull request that changes the formula without changing the worked example is incomplete.
