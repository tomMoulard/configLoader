#!/usr/bin/env bash
# One job for my open SynthFlowAI PRs: keep them rebased onto their base branch
# AND keep their CI green.  Replaces pr-sweep.sh + ci-red-watch.sh, which each
# owned half the problem and deferred the other half to the other -- so a PR that
# was *both* behind and red was owned by nobody and rotted for days (see the
# "why one job" note below).
#
#   pr-bot.sh              one tick (what launchd runs)
#   pr-bot.sh --dry-run    full read-only pass; prints the digest it WOULD write
#   pr-bot.sh --seed       record today's state as the baseline, act on nothing
#   pr-bot.sh --pr 2041    do one PR now: rebase phase forced on, caps ignored
#   pr-bot.sh --now        force the rebase phase on, whatever the clock says
#   pr-bot.sh --status     print the last digest
#   pr-bot.sh --migrate    fold pr-sweep + ci-red-watch state into this job's
#
# Per PR, in this order -- the order is the point:
#   1. prepare the bot's OWN worktree (see "why a dedicated worktree")
#   2. publish: push any commit a previous fix session left behind unpushed
#   3. rebase onto the base branch when GitHub says the PR is behind -- but only
#      inside a rebase window (see "why windows"), since every force-push burns a
#      full CI run
#   4. CI: classify each failing check, rerun the infra flakes, launch one fix
#      session for a real failure -- skipped if 2 or 3 just pushed, because the
#      red result we are looking at is already stale and a fresh run is coming
#   5. report: draft-looks-ready, stale, mergeable, and the digest
#
# --- why one job ---------------------------------------------------------------
# The two-script split had a hole with no owner.  pr-sweep refused to rebase a
# worktree with uncommitted changes; ci-red-watch refused to touch a PR whose
# mergeStateStatus was DIRTY or BEHIND ("pr-sweep's lane").  A PR that was both
# logged "no action" from both scripts every 30 minutes -- orchestrator#2041 did
# it 178 times over four days.  One job cannot hand work to itself, so it cannot
# reproduce that.
#
# --- why a dedicated worktree ---------------------------------------------------
# Both old scripts operated in the PR's own `wt` worktree -- the one the user is
# editing in.  That is what created the deadlock: a fix session died mid-flight,
# left two files modified there, and every later rebase refused to touch it.  It
# also means an unattended `claude -p` session shares a checkout with a human.
#
# So this job gets its own worktree per repo, at $BOT_WT_REL, and never looks at
# anyone else's.  It is disposable by construction:
#   * uncommitted files in it are scrap -- reset --hard + clean -fdx every tick;
#   * commits in it are NOT scrap.  They are a previous session's verified work
#     that never got pushed, so they are kept, built on, and published (step 2).
#     The prompt only permits committing after verification passed, which is what
#     makes that safe -- see ci-red-fix-prompt.md section 5.
# Each PR gets its own local branch $BOT_BRANCH_PREFIX/pr-<N> in that worktree, so
# switching between PRs never loses a commit, and git never refuses a checkout
# because the user already has that branch out in their own worktree.
#
# --- why windows ----------------------------------------------------------------
# The CI half wants to run often (a red check should not sit for hours); the
# rebase half force-pushes, and every force-push cancels and re-runs the whole
# workflow.  So the job ticks every 30 min and only opens the rebase phase in the
# windows in $REBASE_WINDOWS -- the same 09:05/15:05 cadence pr-sweep had.  The
# window is claimed by marker file, not by matching the clock, so a window whose
# tick was skipped (asleep, or the previous tick still held the lock through a
# 45-minute session) is still honoured by the next tick that runs.
set -uo pipefail

OWNER=SynthFlowAI
CLONE_ROOTS="$HOME/go/src/github.com/synthflowai $HOME/workspace/local-mode $HOME/workspace"
STATE_DIR="${PR_BOT_STATE_DIR:-$HOME/.claude/state/pr-bot}"
LOG_DIR="${PR_BOT_LOG_DIR:-$HOME/.claude/logs/pr-bot}"
PROMPT_FILE="${PR_BOT_PROMPT_FILE:-$HOME/.claude/scripts/ci-red-fix-prompt.md}"
DEFLAKE_SKILL="$HOME/.claude/skills/deflake"
LOCK_DIR="$STATE_DIR/.lock"
WINDOW_DIR="$STATE_DIR/.windows"
DIGEST="$LOG_DIR/digest.md"
RUNLOG_DIR="$LOG_DIR/runlogs"

# The bot's worktree, relative to each repo's main checkout.  Dot-prefixed so it
# sorts away from the user's own worktrees and is obvious in `git worktree list`.
BOT_WT_REL=".worktrees/.pr-bot"
BOT_BRANCH_PREFIX="pr-bot"

REBASE_WINDOWS="9 15"        # local hours at which the rebase phase opens
MAX_PRS_PER_TICK=40          # bound the API work; the org rarely has more open
MAX_REBASES_PER_TICK=6       # runaway guard: at most this many force-pushes a tick
MAX_ATTEMPTS_PER_PR=5        # stop retrying a PR that keeps failing to rebase
MAX_SESSIONS_PER_TICK=1      # one `claude -p` per tick: no thundering herd
MAX_RUNS_PER_PR=3            # runaway guard, in case the fix keeps failing CI
MAX_RERUNS_PER_TICK=3        # `gh run rerun` is cheap, but not unlimited
STALE_DAYS=7                 # no commit / comment / review in this many days
REBASE_TIMEOUT=180           # commit signing goes through 1Password; never hang
PUSH_TIMEOUT=120
SESSION_TIMEOUT=45m
GH_TIMEOUT=180               # per gh log download
CLAUDE_BIN="${CLAUDE_BIN:-claude}"   # override to test the launch path with a stub
AUTO_RERUN="${AUTO_RERUN:-1}"        # 0 = classify and report, never rerun

# launchd hands us a bare PATH; claude, gh, git, jq and timeout all live outside it.
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

# commit.gpgsign=true + gpg.format=ssh means every rebased commit is re-signed by
# 1Password's op-ssh-sign, which needs the per-boot launchd ssh-agent socket.  It
# is not in a launchd job's environment, and its path is randomised each boot, so
# it is fetched rather than hardcoded in the plist.
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  _sock="$(launchctl getenv SSH_AUTH_SOCK 2>/dev/null)"
  [ -n "$_sock" ] && export SSH_AUTH_SOCK="$_sock"
  unset _sock
fi
# No interactive git, ever: a credential or editor prompt in a launchd job hangs.
export GIT_TERMINAL_PROMPT=0 GIT_EDITOR=true GIT_PAGER=cat
export LANG="${LANG:-en_US.UTF-8}"   # so ${title:0:N} counts characters, not bytes

mkdir -p "$STATE_DIR" "$LOG_DIR" "$RUNLOG_DIR" "$WINDOW_DIR"
TICK_LOG="$LOG_DIR/tick.log"
INTERACTIVE=0; [ -t 1 ] && INTERACTIVE=1
RUN_TAG="launchd:$$"; [ "$INTERACTIVE" = 1 ] && RUN_TAG="you:$$"
log()    { printf '%s  [%s] %s\n' "$(date '+%F %T')" "$RUN_TAG" "$*" >>"$TICK_LOG"
           [ "$INTERACTIVE" = 1 ] && printf '%s\n' "$*" >&2 || true; }
say()    { printf '%s\n' "$*"; }
# osascript is the only notifier on this machine, and it is what the scripts this
# one replaces already used.  Nothing outbound: no Slack, no PR comment -- the
# user's standing rule is that nothing gets sent on their behalf.
notify() { osascript -e "display notification \"${1//\"/}\" with title \"PR bot\"" >/dev/null 2>&1 || true; }

usage() { say "usage: $0 [--dry-run|--seed|--status|--migrate|--now|--pr <number>]"; }

mode=tick only_pr="" force_window=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tick)    ;;
    --dry-run) mode=dry ;;
    --seed)    mode=seed ;;
    --status)  mode=status ;;
    --migrate) mode=migrate ;;
    --now)     force_window=1 ;;
    --pr)      shift; only_pr="${1:-}"
               [[ "$only_pr" =~ ^[0-9]+$ ]] || { say "usage: $0 --pr <number>"; exit 2; }
               [ "$mode" = tick ] && mode=manual; force_window=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage; exit 2 ;;
  esac
  shift
done

if [ "$mode" = status ]; then
  if [ -s "$DIGEST" ]; then cat "$DIGEST"; else say "no digest yet -- run: $0 --dry-run"; fi
  exit 0
