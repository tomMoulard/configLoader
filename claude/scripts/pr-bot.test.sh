#!/usr/bin/env bash
# Tests for the parts of pr-bot.sh that a --dry-run cannot reach: the bot
# worktree lifecycle.  Those are the destructive ones -- they run `reset --hard`
# and `clean -fdx` unattended -- so they get a real test against throwaway local
# repositories.  No network, no GitHub, no `claude`.
#
#   ./pr-bot.test.sh          run them all
#
# pr-bot.sh is sourced with PR_BOT_LIB=1, which returns before the tick, so only
# the functions under test run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-bot-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$*"; }
check(){ # description expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 -- expected [$2], got [$3]"; fi
}
# A `case` pattern's own ")" would close a $( ), so substring checks go through
# a function rather than being inlined into a check argument.
contains() { # haystack needle -> 1 or 0 on stdout
  case "$1" in *"$2"*) printf 1 ;; *) printf 0 ;; esac
}

# Local commits must not need 1Password, and a launchd-shaped environment has no
# committer identity of its own.
git_local_setup() {
  git -C "$1" config user.email pr-bot-test@example.invalid
  git -C "$1" config user.name  "PR bot test"
  git -C "$1" config commit.gpgsign false
  git -C "$1" config tag.gpgsign false
}

# origin.git + a main checkout with `main` and a feature branch on it.
BRANCH="feat/soniox"
PR=7
new_fixture() { # name -> echoes the main checkout path
  local n="$1" o="$TMP/$1/origin.git" c="$TMP/$1/checkout"
  mkdir -p "$TMP/$1"
  git init --quiet --bare -b main "$o"
  git clone --quiet "$o" "$c" 2>/dev/null
  git_local_setup "$c"
  printf 'base\n' >"$c/file.txt"
  git -C "$c" add file.txt
  git -C "$c" commit --quiet -m "base"
  git -C "$c" push --quiet origin main
  git -C "$c" checkout --quiet -b "$BRANCH"
  printf 'feature\n' >>"$c/file.txt"
  git -C "$c" commit --quiet -am "feature work"
  git -C "$c" push --quiet -u origin "$BRANCH"
  # back to main so the feature branch is not checked out here: that is the shape
  # a real repo has when the user keeps their work in their own wt worktree.
  git -C "$c" checkout --quiet main
  printf '%s' "$c"
}

# The bot worktree's branch name, as pr-bot.sh builds it.
BB="pr-bot/pr-$PR"

export PR_BOT_STATE_DIR="$TMP/state" PR_BOT_LOG_DIR="$TMP/logs"
export PR_BOT_PROMPT_FILE="$HERE/ci-red-fix-prompt.md"
export CLAUDE_BIN=true          # the launch path is not under test here
PR_BOT_LIB=1 . "$HERE/pr-bot.sh"

# ---------------------------------------------------------------------------
say_case() { printf '\n%s\n' "$*"; }

say_case "1. a fresh bot worktree is created on its own branch at the PR head"
C="$(new_fixture fresh)"
bot_worktree "$C" repo "$PR" "$BRANCH" main
rc=$?
check "returns 0"                     0 "$rc"
check "BOT_WT is the bot path"        "$C/.worktrees/.pr-bot" "$BOT_WT"
check "worktree exists"               1 "$([ -d "$BOT_WT" ] && echo 1 || echo 0)"
check "on the bot branch"             "$BB" "$(git -C "$BOT_WT" branch --show-current)"
check "at origin/$BRANCH"             "$(git -C "$C" rev-parse "origin/$BRANCH")" "$(git -C "$BOT_WT" rev-parse HEAD)"
check "nothing unpushed"              0 "$BOT_AHEAD"
# The user's own checkout must be untouched, still on main.
check "main checkout still on main"   main "$(git -C "$C" branch --show-current)"

say_case "2. the feature branch being checked out elsewhere does not block the bot"
# This is the constraint that rules out reusing the user's branch name: git
# refuses to check the same branch out in two worktrees.
C="$(new_fixture shared)"
git -C "$C" checkout --quiet "$BRANCH"     # the human has it out in the main checkout
bot_worktree "$C" repo "$PR" "$BRANCH" main
check "still returns 0"               0 "$?"
check "bot is on its own branch"      "$BB" "$(git -C "$BOT_WT" branch --show-current)"
check "human's checkout untouched"    "$BRANCH" "$(git -C "$C" branch --show-current)"

say_case "3. uncommitted files are scrap: cleaned, tracked and untracked alike"
C="$(new_fixture dirty)"
bot_worktree "$C" repo "$PR" "$BRANCH" main
printf 'half-finished edit\n' >>"$BOT_WT/file.txt"
printf 'abandoned test\n'      >"$BOT_WT/stray_test.go"
mkdir -p "$BOT_WT/subdir"; printf 'junk\n' >"$BOT_WT/subdir/junk.txt"
before="$(git -C "$BOT_WT" rev-parse HEAD)"
bot_worktree "$C" repo "$PR" "$BRANCH" main
check "returns 0"                     0 "$?"
check "tracked edit reverted"         "" "$(git -C "$BOT_WT" status --porcelain --untracked-files=no)"
check "untracked file removed"        0 "$([ -e "$BOT_WT/stray_test.go" ] && echo 1 || echo 0)"
check "untracked dir removed"         0 "$([ -e "$BOT_WT/subdir" ] && echo 1 || echo 0)"
check "HEAD did not move"             "$before" "$(git -C "$BOT_WT" rev-parse HEAD)"

