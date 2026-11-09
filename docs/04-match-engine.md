# Match engine

This document is the rulebook. `contracts/constants.json` holds the numbers. If a number below ever drifts, the JSON wins and this page is fixed.

## States

```text
lobby: open → countdown → started
                         → cancelled
                         → expired

match: countdown → live → final
                        → void

round: pending → active → intermission → closed
```

`live` means “round 1 has started and the match is not over.” `current_round` is 1 through 4 while `live`.

A match is `final` only after round 4 is `closed` and, if the match is rated, both `rating_events` rows and both `users.rating` updates have committed in that same transaction.

A match is `void` when it ends with no winner and no rating change. `end_reason` is `void_early` or `void_no_problem`.

## Creating a Quick Match

Inside one transaction, after the matcher has chosen two distinct users:

1. Take `pg_advisory_xact_lock` on both user ids, lower uuid first.
2. Re-read that neither user is in a match with status `countdown` or `live`. If either is, abort the pair and put the other back on the queue.
3. Confirm neither is still absent from the queue (they clicked Leave). If either left, abort.
4. Pick problems. For each round type, choose a published problem of that language, difficulty, and round type. Exclude ids in either player’s last 20 `seen_problems` rows when at least one candidate remains. If none remain, use the full published pool. If the pool for any round is empty, do not create the match. Return both players to the queue and emit `queue.error` with `NO_PROBLEM`. This is an operator failure, not a player error.
5. Insert `matches` with `origin = quick`, `rated` true unless the pair cap below forces false, `status = countdown`, `countdown_ends_at = now() + countdownMs`.
6. Insert two `match_players` with `rating_before` copied from `users.rating` and seats 1 and 2. Seat 1 is the lower uuid. Seat assignment does not affect scoring.
7. Insert four `match_rounds` in `pending`, each with `snapshot` and `duration_ms` from the constants for that round index. `problem_id` points at the bank row for audit. Grading reads `snapshot`.
8. Insert `seen_problems` for both users and all four problems.
9. Insert `pair_history` with `user_low` / `user_high` ordered by uuid.
10. Commit, then publish `queue.matched` to both users with the `matchId`.

The pair cap: count `pair_history` rows for this unordered pair with `rated = true` and `played_at` inside the last `samePairWindowHours`. If the count is greater than or equal to `samePairRatedCap`, set `rated = false` on the new match.

## Creating a lobby match

When the second distinct user joins an `open` lobby:

1. Lock both users the same way.
2. If either is in a live match, reject the join with `409 MATCH_IN_PROGRESS` and do not change the lobby.
3. Create the match exactly as above with `origin = lobby` and `rated = false`. Do not apply difficulty caps. Do not apply the pair cap, because it is already unrated.
4. Set the lobby to `countdown` and store `match_id`.

Leaving during countdown: delete that user’s `match_players` row only if the match has not reached `live`. Set the match to `void`, `end_reason = void_early`. Re-open the lobby if the host remains, otherwise cancel it. A countdown that reaches zero transitions the match to `live` and the lobby to `started`.

## Opening a round

At countdown end, and at each intermission end:

1. Lock the match.
2. Set the round to `active`, `starts_at = now()`, `ends_at = starts_at + duration_ms`.
3. Set `matches.status = live` and `started_at` if this is round 1.
4. Set `current_round`.
5. Enqueue a delayed job `round-close` at `ends_at`.
6. Publish `match.round.started` and a full per-user snapshot. The two snapshots differ only in `you` versus `opponent` and in that each contains that user’s own draft quota. The problem content is identical.

## Submissions

### Choice rounds (2 and 3)

Body is `{ "optionId": "a" }` plus the idempotency key. No source field.

Rules:

- The round is `active` and `received_at <= ends_at`. A request that arrives later gets `409 ROUND_CLOSED` and is not stored as a graded submission.
- The user has no existing `kind = graded` submission on this round. A second one gets `409 SUBMISSION_QUOTA`.
- `optionId` is one of the four ids in the snapshot.

Grading is immediate. Correct means `optionId == snapshot.correctOptionId`. Write `submissions` as `judged`, write `round_scores`, publish the result to the owner and a progress event to the opponent. Progress for a choice round is `submitted` plus `correct: true|false` after judging, which is immediate. Do not include the correct id in the opponent event.

