# Frontend build

The repository is `codearena-frontend`. It renders CodeArena. It does not decide a winner, a verdict, or a rating. If the server and the screen disagree, the screen changes.

Read `01-product.md`, `04-match-engine.md`, `06-http-api.md`, and `07-realtime.md` before scaffolding.

## Stack

- Node.js 22 and pnpm 9
- Next.js App Router, TypeScript `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`
- React client components for every interactive screen
- Tailwind CSS
- Monaco via `@monaco-editor/react`, bundled, not loaded from a CDN
- TanStack Query for HTTP
- Zod for parsing every HTTP and WebSocket payload
- Playwright for the flows in `13-testing.md`
- Vitest for pure helpers (clock offset, reconnect reducer)

No Redux. The match screen keeps one store module, described below. No Socket.IO client. Use the platform `WebSocket`.

## Environment

`.env.example`:

```text
NEXT_PUBLIC_API_BASE_URL=http://localhost:4000
NEXT_PUBLIC_WS_BASE_URL=ws://localhost:4000
```

No other `NEXT_PUBLIC_` variable. There is no API key in this app.

Production build uses `output: 'standalone'` so the Docker image runs `node server.js`. The image does not contain the problem bank or a copy of the database.

## Routes

| Path | Who | Purpose |
| --- | --- | --- |
| `/` | public | Short explanation and Login / Sign up. If a refresh succeeds, redirect to `/dashboard`. |
| `/login` | public | Email and password |
| `/signup` | public | Email, username, display name, password |
| `/forgot-password` | public | Email form. Always shows “If an account exists, a link is on its way.” |
| `/reset-password` | public | New password, token from the query string |
| `/dashboard` | user | The home the flowchart names |
| `/play/quick` | user | Language and difficulty, then enters the queue |
| `/play/queue` | user | Waiting state |
| `/lobby/new` | user | Create, then redirects to `/lobby/{code}` |
| `/lobby/join` | user | Type a code |
| `/lobby/{code}` | member | Waiting and countdown |
| `/match/{id}` | participant | Arena |
| `/match/{id}/result` | participant | Scores, winner, rating |
| `/players/{username}` | user | Public profile |
| `/leaderboard` | user | Top 100 |
| `/me/history` | user | Own matches |
| `/me/settings` | user | Display name, log out of all sessions |
| `/setter/problems` | setter | List |
| `/setter/problems/new` | setter | Author |
| `/setter/problems/{id}` | setter | Edit, reference run, publish |

An unknown match id, or a match the user is not in, shows a “Match not found” page. It does not redirect to someone else’s result.

## Visual structure

The product is a match, so the arena is the screen that has to be right. The rest should look like one family: a dark ink background (`#12141a`), a paper card (`#f4f1ea`), one accent (`#e85d04`) for the primary action, and a monospace face for code, timers, and ratings. Use a single sans for UI (something already on a default system stack is acceptable: `ui-sans-serif`). Do not introduce a second accent per round. Rounds are labeled in text, “Round 2 of 4 · Predict Output”.

Timer text is at least 2rem, tabular numbers, and not the only signal that time is short. Under 10 seconds the word “Ending” appears beside it.

### Dashboard

- Top bar: “CodeArena”, rating pill, username, Log out.
- Primary button: Quick Match.
- Secondary buttons: Create Lobby, Join Lobby.
- One row: rating, wins, losses, draws.
- Last five matches. Empty copy: “No matches yet. Play a quick match to get a rating.”
- Top five leaderboard rows, link “Full leaderboard”.

### Quick Match setup

Two choices, each a radio group with the four languages and the three difficulties spelled out: C, C++, Python, JavaScript, Easy, Medium, Hard. The labels match `constants.json` `label` fields. Submit label: “Find an opponent”. If the API returns `QUEUE_BLOCKED_DIFFICULTY`, show “Your rating can no longer play rated {difficulty}. Choose a harder queue, or use a lobby.”

### Queue

“Looking for an opponent” plus waited time from `queue.position`, and Cancel. Cancel calls `DELETE /queue` and returns to the dashboard. On `queue.matched`, route to `/match/{id}`.

### Lobby

Show the code in a large monospace string with a Copy button. Show language, difficulty, and who is in the room. The second player’s arrival is `lobby.state`. The countdown is the match countdown, full screen, “Both players ready”, then 3, 2, 1, driven by `countdownEndsAt`.

### Arena

```text
+--------------------------------------------------------------+
| Round 2 of 4 · Predict Output          00:31     you 80 opp 65 |
| opponent: solving · connected                                 |
+-------------------------------+------------------------------+
| prompt markdown               | if choice: four big options   |
| read-only starter code        | if code: Monaco               |
|                               | Run sample    Submit          |
+---------------------------------------------------------------+
```

- The opponent column never has a code editor.
- Run sample is hidden on choice rounds.
- Submit is disabled when `submissionsRemaining` is 0, when the round status is not `active`, or while a graded submit for this round is `queued` or `running`.
- Choice options are buttons. One may be selected. Submit sends the selected id. Changing the selection before submit does not call the API.
- Monaco language modes: `c`, `cpp`, `python`, `javascript`. Minimap off. Font size 16. The starter code is the initial value when the round starts. Switching rounds replaces the buffer. Do not restore round 1’s draft into round 4.
- A local draft may sit in component state. It is not recovered from `localStorage` after a real refresh. On refresh the client loads the snapshot and uses `starterCode` again. A lost draft is acceptable. A draft leaking across users on a shared lab machine is not, which is why it is not in `localStorage`.