fi

state_file() { printf '%s/%s-%s.json' "$STATE_DIR" "$1" "$2"; }

# --- one-shot migration off the two old scripts ---------------------------------
# `handled` is worth carrying over: it is what stops a session being launched again
# for a failure a session already looked at.  The caps (attempts, runs) are NOT
# carried over -- they are what parked seven PRs, and the design that produced
# them is the one being replaced, so every PR starts with a fresh budget.
if [ "$mode" = migrate ]; then
  old_ci="$HOME/.claude/state/ci-red-watch"
  old_sweep="$HOME/.claude/state/pr-sweep"
  n=0
  for f in "$old_ci"/*.json "$old_sweep"/*.json; do
    [ -e "$f" ] || continue
    jq -e . "$f" >/dev/null 2>&1 || continue
    repo="$(jq -r '.repo // empty' "$f")"; pr="$(jq -r '.pr // empty' "$f")"
    [ -n "$repo" ] && [ -n "$pr" ] || continue
    dest="$(state_file "$repo" "$pr")"
    prev='{}'; [ -f "$dest" ] && jq -e . "$dest" >/dev/null 2>&1 && prev="$(cat "$dest")"
    jq -n --argjson prev "$prev" --argjson old "$(cat "$f")" \
          --arg repo "$repo" --arg pr "$pr" '
      { repo: $repo, pr: ($pr | tonumber),
        url:       ($old.url // $prev.url // null),
        last_head: ($old.last_head // $prev.last_head // ""),
        last_seen: ($old.last_seen // $prev.last_seen // null),
        handled:    (((($prev.handled // []) + ($old.handled // [])) | unique)[-400:]),
        rerun_keys: (((($prev.rerun_keys // []) + ($old.rerun_keys // [])) | unique)[-400:]),
        rerun_shas: (((($prev.rerun_shas // []) + ($old.rerun_shas // [])) | unique)[-40:]),
        attempts: 0, runs: 0,
        rebases:     (($prev.rebases // 0) + ($old.rebases // 0)),
        last_rebase: ($old.last_rebase // $prev.last_rebase // null),
        conflict:    ($old.conflict // $prev.conflict // null),
        pending_publish: ($prev.pending_publish // false),
        last_status: ($old.last_status // $prev.last_status // null),
        last_note:   ($old.last_note // $prev.last_note // null) }' >"$dest" || continue
    n=$((n + 1))
  done
  say "migrated $n state file(s) into $STATE_DIR"
  say "attempts/runs caps were reset to 0 on purpose; handled-check history was kept."
  exit 0
fi

for bin in gh jq git timeout "$CLAUDE_BIN"; do
  command -v "$bin" >/dev/null 2>&1 || { log "FATAL: $bin not found in PATH"; say "$bin not found"; exit 1; }
done
[ -f "$PROMPT_FILE" ] || { log "FATAL: prompt file missing: $PROMPT_FILE"; say "prompt file missing"; exit 1; }

RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-bot.XXXXXX")" || { say "cannot create temp dir"; exit 1; }
# LOCK_OWNED gates the cleanup: a run that lost the race must not delete the lock
# belonging to the run that won it.
LOCK_OWNED=0; PR_LOCK=""
cleanup() {
  rm -rf "$RUN_TMP"
  [ -n "$PR_LOCK" ] && rm -rf "$PR_LOCK"
  [ "$LOCK_OWNED" = 1 ] && rm -rf "$LOCK_DIR"
  return 0
}
trap cleanup EXIT

# --- single instance ------------------------------------------------------------
take_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then echo $$ >"$LOCK_DIR/pid"; LOCK_OWNED=1; return 0; fi
  local pid; pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 1; fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null && { echo $$ >"$LOCK_DIR/pid"; LOCK_OWNED=1; return 0; }
  return 1
}
# A per-PR lock, separate from the tick lock: `--pr N` run by hand must not fire a
# second session into the bot worktree a launchd tick is already driving.
take_pr_lock() { # repo pr
  local d="$STATE_DIR/.run-$1-$2"
  if mkdir "$d" 2>/dev/null; then echo $$ >"$d/pid"; PR_LOCK="$d"; return 0; fi
  local pid; pid="$(cat "$d/pid" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 1; fi
  rm -rf "$d"
  mkdir "$d" 2>/dev/null && { echo $$ >"$d/pid"; PR_LOCK="$d"; return 0; }
  return 1
}
drop_pr_lock() { [ -n "$PR_LOCK" ] && rm -rf "$PR_LOCK"; PR_LOCK=""; }

# --- the rebase window ----------------------------------------------------------
# Claimed by marker file rather than by matching the clock, so a window is honoured
# exactly once a day but survives a tick that never ran.
rebase_window_open() {
  [ "$force_window" = 1 ] && return 0
  local today hour w best
  today="$(date '+%Y-%m-%d')"; hour="$(date '+%-H')"
  best=""
  for w in $REBASE_WINDOWS; do
    [ "$hour" -ge "$w" ] && best="$w"
  done
  [ -n "$best" ] || return 1
  [ -e "$WINDOW_DIR/$today-$best" ] && return 1
  printf '%s' "$WINDOW_DIR/$today-$best" >"$RUN_TMP/window-marker"
  return 0
}
claim_rebase_window() {
  local m; m="$(cat "$RUN_TMP/window-marker" 2>/dev/null)"
  [ -n "$m" ] || return 0
  : >"$m"
  # keep the directory from growing for the life of the machine
  find "$WINDOW_DIR" -type f -mtime +14 -delete 2>/dev/null || :
}

state_read() { # repo pr -> the stored object, or a fresh skeleton
  local f; f="$(state_file "$1" "$2")"
  if [ -f "$f" ] && jq -e . "$f" >/dev/null 2>&1; then cat "$f"
  else printf '{"handled":[],"rerun_keys":[],"rerun_shas":[],"runs":0,"attempts":0}'; fi
}

json_array() { # each argument becomes one string element; empties dropped
  local a; a=""
  for a in "$@"; do [ -n "$a" ] && printf '%s\n' "$a"; done | jq -R . | jq -s .
}
in_list() { jq -e --arg x "$1" 'index($x) != null' <<<"$2" >/dev/null 2>&1; }

# First checkout whose origin really is $OWNER/<repo>.
repo_dir() {
  local repo="$1" root dir
  for root in $CLONE_ROOTS; do
    dir="$root/$repo"
    [ -d "$dir/.git" ] || continue
    git -C "$dir" remote get-url origin 2>/dev/null | grep -qi "$OWNER/$repo\\(\\.git\\)\\?$" && { printf '%s' "$dir"; return 0; }
  done
  return 1
}

# --- worktrees a live Claude session is sitting in --------------------------------
# The bot worktree should never have one -- but a human can always `cd` into it,
# and this job must not reset --hard the floor out from under them.
collect_live_sessions() {
  local pid
  : >"$RUN_TMP/live"
  for pid in $(pgrep -x claude 2>/dev/null); do
    lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' >>"$RUN_TMP/live"
  done
}
is_live() { # path
  local line
  [ -s "$RUN_TMP/live" ] || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in "$1"|"$1"/*) return 0 ;; esac
  done <"$RUN_TMP/live"
  return 1
}

# --- the bot's worktree -----------------------------------------------------------
# Leaves the worktree checked out on $BOT_BRANCH_PREFIX/pr-<N>, with no uncommitted
# files, at a tip that contains origin/<branch>.  Sets BOT_WT and BOT_AHEAD (the
# number of commits a previous session left unpushed), or BOT_NOTE on refusal.
BOT_WT=""; BOT_AHEAD=0; BOT_NOTE=""; BOT_UNBUILT=0
bot_worktree() { # repodir repo pr branch base
  local rdir="$1" repo="$2" pr="$3" branch="$4" base="$5"
  local wt="$rdir/$BOT_WT_REL" bb="$BOT_BRANCH_PREFIX/pr-$pr" gd
  BOT_WT=""; BOT_AHEAD=0; BOT_NOTE=""; BOT_UNBUILT=0

  if is_live "$wt"; then
    BOT_NOTE="a live Claude session is in the bot worktree; not touched"; return 1
  fi

  if [ ! -d "$wt" ]; then
    # A dry run creates nothing, so there is no worktree to inspect and every
    # later git question about it would answer "cannot resolve".  Flag it and let
    # the callers report their intent instead.
    if [ "$mode" = dry ]; then
      BOT_NOTE="the bot worktree at $wt does not exist yet; it would be created"
      BOT_WT="$wt"; BOT_UNBUILT=1; return 0
    fi
    # --detach: the branch is chosen per PR below, and a fresh worktree must not
    # claim a branch name the user might have checked out somewhere else.
    git -C "$rdir" worktree add --detach "$wt" HEAD >>"$TICK_LOG" 2>&1 || {
      BOT_NOTE="could not create the bot worktree at $wt"; return 1; }
    log "$repo: created the bot worktree at $wt"
  fi

  # Repos in this org keep secrets for the test suite in a root .env, and the
  # user's own `wt` post-switch hook copies it into every new worktree.  Do the
  # same, every tick, so a fix session can actually run the tests.
  [ "$mode" != dry ] && [ -f "$rdir/.env" ] && cp "$rdir/.env" "$wt/.env" 2>/dev/null

  if [ "$mode" = dry ]; then BOT_WT="$wt"; return 0; fi

  # A tick killed mid-rebase leaves the worktree mid-rebase.  Nothing here is
  # precious, so unwind unconditionally rather than reporting and stalling.
  gd="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)"
  if [ -n "$gd" ] && { [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; }; then
    git -C "$wt" rebase --abort >>"$TICK_LOG" 2>&1 || git -C "$wt" rebase --quit >>"$TICK_LOG" 2>&1
    log "$repo#$pr: unwound a half-finished rebase in the bot worktree"
  fi

  git -C "$wt" fetch --quiet origin \
      "+refs/heads/$branch:refs/remotes/origin/$branch" \
      "+refs/heads/$base:refs/remotes/origin/$base" >>"$TICK_LOG" 2>&1 || {
    BOT_NOTE="git fetch origin failed"; return 1; }

  local remote_head; remote_head="$(git -C "$wt" rev-parse --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null)"
  [ -n "$remote_head" ] || { BOT_NOTE="cannot resolve origin/$branch"; return 1; }

  # Is there a bot branch for this PR already, and does it hold commits that never
  # reached the remote?  Those are a previous session's work: keep them, build on
  # them, publish them.  Everything else about this worktree is disposable.
  local have_bb=0 ahead=0 behind_remote=0
  git -C "$wt" rev-parse --verify --quiet "refs/heads/$bb" >/dev/null 2>&1 && have_bb=1
  if [ "$have_bb" = 1 ]; then
    ahead="$(git -C "$wt" rev-list --count "$remote_head..refs/heads/$bb" 2>/dev/null || echo 0)"
    behind_remote="$(git -C "$wt" rev-list --count "refs/heads/$bb..$remote_head" 2>/dev/null || echo 0)"
    [[ "$ahead" =~ ^[0-9]+$ ]] || ahead=0
    [[ "$behind_remote" =~ ^[0-9]+$ ]] || behind_remote=0
  fi

  # Diverged: origin/<branch> holds commits the bot branch does not, AND the bot
  # branch holds commits origin does not.  Someone force-pushed the PR under us.
  # Rebasing the bot's commits onto the new tip is a merge decision, and the
  # standing rule is that commits are never discarded -- so stop and report.
  if [ "$have_bb" = 1 ] && [ "$ahead" -gt 0 ] && [ "$behind_remote" -gt 0 ]; then
    BOT_NOTE="bot branch $bb has $ahead local commit(s) and origin/$branch moved under it; needs you"
    return 1
  fi

  if [ "$have_bb" = 1 ] && [ "$ahead" -gt 0 ]; then
    git -C "$wt" checkout --quiet "$bb" >>"$TICK_LOG" 2>&1 || {
      BOT_NOTE="could not check out $bb"; return 1; }
    BOT_AHEAD="$ahead"
  else
    # No local work worth keeping: (re)point the bot branch straight at the PR head.
    git -C "$wt" checkout --quiet -B "$bb" "$remote_head" >>"$TICK_LOG" 2>&1 || {
      BOT_NOTE="could not check out $bb at origin/$branch"; return 1; }
    BOT_AHEAD=0
  fi

  # Files only.  reset --hard does not move HEAD here, so the commits above
  # survive; -e .env keeps the secrets we just copied in.
  git -C "$wt" reset --hard --quiet HEAD >>"$TICK_LOG" 2>&1
  git -C "$wt" clean -fdxq -e .env >>"$TICK_LOG" 2>&1

  BOT_WT="$wt"
  return 0
}

# --- publish what a dead session left behind --------------------------------------
# A fast-forward push, never a force: it only fires when origin/<branch> is an
# ancestor of the bot tip, so it can add commits to the PR but never replace any.
PUBLISH_STATE=none; PUBLISH_NOTE=""
do_publish() { # repo pr branch wt ahead
  local repo="$1" pr="$2" branch="$3" wt="$4" ahead="$5" out rc
  PUBLISH_STATE=none; PUBLISH_NOTE=""
  [ "${ahead:-0}" -gt 0 ] || return 0

  if [ "$mode" = dry ] || [ "$mode" = seed ]; then
    PUBLISH_STATE=would
    PUBLISH_NOTE="WOULD push $ahead commit(s) a previous session left unpushed"
    return 0
  fi

  out="$(timeout "$PUSH_TIMEOUT" git -C "$wt" push \
           --force-with-lease="refs/heads/$branch" origin "HEAD:refs/heads/$branch" 2>&1)"
  rc=$?
  printf '%s\n' "$out" >>"$TICK_LOG"
  if [ "$rc" -ne 0 ]; then
    PUBLISH_STATE=failed
    PUBLISH_NOTE="could not push $ahead unpushed commit(s) -- see tick.log"
    return 0
  fi
  PUBLISH_STATE=pushed
  PUBLISH_NOTE="published $ahead commit(s) left unpushed by an earlier fix session"
  log "$repo#$pr: published $ahead unpushed commit(s) to $branch"
  notify "$repo#$pr: pushed $ahead commit(s) an earlier session left behind"
  return 0
}

# --- the rebase -------------------------------------------------------------------
# Sets REBASE_STATE (rebased|conflict|skip|would) and REBASE_NOTE.  Never leaves a
# half-rebased worktree: every failure path ends back at the SHA it started on.
REBASE_STATE=skip; REBASE_NOTE=""; REBASE_CONFLICTS=""
do_rebase() { # repo pr branch base wtpath behind
  local repo="$1" pr="$2" branch="$3" base="$4" wt="$5" behind="$6"
  local head_local remote_head rc out conflicts new_head remote_now after
  REBASE_STATE=skip; REBASE_NOTE=""; REBASE_CONFLICTS=""

  # Nothing on disk to interrogate yet (dry run, worktree not built): report the
  # intent, which is all a dry run owes the reader.
  if [ "${BOT_UNBUILT:-0}" = 1 ]; then
    REBASE_STATE=would
    REBASE_NOTE="WOULD rebase onto origin/$base ($behind behind) and force-push"
    return 0
  fi

  head_local="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  remote_head="$(git -C "$wt" rev-parse --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null)"
  if [ -z "$head_local" ] || [ -z "$remote_head" ]; then
    REBASE_NOTE="cannot resolve HEAD or origin/$branch; not rebased"; return 0
  fi
  # bot_worktree guarantees HEAD contains origin/<branch> (equal, or ahead by a
  # previous session's commits).  Anything else means the tree moved under us
  # between then and now, and a force-push would publish something unreviewed.
  if ! git -C "$wt" merge-base --is-ancestor "$remote_head" HEAD 2>/dev/null; then
    REBASE_NOTE="bot worktree no longer contains origin/$branch; not rebased"; return 0
  fi

  if [ "$mode" = dry ]; then
    REBASE_STATE=would
    REBASE_NOTE="WOULD rebase onto origin/$base ($behind behind) and force-push"
    return 0
  fi

  # rebase.autoStash is true in the user's global config; force it off.  The tree
  # was just cleaned, so there is nothing to stash and a file appearing between
  # then and now should fail loudly rather than be silently stashed away.
  out="$(timeout "$REBASE_TIMEOUT" git -C "$wt" -c rebase.autoStash=false \
           rebase "origin/$base" 2>&1)"
  rc=$?
  printf '%s\n' "$out" >>"$TICK_LOG"

  if [ "$rc" -ne 0 ]; then
    conflicts="$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null | head -6 | tr '\n' ' ')"
    conflicts="${conflicts% }"
    REBASE_CONFLICTS="$conflicts"
    git -C "$wt" rebase --abort >>"$TICK_LOG" 2>&1
    after="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
    if [ "$after" != "$head_local" ]; then
      git -C "$wt" rebase --quit >>"$TICK_LOG" 2>&1
      git -C "$wt" reset --hard "$head_local" >>"$TICK_LOG" 2>&1
      after="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
    fi
    REBASE_STATE=conflict
    if [ "$after" != "$head_local" ]; then
      REBASE_NOTE="REBASE FAILED AND COULD NOT BE UNWOUND -- fix $wt by hand"
      log "$repo#$pr: could not restore $wt to $head_local after a failed rebase"
      notify "$repo#$pr: rebase could not be unwound -- fix $wt by hand"
      return 0
    fi
    case "$out" in
      *"failed to sign"*|*"gpg failed"*|*"error: gpg"*)
        REBASE_NOTE="commit signing failed (1Password unlocked?); branch untouched" ;;
      *)
        if [ -n "$conflicts" ]; then
          REBASE_NOTE="conflicts in $conflicts -- aborted, branch untouched"
        elif [ "$rc" -eq 124 ]; then
          REBASE_NOTE="rebase timed out after ${REBASE_TIMEOUT}s -- aborted, branch untouched"
        else
          REBASE_NOTE="rebase failed (exit $rc) -- aborted, branch untouched"
        fi ;;
    esac
    return 0
  fi

  new_head="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  if [ "$new_head" = "$head_local" ] && [ "$head_local" = "$remote_head" ]; then
    REBASE_NOTE="already on top of origin/$base; nothing pushed"; return 0
  fi

  # The remote must not have moved while we rebased, or the force-push would drop
  # whatever landed on the PR in the meantime.  Belt (this check) and braces (the
  # explicit --force-with-lease expectation on the push itself).
  git -C "$wt" fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/$branch" >>"$TICK_LOG" 2>&1
  remote_now="$(git -C "$wt" rev-parse --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null)"
  if [ "$remote_now" != "$remote_head" ]; then
    git -C "$wt" reset --hard "$head_local" >>"$TICK_LOG" 2>&1
    REBASE_STATE=conflict
    REBASE_NOTE="origin/$branch moved mid-rebase; not force-pushed, branch restored"
    return 0
  fi

  out="$(timeout "$PUSH_TIMEOUT" git -C "$wt" push \
           --force-with-lease="refs/heads/$branch:$remote_head" \
           origin "HEAD:refs/heads/$branch" 2>&1)"
  rc=$?
  printf '%s\n' "$out" >>"$TICK_LOG"
  if [ "$rc" -ne 0 ]; then
    git -C "$wt" reset --hard "$head_local" >>"$TICK_LOG" 2>&1
    REBASE_STATE=conflict
    REBASE_NOTE="force-push refused (exit $rc); branch restored -- see tick.log"
    return 0
  fi

  REBASE_STATE=rebased
  REBASE_NOTE="rebased onto origin/$base ($behind behind) and force-pushed"
  return 0
}

# --- GitHub ------------------------------------------------------------------------
# EVERY check, not just the required ones.  ci-red-watch.sh asked for --required
# first and fell back to all checks only when that came back empty -- but "no
# required checks configured" and "no *failing* required check" are different
# things, and it could not tell them apart.  On gatekeeper#113 the required
# checks (Go, Frontend) both passed while the unrequired "Lint and format" was
# red, so --required returned a non-empty all-green array, the fallback never
# fired, and the job saw nothing to do while the digest went on reporting the PR
# as red for days.  One job gets one definition of red, and it is the same one
# the digest counts.
#
# Only the buckets that mean red -- pending and skipping are somebody else's
# problem.
failing_checks() { # repo pr -> name \t bucket \t link \t workflow
  local out
  out="$(gh pr checks "$2" --repo "$OWNER/$1" --json name,bucket,link,workflow 2>/dev/null </dev/null)"
  [ -n "$out" ] || return 0
  jq -r '.[]? | select(.bucket == "fail" or .bucket == "cancel")
         | [.name, .bucket, (.link // ""), (.workflow // "")] | @tsv' <<<"$out" 2>/dev/null
}

run_id() { printf '%s' "$1" | sed -n 's#.*/actions/runs/\([0-9][0-9]*\).*#\1#p'; }