If the timer fires and the client has not submitted, the score is 0. The UI may keep a local selection highlighted. That selection is not an answer until POST succeeds. There is no auto-submit of an unsent selection. An unsent selection exists only in the browser and the server must not trust it.

### Code rounds (1 and 4)

Two kinds:

- `kind: "sample"`. Runs sample tests only. Does not write `round_scores`. Does not increment `wrong_attempts`. Subject to `maxSampleRuns` and `sampleRunCooldownMs` and the per-minute rate limit.
- `kind: "graded"`. Runs sample tests first. If a sample fails, hidden tests are not run, `tests_passed` for hidden is 0, verdict is the sample failure verdict. If all samples pass, run every hidden test. Do not stop at the first hidden failure. `tests_passed` / `tests_total` in the player-facing graded result count hidden tests only.

A graded submission is rejected with `409 SUBMISSION_QUOTA` when the user already has `maxGradedSubmissions` graded rows on that round, or already has a counted `accepted` on that round. Further submits after acceptance are pointless and would complicate “time of the correct submit.”

`language` in the body must equal the match language. The source file name inside the container is the `sourceFile` for that language. The program must be a whole program:

- C: `int main`, file `main.c`
- C++: `int main`, file `main.cpp`
- Python: `main.py`
- JavaScript: `main.js`, Node, stdin/stdout, no DOM

Source larger than `sourceBytes`, source that is not valid UTF-8, and source containing a NUL byte are `422` with verdict not stored, error code `VALIDATION`. They do not consume quota.

The HTTP handler inserts `status = queued` and returns `202` with the submission id. It does not wait for the container.

## When a graded code verdict comes back

Lock the match. Load the submission. If `received_at` is after the round’s `ends_at`, set `counted = false` and verdict as judged, but do not change `round_scores`. Publish `submission.result` with `counted: false`.

If the round is already `closed`, do the same.

If the verdict is `internal_error`, set `counted = false`, do not increment `wrong_attempts`, publish the result, and allow another submit.

If the verdict is `accepted` and the round is still within the grace window:

- `time_used_ms = received_at - starts_at`
- `wrong_attempts` = the number of earlier graded submissions on this round by this user whose verdict is not `accepted` and not `internal_error`
- Compute the score with the formula below
- Upsert `round_scores` with `correct = true`
- Set this submission `counted = true`

If the verdict is anything else that counts as wrong (`wrong_answer`, `compile_error`, `runtime_error`, `time_limit`, `memory_limit`, `output_limit`):

- Do not write a correct score
- The wrong-attempt count is derived at acceptance time from the rows, not stored incrementally, so a retry of the same job cannot double-count
- Publish the result to the owner, including compile stderr truncated to `stderrBytes`
- Publish opponent progress: `testsPassed`, `testsTotal`, status `wrong`

Sample-run results publish only to the owner, with `kind: "sample"`.

## Closing a round

The `round-close` job runs at `ends_at`. It locks the match.

- If any graded submission on this round is `queued` or `running` and `now() < ends_at + judgeGraceMs`, reschedule the job for the grace deadline and stop.
- Otherwise close it:
  - For each player without a `round_scores` row, insert one with `correct = false`, `score = 0`, `time_used_ms = null`, and `wrong_attempts` equal to the count of their wrong graded submissions.
  - Set the round to `intermission` and `intermission_ends_at = now() + intermissionMs` if the round index is 1, 2, or 3.
  - Enqueue `intermission-end`.
  - If the round index is 4, skip the intermission and finalize.
- Publish `match.round.ended` to both users. For choice rounds the payload includes `correctOptionId` and `explanationMd`. For code rounds it includes each player’s score only, not their source.

If both players already have a correct `round_scores` row before `ends_at`, the API (or the worker, after the second acceptance) enqueues `round-close` immediately. The same function runs. Early close is allowed. The unused time is not added to the next round.

## Scoring

Let `T` be the round duration and `t` the `time_used_ms` of the submission that was accepted. Both are integers. `t` is clamped to `[0, T]` before the formula.

