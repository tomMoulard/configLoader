---
name: worktree-first
description: >-
  Move the session into an isolated git worktree, created with the `wt` CLI,
  before changing any code. Use this at the very start of ANY task that will
  modify files in a git repo — implementing a feature, fixing a bug,
  refactoring, addressing review comments, working a Linear issue, picking up a
  PR (`pr:2020`) — even when the user never says the word "worktree". Also
  covers the wrap-up: commit, merge back with `wt merge`, or tear the worktree
  down. Skip it only for read-only work (questions, explanations, code review,
  investigation) and outside git repos.
---

# Worktree-first

Every code change gets its own worktree and branch. The main checkout stays
clean and reviewable, several Claude sessions can run at once without fighting
over one index, and an abandoned experiment is one `wt remove` away.

This replaces the manual `cd repo && wt switch --create fix/... && claude "..."`
dance: the user now launches `claude` once in the repo root and describes the
task, and you do the switch. This file is also your authorization to call
`EnterWorktree` — no need to ask the user for permission first.

`wt` (worktrunk) owns creation, so worktrees land where the user's `wt` config
says (`.worktrees/<branch>`) and their post-switch hooks run: `.env` copied in,
zoxide updated. A `WorktreeCreate` hook in `settings.json` routes `EnterWorktree`
through `wt` already, so for new work the tool call is all you need.

## 1. Decide

Isolate as soon as it's clear the task will write code. Stay put when:

- the request is read-only — a question, an explanation, an investigation, or
  reviewing someone else's code without touching it. Note that fetching PR or
  review feedback *in order to act on it* is code-change work: isolate first,
  then read the comments from inside the worktree;
- the user asked to work in place ("just fix it here", "no branch");
- you're not in a git repo, or already inside a worktree (`EnterWorktree` refuses the second one anyway);
- the main checkout already holds uncommitted work belonging to this task. It can't follow you across, so ask before moving.

Do this before your first edit. Reading and searching the main checkout first is
fine — but paths shift when you move, so don't build a map you'll have to redo.

## 2. Name the branch

The name is what the user reads in `wt list` and `git branch` for days, so make
it say what the work is: `<type>/<ID>-<kebab-summary>`, type drawn from
`feat | fix | refactor | chore | docs | test`.

Include the tracker ID when it's cheap to know — the user mentioned it, it's in
the prompt, or a Linear lookup on an issue they named turns it up. Don't hunt
for one.

```
fix/ENG-1234-nil-deref-agent-loop
feat/ENG-987-webhook-retry-backoff
refactor/split-call-router            # no ticket known
fix/b-2020                            # bug/PR number is all there is
```

Two constraints: each `/`-separated segment accepts only letters, digits, dots,
underscores and dashes (64 chars total), so `#` is rejected — `fix/b#2020` has
to become `fix/b-2020`. And keep the summary to three to five words.

## 3. Enter the worktree

**New work** — `EnterWorktree({name: "fix/ENG-1234-nil-deref-agent-loop"})`.
The hook runs `wt switch --create` and the session lands inside the new tree.

**An existing branch or PR** — the hook only ever receives a *name*, so it can't
express `pr:2020`. Two steps instead:

```bash
wt switch pr:2020 --no-cd --format json -y 2>/dev/null | jq -r .path
```

then `EnterWorktree({path: "<that path>"})`. Same shape for an existing branch
(`wt switch some/branch ...`) and for stacking on the current branch rather than
the default one (`wt switch --create x --base @ ...`).

Why those flags: `--format json` puts `{action, branch, path, created_branch,
base_branch}` on stdout while wt's human output goes to stderr; `--no-cd` because
only `EnterWorktree` can actually move the session; `-y` so wt never blocks on a
prompt. If `EnterWorktree({name})` fails complaining about the hook, fall back to
this same two-step route with `--create`.

When isolation fails, say so and keep working in the main checkout — don't
half-move and leave the user guessing where the code is.

## 4. Work

Check once that you're where you think you are (`git rev-parse --show-toplevel`,
`git branch --show-current`), then work normally. Commit inside the worktree as
you go, and verify — build, tests, lint — before considering it done.

## 5. Wrap up

Order matters: `wt merge` deletes the worktree, so leave it *before* merging or
the session's cwd vanishes underneath you.

For your own new branch, once the work is complete and verification actually
passed:

1. commit everything in the worktree;
2. `ExitWorktree({action: "keep"})` — back to the main checkout, tree left on disk;
3. `wt -C "<worktree_path>" merge -y --format json` — squashes, rebases onto the
   default branch, fast-forwards it, removes the worktree;
4. report the branch and what landed.

Skip the merge and just report the branch when verification didn't pass or
couldn't run, when the work is unfinished, or when the user wants a PR — then
push and `gh pr create` instead. A branch that came from `pr:N` or from someone
else is never merged locally: commit and push to that branch. Nothing gets
pushed to a remote unless the user asked for it.

Abandoning the work: `ExitWorktree({action: "remove"})`, adding
`discard_changes: true` only after the user confirms losing the changes. The
`WorktreeRemove` hook runs `wt remove`, which deletes the branch if it's merged
and keeps it if it isn't.
