# HTTP API

Base path `/api/v1`. JSON only. Field names are camelCase. Timestamps are ISO-8601 UTC. The machine-readable copy is `contracts/openapi.yaml`. This document explains the behavior the YAML cannot.

## Conventions

### Auth header

Protected routes require `Authorization: Bearer {accessToken}`. The access token lives in browser memory. It is not a cookie. Cookie authentication is used only by `POST /auth/refresh` and `POST /auth/logout`.

### Errors

Every error body:

```json
{
  "error": {
    "code": "ROUND_CLOSED",
    "message": "This round is no longer accepting answers.",
    "details": {},
    "requestId": "uuid"
  }
}
```

`requestId` is also the `X-Request-Id` response header. The client sends `X-Request-Id` if it has one; otherwise the API generates it.

| HTTP | When |
| --- | --- |
| 400 | Malformed JSON |
| 401 | Missing or expired access token, bad login |
| 403 | Authenticated but wrong role, or not a player in this match |
| 404 | No such route or no such id that this caller may know about |
| 409 | State conflict: quota, idempotency, lobby full, already in a match |
| 422 | Well-formed JSON that fails validation |
| 429 | Rate limit. `Retry-After` is set in seconds. |
| 503 | Dependency down. Readiness is failing. |

Unknown ids that the caller must not be able to probe return 404, not 403. A match id that exists but belongs to two other people returns 404 for a third party while the match is in progress, and 404 after it as well, except for the public profile’s recent-match summaries which contain no source.

### Idempotency

`POST /matches/{id}/submissions` requires `Idempotency-Key`, a UUID the client created. See the architecture doc.

### Pagination

History and leaderboard use `?cursor=` opaque strings and `?limit=`. Default limit is 20, maximum 100. The response is `{ "items": [], "nextCursor": null }`.

## Auth

### `POST /auth/signup`

No auth. Body:

```json
{
  "email": "student@example.com",
  "username": "tejas_k",
  "displayName": "Tejas",
  "password": "a long passphrase"
}
```

Password length at least 10. It is hashed with argon2id, memory 19456 KiB, iterations 2, parallelism 1. The plaintext is never logged. Email is stored with `citext`. Username is lowercased.

Success `201` returns the same body as login: access token, expiry, and the public user, and sets the refresh cookie.

Errors: `409 AUTH_EMAIL_TAKEN`, `409 AUTH_USERNAME_TAKEN`, `422 AUTH_WEAK_PASSWORD`, `429 RATE_LIMITED`.

### `POST /auth/login`

```json
{ "email": "student@example.com", "password": "..." }
```

Success `200`:

```json
{
  "accessToken": "jwt",
  "expiresIn": 900,
  "user": {
    "id": "uuid",
    "username": "tejas_k",
    "displayName": "Tejas",
    "role": "player",
    "rating": 1200,
    "ratedMatches": 0,
    "wins": 0,
    "losses": 0,
    "draws": 0
  }
}
```

The refresh token is `Set-Cookie: ca_refresh=...; HttpOnly; Secure; SameSite=Lax; Path=/api/v1/auth; Max-Age=2592000`. `Secure` is omitted when `COOKIE_SECURE=false`, which is allowed only when `NODE_ENV` is not `production`.

Failure is always `401 AUTH_INVALID`, for unknown email and for a wrong password, after a fixed minimum delay of 200 ms so the two cases are harder to time. Do not reveal which field was wrong.

If `REQUIRE_EMAIL_VERIFICATION=true` and `email_verified_at` is null, respond `403 AUTH_UNVERIFIED`.

### `POST /auth/refresh`

Cookie only. Rotates the refresh token. The old row is revoked and `replaced_by` points at the new row. If a revoked token in a family is presented again, revoke every token in that `family_id` and answer `401 AUTH_REFRESH_REUSE`. The client then sends the user to login.

Success body matches login, including a new access token.

### `POST /auth/logout`

Revokes the presented refresh token family member and clears the cookie. `204`.

### `POST /auth/logout-all`

Bearer. Revokes every refresh token of the user. `204`.

### `POST /auth/forgot-password`

```json
{ "email": "student@example.com" }
```

Always `202` with `{ "ok": true }`, even when the email does not exist. When it does, store a hashed token, TTL 30 minutes, and send a link `{WEB_ORIGIN}/reset-password?token=`. `MAIL_MODE=log` writes the link to the API log instead of SMTP.

### `POST /auth/reset-password`

```json
{ "token": "raw", "password": "new long passphrase" }
```

Single use. `204` on success. `400 AUTH_INVALID` on a bad or expired token.

### `POST /auth/verify-email`

```json
{ "token": "raw" }
```

`204`. Used when verification is enabled.

### `GET /auth/me`

Bearer. Returns the `user` object from login.

## Profile

### `PATCH /me`

Bearer. Body may include `displayName` only in v1. Username and email are not editable here. `200` returns the user object.