```text
speed = roundHalfAwayFromZero(100 * (1 - 0.7 * t / T))
```

`speedWeight` in the JSON is `0.7`. `roundMax` is `100`.

Then clamp `speed` into `[speedFloor, roundMax]`, which is `[30, 100]`. The clamp matters only if a bug produces a value outside that range. Inside the legal range the formula already lands there: at `t = 0` the score is 100, at `t = T` the score is 30.

Choice rounds stop here. Wrong is 0. There is no wrong-attempt penalty, because there is only one submit.

Code rounds:

```text
penalty = wrong_attempts * wrongAttemptPenalty
score = speed - penalty
if score < minimumCorrectScore then score = minimumCorrectScore
```

`wrongAttemptPenalty` is 10. `minimumCorrectScore` is 1. A correct code round is never 0.

`roundHalfAwayFromZero` for any real `x`:

```text
if x >= 0 then floor(x + 0.5) else -floor(-x + 0.5)
```

Implement that in `packages/domain`. Do not call `Math.round`.

### Worked match

Durations: syntax 90000, predict 40000, logic 50000, fix 180000.

| Round | A | B |
| --- | --- | --- |
| 1 | Accepted at 30000 ms after 1 wrong submit | No accept |
| 2 | Correct at 10000 ms | Wrong |
| 3 | Wrong | Correct at 25000 ms |
| 4 | Accepted at 60000 ms, 0 wrong | Accepted at 120000 ms, 2 wrong |

Round 1 A: `t/T = 30000/90000`. `1 - 0.7 * 1/3 = 0.7666…`. `100 * that = 76.666…`, rounds to 77. Penalty 10. Score 67. B scores 0.

Round 2 A: `10000/40000 = 0.25`. `1 - 0.175 = 0.825`. Score 83. B scores 0.

Round 3 B: `25000/50000 = 0.5`. `1 - 0.35 = 0.65`. Score 65. A scores 0.

Round 4 A: `60000/180000 = 1/3`. Same speed as round 1, score 77. B: `120000/180000 = 2/3`. `1 - 0.7 * 2/3 = 0.5333…`. `53.333…` rounds to 53. Penalty 20. Score 33.

Totals: A 67+83+0+77 = 227. B 0+0+65+33 = 98. A wins. The time tie-break is not used.

Unit tests must include this table and the boundary `t = T` (score 30 before penalties) and `t = 0` (score 100).

## Winner

Compare only after round 4 is closed, or immediately on a forfeit that awards the match.

1. Higher `total_score` wins. `total_score` is the sum of the four round scores.
2. If the totals are equal, the lower `total_correct_time_ms` wins. That sum includes only rounds with `correct = true`. A player who solved fewer rounds has a smaller time sum only if the other player’s correct rounds took longer, which is acceptable: the primary key is the score, and this key breaks true ties.
3. If those are equal too, `outcome` is `draw` for both and `winner_user_id` is null.

## Rating

Rated matches only. Unrated matches leave `rating_before` in place, write `rating_after = rating_before`, and write no `rating_events` row. The result payload says `rated: false`.

Elo, for a rated match that is not void:

```text
expected = 1 / (1 + 10 ^ ((opponentRatingBefore - ratingBefore) / 400))
actual = 1 if win, 0.5 if draw, 0 if loss
K = 40 if rated_matches < 10
    10 if ratingBefore >= 2000
    20 otherwise
delta = roundHalfAwayFromZero(K * (actual - expected))
rating_after = max(100, rating_before + delta)
```

`rated_matches` counts matches that were rated and reached `final` before this one. Increment it in the same transaction. `K` uses the pre-match rating and the pre-match count.

Both players are updated together. The winner’s `actual` and the loser’s `actual` are complementary, so the deltas are opposites before the floor of 100 is applied. If the floor clips one player, the other player still receives their full delta. Do not “take” the clipped points from the winner.

Worked rating for the match above, both players at 1200 with fewer than 10 rated matches: `expected = 0.5`, `K = 40`, winner delta `roundHalfAwayFromZero(20) = 20`, loser delta `-20`. Ratings become 1220 and 1180.

