---
name: deflake
description: >-
  Confirm, reproduce, diagnose and fix a flaky Go test — one that fails
  intermittently, passes on rerun, is red in CI but green locally, or silently
  skips. Use when the user says "flaky test", "de-flake the tests", "this test
  is flaky", "CI is red but it passes locally", "it passed on rerun", "why does
  this test skip", or when a CI failure reproduces only some of the time. Also
  covers the repetition-loop measurement, `-race`/`-shuffle` triage, and the
  no-quarantine policy.
---

# De-flake a test

A flake is a **rate**, not a yes/no. Turn "it sometimes fails" into a number,
find the cause behind that number, prove the number went to zero.

`worktree-first` puts you in a worktree — one worktree and one PR per flake,
never a batch. `ship-pr` owns the commit/PR half. `repro-test-first` owns
writing a test for a *product* bug. This skill owns confirm → reproduce →
diagnose → verify.

## 1. Confirm it is a flake

Three different things get called flaky:

| Signal | It is |
|---|---|
| Same SHA, one run red and a rerun green | a real flake |
| Red on every run of that SHA, green on the parent | a real bug — go fix the code |
| `docker compose up` / runner / network step failed | infra, not the test |

The confirming evidence is two conclusions on **one commit**:

```bash
gh run list --commit "$SHA" --json databaseId,name,conclusion,createdAt
gh run view <id> --log-failed          # the actual failure, not the summary
gh run rerun <id> --failed             # then compare conclusions
```

Read the failure text before rerunning. A `panic: send on closed channel` or a
`DATA RACE` block is a real concurrency bug surfacing intermittently — a code
fix, not a test fix.

## 2. Get a rate

```bash
~/.claude/skills/deflake/scripts/flake-rate.sh ./pkg/synthesizer/ TestName 50
```

N fresh `go test` processes, a failure percentage, and every failing run's
output kept on disk. Flags: `--race`, `--shuffle`, `--count N`, `--p N`,
`--parallel N`, `--cpu 1,4`, `--short`, `--stop-on-fail`, `--log-dir`, `-v`.
Pass `-` instead of a test name to run the whole package.

Climb the ladder and **stop at the first rung that turns it red** — that rung
names the cause:

1. plain repetition, 20–50× — internal nondeterminism (timing, map order, scheduling).
2. `--count 20` (repeats inside one process) — state leaking between iterations.
3. `--race` — unsynchronised shared memory. Run it even when the others are green.
4. `--shuffle` — depends on another test having run first; the seed is printed.
5. `--p 1` vs `--p 4`, `--cpu 1,4` — a shared port, tempdir, env var, or a
   timing assumption that only holds on an idle box.

Reproduce what CI runs. orchestrator's `.github/workflows/test.yaml` runs
`go test -count=1 -short -timeout 600s -p 4 ./...` on a self-hosted
`orchestrator-runner`, so `--short --p 4` is the faithful repro — and anything
guarded by `testing.Short()` never runs there at all.

## 3. The cause, and the fix for it

| Symptom | Cause | Fix |
|---|---|---|
| Passes alone, fails on a loaded box | `time.Sleep` as a synchronisation primitive (318 of them across orchestrator's tests) | `require.Eventually` with a deadline, a done-channel handshake, or a `synctest` bubble |
| Timing assertions off by milliseconds | real wall clock | `synctest.Test(t, ...)` + `synctest.Wait()` — Go 1.26, stable, **no build tag**; or inject a `now func() time.Time` |
| `WARNING: DATA RACE` | unsynchronised goroutines | fix the sharing (`sync.Mutex`, `atomic`, channel ownership) — never paper over it with a sleep |
| Fails only in a full-package run or under `-shuffle=on` | package-level state one test leaves for another: registries, singletons, metrics, `init()` | per-test fixture + `t.Cleanup` to restore; see `pkg/synthesizer/test_hooks.go` for the atomic-gated hook pattern |
| Assertion order varies | map iteration, unordered slices | `assert.ElementsMatch`, or sort before comparing |
| `connection refused`, DNS, timeouts | a real network call | use `fakes/faketranscriber`, `fakes/fakellm`, `go.uber.org/mock`, or `httptest` |
| `panic: Log in goroutine after Test has completed` | a goroutine outlived the test and wrote to `zaptest.NewLogger(t)` | make the test wait for the goroutine to exit; this fails the *next* test, so the reported test is usually innocent |
| Port / tempdir collision under `-p 4` | hardcoded `:8080`, fixed paths | `net.Listen(":0")`, `t.TempDir()` |
| Leaked goroutines from a prior test | no shutdown handshake | orchestrator has no `goleak` dependency — use the `ttsConnRegistry` style check in `test_hooks.go`, or add `goleak` in its own PR |

**`t.Context()`, never `context.Background()`** — the most common cause in these
repos, so grep the failing package first
(`grep -rn 'context.Background()' --include='*_test.go' pkg/synthesizer/`).
`t.Context()` is cancelled when the test ends, so the goroutines it spawned
stop; `context.Background()` lets them run past the test into the next one,
where they trip the zaptest panic above or corrupt shared state.

## 4. Skips are not passes

A skip is a green check over zero coverage. When asked why a test skips, or when
one "passes" suspiciously fast:

```bash
go test ./pkg/X/ -run 'TestName' -v | grep -E 'SKIP|no test files|no tests to run'
go list -f '{{.Dir}} ignored={{.IgnoredGoFiles}}' ./pkg/... | grep -v 'ignored=\[\]'
```

Three ways a test disappears, all live in orchestrator today:

- **Env-guarded** — `t.Skip("Skipping test as INTEGRATION_TEST is not set")`,
  `t.Skipf("Toxiproxy server not available")`. CI never sets these, so the test
  is dead there. Wire the dependency into CI or say so out loud.
- **A stale build tag** — `pkg/telephony/mediabridge/warmtransfer/room_manager_node_test.go`
  still carries `//go:build goexperiment.synctest`. `synctest` graduated in Go
  1.25 and the repo is on 1.26, so `GOEXPERIMENT` is unset and `go list` reports
  the file in `IgnoredGoFiles` — it has not compiled in months. Delete the tag.
- **`testing.Short()`** — CI passes `-short`, so those bodies never run in CI.

Report a skip as broken coverage, not as a pass.

## 5. Fix, don't quarantine

Deleting the assertion, adding a retry, or lengthening the sleep are not fixes —
they hide the rate. orchestrator already carries 23 quarantined tests
(`t.Skip("pending test - skipped")`, `"skipping because data race"`,
`"skipping because broken"`) with no owner and no ticket. Do not add the 24th.
`t.Skip` is acceptable only with a filed Linear ticket and a named owner, in the
skip message itself:

```go
t.Skip("ENG-4321: flaky under -p 4, owner @tommoulard, quarantined 2026-08-28")
```

Ask before quarantining. It is a decision the user makes, not you.

## 6. Verify, then ship

Re-run the **same** command at the **same** N that produced the original
failure — a 4% flake needs 50 iterations to show it is gone, 5 green runs prove
nothing.

```bash
flake-rate.sh ./pkg/synthesizer/ TestName 50 --race      # before: 12.0% failing
flake-rate.sh ./pkg/synthesizer/ TestName 50 --race      # after:  clean over 50
```

Put both numbers in the PR body, with the exact flags and the rung that caught
it, then hand off to `ship-pr`: one flake, one PR, the diagnosis in the commit
message. A `flaky-test radar` job may later feed candidates here — treat what it
reports as an unconfirmed claim and start again at step 1.