# Cached: a tick, a --dry-run and the session that follows all want the same log.
fetch_log() { # repo run_id -> path (may be an empty file)
  local dest="$RUNLOG_DIR/$1-$2.log"
  if [ ! -s "$dest" ]; then
    timeout "$GH_TIMEOUT" gh run view "$2" --repo "$OWNER/$1" --log-failed >"$dest" 2>/dev/null </dev/null || true
  fi
  printf '%s' "$dest"
}

# Did this workflow already go green on this very commit?  Two ways it can have:
# another run of the same workflow on the same SHA, or an earlier attempt of this
# run in which this job passed.  Either one means the check is non-deterministic.
prior_success() { # repo workflow sha run_id check_name
  local repo="$1" wf="$2" sha="$3" rid="$4" name="$5" attempt a
  if [ -n "$wf" ]; then
    gh run list --repo "$OWNER/$repo" --commit "$sha" --workflow "$wf" --limit 20 \
       --json databaseId,conclusion 2>/dev/null </dev/null \
    | jq -e --argjson cur "$rid" 'any(.[]?; .conclusion == "success" and .databaseId != $cur)' \
       >/dev/null 2>&1 && return 0
  fi
  attempt="$(gh run view "$rid" --repo "$OWNER/$repo" --json attempt --jq '.attempt // 1' 2>/dev/null </dev/null)"
  [[ "$attempt" =~ ^[0-9]+$ ]] || attempt=1
  a=1
  while [ "$a" -lt "$attempt" ]; do
    gh api "repos/$OWNER/$repo/actions/runs/$rid/attempts/$a/jobs" --paginate 2>/dev/null </dev/null \
    | jq -e --arg n "$name" 'any(.jobs[]?; .name == $n and .conclusion == "success")' \
       >/dev/null 2>&1 && return 0
    a=$((a + 1))
  done
  return 1
}

