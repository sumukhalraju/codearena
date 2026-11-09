# Realtime

Transport is a WebSocket at `{WS_ORIGIN}/ws/v1?ticket={ticket}`. The ticket comes from `POST /api/v1/realtime/ticket`. The server accepts the socket, reads exactly one ticket, deletes the Redis key, and closes the socket with code `4401` if the ticket is missing, unknown, or already used.

Messages are UTF-8 text frames. Each frame is one JSON object:

```json
{ "type": "match.join", "payload": { "matchId": "uuid" } }
```

There is no binary frame, no Socket.IO packet, and no subprotocol. Unknown `type` values produce an `error` message and do not close the socket. A frame larger than 64 KiB closes the socket with `4400`. The client never sends source code on the socket. Source goes through REST.

The server emits `hello` immediately after the ticket checks out:

```json
{
  "type": "hello",
  "payload": { "userId": "uuid", "serverTime": "2026-11-09T12:00:00.000Z" }
}
```

## Client to server

| type | payload | Effect |
| --- | --- | --- |
| `ping` | `{ "sentAt": "iso" }` | Refresh presence TTL. Reply `pong`. |
| `match.join` | `{ "matchId": "uuid" }` | If the caller is a participant and the match is not void-and-forgotten, subscribe this socket to the match and send `match.snapshot`. Otherwise `error` code `NOT_FOUND`. |
| `match.leave` | `{ "matchId": "uuid" }` | Unsubscribe this socket. Does not forfeit. Closing the laptop is what starts the disconnect timer, and only after every socket for that user is gone and the presence key expires. |
| `lobby.join` | `{ "code": "K7MQ2P" }` | Subscribe to lobby events. Does not join the lobby. Joining is REST. |
| `queue.watch` | `{}` | Subscribe to queue events for this user. |

`pong` payload is `{ "sentAt", "serverTime" }`. The client treats a missing `pong` for 15 seconds as a dead socket, fetches a new ticket, and connects again. It reconnects with the same match by sending `match.join` after `hello`.

## Server to client

Events are addressed to a user, not to “everyone in the match” as a shared broadcast of one payload. The API builds a payload per user so one player’s stderr never sits in the other player’s message. Redis channel is `user:{userId}`. Every API replica subscribes with a pattern subscription and writes to the local sockets of that user.

| type | When | Payload fields |
| --- | --- | --- |
| `hello` | Connect | `userId`, `serverTime` |
| `pong` | Reply to ping | `sentAt`, `serverTime` |
| `queue.position` | Every matcher tick while queued, and on join | `ahead`, `waitedMs`, `windowRatingDelta` (`null` when the window is open to anyone) |
| `queue.matched` | Pair created | `matchId`, `countdownEndsAt`, `language`, `difficulty`, `rated`, `opponentUsername` |
| `queue.reset` | Redis queue state was lost | `{}` |
| `queue.error` | Pair aborted, for example no problem in the bank | `code`, `message` |
| `lobby.state` | Membership or status change | The lobby object from the HTTP doc |
| `lobby.invite` | Rematch created | `code`, `language`, `difficulty`, `hostUsername` |
| `match.snapshot` | After `match.join`, and any time the client asks for a full refresh by sending `match.join` again | Full client projection |
| `match.round.started` | Round becomes active | `roundIndex`, `type`, `title`, `interaction`, `startsAt`, `endsAt`, `serverTime`, plus the round content fields of the snapshot |
| `match.timer` | Optional, at most every 5 seconds | `roundIndex`, `endsAt`, `serverTime`. The client may render the clock from `endsAt` alone. This event exists to correct drift. |
| `match.opponent.progress` | Opponent submission graded or round status change | `roundIndex`, `status`, `testsPassed`, `testsTotal`, `totalScore` |
| `match.opponent.connection` | Presence change | `connected` boolean |
| `submission.result` | A submission of the recipient was judged | See below |
| `match.round.ended` | Round closed, intermission begins or match is about to finalize | `roundIndex`, `yourScore`, `opponentScore`, `correctOptionId`, `explanationMd`, `intermissionEndsAt` |
| `match.ended` | Match `final` or `void` | Same object as `GET /matches/{id}/result` |
| `error` | Bad client message | `code`, `message` |

`correctOptionId` and `explanationMd` are null on `match.round.ended` for code rounds, and populated for choice rounds.

`match.opponent.progress.status` is one of `solving`, `judging`, `correct`, `wrong`. `solving` is the default at round start. `judging` is sent when a graded code submission is queued. Choice rounds jump from `solving` to `correct` or `wrong`.

### `submission.result`

```json
{
  "type": "submission.result",
  "payload": {
    "submissionId": "uuid",
    "roundIndex": 1,
    "kind": "graded",
    "status": "judged",
    "verdict": "wrong_answer",
    "counted": false,
    "testsPassed": 1,
    "testsTotal": 3,
    "score": null,
    "compileStderr": null,
    "sampleExcerpt": "ok\n"
  }
}
```

`score` is a number only when `counted` is true and the verdict is `accepted`. `compileStderr` is present only for the owner and only for `compile_error` and `runtime_error`.

## Snapshot

`match.snapshot` payload:

```json
{
  "matchId": "uuid",
  "status": "live",
  "origin": "quick",
  "rated": true,
  "language": "python",
  "difficulty": "easy",
  "serverTime": "2026-11-09T12:00:00.000Z",
  "countdownEndsAt": null,
  "you": {
    "username": "tejas_k",
    "rating": 1200,
    "totalScore": 67,
    "connected": true
  },
  "opponent": {
    "username": "srujan_bm",
    "rating": 1200,
    "totalScore": 0,
    "connected": true,
    "roundStatus": "solving"
  },
  "round": {
    "index": 2,
    "type": "predict",
    "title": "Predict Output",
    "interaction": "choose_answer",
    "status": "active",
    "startsAt": "...",
    "endsAt": "...",
    "promptMd": "...",
    "starterCode": "s = 0\n...",
    "options": [{ "id": "a", "text": "6" }],
    "submissionsRemaining": 1,
    "sampleRunsRemaining": null
  },
  "yourSubmissions": [],
  "intermission": null,
  "result": null
}
```

During countdown, `round` is null and `countdownEndsAt` is set. During intermission, `round.status` is `intermission` and `intermission` is `{ "endsAt", "yourScore", "opponentScore", "correctOptionId", "explanationMd" }`. After the match ends, the server sends `match.ended` and the snapshot’s `result` is the result object. The client navigates to the result route when it receives `match.ended`.

`yourSubmissions` during a live match contains only the caller’s rows: `{ submissionId, kind, verdict, status, testsPassed, testsTotal, counted, receivedAt }`. No opponent source.

## Ordering

Events for one user are published to Redis in the order the transaction committed. The API writes them to a given socket in that order. The client applies `match.snapshot` as a full replacement of its match store. It applies other events only if it already has a snapshot for that `matchId`. If it receives `match.round.started` before a snapshot, it sends `match.join` again and ignores the early event.

The client does not animate a score that contradicts the latest snapshot.

## Backpressure

If a socket’s outbound buffer exceeds 1 MiB, the API closes it with `4408`. The client reconnects and joins again. Dropping events silently is forbidden, because a dropped `match.ended` would strand the player. Closing and snapshotting is the recovery.

## Auth and the query string

Do not put the access token or the refresh token in the WebSocket URL. Tickets expire in 30 seconds and are deleted on use. Access logs may retain the URL. A leaked log line must not grant a second connection.