### `GET /players/{username}`

Bearer, any logged-in user. `200`:

```json
{
  "username": "tejas_k",
  "displayName": "Tejas",
  "rating": 1220,
  "wins": 1,
  "losses": 0,
  "draws": 0,
  "ratedMatches": 1,
  "joinedAt": "2026-11-09T00:00:00.000Z",
  "recentMatches": [
    {
      "matchId": "uuid",
      "playedAt": "2026-11-09T00:00:00.000Z",
      "language": "python",
      "difficulty": "easy",
      "rated": true,
      "outcome": "win",
      "score": 227,
      "opponentScore": 98,
      "opponentUsername": "srujan_bm",
      "ratingDelta": 20
    }
  ]
}
```

`ratingDelta` is null when `rated` is false.

### `GET /me/history`

Bearer. Cursor pagination of the same match summary, for the caller only, newest first.

### `GET /leaderboard?limit=100`

Bearer. Top players by `rating DESC, wins DESC, username ASC`. Each item is `{ rank, username, displayName, rating, wins, losses, draws }`. `rank` is the index in this list, starting at 1, not a dense rank across a filtered set. v1 has no filters.

## Problems, player-facing

### `GET /problems`

Bearer. Query: `language`, `difficulty`, `roundType`. All optional. Only published problems. The response items are `{ id, slug, title, language, difficulty, roundType }`. No prompt, no starter, no options. Players meet problems inside a match, not by browsing the bank. This list exists so the setter UI and the tests can confirm what is live. A player-role caller may call it. It still returns only the safe fields.

### `GET /problems/{id}`

Setter or admin only. Returns the full authoring object, including hidden tests and `correctOptionId`. A player receives `404`.

## Queue

### `POST /queue`

Bearer.

```json
{ "language": "python", "difficulty": "easy" }
```

`202`:

```json
{ "language": "python", "difficulty": "easy", "enqueuedAt": "...", "rating": 1200 }
```

Errors:

- `409 QUEUE_ALREADY` if this user is already queued.
- `409 MATCH_IN_PROGRESS` if they are in a countdown or live match.
- `403 QUEUE_BLOCKED_DIFFICULTY` if the rated cap forbids this difficulty at their rating.
- `422` if the language or difficulty is not in the constants.

Leaving the page does not leave the queue. The client must call delete, or the user stays queued until they disconnect for the full disconnect timeout, at which point the API removes them.

### `DELETE /queue`

Bearer. `204` if removed or if they were not queued.

### `GET /queue`

Bearer. `200` with the object above, or `204` if they are not queued.

## Lobbies

### `POST /lobbies`

Bearer.

```json
{ "language": "cpp", "difficulty": "medium" }
```

`201`:

```json
{
  "code": "K7MQ2P",
  "language": "cpp",
  "difficulty": "medium",
  "status": "open",
  "hostUsername": "tejas_k",
  "players": [{ "username": "tejas_k" }],
  "expiresAt": "..."
}
```

The caller who is already hosting an `open` lobby gets that lobby back with `200` instead of creating a second one.

### `POST /lobbies/{code}/join`

Bearer. `200` returns the lobby object including both players. `404` if the code is unknown or expired. `409 LOBBY_FULL` if two players are already in and the caller is not one of them. `409 MATCH_IN_PROGRESS` as in queue join.

Joining as the second player creates the match and moves the lobby to `countdown`. The response then includes `matchId` and `countdownEndsAt`.

### `POST /lobbies/{code}/leave`

Bearer. `204`. Implements the leave rules in the match engine.

### `GET /lobbies/{code}`

Bearer, and only if the caller is in that lobby. Otherwise `404`.

## Matches

### `GET /matches/{id}`

Bearer, participant only, `404` otherwise. Returns the client projection described in the match engine for the caller’s point of view, plus `status`. This is the snapshot a client uses if it loads the URL directly before the socket is up. The same builder function produces the WebSocket snapshot. Do not maintain two copies of the projection.

### `POST /matches/{id}/submissions`

Bearer, participant. Header `Idempotency-Key`.

Choice body:

```json
{ "roundIndex": 2, "kind": "graded", "optionId": "b" }
```

Code body:

```json
{
  "roundIndex": 1,
  "kind": "graded",
  "language": "python",
  "source": "print('ok')\n"
}
```

`kind` may be `sample` for code rounds and must be `graded` for choice rounds.

`202` for code:

```json
{ "submissionId": "uuid", "status": "queued", "kind": "graded" }
```

`200` for a choice, already judged:

```json
{
  "submissionId": "uuid",
  "status": "judged",
  "kind": "graded",
  "verdict": "accepted",
  "counted": true,
  "score": 83,
  "correct": true
}
```

A wrong choice returns `verdict: "wrong_answer"`, `score: 0`, `correct: false`, and still does not include the right option. The player learns the right option at intermission over the socket.

