# Local development

Run this from the parent clone after `git submodule update --init`.

## Data plane

Docker Desktop on Windows, or Docker Engine on Linux.

```powershell
docker compose -f deploy/docker-compose.data.yml up -d
```

That starts:

| Service | Address |
| --- | --- |
| PostgreSQL 16 | `localhost:5432`, database `codearena`, user `codearena`, password `codearena` |
| Redis 7 | `localhost:6379`, no password |
| MinIO | `localhost:9000`, console `localhost:9001`, user `minio`, password `minio12345` |

These passwords are for a laptop only. The production VPS does not use this file.

Stop with:

```powershell
docker compose -f deploy/docker-compose.data.yml down
```

Add `-v` only when you mean to delete the local database.

## Applications

When the child repositories contain code, each has its own README with `pnpm install` and `pnpm dev`. The intended ports are fixed so the env files match:

- Web: `http://localhost:3000`
- API and WebSocket: `http://localhost:4000` and `ws://localhost:4000`
- Worker health, not for browsers: `http://localhost:4001`

Copy `deploy/env.example` to `backend/.env` and set `COOKIE_SECURE=false`. Copy `frontend/.env.example` to `frontend/.env.local`.

Create the first user with the bootstrap script, or with signup once that route exists. Signup is the normal path. Bootstrap is how production gets its first admin.

## Windows notes

The team’s machines are Windows. Services still run in Linux containers. Do not run the judge on the Windows host outside Docker. Path mounts in the worker must use the form Docker Desktop accepts. The worker should put submission directories under a folder that is already shared with Docker, and the backend README should name that folder when the code exists. A common choice is a directory inside the backend workspace, which Docker Desktop already shares.

Line endings: this repo uses `.gitattributes` with `* text=auto`. Do not commit a change that rewrites every file because Git autocrlf differed. If a pull request shows the entire file as changed, fix Git and reopen the branch.

## Daily loop

1. Pull the parent and run `git submodule update --init`.
2. If you work on the client, branch inside `frontend/` and push to `codearena-frontend`.
3. If you work on the server, branch inside `backend/` and push to `codearena-backend`.
4. If you change a rule, branch on the parent first, get it reviewed, then implement.

A rule change and its implementation are two pull requests. The implementation names the parent commit it follows.
