# Judge and sandbox

Rounds 2 and 3 never reach this subsystem. Rounds 1 and 4 always do. Sample runs and graded runs share one queue and one sandbox implementation. Graded jobs are preferred: the BullMQ priority of a graded job is higher than a sample job.

## Job payload

```json
{
  "submissionId": "uuid",
  "language": "python",
  "source": "print(1)\n",
  "compile": null,
  "run": "python3 -I /work/main.py",
  "sourceFile": "main.py",
  "timeLimitMs": 2000,
  "memoryLimitKb": 131072,
  "tests": [{ "ordinal": 1, "visibility": "sample", "input": "1\n", "expectedOutput": "1\n" }]
}
```

The worker loads this from PostgreSQL by `submissionId` at execution time. The BullMQ payload is only `{ "submissionId": "..." }`. Source and tests are not placed in Redis. Redis is not a place for hidden tests.

## Images

One image per language, built from a Dockerfile the backend repo will contain when implementation starts. Pin the base image by digest in production. Tags are allowed on a developer machine.

| Image | Base | Extra packages | User |
| --- | --- | --- | --- |
| `codearena-lang-c` | `gcc:13` | `coreutils` for `timeout` | `runner` uid 10000 |
| `codearena-lang-cpp` | `gcc:13` | same | same |
| `codearena-lang-python` | `python:3.12-slim` | none | same |
| `codearena-lang-javascript` | `node:22-bookworm-slim` | none | same |

The image’s entrypoint is a script `/opt/arena/run.sh` that:

1. Refuses to run if any argument is missing.
2. Does not read secrets from the environment. The worker passes no environment except `PATH` and `HOME=/tmp`.
3. Compiles if a compile command was given, with `timeout` wrapping it, writing the binary to `/tmp/main`.
4. Runs the program with stdin from a pipe the worker owns, stdout and stderr captured by the worker, not written to a world-readable file.
5. Exits with the program’s status, or a dedicated status the worker maps: 124 from `timeout` means time limit.

Do not install git, curl, wget, package managers’ extra indexes, or a shell history. `python:3.12-slim` is already more than the player needs. Do not mount a package cache.

The worker pulls these images on boot and fails its readiness check until the pull succeeds. It never pulls during a match.

## Container contract

Every run, compile included, uses a new container. The container name is `ca-{submissionId}-{phase}` where phase is `compile` or `test-{ordinal}`. Before creating it, `docker rm -f` that name so a retry cannot collide.

Flags, all of them, every time:

```text
--rm
--network none
--read-only
--cap-drop ALL
--security-opt no-new-privileges:true
--security-opt seccomp=/opt/arena/seccomp.json
--pids-limit 64
--memory {memoryLimitKb}k
--memory-swap {memoryLimitKb}k
--cpus 1
--user 10000:10000
--tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m
--workdir /work
--name ca-{submissionId}-{phase}
```

Mount the source directory read-only at `/work`. That directory contains only the one source file. It does not contain the expected output, the tests, or another student’s files. The worker writes the source to a fresh directory under the worker’s data dir with mode `0755` on the directory and `0644` on the file, owned so uid 10000 can read it. Delete that directory in a `finally` block.

Stdin is the test input, piped. Stdout is capped at `stdoutBytes` (256 KiB). If the process writes more, kill it and use verdict `output_limit`. Stderr is capped at `stderrBytes` (8 KiB) and the extra is discarded. Stderr is returned to the owner on `compile_error` and `runtime_error` only. It is never sent to the opponent.

`--memory-swap` equal to `--memory` disables swap. A process that hits the cgroup limit is verdict `memory_limit` (Docker exit 137 combined with OOMKilled true). Exit 137 without OOMKilled is `runtime_error` unless the worker itself called `docker kill` because the wall clock fired, in which case the verdict is `time_limit`.

The wall clock the worker enforces is `timeLimitMs + 1000` for a run and `compileTimeoutMs` (10 seconds) for a compile. The inner `timeout` uses the same budget. The outer kill exists because a process can ignore the inner timer if it is stuck in uninterruptible sleep. The worker’s kill is the one that counts.

CPU is one core. `pids-limit` 64 stops a fork bomb from creating enough processes to hurt the host. `/tmp` is `noexec` so a compile must write the binary and the kernel must be allowed to execute it. `noexec` on `/tmp` conflicts with compiling to `/tmp/main`.

Resolve that conflict this way: `/tmp` is `exec`, not `noexec`, size 64m, `nosuid`, `nodev`. The root filesystem stays read-only. There is no other writable executable mount. Document the exception in the Dockerfile comment so nobody “hardens” it back to `noexec` and breaks C and C++.

Python and Node do not need an executable `/tmp`. They still get the same mount so the flag list has one shape. Their images do not have a compiler.

## Seccomp

Start from Docker’s default profile and remove `socket`, `connect`, `bind`, `listen`, `accept`, `ptrace`, `personality`, and the mount family. Network is already disabled by `--network none`. Seccomp is the second layer, not the excuse to drop `--network none`.