### `GET /matches/{id}/submissions/{submissionId}`

Bearer. Owner, while the match is not final: their submission, with sample stdout excerpts and compile stderr, without hidden inputs. Either participant, after `final`: the same, and for the opponent only the source of their best counted submission on code rounds (highest `tests_passed`, then earliest `received_at`) is exposed through the result endpoint below rather than by guessing ids. A direct get of an opponent submission id before `final` is `404`. After `final`, either participant may get either player’s submissions for that match.

### `GET /matches/{id}/result`

Bearer, participant, and only when `final` or `void`. `409` if the match is still going.

```json
{
  "matchId": "uuid",
  "status": "final",
  "rated": true,
  "endReason": "completed",
  "language": "python",
  "difficulty": "easy",
  "you": {
    "username": "tejas_k",
    "outcome": "win",
    "totalScore": 227,
    "ratingBefore": 1200,
    "ratingAfter": 1220,
    "ratingDelta": 20
  },
  "opponent": {
    "username": "srujan_bm",
    "outcome": "loss",
    "totalScore": 98,
    "ratingBefore": 1200,
    "ratingAfter": 1180
  },
  "rounds": [
    {
      "index": 1,
      "type": "syntax",
      "title": "Find Syntax Error",
      "yourScore": 67,
      "opponentScore": 0,
      "yourTimeMs": 30000,
      "opponentTimeMs": null,
      "explanationMd": "...",
      "correctOptionId": null,
      "yourOptionId": null,
      "opponentOptionId": null,
      "yourBestSource": "fixed program",
      "opponentBestSource": null
    }
  ]
}
```

On a void match, outcomes are null, scores are 0, and rating fields are unchanged with `ratingDelta: 0` and `rated: false` in spirit even if the row was created rated. The response sets `rated: false` for voids.

### `POST /matches/{id}/rematch`

Bearer, participant, match finished. `201` returns the lobby object. Publishes `lobby.invite` to the opponent.

## Realtime ticket

### `POST /realtime/ticket`

Bearer. `201`:

```json
{ "ticket": "random-256-bit-hex", "expiresIn": 30 }
```

The ticket is single use, stored in Redis as `wsticket:{ticket}` → user id, TTL 30 seconds. It is not a JWT and it is not the access token. The WebSocket query string carries the ticket, which will show up in access logs, so it must be useless a second after a successful connect.

## Setter

All routes require role `setter` or `admin`.

### `POST /setter/problems`

Creates an unpublished problem. Body is one object from the problem pack: the fields in `contracts/problem-pack.example.json` except the pack wrapper. `201` returns the problem including its id. `correctOptionId` is accepted and stored and is never returned from a player route.

### `PATCH /setter/problems/{id}`

Partial update. Refuses with `409 PROBLEM_FROZEN` if any `match_rounds` row references the id and the patch changes starter code, tests, options, or the correct option. Title and explanation may still change. In practice setters should edit a copy. The freeze exists so a live snapshot’s `problem_id` audit trail still describes a problem that has the same tests. The live match itself reads `snapshot` and is safe either way. The freeze protects the audit.

### `POST /setter/problems/{id}/reference-run`

Body `{ "source": "..." }`. `202` with a submission-like id that is not attached to a match. Poll `GET /setter/reference-runs/{runId}` for the verdict. On full acceptance the API sets `reference_passed_at`.

### `POST /setter/problems/{id}/publish`

`200` when the authoring rules in the judge doc pass and, for code problems, `reference_passed_at` is non-null. Otherwise `422`.

### `POST /setter/problems/{id}/unpublish`

`200`. Does not affect matches already created.

### `POST /setter/problem-packs`

Body is the pack file. `200` with `{ "created": 4, "ids": [] }`. The import is one transaction. A duplicate slug fails the whole pack with `409`.

## Admin

### `PATCH /admin/users/{id}`

Admin only. Body `{ "role": "setter" }`. Writes an `audit_log` row. Cannot demote the last remaining admin. `200` returns the user.

## Health

No auth.

- `GET /health/live` returns `200` `{ "ok": true }` when the process is up.
- `GET /health/ready` returns `200` only when PostgreSQL answers `SELECT 1` and Redis answers `PING`. Otherwise `503`.

Caddy uses live for “is the process there” and the deploy script uses ready before it shifts traffic.

## Rate limits

From `constants.json` `rateLimits`. Implementation is a Redis sliding window keyed by IP for signup and login, and by user id for the authenticated routes. `429` body uses code `RATE_LIMITED`.

## CORS

`Access-Control-Allow-Origin` is exactly `WEB_ORIGIN`. `Allow-Credentials: true`. Methods: `GET, POST, PATCH, DELETE, OPTIONS`. Headers: `Authorization, Content-Type, Idempotency-Key, X-Request-Id`. No wildcard origin in production.