# --- classification ----------------------------------------------------------------
# A deterministic failure wins over an infra signal, because a cancellation is very
# often the *consequence* of another job going red (fail-fast cancels its siblings).
REAL_RE='--- FAIL: |FAIL[[:space:]]+github\.com/|^panic: |[[:space:]]panic: |\[build failed\]|cannot find package|undefined: [A-Za-z_]|declared and not used|imported and not used|syntax error:|go: updates to go\.mod needed|\(typecheck\)|\.(go|py|ts|tsx|tf|proto):[0-9]+:[0-9]+: |make: \*\*\* |Error: .*golangci-lint|assert(ion)? failed'
INFRA_RE='the operation was canceled|the job was canceled|received a shutdown signal|lost communication with the server|no space left on device|toomanyrequests|429 too many requests|50[0234] (bad gateway|service unavailable|gateway time-out|internal server error)|tls handshake timeout|connection reset by peer|i/o timeout|could not resolve host|network is unreachable|temporary failure in name resolution|error response from daemon|unable to find image|manifest unknown|pull access denied|failed to download action|failed to pull|exit code 143|gzip: stdin: unexpected end of file|the runner has received|runner lost'

CLASS=""; REASON=""
classify() { # logfile bucket
  local lf="$1" bucket="$2"
  if [ -s "$lf" ] && grep -qE -- "$REAL_RE" "$lf" 2>/dev/null; then
    CLASS=real
    if grep -qE -- '--- FAIL: ' "$lf" 2>/dev/null; then
      REASON="test failed: $(grep -oE -- '--- FAIL: [A-Za-z0-9_/]+' "$lf" 2>/dev/null | head -3 | sed 's/--- FAIL: //' | tr '\n' ' ' | sed 's/ $//')"
    elif grep -qE -- '\(typecheck\)|cannot find package|\[build failed\]|undefined: ' "$lf" 2>/dev/null; then
      REASON="build or typecheck error"
    else
      REASON="deterministic failure in the job log"
    fi
    return
  fi
  if [ -s "$lf" ] && grep -qiE -- "$INFRA_RE" "$lf" 2>/dev/null; then
    CLASS=infra
    REASON="$(grep -oiE -- "$INFRA_RE" "$lf" 2>/dev/null | head -1 | tr -d '\r')"
    [ -n "$REASON" ] || REASON="infrastructure signal in the job log"
    return
  fi
  if [ ! -s "$lf" ]; then
    if [ "$bucket" = cancel ]; then CLASS=infra; REASON="cancelled, no failed-job output"
    else CLASS=real; REASON="failed with no downloadable log"; fi
    return
  fi
  # Something failed, nothing in the log says what.  A session reads it better than
  # a regex does, so this goes to a human-shaped reader, not to a rerun.
  CLASS=real; REASON="unrecognised failure, needs reading"
}

