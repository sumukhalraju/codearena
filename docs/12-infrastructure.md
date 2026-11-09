# Infrastructure

The production target a four-person team can run is one Linux VPS. The scale-out path is described after it. Do not start on Kubernetes.

## VPS

- Ubuntu 24.04, 4 vCPU, 8 GB RAM, 80 GB disk.
- Docker Engine and the Docker Compose plugin.
- Caddy on 80 and 443, with a real DNS name.
- `ufw` allow 22, 80, 443. Default deny incoming.
- Unattended security upgrades enabled.
- A non-root deploy user in the `docker` group. SSH keys only. Password login off.
- Disk encryption, or a provider volume that is encrypted. Write down which one in the team’s private runbook. Do not commit the runbook if it contains the host name plus an admin email together with a secret. The host name itself is fine in the Caddyfile.

Two DNS names:

- `app.example.com` → the `web` container
- `api.example.com` → the `api` container

WebSocket traffic uses `api.example.com` with the same TLS certificate. `WS_ORIGIN` is `wss://api.example.com`.

Replace `example.com` when a domain exists. Until then, deploy does not happen and local development uses the compose data plane plus `next dev` and the API on localhost.

## Processes on the box

| Container | Published | Notes |
| --- | --- | --- |
| `caddy` | 80, 443 | Routes by host |
| `web` | internal 3000 | Next standalone |
| `api` | internal 4000 | HTTP and WebSocket |
| `worker` | internal 4001 | Health only, not in Caddy |
| `postgres` | not published to the host | Volume `pgdata` |
| `redis` | not published | Append-only file on |
| `migrate` | one-shot | Exits before `api` starts |

The worker mounts `/var/run/docker.sock`. No other container does. Language containers are siblings on the host daemon, not children inside the worker’s pid namespace. They still get the flags in the judge doc. `--network none` on those siblings is what keeps them off the database.

Memory budget, rough, so nobody is surprised: PostgreSQL 1 GB, Redis 256 MB, API 512 MB, web 512 MB, worker 512 MB, and the rest for up to two compile-and-run containers at 256 MB each. If the box starts swapping, lower worker concurrency from 2 to 1 before buying a bigger machine.

## Reference data plane

`deploy/docker-compose.data.yml` starts PostgreSQL, Redis, and MinIO for local development. MinIO is reserved for a later export of match transcripts. v1 stores source in PostgreSQL, which is inside the 64 KiB cap, so the application does not need MinIO to be correct. The service is there so a future export has a place to land without a redesign of the compose file. The app must boot if MinIO is empty.

Production compose is written when the Dockerfiles exist, in the backend and frontend repos, and copied into a private deploy checklist. It is not invented as a second source of ports here. Ports above are the ones it must use.

## Environment

`deploy/env.example` lists every variable. Production values live in a file on the VPS, mode `0600`, owned by the deploy user, not in Git.

`COOKIE_SECURE=true` in production. `NODE_ENV=production`. `REQUIRE_EMAIL_VERIFICATION` starts `false` for the first plays and becomes `true` when SMTP works.

Bootstrap: run `pnpm admin:bootstrap` once inside the API image with the bootstrap variables set, verify login, then remove those three variables and restart.

## Backups

- Nightly `pg_dump -Fc` of the CodeArena database to a directory outside the Docker volume, then copy off the VPS. Keep 7 daily dumps.
- Redis is not backed up as data. Queue loss is specified as `queue.reset`.
- A restore drill is part of calling the deploy production: load a dump into a scratch database and run `SELECT count(*) FROM users` and `SELECT count(*) FROM matches`. Do this once before the panel demo if the demo is on the VPS, and write the date in the team notes.

## Deploys

1. Build images from a git SHA. Tag them with the SHA, not only `latest`.
2. Run migrations as the one-shot.
3. Start the worker, then the API, then the web.
4. Hit `/health/ready` on the API.
5. Keep the previous images so a rollback is `compose up` with the previous tag.

Do not edit code on the VPS. The VPS runs images built by GitHub Actions.

## CI shape

Each child repo, once it has code:

- On pull request: install, typecheck, unit test, and for the backend the integration suite.
- On main: build the image and push it to GitHub Container Registry under the team’s private packages.

The parent repo:

- Rejects pull requests that change `docs/04-match-engine.md` numbers without changing `contracts/constants.json`.
- A human reviewer checks that, because a bot is not required to understand the formula. The constants file is short on purpose.

GitHub Actions examples are not committed yet, because there is no package to install and a red workflow on an empty repo helps nobody. Add the workflow in the first pull request that adds `package.json`.

## Observability

- JSON logs to stdout. Docker’s journal keeps them. That is the log stack for v1.
- A request id on every HTTP response and every log line from that request.
- Worker logs a line for every verdict: submission id, verdict, duration, language. Not the source.
- Once a week, someone looks at `internal_error` count. If it is not zero, the sandbox is broken and players are being refunded attempts, which is the correct failure mode and still a bug.
- Uptime: an external check on `https://api.example.com/health/live` every five minutes is enough. The college project does not need PagerDuty. It does need the team to notice before a demo.

Prometheus is the upgrade when more than one machine exists. Do not block production on it. Do keep logs structured so a later collector can read them.

## Scale path

When one worker cannot drain the judge queue (jobs waiting more than 10 seconds before start, measured from `received_at` to the running timestamp):

1. Move PostgreSQL to a managed instance and Redis to a managed instance.
2. Add a second worker on a second VM that exists only to run containers. It has no Caddy and no inbound ports other than SSH.
3. Split the database role as described in the architecture doc.
4. Only then consider gVisor.

Horizontal API replicas can happen earlier, on the same box they are usually a waste. Do it when CPU on the API process, not the judge, is the bottleneck.

## Local development

Documented as commands in `docs/17-local-dev.md`.
