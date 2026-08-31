#!/usr/bin/env bash
# Claude Code WorktreeRemove hook — tear down with `wt` so the branch is deleted
# when it is merged (kept when it is not) and wt's post-remove hooks run.
#
# stdin (JSON): {"hook_event_name":"WorktreeRemove","worktree_path":"/abs/path"}
set -uo pipefail

die() { printf 'wt WorktreeRemove hook: %s\n' "$*" >&2; exit 1; }

command -v wt >/dev/null 2>&1 || die "wt not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq not found in PATH"

path="$(jq -r '.worktree_path // empty')" || die "could not parse hook input"
[ -n "$path" ] || die "hook input contained no .worktree_path"
[ -d "$path" ] || exit 0  # already gone; nothing to tear down

# Run from the main worktree: cwd may be inside the tree we are about to delete.
root="$(git -C "$path" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
[ -n "${root:-}" ] || die "could not locate the main worktree for $path"

# -f: Claude Code has already gated on uncommitted changes before calling us.
wt -C "$root" remove "$path" --foreground -f -y --format json >/dev/null 2>&1 ||
  die "wt remove failed for $path"