say_case "4. commits are NOT scrap: an unpushed session commit survives a clean"
C="$(new_fixture commits)"
bot_worktree "$C" repo "$PR" "$BRANCH" main
git_local_setup "$BOT_WT"
printf 'the fix\n' >>"$BOT_WT/file.txt"
git -C "$BOT_WT" commit --quiet -am "fix(pkg): make the test pass"
fixsha="$(git -C "$BOT_WT" rev-parse HEAD)"
printf 'scrap on top\n' >>"$BOT_WT/file.txt"      # plus uncommitted junk
bot_worktree "$C" repo "$PR" "$BRANCH" main
check "returns 0"                     0 "$?"
check "the commit is still HEAD"      "$fixsha" "$(git -C "$BOT_WT" rev-parse HEAD)"
check "reports 1 unpushed commit"     1 "$BOT_AHEAD"
check "the junk on top is gone"       "" "$(git -C "$BOT_WT" status --porcelain --untracked-files=no)"

say_case "5. do_publish pushes exactly those commits, as a fast-forward"
remote_before="$(git -C "$C" rev-parse "origin/$BRANCH")"
do_publish repo "$PR" "$BRANCH" "$BOT_WT" "$BOT_AHEAD"
check "state is pushed"               pushed "$PUBLISH_STATE"
git -C "$C" fetch --quiet origin
check "origin advanced to the fix"    "$fixsha" "$(git -C "$C" rev-parse "origin/$BRANCH")"
check "it was a fast-forward"         1 "$(git -C "$C" merge-base --is-ancestor "$remote_before" "$fixsha" && echo 1 || echo 0)"
# and afterwards there is nothing left pending
bot_worktree "$C" repo "$PR" "$BRANCH" main
check "nothing unpushed now"          0 "$BOT_AHEAD"

say_case "6. a diverged bot branch is reported, never force-cleaned"
C="$(new_fixture diverged)"
bot_worktree "$C" repo "$PR" "$BRANCH" main
git_local_setup "$BOT_WT"
printf 'session work\n' >>"$BOT_WT/file.txt"
git -C "$BOT_WT" commit --quiet -am "fix: session work"
mine="$(git -C "$BOT_WT" rev-parse HEAD)"
# meanwhile somebody force-pushes the PR branch out from under the bot
other="$TMP/diverged/other"
git clone --quiet "$TMP/diverged/origin.git" "$other" 2>/dev/null
git_local_setup "$other"
git -C "$other" checkout --quiet -b "$BRANCH" "origin/$BRANCH"
printf 'somebody else\n' >>"$other/file.txt"
git -C "$other" commit --quiet -am "amended elsewhere"
git -C "$other" push --quiet --force origin "$BRANCH"
bot_worktree "$C" repo "$PR" "$BRANCH" main
check "refuses"                       1 "$?"
check "says it needs a human"         1 "$(contains "$BOT_NOTE" "needs you")"
check "the session commit survives"   "$mine" "$(git -C "$C" rev-parse "refs/heads/$BB")"

say_case "7. a half-finished rebase in the bot worktree is unwound, not reported"
C="$(new_fixture midrebase)"
bot_worktree "$C" repo "$PR" "$BRANCH" main
git_local_setup "$BOT_WT"
# make main and the branch touch the same line, so a rebase must conflict
git -C "$C" checkout --quiet main
printf 'main moved\n' >>"$C/file.txt"
git -C "$C" commit --quiet -am "main moves"
git -C "$C" push --quiet origin main
git -C "$BOT_WT" fetch --quiet origin
git -C "$BOT_WT" -c rebase.autoStash=false rebase origin/main >/dev/null 2>&1
gd="$(git -C "$BOT_WT" rev-parse --absolute-git-dir)"
check "fixture really is mid-rebase"  1 "$({ [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; } && echo 1 || echo 0)"
bot_worktree "$C" repo "$PR" "$BRANCH" main
check "returns 0"                     0 "$?"
gd="$(git -C "$BOT_WT" rev-parse --absolute-git-dir)"
check "no longer mid-rebase"          0 "$({ [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; } && echo 1 || echo 0)"

say_case "8. a live Claude session in the bot worktree is never touched"
C="$(new_fixture live)"
bot_worktree "$C" repo "$PR" "$BRANCH" main
printf 'a human is editing this\n' >>"$BOT_WT/file.txt"
printf '%s\n' "$BOT_WT" >"$RUN_TMP/live"      # what collect_live_sessions would find
bot_worktree "$C" repo "$PR" "$BRANCH" main
check "refuses"                       1 "$?"
check "says a session is in it"       1 "$(contains "$BOT_NOTE" "live Claude session")"
check "the human's edit survives"     1 "$(git -C "$TMP/live/checkout/.worktrees/.pr-bot" status --porcelain --untracked-files=no | grep -c .)"
: >"$RUN_TMP/live"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
