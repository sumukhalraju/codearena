# Security and fairness

## Assets

| Asset | Why it matters |
| --- | --- |
| Student source in an active match | Copying it is the cheat this product can actually prevent |
| Hidden tests and correct option ids | Leaking them makes the match a memory test against last week’s network tab |
| Password hashes and refresh tokens | Account takeover |
| Rating writes | A bug here is a fairness bug even when nobody is attacking |
| The Docker socket | It is host root on a typical install |
| SMTP credentials and `JWT_ACCESS_SECRET` | Forgery and mail abuse |

## Threats and the control that answers them

| Threat | Control |
| --- | --- |
| Student code reads the expected output | Expected output is never mounted into the container. Comparison is in the worker. |
| Student code scans the internal network | `--network none` |
| Fork bomb or disk fill | `pids-limit`, tmpfs size, read-only root, stdout cap |
| Container reuse leaks `/tmp` to the next student | New container every phase, `docker rm -f` before run, delete the host source directory in `finally` |
| API process is compromised and also has the socket | API container has no socket mount |
| Opponent reads source via the snapshot | Separate DTO. A test locks this. |
| User enumerates match ids | 404 for non-participants |
| User enumerates emails at login | Same error and a floor on response time |
| Refresh token stolen and reused | Family revocation on reuse |
| Access token in the WebSocket URL ends up in logs | Ticket, 30 seconds, single use |
| CSRF on refresh | `SameSite=Lax` cookie, path limited to `/api/v1/auth`, and the refresh route checks `Origin` against `WEB_ORIGIN` when `Origin` is present |
| Setter account phishing | Roles are separate. Players cannot publish. |
| Two friends farm rating | Unrated lobbies, pair cap, difficulty caps |
| Replay of a submit doubles the score | Idempotency key and the counted-flag inside the row lock |
| Admin lockout | Cannot demote the last admin |
| Backup stolen | PostgreSQL backups are encrypted at rest by the operator, and password hashes are argon2id so a backup is not a password list. Document the disk encryption on the VPS. |

## Auth details

- argon2id parameters: memoryCost 19456, timeCost 2, parallelism 1.
- Access token 15 minutes, bearer, memory only.
- Refresh token 32 random bytes, only the SHA-256 hash stored, 30 days, rotation on every refresh.
- Password reset token 32 random bytes, SHA-256 stored, 30 minutes, single use.
- No security questions. No password in email.
- Signup, login, forgot-password, and reset are rate limited per the constants.
- `JWT` secret rotation: support two secrets, `JWT_ACCESS_SECRET` and `JWT_ACCESS_SECRET_PREVIOUS`, verify with either, sign with the current. Rotation is “set previous to old, set current to new, redeploy, remove previous a day later.”

## Fairness the code has to guarantee

- Same snapshot bytes of prompt, starter, and options for both seats. The test inserts a match and projects it as both users.
- Receive time, not judge time, is `t` in the score.
- `internal_error` does not increment wrong attempts and does not consume a choice submit. For a choice round the grade is local and `internal_error` should be unreachable. If the transaction fails, the client retries the same idempotency key.
- Sample runs never call the scoring function.
- The finalize transaction is the only rating writer. Search the code for `rating` assignments in review.

## Abuse limits that are out of scope

- Two people in the same room talking. The product cannot stop that in a lobby, and a lobby is unrated, so the damage is a practice session.
- A second account. Email verification, when enabled, raises the cost. It does not stop it. Device fingerprinting is not part of this build. Do not add a hidden tracker “for cheat detection.”
- Plagiarism of problem statements by players. Setters write original problems.
- A kernel exploit out of the container. Named honestly in the judge doc. The follow-up is gVisor, not a claim that the current flags are magic.

## Disclosure

`SECURITY.md` at the repo root tells a reporter to mail the internal guide and the repo owner rather than opening a public issue with exploit detail. The sandbox controls are public in this repo on purpose, so the team can implement them. The production host name, the admin email, and any real problem’s hidden tests are not.

## Dependency hygiene

pnpm lockfile committed. `pnpm audit` in CI. A high-severity advisory fails the pipeline unless the pull request documents why it cannot be upgraded yet. Language images are rebuilt monthly so the base digest moves. That rebuild is a calendar reminder in the delivery doc, not an automatic production push.
