---
name: repro-test-first
description: >-
  Reproduce a bug with a failing test before fixing it, and prove the test
  actually fails first. Use whenever the user asks for "a UT that reproduces the
  issue", "put that into evidence", a repro or regression test — and by
  default on ANY bugfix, including a production defect that came out of a call
  investigation, even when they only say "fix it". Covers picking the layer
  (unit / integration / E2E), faking dependencies, the Go test rules for these
  repos, and landing the test and the fix as two separate commits.
---

# Repro test first

A test written after the fix proves nothing. The only artifact that proves a bug
existed is a test that **failed before the change and passes after**. Everything
below exists to produce that evidence.

Touching code? `worktree-first` puts you in a worktree first. Committing and
opening the PR? That is `ship-pr`. Building behavior that does not exist yet
rather than fixing shipped code? That is `tdd`. This skill owns only the
test-then-fix loop.

## 1. The loop — hard sequence, no reordering

1. Write the test asserting the **correct** behavior (not today's behavior).
2. **Run it and show the real failure output.** Paste the actual `--- FAIL` /
   panic block from the run.
3. Fix the production code. Do not touch the test.
4. Run the *same* command again; show it passing.
5. Run the whole package, then the wider suite, to prove nothing else broke.

Step 2 is the point of the skill. **If the test passes before the fix, it is not
a repro** — the assertion is wrong, or it is at the wrong layer, or the bug is
not where you think. Say so and go back to step 1. Never soften or rewrite the
test after the fix to make it green, and never report a red-then-green you did
not actually observe.

## 2. Pick the narrowest layer that can exhibit the bug

| Bug lives in | Test |
|---|---|
| pure logic, mapping, parsing, ordering | unit, table-driven, same package |
| node / state-machine / latch behavior | unit with fakes for the I/O edges |
| wiring between packages | `_test` package (`package llm_test`) |
| needs LiveKit / Qdrant / Deepgram | integration, gated + skipped by default |
| needs a real phone call | gatekeeper E2E — **last resort** |

```bash
# orchestrator: one test, cache defeated
source .env && go test -run 'TestGetChosenIntent_LatchesIVROffAfterHumanHandoff' ./pkg/llm/ -count=1
# orchestrator integration: env-gated (see pkg/llm/groq_integration_test.go)
source .env && INTEGRATION_TEST=true go test ./pkg/transcriber/user_track/integration_test -count=1
# conductor integration: build tag
go test -tags=integration ./internal/e2e -run TestCallerAgentPullFrameAppliesPrecisePlaybackPause -count=1
# the wide check before you call it done
source .env && go test -race -count=1 -short -timeout 600s -p 4 ./...
make lint test-unit
```

Do not jump to gatekeeper because a unit repro is fiddly. It places real calls,
costs money and minutes, and is flaky evidence for a deterministic defect.

## 3. Go rules — these are the user's own corrections

- **`t.Context()`, never `context.Background()` / `context.TODO()`** in a test.
- **Failures surface directly.** `require`/`t.Fatalf` at the failure point. No
  `if err != nil { t.Log(err) }`, no error swallowed into a bool, no assertion
  inside a goroutine the test never joins.
- **`-count=1` whenever checking a repro** — the test cache will happily hand
  back a stale PASS and destroy the evidence.
- **`-race`** for anything concurrent; without it the race is not a failure.
- **Table-driven for pure logic** — `tests := []struct{ name … }`, `t.Run`,
  `t.Parallel()`. House idiom: `pkg/llm/model_mapping_test.go`.
- testify: `require` for preconditions, `assert` for the assertions after.
- **No `time.Sleep`.** Timing-dependent behavior goes in
  `synctest.Test(t, func(t *testing.T) { … })` — see
  `pkg/llm/node_synctest_test.go`, `pkg/transcriber/base_callback_test.go`.
- Read two neighbouring `_test.go` files in the target package before writing
  and match them: helper constructors (`newTestSetup`), fixtures, naming.
- Name the test for the behavior, and put the evidence in the doc comment — call
  UUID, ticket, and what RED looks like. Model: the header comment on
  `TestGetChosenIntent_LatchesIVROffAfterHumanHandoff` in
  `pkg/llm/ivr_latch_test.go`.

## 4. Faking dependencies

- Introduce the **narrowest interface at the consumer** — only the methods the
  code under test calls, declared in the consuming package. Example:
  `Generator` in `pkg/rag/retriever.go`.
- **Generate the mock, don't hand-write it,** and keep it next to the interface.
  orchestrator already uses both `mockgen -typed` (→ `fake_act_on.go`,
  `mocks/`) and counterfeiter (→ `fakes/fakellm/`), each declared by a
  `//go:generate` line above the interface. Add the directive, then
  `go generate ./pkg/llm/...` or `make generate`.
- **Do not introduce a new mocking framework** into a repo that doesn't use one.
  A hand-rolled struct with func fields is fine for a one-off in a package with
  no generated mocks.
- Faking a concrete client (bert, retriever, transcriber) is the usual unlock
  for turning "needs a live service" into a unit test — do that before reaching
  for the integration suite.

## 5. When the bug came from a production call

The repro's inputs are the **real** transcript, turn timings and agent config —
`call-forensics` pulls them from the portal/logs. Never invent a plausible
transcript. Put the call UUID and the portal link in the test's doc comment,
and drop bulky real payloads in `testdata/`.

## 6. When a repro genuinely isn't reachable

First exhaust: `synctest` for clock/ordering, `-race -count=100` for a flake, an
internal test package (`package llm`) to reach unexported state, a fake at the
provider boundary.

If it is still out of reach — provider-dependent, needs real audio, a race you
cannot pin — **tell the user plainly**: "I could not reproduce this in a test
because X." Then offer what you can: an assertion on the log line or metric the
fix emits, a targeted gatekeeper check, or a narrowed unit test for the piece
that *is* deterministic. Writing a test that asserts the fix's own
implementation and calling it a repro is worse than having no test.

## 7. Two commits

The test and the fix land separately so a reviewer can check out the test commit
and watch it fail:

```
test(ENG-1234): failing repro for DTMF pressed at human after IVR handoff
fix(ENG-1234): latch IVR off once a human has picked up
```

Hand the rest — push, PR body, review — to `ship-pr`.
