---
name: tdd
description: >-
  Build new behavior test-first in Go — red before green, one vertical slice per
  cycle. Use whenever the user says "TDD", "test-first", "test driven",
  "red-green", "write the test first", "let's do this with tests", asks for a
  new function/endpoint/node "with tests", or asks where a test belongs, what
  the seam is, or whether a test is any good. Also use it unprompted before
  implementing a new capability in a Go repo. Covers proving RED in a language
  where a missing function is a build error, choosing the seam, the
  anti-patterns (implementation-coupled, tautological, horizontal slicing,
  mock theatre) and the exact `go test` commands. For a bug that already exists
  in shipped code, use `repro-test-first` instead.
---

# TDD in Go

A test written after the code documents whatever the code happens to do. A test
written first is a **specification you agreed to before you had a stake in the
implementation** — that is the whole value, and it evaporates the moment you
write the test to fit code you have already written.

The loop is red → green. Refactoring is a separate, later activity with its own
skill.

Touching code? `worktree-first` puts you in a worktree first. Committing and
opening the PR? `ship-pr`. Fixing a defect that already exists? `repro-test-first`
— that skill's job is evidence a bug existed; this one's job is a spec for
behavior that does not exist yet. Test fails intermittently? `deflake`.

## 1. The cycle

One cycle produces one **vertical slice**: one observable behavior, tested and
implemented end to end. Not one layer, not one file — one thing the caller can
now do.

1. Name the behavior in a sentence. That sentence becomes the test name.
2. Write the test against the API you *wish* existed.
3. **Get to a real RED** (§2) and read the failure message.
4. Implement the least code that makes it pass. Nothing speculative.
5. Run the package, then the wide check (§7).
6. Next slice.

Do not run ahead. Two cycles of work in one cycle means the second test was
written against code you had already built — which is just testing after the
fact with extra ceremony.

## 2. Proving RED — the Go wrinkle

In Go a test for a function that does not exist yet **does not compile**, and a
build failure is not a red test. It proves you typed a name; it says nothing
about your assertion. So the first cycle has an extra beat:

```bash
# 2. write the test, run it → build failure. Expected, not informative.
source .env && go test -run 'TestPacer_HoldsFirstChunkUntilBudget' ./pkg/synthesizer/ -count=1
# ./pacer_test.go:19:12: undefined: NewPacer

# 3. add the smallest stub that compiles: real signature, zero-value return.
# 4. run again → a real assertion failure with got/want. THIS is red.
#     --- FAIL: TestPacer_HoldsFirstChunkUntilBudget
#         pacer_test.go:24: expected first chunk released after 120ms, got 0s
```

Read that message as if it arrived in a bug report. If it does not describe the
missing behavior in plain words, the *test* needs work — fix it before you
implement, because this message is what a future reader gets at 2am.

`-count=1` on every run. The test cache will hand back a stale PASS and quietly
destroy the evidence.

Never report a red-then-green you did not actually observe, and never edit the
test after green to make it pass. If a test passes against the zero-value stub,
the assertion is not asserting anything — say so and rewrite it.

## 3. The seam — decide it out loud, before writing

A seam is the boundary where the behavior is observable **without looking
inside**. Pick the narrowest one that can express the behavior, and state your
choice in one line before writing code: *"I'll test this at `Pacer.Next` in
`package synthesizer_test`, faking the `ConnectionAdapter`."* If that is the
wrong seam, correcting it costs the user a sentence instead of a rewritten
suite.

| The behavior is | Seam | Package |
|---|---|---|
| pure logic: mapping, parsing, ordering, budget maths | the exported function | same package, table-driven |
| a type's state machine / latch / lifecycle | exported methods, observed via return values or exported accessors | same package |
| a feature that spans packages, or a new public API | the owning package's entry point | `package x_test` — proves the API is usable from outside, which is the point |
| an HTTP or gRPC handler | the handler via `httptest` | `package x_test` |
| needs LiveKit / Qdrant / Deepgram / a provider | a fake at the client interface | unit; integration only for the wiring itself |

orchestrator has 12 files in `package llm_test` and 9 in `package synthesizer_test`
— an external test package is normal here, not exotic. Reach into the internal
package only when the behavior genuinely has no exported observation, and say
why in a comment. More often that is a signal the thing you want to observe
should be part of the API.

## 4. What a good test looks like

- **The name is the spec.** `TestGetChosenIntent_LatchesIVROffAfterHumanHandoff`
  tells you the rule without opening the file. `TestGetChosenIntent2` does not.
  Subtests get lowercase sentences: `"holds the chunk when the budget is unmet"`.
- **Arrange the caller's world, assert the caller's observation.** If a test's
  assertions would survive a full rewrite of the internals, it is testing
  behavior. If they would not, it is testing today's code.
