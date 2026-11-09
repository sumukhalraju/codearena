# Delivery plan

The spec is the whole production system. The work lands in this order so there is always a playable slice and nobody builds the judge before two browsers can see the same round.

Four workstreams can move in parallel after milestone 0. They meet at the contracts in this repo.

| Stream | Owns |
| --- | --- |
| Client | `codearena-frontend` |
| Match | Backend modules matches, lobbies, queue, realtime, domain scoring |
| Judge | Worker, images, seccomp, setter reference runs |
| Accounts | Auth, profiles, leaderboard, deployment, backups |

Names are not assigned. The four project members pick streams in a five-minute conversation. One person can hold accounts plus deployment, because that stream is smaller until the VPS exists.

## Milestone 0 — repos and a walking skeleton

- Parent, frontend, and backend repositories exist and the submodules pin.
- Backend boots, connects to PostgreSQL and Redis from `deploy/docker-compose.data.yml`, and answers `/health/ready`.
- Frontend boots and shows `/login`.
- CI typechecks both.

Exit: a teammate can clone with `--recurse-submodules` and run the data plane.

## Milestone 1 — accounts

- Signup, login, refresh, logout, me.
- Dashboard shell with an empty history.
- Access token in memory, cookie refresh working across `localhost` ports.

Exit: two real accounts exist.

## Milestone 2 — bank

- Setter create and the pack import.
- The example pack loads in development.
- Publish rules enforced, including the reference run against the real Python image for the two code problems.

Exit: four published Python easy problems, one per round.

## Milestone 3 — lobby and choice rounds

- Create, join, countdown, rounds 2 and 3 playable with no Docker.
- Intermission shows the correct option.
- Socket snapshot and refresh-reload agree.
- Rounds 1 and 4 can be stubbed with an automatic 0 only behind a development flag that cannot be set in production. Prefer instead to wait for milestone 4 if the stub starts leaking into the UI. A stub is allowed only if the result screen says “code rounds not judged” and the build refuses to start when `NODE_ENV=production`.

Exit: two browsers finish a match of choice rounds and see scores. This is the first panel-safe demo if time is short, and it is not the production system.

## Milestone 4 — judge

- Rounds 1 and 4 use the sandbox.
- Sample run does not change score.
- The sandbox tests in `13-testing.md` pass for Python.
- C, C++, and JavaScript images pass the nightly fixture.

Exit: the example pack can be played for real in a lobby, end to end.

## Milestone 5 — rating, result, rematch, history

- Finalize transaction, Elo tests, result page, rematch lobby, profile, leaderboard.
- Lobby remains unrated. The UI says so.

Exit: the product loop in the flowchart is true for friends.

## Milestone 6 — Quick Match

- Queue, matcher, difficulty caps, pair cap, problem avoidance.
- Disconnect and forfeit rules, including the early void.
- Reconnect within 30 seconds restores the snapshot.

Exit: two accounts on two machines find each other and a rating moves.

## Milestone 7 — production deploy

- VPS, TLS, backups, one restore drill, bootstrap admin, `COOKIE_SECURE`, images pinned by digest, firewall.
- Email verification flag turned on only after a real SMTP send is observed.
- `LOG_SUBMISSION_SOURCE` confirmed false.
- Playwright suite run against the deployed environment’s lobby flow once.

Exit: the team can hand the guide a URL.

## After the production exit, still not this semester’s build unless the guide asks

Leagues, seasons, tournaments, streaks, achievements, practice mode, recommendations, mobile, CLI, gVisor, a friend graph, chat, and a second rating per language.

## Panel demo script, once milestone 5 is in

1. Sign up on the projector.
2. Create a Python Easy lobby and show the code.
3. Join from a second laptop.
4. Play all four rounds badly on one side and correctly on the other.
5. Show the result saying Unrated, then the dashboard.
6. Show the leaderboard only if milestone 6 has landed. Do not pretend a lobby moved the rating.

## Semester risk

The judge is the risky stream. Start the Python image in milestone 2, not milestone 4, so a Dockerfile problem surfaces while choice rounds are still being built. The milestone numbers say when it is player-facing. They do not say when the first container is allowed to run.
