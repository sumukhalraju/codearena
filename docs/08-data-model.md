# Data model

`contracts/schema.sql` is the schema. This page is how to use it, and which facts are not in PostgreSQL.

## PostgreSQL

| Table | Holds |
| --- | --- |
| `users` | Identity, role, password hash, current rating, win/loss/draw counters |
| `refresh_tokens` | Hashed refresh tokens and rotation families |
| `password_reset_tokens`, `email_verification_tokens` | Hashed one-time tokens |
| `problems` | The editable bank, including `correct_option_id` and `reference_passed_at` |
| `test_cases` | Sample and hidden tests for code problems |
| `matches`, `match_players` | One battle and the two seats |
| `match_rounds` | Frozen `snapshot` plus the round clock |
| `round_scores` | The official per-round score once it exists |
| `submissions`, `submission_tests` | Every sample run and graded attempt |
| `rating_events` | One row per user per rated final match. The audit of Elo. |
| `lobbies`, `lobby_players` | Private rooms |
| `seen_problems` | Recency for the “don’t repeat the last 20” rule |
| `pair_history` | The 24 hour rated-pair cap |
| `idempotency_keys` | Stored responses for safe retries |
| `audit_log` | Role changes and problem publish/unpublish |

Counters on `users` (`wins`, `losses`, `draws`, `rated_matches`, `rating`) are updated only inside the finalize transaction. They are a cache of `rating_events` plus match outcomes. A repair script must be able to recompute rating by replaying `rating_events` from 1200. Do not update `users.rating` anywhere else, including an admin form. There is no “set rating” endpoint in v1.

`match_rounds.snapshot` is jsonb. Its shape is fixed in `04-match-engine.md`. The application validates it with Zod before insert. The database does not parse it.

## Redis keys

| Key | Type | TTL | Value |
| --- | --- | --- | --- |
| `queue:{language}:{difficulty}` | ZSET | none | member userId, score = rating at enqueue time |
| `queue:meta:{userId}` | HASH | 2 hours | `enqueuedAt`, `language`, `difficulty` |
| `presence:{userId}` | STRING | 15 seconds | socket count |
| `wsticket:{ticket}` | STRING | 30 seconds | userId |
| `user:{userId}` | pub/sub channel | n/a | JSON event |
| `lock:matcher` | STRING | 5 seconds | worker id, refreshed by the tick |
| `ratelimit:{bucket}:{id}` | STRING or sorted set | window size | sliding window counter |

BullMQ owns its own key prefix `bull:`. Do not put hidden tests in any of these keys.

Queue removal deletes both the ZSET member and the hash. A hash without a ZSET member is dirt, and the matcher ignores it.

## Who may write what

| Data | Writer |
| --- | --- |
| `users` password and profile | Auth module |
| `users.rating` and counters | Finalize transaction only |
| `problems`, `test_cases` | Setter module |
| `matches` and children | Match module, called by the matcher, the lobby service, and the worker |
| `submissions` insert | Submission controller |
| `submissions` verdict columns | Worker |
| Redis queue | Queue module |
| Containers | Worker |

Prisma repositories sit inside those modules. A controller does not import `PrismaClient` directly. This is what keeps the “rating has one writer” rule enforceable in review.

## Indexes already in the schema

They cover the leaderboard, the problem picker, “submissions still queued,” history by user, and the pair-cap lookup. Do not add an index for a query that does not exist. Do add the index in `schema.sql` in the same pull request as a new query that would otherwise scan.

## Retention

- `idempotency_keys` older than 24 hours may be deleted by a daily job.
- `refresh_tokens` expired and revoked older than 30 days may be deleted.
- Matches, submissions, and rating events are kept. They are the academic record of the system working. A later privacy request would delete a user by replacing `email`, `username`, and `display_name` with tombstones and setting `password_hash` to a random hash, and would keep the match rows so the opponent’s history still resolves. That tombstone job is specified here and is not required for the first production deploy. Do not `ON DELETE CASCADE` a user out of `match_players`.

## Seed

The first admin is inserted by a one-shot script `pnpm admin:bootstrap` when `users` has zero rows. It reads `BOOTSTRAP_ADMIN_EMAIL`, `BOOTSTRAP_ADMIN_USERNAME`, and `BOOTSTRAP_ADMIN_PASSWORD` from the environment, creates role `admin`, and exits. If any user exists, it exits without writing. The production runbook says to unset those variables after it succeeds.

Problem packs are imported through the setter API, not by the bootstrap script. The example pack is documentation. It is a legal import body, and it is fine to load it in development.