# --- the fix session ----------------------------------------------------------------
# no-commits | pushed | local-only -- given the bot worktree, its pre-session HEAD
# and the PR's own branch (HEAD is on a pr-bot/* branch, so `origin/$(current)`
# would never resolve).
session_outcome() { # wtpath head_before branch
  local wt="$1" before="$2" branch="$3" after remote
  after="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  if [ -z "$after" ] || [ "$after" = "$before" ]; then printf 'no-commits'; return; fi
  git -C "$wt" fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null
  remote="$(git -C "$wt" rev-parse --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null)"
  [ "$remote" = "$after" ] && { printf 'pushed'; return; }
  printf 'local-only'
}

sedsafe() { printf '%s' "$1" | tr -d '&|\\' | tr '\n' ' '; }

SESSION_OUTCOME=""
launch() { # repo pr url branch head class checks logfile runurls wtpath
  local repo="$1" pr="$2" url="$3" branch="$4" head="$5" class="$6" checks="$7"
  local logfile="$8" runurls="$9" wtpath="${10}"
  local sha7="${head:0:7}" note runlog prompt head_before rc outcome commits push_cmd
  SESSION_OUTCOME=""

  if ! take_pr_lock "$repo" "$pr"; then
    log "$repo#$pr: a session is already running for this PR; not launching another"; return 1
  fi

  case "$class" in
    flaky) note="This check already went green once on this exact commit and a rerun did not clear it, so treat it as a flake: use the deflake skill at $DEFLAKE_SKILL/SKILL.md and measure the failure rate before changing anything." ;;
    *)     note="This is a deterministic failure: it fails the same way on every run of this commit." ;;
  esac

  # HEAD is on a bot-owned branch, so the session cannot `git push` with no
  # arguments -- it has to name the PR's branch explicitly.
  push_cmd="git push --force-with-lease=refs/heads/$branch origin HEAD:refs/heads/$branch"

  runlog="$LOG_DIR/${repo}-${pr}-${sha7}.log"
  prompt="$(sed -e "s|{{OWNER}}|$OWNER|g" -e "s|{{NAME}}|$repo|g" -e "s|{{REPO}}|$OWNER/$repo|g" \
                -e "s|{{PR}}|$pr|g" -e "s|{{URL}}|$url|g" -e "s|{{BRANCH}}|$(sedsafe "$branch")|g" \
                -e "s|{{HEAD}}|$head|g" -e "s|{{WORKTREE}}|$wtpath|g" \
                -e "s|{{BOT_BRANCH}}|$(sedsafe "$BOT_BRANCH_PREFIX/pr-$pr")|g" \
                -e "s|{{PUSH_CMD}}|$(sedsafe "$push_cmd")|g" \
                -e "s|{{CHECKS}}|$(sedsafe "$checks")|g" -e "s|{{LOG_FILE}}|$logfile|g" \
                -e "s|{{RUN_URLS}}|$(sedsafe "$runurls")|g" \
                -e "s|{{CLASS}}|$class|g" -e "s|{{CLASS_NOTE}}|$(sedsafe "$note")|g" \
                "$PROMPT_FILE")"

  head_before="$(git -C "$wtpath" rev-parse HEAD 2>/dev/null)"

  log "$repo#$pr@$sha7: $class failure in [$checks]; session -> $runlog"
  notify "$repo#$pr: fixing red CI ($checks)"
  if [ "$INTERACTIVE" = 1 ]; then
    say "running a session on $repo#$pr - this takes minutes, and its output is buffered."
    say "  watch it:  tail -f $runlog"
  fi

  # ANTHROPIC_API_KEY, if set in the environment, takes precedence over the
  # claude.ai login and breaks the session, so it is dropped here.
  ( cd "$wtpath" && env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDECODE \
      timeout "$SESSION_TIMEOUT" "$CLAUDE_BIN" -p --dangerously-skip-permissions "$prompt" ) \
    >"$runlog" 2>&1
  rc=$?

  outcome="$(session_outcome "$wtpath" "$head_before" "$branch")"
  SESSION_OUTCOME="$outcome"
  commits=0
  [ "$outcome" != no-commits ] && commits="$(git -C "$wtpath" rev-list --count "$head_before..HEAD" 2>/dev/null || echo 0)"

  log "$repo#$pr@$sha7: session exit=$rc outcome=$outcome commits=$commits worktree=$wtpath"
  if [ "$rc" -ne 0 ]; then
    notify "$repo#$pr: session FAILED (exit $rc) - see $runlog"
  elif [ "$outcome" = no-commits ]; then
    notify "$repo#$pr: session changed nothing - see $runlog"
  elif [ "$outcome" = pushed ]; then
    notify "$repo#$pr: $commits commit(s) pushed, CI should re-run"
  else
    # Not a dead end any more: the commits live on the bot branch, and the next
    # tick's publish step pushes them.
    notify "$repo#$pr: $commits commit(s) committed, not pushed - will publish next tick"
  fi

  drop_pr_lock
  # A session that failed does not get its checks marked handled, so the next tick
  # retries them; runs still climbs, so MAX_RUNS_PER_PR ends the retrying.
  return $rc
}

# Sourcing the script for tests stops here; below is the tick itself.
if [ "${PR_BOT_LIB:-0}" = 1 ]; then return 0; fi

# --- the tick -----------------------------------------------------------------------
if [ "$mode" != dry ]; then
  take_lock || { log "another run is in progress; skipping tick"; exit 0; }
fi
collect_live_sessions

WINDOW=0
rebase_window_open && WINDOW=1

prs="$(gh search prs --author @me --state open --owner "$OWNER" --limit "$MAX_PRS_PER_TICK" \
         --json number,repository,url 2>>"$TICK_LOG")" || { log "gh search prs failed"; exit 1; }
[ -n "$prs" ] || { log "no open PRs"; exit 0; }

if [ -n "$only_pr" ]; then
  prs="$(jq --argjson n "$only_pr" '[.[] | select(.number == $n)]' <<<"$prs")"
  [ "$(jq 'length' <<<"$prs")" -gt 0 ] || { say "PR $only_pr is not an open PR of yours in $OWNER"; exit 1; }
fi

ROWS="$RUN_TMP/rows"; : >"$ROWS"
ACT="$RUN_TMP/actionable"; : >"$ACT"
n_total=0 n_rebased=0 n_conflict=0 n_behind=0 n_would=0 n_published=0
n_red=0 n_pending=0 n_ready=0 n_stale=0 n_merge=0
rebases_done=0 sessions=0 reruns=0 already=0

