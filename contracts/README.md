# Contracts

These files are the part of the spec a program can check.

| File | Wins on |
| --- | --- |
| `constants.json` | Durations, caps, penalties, rating constants, language ids |
| `schema.sql` | Tables, columns, checks |
| `openapi.yaml` | HTTP paths and JSON names |
| `problem-pack.example.json` | The import body setters and local seed use |

WebSocket payloads live in `docs/07-realtime.md` because AsyncAPI would be a second document to keep in sync before any code exists. When a generator is introduced, generate it from that doc’s examples rather than inventing event names in the client.

`docs/02-decisions.md` records why the product is this shape. It is not a second rulebook.
