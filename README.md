# CodeArena

CodeArena is a headless, real-time, one-on-one competitive coding platform. Two players get the same four-round battle, play under a server-owned clock, and leave with a winner and a rating change.

It is the coding counterpart of a Matiks duel: short rounds, a shared opponent, a visible rating, and a path back to the dashboard to play again. It is not a long-form online judge. The round order is fixed by the Phase-1 flowchart:

1. Find the syntax error, by editing code.
2. Predict the output, by choosing an answer.
3. Find the logical error, by choosing an answer.
4. Fix the code, by editing code.

Languages are C, C++, Python, and JavaScript. Difficulties are Easy, Medium, and Hard. A player enters through Quick Match, Create Lobby, or Join Lobby.

This repository is the production blueprint. It does not contain the application. The web client and the API are separate Git repositories nested here as submodules.

| Path | Repository | What it is |
| --- | --- | --- |
| this repo | `codearena` | Product rules, architecture, HTTP and WebSocket contracts, database, deployment |
| `frontend/` | `codearena-frontend` | Build manual for the Next.js client |
| `backend/` | `codearena-backend` | Build manual for the API, match authority, and judge worker |

Nothing in `frontend/` or `backend/` is allowed to invent a rule that contradicts this repository. If a rule needs to change, change it here first and then implement it.

## Read this first

1. [docs/00-start-here.md](docs/00-start-here.md)
2. [docs/01-product.md](docs/01-product.md)
3. [docs/02-decisions.md](docs/02-decisions.md)
4. [docs/04-match-engine.md](docs/04-match-engine.md)
5. The build manual for the repo you are implementing: [docs/09-frontend.md](docs/09-frontend.md) or [docs/10-backend.md](docs/10-backend.md)

The full reading order is in [docs/00-start-here.md](docs/00-start-here.md).

## What “production” means here

A production build of CodeArena has all of the following. A demo may land them in the order in [docs/14-delivery.md](docs/14-delivery.md), but the finished system is not missing any of them.

- The server is the only authority for the clock, scores, verdicts, and rating.
- The web app is one client. A later phone or terminal client can play the same match through the same HTTP and WebSocket contracts.
- Untrusted code runs in a single-use container with no network, a read-only root filesystem, a dropped capability set, and a hard timeout.
- Match rows, scores, and rating changes commit in PostgreSQL. Redis holds the queue, presence, and fan-out, and can be rebuilt.
- Quick Match is rated. A private lobby is unrated.
- Login uses an email and a password. Access tokens stay in memory. Refresh tokens are rotated `HttpOnly` cookies.
- The API is stateless and can run as more than one process. The judge is a separate process.
- TLS, structured logs, backups, and a restore drill exist before the service is called production.

## Clone

Teammates need access to all three private repositories. Access to this parent repo does not grant access to the nested ones.

```powershell
git clone --recurse-submodules https://github.com/sumukhalraju/codearena.git
cd codearena
```

If the clone was made without submodules:

```powershell
git submodule update --init --recursive
```

Day to day, the parent pins a commit of each child. After a child repository moves forward:

```powershell
git submodule update --remote frontend
git add frontend
git commit -m "Pin frontend to the latest contract implementation"
```

Work that changes a product rule happens on a branch of this repo. Work that implements the client happens on a branch of `codearena-frontend`. Work that implements the server happens on a branch of `codearena-backend`.

## Layout

```text
codearena/
  docs/                     prose specification
  contracts/
    constants.json          numeric rules (wins if prose disagrees on a number)
    schema.sql              PostgreSQL shape
    openapi.yaml            HTTP shape
    problem-pack.example.json
  deploy/                   reference data-plane and environment template
  scripts/                  team admin helpers
  frontend/                 submodule → codearena-frontend
  backend/                  submodule → codearena-backend
  DOC-20261027-WA0002.pptx  original Phase-1 deck
```

## Normative order

When two files disagree, use this order:

1. `contracts/constants.json` for every duration, cap, penalty, and rating number.
2. `contracts/schema.sql` for stored columns and constraints.
3. `contracts/openapi.yaml` for HTTP paths and JSON field names.
4. `docs/07-realtime.md` for WebSocket event names and payloads.
5. `docs/04-match-engine.md` for scoring, winner, forfeit, and void rules.
6. Other docs for everything else.

A pull request that changes a rule updates every artifact that states that rule. Reviewers reject a partial update.

## Team

Phase-1, V Semester, Department of CSE, RNS Institute of Technology, 2026–2027.

- Srujan BM (1RN24CS261)
- Sujan Sagar G (1RN24CS263)
- Sumukha L Raju (1RN24CS266)
- Tejas K Gowda (1RN24CS275)
- Internal guide: Ms. Vinutha A Patil

Invite a GitHub account to all three repositories:

```powershell
./scripts/invite-collaborator.ps1 -Username their-github-login
```

## What is intentionally not here

There is no Next.js app, no NestJS app, no Dockerfile for the API, and no judge implementation. Those are the work this blueprint is for. The only runnable file is `deploy/docker-compose.data.yml`, which starts PostgreSQL, Redis, and MinIO so implementation can begin against the real data services.