A draw with equal ratings moves both by 0.

## Disconnect and forfeit

The client sends `ping` every `clientHeartbeatMs` (5 seconds). The API refreshes `presence:{userId}` with TTL `serverTimeoutMs` (15 seconds). When the key expires, or the socket closes and no replacement socket arrives, the API sets `match_players.last_disconnected_at` if it was null and starts a 30 second `reconnectGraceMs` timer.

A `match.join` from that user before the grace ends clears `last_disconnected_at` and cancels the forfeit timer. The client then receives a snapshot.

If the grace ends and the player is still absent:

Let `S` be the absent player and `P` the present player. Let the scores be whatever is already written, treating unwritten rounds as 0.

- If the match is `countdown`, or it is `live` on round 1 and both players have zero submissions and `now() < round.starts_at + voidIfNoSubmissionWithinMs`, void the match. `end_reason = void_early`. No rating change. The present player returns to the dashboard with “Opponent left. This match was not rated.”
- Else if `score(S) < score(P)` or the scores are equal, forfeit: close every open round with 0 for both players on rounds that have no row yet, set `S.forfeit = true`, `S.outcome = loss`, `P.outcome = win`, finalize rating as a normal win for `P`. `end_reason = forfeit`.
- Else `score(S) > score(P)`: do not end the match. `S` stays in the match, absent. Their later rounds score 0 when they close. `P` keeps playing. Publish `match.opponent.connection` with `connected: false`. The normal winner rules run at the end. A later reconnect of `S` is still accepted until the match is `final`, and they may submit on a round that is still `active`.

The clock does not pause in any of these branches.

## Rematch

`POST /matches/{id}/rematch` is allowed only when the match is `final` or `void` and the caller was a player.

It creates a normal unrated lobby using the finished match’s language and difficulty, with the caller as host, and publishes `lobby.invite` to the other player with the code. It does not start the countdown until that player calls join. If they do nothing, the lobby expires like any other.

## Problem snapshot shape

Stored in `match_rounds.snapshot`. This is the worker and API view, not the client view.

```json
{
  "problemId": "uuid",
  "slug": "py-syntax-missing-colon",
  "roundType": "syntax",
  "language": "python",
  "title": "Missing colon",
  "promptMd": "...",
  "starterCode": "...",
  "explanationMd": "...",
  "options": [{ "id": "a", "text": "..." }],
  "correctOptionId": "a",
  "timeLimitMs": 2000,
  "memoryLimitKb": 131072,
  "samples": [{ "input": "3\n", "expectedOutput": "ok\n" }],
  "hidden": [{ "input": "0\n", "expectedOutput": "no\n" }]
}
```

`options` and `correctOptionId` are null on code rounds. `samples` and `hidden` are empty arrays on choice rounds. `starterCode` on a choice round is the program the player reads, not a program they edit.

## Client projection while a round is active

Send `promptMd`, `starterCode`, `options` (ids and text only), clock, quotas, and the caller’s own submission list. Omit `correctOptionId`, `explanationMd`, `hidden`, and sample `expectedOutput`. The client needs sample `input` so the player understands the example. It learns whether the sample passed from the verdict, not from being handed the expected string in advance. Expected sample output is shown in the statement only when the author pasted it into `promptMd`. Authors should paste sample explanations into `promptMd` for code rounds. The structured `expectedOutput` stays on the server so the judge, not the prose, is authoritative.

## Concurrency cases the tests must hit

- Two graded submits in flight, the slower request arrives at HTTP second and would exceed quota. The quota check and the insert are in one transaction so only one waits; the other gets `SUBMISSION_QUOTA` if the cap was one, or both are kept if the cap allows both.
- Accept verdict applied twice because the job was retried. The second apply sees `counted = true` and writes nothing.
- `round-close` and the accept verdict run together. One blocks on the row lock. If close wins first, the verdict is stored with `counted = false` only when `received_at > ends_at` or the grace has already expired. If the verdict’s `received_at` is `<= ends_at` and the close is waiting on grace, the verdict wins and the score counts.
- Both players accept at the same moment and both try to close the round early. One transition occurs.
- Matcher tick overlaps with Leave Queue. The user is not paired.