while IFS=$'\t' read -r pr repo url; do
  [ -n "$pr" ] || continue
  n_total=$((n_total + 1))

  meta="$(gh pr view "$pr" --repo "$OWNER/$repo" --json \
            number,title,url,isDraft,body,headRefName,baseRefName,headRefOid,isCrossRepository,headRepositoryOwner,reviewDecision,mergeable,mergeStateStatus,commits,comments,reviews 2>>"$TICK_LOG")"
  if [ -z "$meta" ] || ! jq -e . <<<"$meta" >/dev/null 2>&1; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' '?' '?' '?' '?' '?' "#$pr $repo" "gh pr view failed" >>"$ROWS"
    log "$repo#$pr: gh pr view failed"
    continue
  fi

  title="$(jq -r '.title // ""' <<<"$meta")"
  is_draft="$(jq -r '.isDraft // false' <<<"$meta")"
  branch="$(jq -r '.headRefName // ""' <<<"$meta")"
  base="$(jq -r '.baseRefName // "main"' <<<"$meta")"
  head_sha="$(jq -r '.headRefOid // ""' <<<"$meta")"
  cross="$(jq -r '.isCrossRepository // false' <<<"$meta")"
  head_owner="$(jq -r '.headRepositoryOwner.login // ""' <<<"$meta")"
  decision="$(jq -r '.reviewDecision // ""' <<<"$meta")"
  mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$meta")"
  body_len="$(jq -r '(.body // "") | gsub("\\s";"") | length' <<<"$meta")"
  quiet_days="$(jq -r '
      [ (.commits[]?.committedDate), (.comments[]?.createdAt), (.reviews[]?.submittedAt) ]
      | map(select(. != null) | fromdateiso8601)
      | if length == 0 then 9999 else ((now - max) / 86400 | floor) end' <<<"$meta" 2>/dev/null)"
  [[ "$quiet_days" =~ ^[0-9]+$ ]] || quiet_days=0
  sha7="${head_sha:0:7}"

  # --- behind-ness, straight from the API: no fetch of 150 repos to find out ---
  cmp_head="$branch"
  [ "$cross" = true ] && [ -n "$head_owner" ] && cmp_head="$head_owner:$branch"
  cmp="$(gh api "repos/$OWNER/$repo/compare/$base...$cmp_head" \
           --jq '{behind: .behind_by, ahead: .ahead_by, basetip: .base_commit.sha}' 2>>"$TICK_LOG")"
  cmp_ok=1
  if [ -z "$cmp" ] || ! jq -e . <<<"$cmp" >/dev/null 2>&1; then cmp='{}'; cmp_ok=0
    log "$repo#$pr: could not compare $base...$cmp_head"
  fi
  behind="$(jq -r '.behind // 0' <<<"$cmp" 2>/dev/null)"; [[ "$behind" =~ ^[0-9]+$ ]] || behind=0
  basetip="$(jq -r '.basetip // ""' <<<"$cmp" 2>/dev/null)"

  # --- CI, read once and used by both halves -----------------------------------
  checks="$(gh pr checks "$pr" --repo "$OWNER/$repo" --json name,state,bucket 2>/dev/null)"
  jq -e . <<<"${checks:-}" >/dev/null 2>&1 || checks='[]'
  c_fail="$(jq -r '[.[]? | select(.bucket == "fail")] | length' <<<"$checks")"
  c_pend="$(jq -r '[.[]? | select(.bucket == "pending")] | length' <<<"$checks")"
  c_pass="$(jq -r '[.[]? | select(.bucket == "pass")] | length' <<<"$checks")"
  failed_jobs="$(jq -r '[.[]? | select(.bucket == "fail") | .name] | .[0:3] | join(", ")' <<<"$checks")"
  if   [ "$c_fail" -gt 0 ]; then ci=fail;    g_ci='x'
  elif [ "$c_pend" -gt 0 ]; then ci=pending; g_ci='o'
  elif [ "$c_pass" -gt 0 ]; then ci=pass;    g_ci='+'
  else                           ci=none;    g_ci='.'
  fi

  prev="$(state_read "$repo" "$pr")"
  attempts="$(jq -r '.attempts // 0' <<<"$prev")"
  runs="$(jq -r '.runs // 0' <<<"$prev")"
  handled_json="$(jq -c '.handled // []' <<<"$prev")"
  rkeys_json="$(jq -c '.rerun_keys // []' <<<"$prev")"
  rshas_json="$(jq -c '.rerun_shas // []' <<<"$prev")"
  pending_pub="$(jq -r '.pending_publish // false' <<<"$prev")"
  conf_head="$(jq -r '.conflict.head // ""' <<<"$prev")"
  conf_base="$(jq -r '.conflict.base // ""' <<<"$prev")"
  conf_paths="$(jq -r '.conflict.paths // ""' <<<"$prev")"
  conf_since="$(jq -r '.conflict.since // ""' <<<"$prev")"
  sha_reran=0; in_list "$head_sha" "$rshas_json" && sha_reran=1

  note=""; g_rb='.'; g_act='.'
  rb_state=none; pub_state=none; cpaths_out="$conf_paths"
  pushed_this_tick=0
  bot_wt=""; bot_ahead=0

  # --- is there any reason to touch a worktree at all this tick? ---------------
  # Preparing one costs a fetch, so it only happens when something will use it.
  want_rebase=0
  if [ "$cmp_ok" = 1 ] && [ "$behind" -gt 0 ] && [ "$cross" != true ] && [ "$mode" != seed ]; then
    if [ "$WINDOW" = 1 ]; then
      if [ -n "$conf_head" ] && [ "$conf_head" = "$head_sha" ] && [ "$conf_base" = "$basetip" ] && [ "$mode" != manual ]; then
        # Nothing has moved since the conflict, so the rebase would fail
        # identically.  Skipping keeps an unchanged tick cheap and silent.
        rb_state=conflict
        note="conflict unchanged since ${conf_since:-earlier}${conf_paths:+ ($conf_paths)}"
      elif [ "$mode" != manual ] && [ "$attempts" -ge "$MAX_ATTEMPTS_PER_PR" ]; then
        rb_state=skip; note="$behind behind $base; hit MAX_ATTEMPTS_PER_PR=$MAX_ATTEMPTS_PER_PR (clear $(state_file "$repo" "$pr"))"
      elif [ "$rebases_done" -ge "$MAX_REBASES_PER_TICK" ]; then
        rb_state=skip; note="$behind behind $base; MAX_REBASES_PER_TICK=$MAX_REBASES_PER_TICK reached this tick"
      else
        want_rebase=1
      fi
    else
      rb_state=skip; note="$behind behind $base; next rebase window ${REBASE_WINDOWS// /:00, }:00"
    fi
  elif [ "$cmp_ok" = 0 ]; then
    rb_state=skip; note="could not compare against $base; behind-ness unknown"
  elif [ "$cross" = true ] && [ "$behind" -gt 0 ]; then
    rb_state=skip; note="head is a fork ($head_owner); not rebased"
  elif [ "$behind" -eq 0 ]; then
    rb_state=insync
  fi

  # A red check is worth a worktree only if the CI half might act on it.
  want_ci=0
  [ "$ci" = fail ] && [ "$mode" != seed ] && want_ci=1

  if [ "$want_rebase" = 1 ] || [ "$want_ci" = 1 ] || [ "$pending_pub" = true ]; then
    rdir="$(repo_dir "$repo")"
    if [ -z "$rdir" ]; then
      note="${note:+$note; }no local clone under \$CLONE_ROOTS"
      want_rebase=0; want_ci=0
    elif bot_worktree "$rdir" "$repo" "$pr" "$branch" "$base"; then
      bot_wt="$BOT_WT"; bot_ahead="$BOT_AHEAD"
      [ -n "$BOT_NOTE" ] && note="${note:+$note; }$BOT_NOTE"
    else
      note="${note:+$note; }${BOT_NOTE:-could not prepare the bot worktree}"
      want_rebase=0; want_ci=0
      [ "$rb_state" = none ] && rb_state=skip
    fi
  fi

  # --- 2. publish whatever a previous session left unpushed --------------------
  if [ -n "$bot_wt" ] && [ "${bot_ahead:-0}" -gt 0 ]; then
    do_publish "$repo" "$pr" "$branch" "$bot_wt" "$bot_ahead"
    pub_state="$PUBLISH_STATE"
    [ -n "$PUBLISH_NOTE" ] && note="${note:+$note; }$PUBLISH_NOTE"
    case "$pub_state" in
      pushed) g_act='P'; n_published=$((n_published + 1)); pushed_this_tick=1
              printf 'published\t%s#%s\n' "$repo" "$pr" >>"$ACT" ;;
      would)  g_act='P'; n_published=$((n_published + 1)) ;;
      failed) printf 'publish-failed\t%s#%s\n' "$repo" "$pr" >>"$ACT" ;;
    esac
  fi

  # --- 3. rebase --------------------------------------------------------------
  if [ "$want_rebase" = 1 ] && [ -n "$bot_wt" ]; then
    do_rebase "$repo" "$pr" "$branch" "$base" "$bot_wt" "$behind"
    rb_state="$REBASE_STATE"
    [ -n "$REBASE_NOTE" ] && note="${note:+$note; }$REBASE_NOTE"
    [ -n "$REBASE_CONFLICTS" ] && cpaths_out="$REBASE_CONFLICTS"
    case "$rb_state" in
      rebased) rebases_done=$((rebases_done + 1)); cpaths_out=""; pushed_this_tick=1 ;;
      would)   rebases_done=$((rebases_done + 1)) ;;   # a dry run burns the same budget
      skip)    [ -n "$REBASE_NOTE" ] && note="$behind behind $base; $note" ;;
    esac
  fi

  case "$rb_state" in
    rebased)  g_rb='^'; n_rebased=$((n_rebased + 1)) ;;
    would)    g_rb='^'; n_would=$((n_would + 1)) ;;
    conflict) g_rb='!'; n_conflict=$((n_conflict + 1)) ;;
    skip)     g_rb='v'; n_behind=$((n_behind + 1)) ;;
    *)        g_rb='.' ;;
  esac
  [ "$ci" = fail ] && n_red=$((n_red + 1))
  [ "$ci" = pending ] && n_pending=$((n_pending + 1))

  # --- 4. CI -------------------------------------------------------------------
  # A push this tick makes the red result we are holding stale: the run it came
  # from is being cancelled and replaced right now.  Wait for the new verdict
  # rather than fixing a failure that may no longer exist.  This is the handoff
  # the two-script design got wrong -- here it is a sequence point, not a lane.
  if [ "$want_ci" = 1 ] && [ "$pushed_this_tick" = 1 ]; then
    want_ci=0
    note="${note:+$note; }CI red on $sha7, but this tick pushed: waiting for the new run"
  fi

  if [ "$want_ci" = 1 ] && [ -n "$bot_wt" ]; then
    fails="$(failing_checks "$repo" "$pr")"
    new_keys=(); seed_keys=(); rerun_rids=(); rerun_keys_new=(); giveup_keys=()
    session_checks=""; session_class=""; session_logs=""; session_urls=""

    while IFS=$'\t' read -r cname bucket clink cwf; do
      [ -n "$cname" ] || continue
      key="$sha7:$cname"
      seed_keys+=("$key")
      rid="$(run_id "$clink")"
      if [ -z "$rid" ]; then
        [ "$mode" = dry ] && say "  - $cname  [external: no Actions run behind this check]  would: nothing"
        continue
      fi
      lf="$(fetch_log "$repo" "$rid")"
      classify "$lf" "$bucket"
      cls="$CLASS"; why="$REASON"
      # A deterministic-looking failure that already passed once on this same SHA
      # is not deterministic: it is a flake.
      if [ "$cls" = real ] && prior_success "$repo" "$cwf" "$head_sha" "$rid" "$cname"; then
        cls=flaky; why="passed on another run of $sha7; $why"
      fi

      known=0
      [ "$mode" != manual ] && in_list "$key" "$handled_json" && known=1
      action=""
      if [ "$known" = 1 ]; then
        action="nothing (already handled)"; already=$((already + 1))
      else
        case "$cls" in
          infra)
            if [ "$sha_reran" = 1 ]; then
              action="nothing (already reran $sha7 once; infra needs a human)"
              giveup_keys+=("$key")
            else
              action="gh run rerun --failed $rid"
              rerun_rids+=("$rid"); rerun_keys_new+=("$key")
            fi ;;
          flaky)
            if [ "$sha_reran" = 1 ] || in_list "$key" "$rkeys_json"; then
              action="launch a session (deflake)"
              session_checks="${session_checks:+$session_checks, }$cname"
              session_logs="${session_logs:+$session_logs }$lf"
              session_urls="${session_urls:+$session_urls }${clink%%/job/*}"
              session_class=flaky; new_keys+=("$key")
            else
              action="gh run rerun --failed $rid"
              rerun_rids+=("$rid"); rerun_keys_new+=("$key")
            fi ;;
          real)
            action="launch a session (fix)"
            session_checks="${session_checks:+$session_checks, }$cname"
            session_logs="${session_logs:+$session_logs }$lf"
            session_urls="${session_urls:+$session_urls }${clink%%/job/*}"
            [ "$session_class" = flaky ] || session_class=real
            new_keys+=("$key") ;;
        esac
      fi
      [ "$mode" = dry ] && say "  - $repo#$pr $cname  [$bucket -> $cls: $why]  would: $action"
    done <<<"$fails"

    if [ "$mode" = dry ]; then
      [ -n "$session_checks" ] && g_act='S'
      [ "${#rerun_rids[@]}" -gt 0 ] && g_act='R'
    else
      # Reruns first, and they take the whole tick for this PR: a session must not
      # race a rerun of the same commit.  The session, if any, comes next tick.
      if [ "${#rerun_rids[@]}" -gt 0 ] && [ "$AUTO_RERUN" = 1 ] && [ "$reruns" -lt "$MAX_RERUNS_PER_TICK" ]; then
        done_rids=""
        for rid in "${rerun_rids[@]}"; do
          case " $done_rids " in *" $rid "*) continue ;; esac
          done_rids="$done_rids $rid"
          if gh run rerun "$rid" --repo "$OWNER/$repo" --failed >>"$TICK_LOG" 2>&1 </dev/null; then
            log "$repo#$pr@$sha7: reran failed jobs of run $rid (transient failure)"
            reruns=$((reruns + 1)); g_act='R'
          else
            log "$repo#$pr@$sha7: rerun of $rid failed (still running, or no rerunnable jobs)"
          fi
        done
        if [ "$g_act" = 'R' ]; then
          handled_json="$(jq -c --argjson a "$(json_array ${rerun_keys_new[@]+"${rerun_keys_new[@]}"})" '. + $a | unique' <<<"$handled_json")" 2>/dev/null || :
          rkeys_json="$(jq -c --argjson a "$(json_array ${rerun_keys_new[@]+"${rerun_keys_new[@]}"})" '. + $a | unique' <<<"$rkeys_json")"
          rshas_json="$(jq -c --argjson a "$(json_array "$head_sha")" '. + $a | unique' <<<"$rshas_json")"
          note="${note:+$note; }reran transient CI failure"
          printf 'rerun\t%s#%s\n' "$repo" "$pr" >>"$ACT"
        fi
      elif [ "${#giveup_keys[@]}" -gt 0 ] && [ -z "$session_checks" ]; then
        handled_json="$(jq -c --argjson a "$(json_array ${giveup_keys[@]+"${giveup_keys[@]}"})" '. + $a | unique' <<<"$handled_json")"
        log "$repo#$pr@$sha7: infra failure survived its rerun; marked handled, needs a human"
        note="${note:+$note; }CI infra failure survived a rerun -- needs a human"
        notify "$repo#$pr: CI infra failure survived a rerun - look at it"
        printf 'ci-infra\t%s#%s\n' "$repo" "$pr" >>"$ACT"
      elif [ -n "$session_checks" ]; then
        if [ "$sessions" -ge "$MAX_SESSIONS_PER_TICK" ] && [ "$mode" = tick ]; then
          note="${note:+$note; }fix session queued for the next tick (MAX_SESSIONS_PER_TICK=$MAX_SESSIONS_PER_TICK)"
        elif [ "$mode" = tick ] && [ "$runs" -ge "$MAX_RUNS_PER_PR" ]; then
          note="${note:+$note; }hit MAX_RUNS_PER_PR=$MAX_RUNS_PER_PR (clear $(state_file "$repo" "$pr"))"
        else
          for k in ${giveup_keys[@]+"${giveup_keys[@]}"}; do new_keys+=("$k"); done
          combined="$LOG_DIR/${repo}-${pr}-${sha7}.failed.log"
          : >"$combined"
          for lf in $session_logs; do
            printf '\n===== %s =====\n' "$lf" >>"$combined"
            cat "$lf" >>"$combined" 2>/dev/null
          done
          if launch "$repo" "$pr" "$url" "$branch" "$head_sha" "$session_class" \
                    "$session_checks" "$combined" "$session_urls" "$bot_wt"; then
            handled_json="$(jq -c --argjson a "$(json_array ${new_keys[@]+"${new_keys[@]}"})" '. + $a | unique' <<<"$handled_json")"
          fi
          runs=$((runs + 1)); sessions=$((sessions + 1)); g_act='S'
          note="${note:+$note; }fix session: $SESSION_OUTCOME"
          # local-only commits are not lost and not stale: next tick publishes them
          [ "$SESSION_OUTCOME" = local-only ] && pending_pub=true
          [ "$SESSION_OUTCOME" = pushed ] && pending_pub=false
          printf 'session\t%s#%s\t%s\n' "$repo" "$pr" "$session_checks" >>"$ACT"
        fi
      fi
    fi
  fi

  [ "$pub_state" = pushed ] && pending_pub=false

  # behind-ness AFTER this tick: a successful rebase clears it
  still_behind="$behind"
  [ "$rb_state" = rebased ] && still_behind=0

  # --- 5. report ---------------------------------------------------------------
  g_dr='.'
  if [ "$is_draft" = true ]; then
    if [ "$ci" = pass ] && [ "$still_behind" -eq 0 ] && [ "$body_len" -ge 30 ]; then
      g_dr='*'; n_ready=$((n_ready + 1))
      note="${note:+$note; }looks ready: gh pr ready $pr --repo $OWNER/$repo"
      printf 'ready\t%s#%s\n' "$repo" "$pr" >>"$ACT"
    else
      g_dr='d'
    fi
  fi

  g_hk='.'
  conflicting_now=0
  [ "$mergeable" = CONFLICTING ] && conflicting_now=1
  old_conflict=0
  { [ "$conflicting_now" = 1 ] && [ -n "$conf_since" ]; } && old_conflict=1
  [ "$rb_state" = conflict ] && [ -n "$conf_since" ] && old_conflict=1

  if [ "$quiet_days" -gt "$STALE_DAYS" ] || [ "$old_conflict" = 1 ]; then
    g_hk='~'; n_stale=$((n_stale + 1))
    [ "$quiet_days" -gt "$STALE_DAYS" ] && note="${note:+$note; }stale: quiet for ${quiet_days}d"
    [ "$old_conflict" = 1 ] && note="${note:+$note; }merge conflict predates this tick"
    printf 'stale\t%s#%s\n' "$repo" "$pr" >>"$ACT"
  elif [ "$decision" = APPROVED ] && [ "$ci" = pass ] && [ "$still_behind" -eq 0 ] \
       && [ "$is_draft" != true ] && [ "$conflicting_now" = 0 ]; then
    g_hk='>'; n_merge=$((n_merge + 1))
    note="${note:+$note; }approved + green + up to date: ready to merge"
    printf 'mergeable\t%s#%s\n' "$repo" "$pr" >>"$ACT"
  fi

  [ "$ci" = fail ] && { note="${note:+$note; }CI red: ${failed_jobs:-unknown job}"
                        printf 'ci-red\t%s#%s\t%s\n' "$repo" "$pr" "$failed_jobs" >>"$ACT"; }
  [ "$rb_state" = rebased ]  && printf 'rebased\t%s#%s\n' "$repo" "$pr" >>"$ACT"
  [ "$rb_state" = conflict ] && printf 'conflict\t%s#%s\t%s\n' "$repo" "$pr" "$note" >>"$ACT"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$g_rb" "$g_ci" "$g_act" "$g_dr" "$g_hk" \
         "$(printf '#%-6s %-16s %s' "$pr" "$repo" "$title")" "$note" >>"$ROWS"

  # --- persist -----------------------------------------------------------------
  if [ "$mode" != dry ]; then
    bump=0
    case "$rb_state" in conflict) bump=1 ;; esac
    [ "$mode" = seed ] && bump=0
    seeded_handled="$handled_json"
    if [ "$mode" = seed ]; then
      seeded_handled="$(json_array ${seed_keys[@]+"${seed_keys[@]}"})"
      [ "$seeded_handled" = "[]" ] && seeded_handled="$handled_json"
    fi
    jq -n --argjson prev "$prev" --arg repo "$repo" --arg pr "$pr" \
          --arg head "$head_sha" --arg basetip "$basetip" --arg st "$rb_state" \
          --arg url "$url" --arg now "$(date '+%F %T')" --arg cpaths "$cpaths_out" \
          --arg note "$note" --argjson bump "$bump" --argjson runs "$runs" \
          --argjson handled "$seeded_handled" --argjson rk "$rkeys_json" --argjson rs "$rshas_json" \
          --argjson pending "$([ "$pending_pub" = true ] && echo true || echo false)" \
          --argjson conflicting "$([ "$rb_state" = conflict ] && echo true || echo false)" '
        { repo: $repo, pr: ($pr | tonumber), url: $url, last_seen: $now,
          last_head: $head, last_base: $basetip, last_status: $st, last_note: $note,
          attempts: (if $st == "rebased" then 0 else (($prev.attempts // 0) + $bump) end),
          rebases: (($prev.rebases // 0) + (if $st == "rebased" then 1 else 0 end)),
          last_rebase: (if $st == "rebased" then $now else ($prev.last_rebase // null) end),
          runs: $runs,
          handled:    (($handled | unique)[-400:]),
          rerun_keys: (($rk      | unique)[-400:]),
          rerun_shas: (($rs      | unique)[-40:]),
          pending_publish: $pending,
          conflict: (if $conflicting
                     then { head: $head, base: $basetip, paths: $cpaths,
                            since: ($prev.conflict.since // $now) }
                     else null end) }' >"$(state_file "$repo" "$pr")" 2>>"$TICK_LOG"
  fi
done < <(jq -r '.[] | [(.number | tostring), .repository.name, .url] | @tsv' <<<"$prs")

[ "$mode" != dry ] && [ "$WINDOW" = 1 ] && claim_rebase_window

# --- render the digest ----------------------------------------------------------
stamp="$(date '+%F %T')"
D="$RUN_TMP/digest.md"
{
  printf '# PR bot - %s%s\n\n' "$stamp" "$([ "$mode" = dry ] && printf ' (dry run)' || printf '')"
  printf '%s open PR(s) - ' "$n_total"
  if [ "$mode" = dry ]; then printf 'would rebase %s | ' "$n_would"
  else                       printf 'rebased %s | ' "$n_rebased"; fi
  printf 'published %s | conflict %s | behind %s | CI red %s | pending %s | ready %s | stale %s | mergeable %s\n' \
    "$n_published" "$n_conflict" "$n_behind" "$n_red" "$n_pending" "$n_ready" "$n_stale" "$n_merge"
  printf 'rebase window: %s\n\n' "$([ "$WINDOW" = 1 ] && printf 'OPEN' || printf 'closed (opens at %s)' "${REBASE_WINDOWS// /:00, }:00")"
  printf '```\n'
  printf 'col 1  rebase   ^ rebased+pushed    ! conflict, needs you   v behind, waiting   . in sync\n'
  printf 'col 2  ci       + green             x red                   o pending           . no checks\n'
  printf 'col 3  action   S fix session       R rerun                 P published commits . nothing\n'
  printf 'col 4  draft    * ready to undraft  d still a draft         . not a draft\n'
  printf 'col 5  house    > mergeable         ~ stale / old conflict  . nothing\n'
  printf '```\n\n'
  if [ ! -s "$ROWS" ]; then
    printf '_no open PRs_\n'
  else
    while IFS=$'\t' read -r a b c d e label note; do
      [ -n "$label" ] || continue
      if [ -n "$note" ]; then printf '    %s %s %s %s %s  %s  -- %s\n' "$a" "$b" "$c" "$d" "$e" "$label" "$note"
      else                    printf '    %s %s %s %s %s  %s\n'        "$a" "$b" "$c" "$d" "$e" "$label"; fi
    done <"$ROWS"
  fi
  printf '\n_%s - %s_\n' "$0" "$([ "$mode" = dry ] && printf 'nothing was changed' || printf 'mode=%s' "$mode")"
} >"$D"

if [ "$mode" = dry ]; then
  say ""
  cat "$D"
  say ""
  say "dry run: no worktree was created or cleaned, nothing was rebased, pushed, rerun or recorded."
  exit 0
fi

cp "$D" "$DIGEST"
{ printf '\n===== %s (%s) =====\n' "$stamp" "$mode"; cat "$D"; } >>"$LOG_DIR/sweep-$(date '+%Y-%m-%d').log"

# --- notify only when the actionable set actually changed ------------------------
sort "$ACT" >"$RUN_TMP/act.sorted" 2>/dev/null || : >"$RUN_TMP/act.sorted"
FP="$STATE_DIR/.last-actionable"
changed=1
[ -f "$FP" ] && cmp -s "$FP" "$RUN_TMP/act.sorted" && changed=0
cp "$RUN_TMP/act.sorted" "$FP" 2>/dev/null || :

if [ "$mode" = seed ]; then
  say "seeded $n_total PR(s); the next tick is silent unless something changes."
  log "seed done; PRs=$n_total"
  exit 0
fi

log "$mode done; PRs=$n_total window=$WINDOW rebased=$n_rebased published=$n_published conflict=$n_conflict behind=$n_behind ci_red=$n_red sessions=$sessions reruns=$reruns ready=$n_ready stale=$n_stale mergeable=$n_merge"

if [ "$changed" = 1 ] && [ -s "$RUN_TMP/act.sorted" ]; then
  summary=""
  [ "$n_rebased" -gt 0 ]   && summary="$summary${summary:+, }$n_rebased rebased"
  [ "$n_published" -gt 0 ] && summary="$summary${summary:+, }$n_published published"
  [ "$sessions" -gt 0 ]    && summary="$summary${summary:+, }$sessions fixed"
  [ "$n_conflict" -gt 0 ]  && summary="$summary${summary:+, }$n_conflict conflict"
  [ "$n_red" -gt 0 ]       && summary="$summary${summary:+, }$n_red CI red"
  [ "$n_ready" -gt 0 ]     && summary="$summary${summary:+, }$n_ready ready"
  [ "$n_merge" -gt 0 ]     && summary="$summary${summary:+, }$n_merge mergeable"
  [ "$n_stale" -gt 0 ]     && summary="$summary${summary:+, }$n_stale stale"
  [ -n "$summary" ] && notify "$summary - pr-bot.sh --status"
fi

if [ "$INTERACTIVE" = 1 ]; then
  cat "$DIGEST"
elif [ "$changed" = 0 ]; then
  log "nothing actionable changed since the last tick"
fi
exit 0