Ship the profile as `sandbox/seccomp.json` in the backend repo when that repo is implemented. A submission that dies with `EPERM` on a normal `read` or `write` of stdin/stdout is a profile bug, verdict `internal_error`, and it does not charge the player. Add a fixture program that only reads stdin and writes stdout to CI. That fixture must pass under the profile.

## Comparison

Comparison runs in the worker, in TypeScript, after the container is gone.

```text
normalize(s):
  replace CRLF and bare CR with LF
  remove trailing spaces and tabs on each line
  if the string ends with a single LF, that LF is optional
  do not strip leading whitespace
  do not lowercase
  do not parse numbers

a test passes when normalize(stdout) == normalize(expected)
```

No floating-point tolerance. No token mode. If the author’s expected output uses a different rule, the author’s expected output is wrong and must be edited.

Verdict for one test:

| Observation | Verdict |
| --- | --- |
| Compile command exit non-zero | `compile_error` and skip all tests |
| Timed out | `time_limit` |
| OOMKilled | `memory_limit` |
| Stdout exceeded the cap | `output_limit` |
| Exit status non-zero | `runtime_error` |
| Normalized stdout differs | `wrong_answer` |
| Normalized stdout matches | pass |

Overall verdict is `accepted` only when every test that was supposed to run passed. If a sample fails, overall is that sample’s verdict and hidden tests are not run. If samples pass and a hidden test fails, overall is that hidden test’s verdict. `tests_passed` counts hidden tests that passed. `tests_total` counts hidden tests. On a sample failure both numbers are 0 and `tests_total` is still the hidden count, so the UI can say `0 / N` without implying the hidden tests ran.

`submission_tests` stores one row per test that actually ran. For hidden rows, `stdout_excerpt` is null. For sample rows, `stdout_excerpt` is the first 500 characters of normalized stdout so the owner can see what they printed. Expected output is never copied into `submission_tests`.

## Quotas and priorities

- Queue name: `judge`.
- Graded priority: 1. Sample priority: 10. BullMQ treats a lower number as more important.
- Worker concurrency: 2 on the 4 vCPU VPS. Each job runs tests sequentially, not in parallel containers, so one submission cannot take every core.
- Job attempts: 2. The second attempt happens only when the worker caught an infrastructure error (daemon down, image missing, container failed to start). A real `wrong_answer` is not retried.
- Job timeout in BullMQ: compile budget + tests × (run budget + 1 second) + 5 seconds.

## What the player sees

| Verdict | Owner sees | Opponent sees |
| --- | --- | --- |
| `accepted` | Accepted, tests `N/N`, score if counted | Status correct, tests `N/N`, no source |
| `wrong_answer` | Wrong answer, and the sample diff if a sample failed | Status wrong, tests `k/N` |
| `compile_error` | Compiler stderr, truncated | Status wrong |
| `runtime_error` | Non-zero exit, stderr truncated, no hidden input | Status wrong |
| `time_limit` | Time limit on sample or “on a hidden test” | Status wrong |
| `memory_limit` | Memory limit | Status wrong |
| `output_limit` | Output limit | Status wrong |
| `internal_error` | “The judge failed. This attempt was not counted.” | Nothing |

The opponent never sees stderr. Stderr can echo the source.

## Authoring rules the setter API enforces

Before `is_published` can become true, a code problem must have:

- `starter_code` non-empty and within `sourceBytes`
- 1 to 3 sample tests and 3 to 20 hidden tests
- each input and expected output within `stdoutBytes`
- `time_limit_ms` and `memory_limit_kb` inside the caps in `constants.json`
- a reference run recorded: the setter submits a reference solution through `POST /setter/problems/{id}/reference-run`, the worker runs it as a normal sandbox job against all tests, and the problem stores `reference_passed_at` only if every test passes

`problems.reference_passed_at` is already in `contracts/schema.sql`. It stays null on drafts and on choice problems. The publish transition sets nothing by itself. It refuses a code problem whose `reference_passed_at` is null.

Choice problems publish only when `options` has length 4, every id is unique, every text is non-empty and within `optionTextMaxBytes`, and `correctOptionId` equals one of the ids. They do not require a reference run.

## Host hardening on the VPS

- AppArmor or the Docker default seccomp plus our profile.
- The worker user is in the `docker` group and in no other privileged group. Prefer a rootless Docker or a dedicated dockerd if the operator knows how to run it. If the team uses rootful Docker, say so in the deployment notes and do not pretend it is rootless.
- `ufw` allows 22, 80, and 443 only.
- No student container is started with `--privileged`, a host pid namespace, a host network, or an extra volume.
- Log the submission id and the verdict. Do not log the source or the hidden input at info level. A debug flag `LOG_SUBMISSION_SOURCE=true` may log source on a developer machine and must be false in production.

## Known limits

A container is not a perfect jail. A kernel exploit escapes it. The production mitigation on this project’s budget is: unprivileged user, no network, no capabilities, short life, cgroup limits, and the worker being the only process that can start containers. The upgrade is gVisor behind the same `Sandbox.run` interface. Do not block the semester on gVisor. Do not describe the default Docker setup as “fully secure against a hostile kernel exploit” in the report. Describe the controls that are actually on.
