# Backend build

The repository is `codearena-backend`. It is the authority for accounts, matches, judging, and rating. Two processes boot from it: `api` and `worker`.

## Stack

- Node.js 22, pnpm 9, TypeScript with the same strict flags as the frontend
- NestJS 10
- Prisma, PostgreSQL 16
- Redis 7 and BullMQ
- `argon2` for passwords
- `zod` at the HTTP boundary even though Nest pipes exist. One schema per body, shared with the domain tests where the shape is internal.
- `dockerode` for the sandbox. The daemon socket is mounted into the worker only.
- Vitest for domain tests. Supertest plus Testcontainers for HTTP tests.

Do not add a second web framework. Do not call the judge from a Nest interceptor that runs inside the request.

## Workspace layout to create

```text
apps/api/src/main.ts
apps/api/src/app.module.ts
apps/api/src/modules/auth/
apps/api/src/modules/users/
apps/api/src/modules/problems/
apps/api/src/modules/queue/
apps/api/src/modules/lobbies/
apps/api/src/modules/matches/
apps/api/src/modules/submissions/
apps/api/src/modules/realtime/
apps/api/src/modules/leaderboard/
apps/api/src/modules/health/
apps/worker/src/main.ts
apps/worker/src/matcher/
apps/worker/src/timers/
apps/worker/src/judge/
apps/worker/src/reconciler/
packages/domain/src/score.ts
packages/domain/src/elo.ts
packages/domain/src/compare-output.ts
packages/domain/src/round.ts
packages/db/prisma/schema.prisma
packages/db/prisma/migrations/
sandbox/seccomp.json
sandbox/images/c.Dockerfile
sandbox/images/cpp.Dockerfile
sandbox/images/python.Dockerfile
sandbox/images/javascript.Dockerfile
sandbox/run.sh
contracts/                 vendored parent contracts
```

`packages/domain` imports nothing from Nest, Prisma, or `dockerode`. It is pure functions. The worked example in `04-match-engine.md` is a test in this package. If that test fails, the server is wrong, not the test.

## Module duties

| Module | May write | Must not |
| --- | --- | --- |
| `auth` | users (credentials), refresh and reset tokens | touch rating or matches |
| `users` | `display_name` | change rating, role (admin module does roles) |
| `problems` | problems, test cases, reference runs | start a match |
| `queue` | Redis queue keys | pair users. Pairing is the worker. |
| `lobbies` | lobbies, and it calls `matches.createFromLobby` | compute scores |
| `matches` | matches, rounds, scores, rating finalize | open a Docker socket |
| `submissions` | insert submission rows, enqueue BullMQ | compare output in the request |
| `realtime` | tickets, socket fan-out | contain match rules. It asks `matches` for a projection. |
| `leaderboard` | nothing | cache a rating that can disagree with `users.rating` for more than the request |
| `health` | nothing | require auth |

An admin role change lives in `apps/api/src/modules/auth/admin.controller.ts` or a tiny `admin` module. It is the only writer of `users.role`, and it writes `audit_log`.

## Process boot

`api` listens on `PORT` (4000 in development). It runs the HTTP server and the WebSocket server on that port. It does not start the matcher and it does not consume `judge` jobs.

`worker` does not bind a public port. It exposes `GET /health/live` and `GET /health/ready` on `WORKER_PORT` (4001), bound to the Docker network only, not published on the host firewall. Ready means Redis is up, PostgreSQL is up, and the four language images are present locally.

Migrations are a third command, `pnpm db:migrate`, run as a one-shot container before `api` rolls. `api` refuses to start if the Prisma migration table is behind the code, and it does not apply migrations itself.

## Matcher tick

Every `matchmaking.tickMs` (1000):

1. Acquire `lock:matcher`. If not acquired, return.
2. For each language and difficulty, read the ZSET.
3. Consider players in ascending wait time. For each, the allowed rating delta comes from the window whose `afterMs` is the greatest value still `<= waitedMs`. A null delta means any opponent in that ZSET.
4. Pair the two eligible players with the smallest absolute rating difference. A player is ineligible if their presence key is missing, they are in a live match, or they are the same user.
5. Call `matches.createFromQueue(a, b)` which applies the transaction in the match-engine doc.
6. Release the lock.

Do not pair inside the HTTP request that joins the queue. The request only inserts the Redis entries and returns.

## Timers

Use BullMQ delayed jobs, not `setTimeout`, so a restart does not forget a round end.

| Job | Runs |
| --- | --- |
| `countdown-end` | Opens round 1 |
| `round-close` | The close function in the match engine |
| `intermission-end` | Opens the next round |
| `disconnect-forfeit` | The forfeit rules |
| `lobby-expire` | Marks the lobby expired if it is still `open` |

Each job id is deterministic: `round-close:{matchId}:{roundIndex}`. Adding the job twice does not create two closes.

## Judge consumer

The pseudocode that must be recognizable in `apps/worker/src/judge/run-job.ts`:

```text
load submission and snapshot
if submission already judged: return
mark running
write source to an empty directory
if compile command exists: run container compile
if compile failed: write compile_error and return
for each test that should run:
  run container
  compare outside
write verdict in a transaction that locks the match
publish user events
delete the source directory
```

The Docker flags are copied from `05-judge-and-sandbox.md`. A reviewer should be able to diff the code against that list.

## Projection

`MatchesService.project(matchId, viewerUserId)` returns the snapshot in `07-realtime.md`. HTTP `GET /matches/{id}` and the socket `match.snapshot` both call it. One function, one test that asserts hidden fields are absent while the round is active, present in the intermission only for the fields the realtime doc allows, and present on the result only after `final`.

## Config

Environment variables, all required in production, validated with Zod at boot. A missing variable crashes the process. There is no silent default for a secret.

See `deploy/env.example` in the parent repo for the list. The backend `.env.example` mirrors it.

`COOKIE_SECURE`, `WEB_ORIGIN`, `DATABASE_URL`, `REDIS_URL`, and `JWT_ACCESS_SECRET` are the ones people forget. `JWT_ACCESS_SECRET` is at least 32 bytes of randomness. Access JWTs carry `sub`, `username`, and `role`, and they expire in `auth.accessTtlSec`. They are signed HS256. They do not carry the rating. Rating is read from the database when a decision depends on it, so a token issued before a match cannot keep a stale rating alive inside a cap check.

## Logging

JSON lines to stdout. Fields: `time`, `level`, `msg`, `requestId`, `userId` when known, `matchId` when known, `submissionId` when known. Do not log passwords, refresh tokens, tickets, source code, or hidden inputs. Pino is a fine implementation. The format is the requirement, the library is not sacred.

## Errors

Throw a domain error type `{ code, httpStatus, message }` and map it once in an exception filter to the error JSON in the HTTP doc. Do not hand-build that JSON in controllers.

## Seed and fixtures

`pnpm admin:bootstrap` as described in the data model. `pnpm problems:import -- packages/db/fixtures/demo-pack.json` is a thin client of the same function the setter HTTP route calls, for local development, and it refuses to run when `NODE_ENV=production`.

## Review checklist for a backend pull request

- Domain tests for score and Elo still include the worked example.
- No new Docker flag, and no missing Docker flag, relative to the judge doc.
- `users.rating` is assigned in one function.
- Player DTOs are built by the projection, not by returning a Prisma row.
- A new route was added to the parent `openapi.yaml` in the same change set (parent PR first, or the same day, pinned together).