### Intermission

A panel over the arena for the intermission window: “Round score”, both numbers, and for choice rounds the correct option text and `explanationMd`. It dismisses itself when `match.round.started` arrives for the next round. The player cannot skip it early. The server owns the 5 seconds.

### Result

Winner’s display name, or “Draw”. The four-row table from the product doc. Rating `1200 → 1220 (+20)` or the word “Unrated”. Links to review source, which expands `yourBestSource` and `opponentBestSource` when those fields are non-null. Buttons: “Back to dashboard” and “Rematch”. Rematch calls the rematch endpoint and routes the host to the new lobby. The opponent sees an invite banner if they are connected, and otherwise they see nothing until they look at the dashboard. The invite is not email in v1. If the opponent is offline, the host still has a code they can send themselves.

### Setter

A plain form. Fields follow the problem pack. Code problems get a test-case editor (input and expected output, sample versus hidden) and a Reference solution textarea whose button calls `reference-run` and polls. Publish stays disabled until the latest reference poll returns `accepted` and the client-side checks (4 options, non-empty starter) pass. The server still rejects a bad publish. The disabled button is a convenience, not the control.

## Client state

One module `src/features/match/match-store.ts` holds the latest snapshot and applies socket events. TanStack Query holds profiles, history, and the leaderboard. Do not also put the match in React Query. The socket is the feed.

Access token: a variable in `src/lib/auth/token.ts`, not `localStorage`, not a cookie the JavaScript can read. On load, `POST /auth/refresh` with `credentials: 'include'`. On 401 from any call, try refresh once, then route to `/login`.

WebSocket client:

1. Fetch a ticket.
2. Connect.
3. On `hello`, send `match.join` if the route is a match, `queue.watch` if the route is the queue, `lobby.join` if the route is a lobby.
4. On socket close, wait with jitter from 200 ms to 2 seconds and repeat, up to forever while the route is mounted. Stop when the route unmounts.
5. Parse with Zod. A payload that fails the schema is logged and ignored, and the client sends `match.join` to resync if a match is open.

Clock helper, unit tested:

```text
remainingMs(endsAt, serverTime, clientNow, clientNowAtReceipt)
```

Use the offset measured when `serverTime` arrived. Recompute every 200 ms for display. At `remainingMs <= 0`, show `0:00` and wait for the server. Do not fire a local “round over” that changes score.

## Folder layout to create when scaffolding

```text
src/app/                         routes above, thin pages
src/components/                  button, timer, code-view, banner
src/features/auth/
src/features/dashboard/
src/features/queue/
src/features/lobby/
src/features/match/              arena, store, socket bindings
src/features/result/
src/features/profile/
src/features/setter/
src/lib/api/                     fetch wrapper, generated types
src/lib/ws/
src/lib/time/
contracts/                       vendored copy of the parent contracts
```

Generate types from the parent `contracts/openapi.yaml` with `openapi-typescript` and commit the output. Hand-written response types are not allowed next to generated ones.

## Accessibility and input

- Every control is a button or a labeled input. The countdown is text, not only a color flash.
- Monaco gets a visible label “Your solution”.
- Submit can be triggered with Ctrl+Enter or Cmd+Enter inside the editor.
- Focus the first option, or the editor, when a round starts.
- Respect `prefers-reduced-motion` by dropping the countdown scale animation. The digits still change.

## What the UI must not do

- Compute Elo or the speed score for anything except an optional optimistic decoration that is removed when the server number arrives. Prefer showing nothing until the server number arrives. There is no optimistic score in v1.
- Show opponent source, opponent option, hidden tests, or the correct option during an active round.
- Keep the user in the arena after `match.ended`. Go to the result route.
- Open a second WebSocket per tab. One socket per tab. Two tabs are two sockets and are allowed. Presence is a count.
- Bundle a judge, a compiler, or the hidden tests “for offline practice.”

## Empty, error, and edge copy

| State | Copy |
| --- | --- |
| Queue, no opponent yet | “Looking for an opponent. You can cancel and come back.” |
| `NO_PROBLEM` | “The problem bank has no published set for this language and difficulty. Try another, or tell a setter.” |
| Socket down | A banner “Reconnecting”. The editor stays usable. Submit stays enabled and uses HTTP. The socket is not required to submit. |
| Submit while reconnecting | Normal POST. The result appears when the socket returns, and a poll of `GET /matches/{id}` every 3 seconds covers a socket that stays down. Stop polling when the socket is healthy or the match has ended. |
| Opponent disconnected | “Opponent disconnected. The clock keeps running.” |
| Void early | “Opponent left before the match started. Rating was not changed.” |
| 429 | “Too many attempts. Wait {Retry-After} seconds.” |
| 5xx | “The server could not do that. Your last submit is safe to retry.” The client retries only with the same idempotency key. |

## Production UI checklist

- Refresh on the result page shows the same scores as the live transition. It uses `GET /matches/{id}/result`.
- A reload in the middle of round 4 returns to round 4 with the server’s remaining time, not to round 1.
- The Quick Match button cannot be double-clicked into two queue joins. Disable it when the mutation is in flight.
- Lobby code input strips spaces and uppercases before POST.
- All four languages render a Monaco mode and send the matching `language` field.
