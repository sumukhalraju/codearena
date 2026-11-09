# Contributing

## Where a change goes

| Change | Repository |
| --- | --- |
| A rule, a score, a route, a column, a timer | `codearena` (this repo) first |
| A screen or client behavior that the spec already describes | `codearena-frontend` |
| A handler, a query, the judge, a migration that matches `schema.sql` | `codearena-backend` |

Do not implement a behavior that the parent docs do not describe. Add the behavior to the docs, get it reviewed, then implement it.

## Branches

- `main` is releasable.
- Feature branches are `feat/short-name`, fixes are `fix/short-name`.
- Open a pull request. One other teammate reviews it.
- No force-push to `main`.

The parent `main` moves when the spec moves. Pin the submodules to the child commits that implement the spec you just merged. A submodule pin is its own small commit.

## Commits

Say what changed and why, in a sentence. `feat: freeze problems that are already in a live match` is enough. Do not commit `.env` files, dumps, or real hidden tests from a future graded assignment if the guide wants those private. The example pack in `contracts/` is fake and is fine.

## Pull request

Use the template. If the pull request changes a number, link the line in `contracts/constants.json`. If it changes a player-visible field, link `contracts/openapi.yaml` or `docs/07-realtime.md`.

## Definition of done

- The spec and the code agree, with the spec merged first.
- The tests named in `docs/13-testing.md` for that area exist and pass.
- A player still cannot see hidden tests or the opponent’s source during a round. If you touched projections, you ran that test.

## Local data

`docs/17-local-dev.md`.
