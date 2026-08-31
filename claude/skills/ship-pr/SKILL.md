---
name: ship-pr
description: >-
  Turn finished work into logically separated, signed commits, push the branch,
  and open the pull request. Use whenever the user says "open/create/prepare a
  PR", "with proper commits", "do proper commits", "commit and push", "commit
  this", "open a draft PR", "mark the PR as ready", "update the PR
  description", or "review everything before publishing" — and at the end of
  any implementation session whose work is meant to land as a PR rather than a
  local merge. Also covers splitting one dirty tree into several commits, and
  splitting one task into several PRs.
---

# Ship a PR

The wrap-up half of a session. Commits carry the reasoning, the PR body carries
the evidence.

## 1. Before you commit

Branching is `worktree-first`'s job — read
`~/.claude/skills/worktree-first/SKILL.md` and follow it, don't re-derive it.
The usual case here is the easy one: the work already sits in a worktree.

```bash
git rev-parse --show-toplevel && git branch --show-current && git status --short
```

Edits left in the *main* checkout can't follow you into a worktree — ask before
moving them (worktree-first §1). Read the repo's `CLAUDE.md` / `AGENTS.md`
first; several carry their own commit and test rules.

## 2. "Proper commits"

One concern per commit. Each commit builds, and its body says *why*.

- **A revert and the change that follows it are always two commits.** Never one.
- **Refactor separate from behaviour change**, refactor first, labelled "no
  behaviour change".
- Test separate from fix is fine; the repro-test-first flow may pair them — see
  the `repro-test-first` skill, and say in the PR which you did.
- Generated code, `gofmt`-only churn and dependency bumps get their own commit.

Splitting an already-dirty tree — no `git add -p` here, no TTY for interactive
git:

```bash
git status --short                        # inventory first
git add pkg/llm/node.go pkg/llm/flush.go  # pathspec staging, one concern
git commit -m "refactor(llm): extract flushUninterruptibleTurnLocked"
go build ./... && go test ./pkg/llm/      # every commit stands on its own
```

Two concerns tangled in **one file**: park the diff, rebuild concern #1 by
editing, commit, restore the rest.

```bash
git diff -- pkg/llm/node.go > /tmp/split.patch
git checkout -- pkg/llm/node.go
# edit the file down to concern #1, commit it, then:
git apply --3way /tmp/split.patch
```

**Subjects** are conventional commits matching the branch type:
`<type>(<scope>): <imperative, lowercase, no period>`, ≤72 chars. Types
`feat | fix | refactor | chore | docs | test`, plus `perf` for latency work.
Scope is the package or area (`rag`, `tts`, `llm`, `conversation`, `stt`,
`transcriber`) **or** the ticket when the ticket is the frame —
`fix(ENG-6686): play the RAG preamble before the lookup`. Otherwise the ticket
goes in a `Refs: ENG-6686` trailer.

**Every commit is signed, and it happens automatically** — `commit.gpgsign=true`
is set globally, so no flag is needed and none should be added. Signing is
**OpenPGP** (`gpg.format=openpgp`) with key `20E4E2219305D1CD`
(`Tom Moulard <tom.moulard@synthflow.ai>`, ed25519, no expiry), via gpg-agent.

A commit that fails on signing means gpg-agent could not produce a signature —
usually a pinentry prompt that never reached a TTY. Export `GPG_TTY=$(tty)` and
retry once; if it still fails, say so and stop. **Never** route around it with
`--no-gpg-sign`, and never leave an unsigned commit on a branch that will be
pushed. Verify with `git log --show-signature -1` — you want
`Good signature from "Tom Moulard"`.

If GitHub shows a commit as *Unverified* while the local signature is good, the
public key is missing from the account, not broken locally:
`gh auth refresh -h github.com -s admin:gpg_key` then
`gh api -X POST user/gpg_keys -f armored_public_key="$(cat ~/.claude/state/gpg-pubkey-20E4E2219305D1CD.asc)"`.
Rollback to the previous SSH-via-1Password setup: `~/.claude/scripts/restore-ssh-signing.sh`.

## 3. No AI attribution

Never emit `🤖 Generated with Claude Code` or `Co-Authored-By: Claude` in a
commit, PR title, PR body or PR comment. `attribution.commit`/`attribution.pr`
are blanked in `settings.json` and the PostToolUse hook
`gh plugin-rm-generated-by claude-hook` strips stragglers — a safety net, not
permission to write it.

## 4. Push

```bash
git push -u origin "$(git branch --show-current)"   # first push
git please                                          # after a rebase or amend
```

`git please` is `push --force-with-lease`; never plain `--force`. Nothing is
pushed unless the user asked for a push or a PR.

## 5. Open it — draft by default

Title = the lead commit's subject; it is what lands on `main` after squash.
Write the body to a file — `--body` on the command line mangles code fences.

```bash
gh pr create --draft --base main --title "fix(rag): …" --body-file /tmp/pr.md
```

```markdown
## What          one paragraph: the change and the symptom it addresses
## Why           the mechanism, with `pkg/llm/node.go:4959` references
## How           what the diff does; with >1 commit, list them:
                 1. **refactor** — extract X. No behaviour change.
                 2. **fix** — the real change, plus the regression test.
## Testing       the evidence — see below
## Out of scope  follow-ups deliberately left out

Refs: [ENG-6686](https://linear.app/synthflow/issue/ENG-6686)
```

`ENG-`/`VOI-`/`PRO-`/`TEL-` → `https://linear.app/synthflow/issue/<ID>`.

**Testing is never vague.** Name commands and results: new test verified RED on
`origin/main` and green here, `-race -count=2`, `make lint: 0 issues`, every
pre-existing failure named as pre-existing. Real numbers, call UUIDs and log
queries beat adjectives.

**Anything touching call flow, turn ordering or latency gets a mermaid
`sequenceDiagram`** under `### Timeline of a <…> turn` — the user asks for this
by name. Caller / Orchestrator / Planner LLM / KB / Answer LLM / TTS, `par … and
…` for the overlapping legs. Worked example: `pr-body-template.md` beside this file.

## 6. Draft → ready

`gh pr ready <n>` only once all five hold:

1. `gh pr checks <n> --watch` green, or every red is a named pre-existing failure;
2. self-review of the whole diff — `gh pr diff <n>`, read every hunk;
3. body matches what landed (`gh pr edit <n> --body-file /tmp/pr.md`);
4. no debug leftovers —
   `git diff origin/main... | grep -nE 'fmt\.Print|spew\.|t\.Skip|// *(DEBUG|XXX)'`;
5. ticket linked.

Review fixups: amend the tip with `git oops` + `git please`; anything deeper
gets a follow-up commit — `git rebase -i` is unavailable here.

## 7. After opening

Report the URL and stop. Watch CI with `gh pr checks <n> --watch` only if the
user is waiting on it. **Do not poll for CodeRabbit** —
`~/.claude/scripts/coderabbit-watch.sh` ticks every 30 min under launchd and
opens its own session in the PR's worktree for new review comments
(`coderabbit-watch.sh --pr <n>` forces a tick now). Never post a PR comment or
Slack message on the user's behalf without asking first.

## 8. Several PRs at once

"each on a separate PR" / "one PR for each bug" → **one worktree per PR**, each
off the default branch, so they review and merge independently; do a shared
refactor once, in the first PR. Stack only when B genuinely needs A:
`wt switch --create fix/b --base @ --no-cd --format json -y` (worktree-first
§3), `gh pr create --base fix/a`, and say so in the body. After A merges:
`git fetch origin && git rebase origin/main && git please`.
