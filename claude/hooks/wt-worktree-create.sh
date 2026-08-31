#!/usr/bin/env bash
# Claude Code WorktreeCreate hook — create worktrees with `wt`, not plain git.
#
# stdin  (JSON): {"hook_event_name":"WorktreeCreate","name":"fix/ENG-123-thing",...}
# stdout       : absolute worktree path, as the last non-empty line
#
# Routing creation through wt keeps worktrees where wt's config puts them
# (.worktrees/<branch>) and runs its post-switch hooks — .env copy, zoxide.
set -uo pipefail

die() { printf 'wt WorktreeCreate hook: %s\n' "$*" >&2; exit 1; }

command -v wt >/dev/null 2>&1 || die "wt not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq not found in PATH"

name="$(jq -r '.name // empty')" || die "could not parse hook input"
[ -n "$name" ] || die "hook input contained no .name"

# --no-cd: nothing here should chdir; Claude Code moves the session using the
# path we print.  -y: never block on an approval prompt inside a hook.
json="$(wt switch --create "$name" --no-cd --format json -y 2>/dev/null)" ||
  # Branch or worktree already exists: reuse it rather than failing the session.
  json="$(wt switch "$name" --no-cd --format json -y 2>/dev/null)" ||
  die "wt could not create or switch to a worktree for '$name'"

path="$(printf '%s' "$json" | jq -r 'select(.path != null) | .path' | tail -n 1)"
[ -n "$path" ] || die "wt returned no path (output: $json)"
[ -d "$path" ] || die "wt reported $path, but that directory does not exist"

printf '%s\n' "$path"