- **Expected values come from outside the code under test** — a literal, a
  worked example, a spec, a recorded real payload in `testdata/`. Never
  recomputed by the same helper, format string or map the implementation uses.
- **Table-driven, grown one row at a time.** The table is the accumulated spec
  after N cycles, not a plan written upfront. House idiom:
  `pkg/llm/model_mapping_test.go`.
- Read two neighbouring `_test.go` files in the target package first and match
  them — helper constructors (`newTestSetup`), fixtures, naming. A test that
  looks foreign in its package gets rewritten by the next person.

## 5. Anti-patterns, as they appear in a Go diff

| In the diff | Why it rots | Instead |
|---|---|---|
| `mock.EXPECT().Fetch(gomock.Any()).Times(1)` as the *only* assertion | asserts the code called a collaborator — i.e. asserts its own implementation. Every refactor is a red test with no bug. | assert the value or effect the caller observes; keep the mock as a stub |
| test reads an unexported field, or calls an unexported func, to check state | couples the test to the layout of the struct | assert at the exported surface, or make the observation part of the API |
| expected value built by calling the code under test, or reusing its map / `fmt` string / constant | tautology: passes by construction, would pass if the logic were inverted | independent literal or `testdata/` fixture |
| `assert.Contains(err.Error(), "budget")` | couples to prose; a reworded message is a failure | sentinel error + `require.ErrorIs`, or `errors.As` for typed errors |
| a 12-row table landed before any implementation | tests imagined behavior; you discover half the rows were wrong *after* writing them | one row per cycle |
| a golden file regenerated with `UPDATE_GOLDEN=1` to get green | records whatever the code did, including the bug | read the diff and justify every line before accepting it; goldens are for large structured output you actually review (`pkg/graph_flow/engine_test.go`) |
| assertions on log lines or emitted spans standing in for behavior | logs are not a contract | assert the behavior; keep log assertions as a supplement, never the only check |

## 6. Go rules of the loop

These are the user's own standing corrections — a PR that breaks them comes back.

- **`t.Context()`, never `context.Background()` / `context.TODO()`** in a test.
  `t.Context()` is cancelled at test end, so the goroutines it spawned stop
  instead of leaking into the next test.
- **`t.Parallel()` in every test and every subtest.** `paralleltest` and
  `tparallel` are enabled in `.golangci.yml`; omitting it fails `make lint`.
- **Failures surface at the failure point.** `require` for preconditions,
  `assert` for the assertions after. No `if err != nil { t.Log(err) }`, no error
  swallowed into a bool, no assertion inside a goroutine the test never joins.
- **`-race`** for anything concurrent; without it the race is not a failure.
- **No `time.Sleep`.** Timing behavior goes in
  `synctest.Test(t, func(t *testing.T) { … })` — Go 1.26, no build tag. Models:
  `pkg/llm/node_synctest_test.go`, `pkg/transcriber/base_callback_test.go`.
- Fakes: declare the **narrowest interface at the consumer** — only the methods
  the code under test calls, in the consuming package — then *generate* the
  mock next to it with a `//go:generate` line and `make generate`. The repo
  already uses `mockgen -typed` (`pkg/llm/act_on_intent.go` → `fake_act_on.go`)
  and counterfeiter (`fakes/fakellm/`). Do not introduce a third framework; a
  hand-rolled struct with func fields is fine in a package that has neither.

## 7. Green means the suite is green

```bash
source .env && go test -run 'TestName' ./pkg/x/ -count=1        # the slice
source .env && go test ./pkg/x/ -count=1 -race                  # the package
source .env && go test -race -count=1 -short -timeout 600s -p 4 ./...   # what CI runs
make lint test-unit
```

A slice is not done until the package is green, and the feature is not done
until the wide check is. `make test-unit` is `go test -timeout 90s ./...` with
`.env` exported; CI adds `-short -p 4`, so anything behind `testing.Short()`
never runs there.

## 8. Refactor after green, not during

Keep red-green tight: while a test is red, the only edit that is allowed is the
one that makes it pass. Refactoring under a red test means you cannot tell which
change broke what.

Once green, the tests are the safety net that makes cleanup safe — and `simplify`
/ `code-review` own that pass. Run it at the end of the feature, or per slice if
the design is drifting, but as its own step with its own green run.

## 9. Landing it

One commit per slice keeps the story readable — `feat(pacer): hold the first
chunk until the budget is met`, test and implementation together, since for new
behavior the test is not standalone evidence the way a bug repro is. Split
differently if the user asks. `ship-pr` owns the commits, the push and the PR
body; put the seam you chose and the slices you cut in the description so the
reviewer starts where you started.
