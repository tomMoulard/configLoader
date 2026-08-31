#!/usr/bin/env bash
# Sweep my open SynthFlowAI PRs twice a day: rebase the ones that fell behind
# main, and report everything else instead of touching it.
#
#   pr-sweep.sh              one tick (what launchd runs)
#   pr-sweep.sh --dry-run    full read-only pass; prints the digest it WOULD write
#   pr-sweep.sh --seed       record today's state as the baseline, act on nothing
#   pr-sweep.sh --pr 2023    sweep one PR now, ignoring stored state
#   pr-sweep.sh --status     print the last digest
#
# What it does, per PR:
#   1. rebases onto its base branch when GitHub says it is behind -- in the PR's
#      own `wt` worktree, never in the main checkout, never in a dirty worktree
#      and never in one a live Claude session is sitting in.  A conflict is
#      aborted and reported; the branch is left byte-for-byte as it was.
#   2. reports CI (pass / fail / pending) and names the failing jobs.  It never
#      reruns anything -- ci-red-watch.sh owns failures.
#   3. flags drafts that look ready, stale PRs, and mergeable PRs.
#
# Why the worktree and not the checkout: the user's main clone is where they are
# working right now, and a rebase there would yank the floor out from under an
# editor.  A PR without a worktree is reported, not rebased.
#
# Why "local HEAD must equal origin/<branch>" before any rebase: the PR head is
# origin/<branch>.  If the worktree has drifted from it -- unpushed commits, or a
# push from another machine -- then rebasing and force-pushing would replace the
# PR with something the user never published.  Drift is reported, not resolved.
set -uo pipefail

OWNER=SynthFlowAI
CLONE_ROOTS="$HOME/go/src/github.com/synthflowai $HOME/workspace/local-mode"
STATE_DIR="$HOME/.claude/state/pr-sweep"
LOG_DIR="$HOME/.claude/logs/pr-sweep"
LOCK_DIR="$STATE_DIR/.lock"
DIGEST="$LOG_DIR/digest.md"

MAX_PRS_PER_TICK=40          # bound the API work; the org rarely has more open
MAX_REBASES_PER_TICK=6       # runaway guard: at most this many force-pushes a tick
MAX_ATTEMPTS_PER_PR=5        # stop retrying a PR that keeps failing to rebase
STALE_DAYS=7                 # no commit / comment / review in this many days
REBASE_TIMEOUT=180           # commit signing goes through 1Password; never hang
PUSH_TIMEOUT=120

# launchd hands us a bare PATH; gh, wt, jq and timeout all live outside it.
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

mkdir -p "$STATE_DIR" "$LOG_DIR"
TICK_LOG="$LOG_DIR/tick.log"
INTERACTIVE=0; [ -t 1 ] && INTERACTIVE=1
RUN_TAG="launchd:$$"; [ "$INTERACTIVE" = 1 ] && RUN_TAG="you:$$"
log()    { printf '%s  [%s] %s\n' "$(date '+%F %T')" "$RUN_TAG" "$*" >>"$TICK_LOG"
           [ "$INTERACTIVE" = 1 ] && printf '%s\n' "$*" >&2 || true; }
say()    { printf '%s\n' "$*"; }
# osascript is the only notifier on this machine (no terminal-notifier installed),
# and it is what coderabbit-watch.sh already uses.  Nothing outbound: no Slack, no
# PR comment -- the user's standing rule is nothing gets sent on their behalf.
notify() { osascript -e "display notification \"${1//\"/}\" with title \"PR sweep\"" >/dev/null 2>&1 || true; }

usage() { say "usage: $0 [--dry-run|--seed|--status|--pr <number>]"; }

mode=tick only_pr=""
case "${1:-}" in
  ""|--tick) ;;
  --dry-run) mode=dry ;;
  --seed)    mode=seed ;;
  --status)  mode=status ;;
  -h|--help) usage; exit 0 ;;
  --pr)      mode=manual; only_pr="${2:-}"
             [[ "$only_pr" =~ ^[0-9]+$ ]] || { say "usage: $0 --pr <number>"; exit 2; } ;;
  *)         usage; exit 2 ;;
esac

if [ "$mode" = status ]; then
  if [ -s "$DIGEST" ]; then cat "$DIGEST"; else say "no digest yet -- run: $0 --dry-run"; fi
  exit 0
fi

for bin in gh jq wt git timeout; do
  command -v "$bin" >/dev/null 2>&1 || { log "FATAL: $bin not found in PATH"; say "$bin not found"; exit 1; }
done

RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-sweep.XXXXXX")" || { say "cannot create temp dir"; exit 1; }
# LOCK_OWNED gates the cleanup: a run that lost the race must not delete the lock
# belonging to the run that won it.
LOCK_OWNED=0
cleanup() { rm -rf "$RUN_TMP"; [ "$LOCK_OWNED" = 1 ] && rm -rf "$LOCK_DIR"; return 0; }
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

state_file() { printf '%s/%s-%s.json' "$STATE_DIR" "$1" "$2"; }
state_read() { # repo pr -> the stored object, or {}
  local f; f="$(state_file "$1" "$2")"
  if [ -f "$f" ] && jq -e . "$f" >/dev/null 2>&1; then cat "$f"; else printf '{}'; fi
}

# First checkout whose origin really is $OWNER/<repo>.  Same two roots as
# coderabbit-watch.sh: the GOPATH tree, with ~/workspace/local-mode as fallback.
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
# `claude` processes, by cwd.  Cheap (~30ms) and collected once per run.
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

# --- wt worktrees, cached per repo ------------------------------------------------
wt_list() { # repodir repo
  local f="$RUN_TMP/wt-$2.json"
  if [ ! -f "$f" ]; then
    wt -C "$1" list --format json 2>/dev/null >"$f" || :
    jq -e . "$f" >/dev/null 2>&1 || printf '[]' >"$f"
  fi
  cat "$f"
}
wt_path_for_branch() { # repodir repo branch
  wt_list "$1" "$2" | jq -r --arg b "$3" \
    '[ .[]? | select(.kind == "worktree") | select(.is_main != true) | select(.branch == $b) | .path ][0] // empty' 2>/dev/null
}

# --- the rebase -------------------------------------------------------------------
# Sets REBASE_STATE (rebased|conflict|skip|would) and REBASE_NOTE.
# Never leaves a half-rebased worktree: every failure path ends with the worktree
# verified back at the SHA it started on.
REBASE_STATE=skip; REBASE_NOTE=""; REBASE_CONFLICTS=""
do_rebase() { # repo pr branch base wtpath behind
  local repo="$1" pr="$2" branch="$3" base="$4" wt="$5" behind="$6"
  local gd dirty head_local remote_head rc out conflicts new_head remote_now after
  REBASE_STATE=skip; REBASE_NOTE=""; REBASE_CONFLICTS=""

  # Dirtiness first, before anything is touched.  Tracked changes only: a rebase
  # does not rewrite untracked files, and git refuses outright rather than
  # clobbering one -- which lands in the abort path below.
  dirty="$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${dirty:-0}" != 0 ]; then
    REBASE_NOTE="worktree has $dirty uncommitted change(s); not touched"; return 0
  fi
  gd="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)"
  if [ -n "$gd" ] && { [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; }; then
    REBASE_NOTE="worktree is already mid-rebase; not touched"; return 0
  fi

  git -C "$wt" fetch --quiet origin \
      "+refs/heads/$base:refs/remotes/origin/$base" \
      "+refs/heads/$branch:refs/remotes/origin/$branch" >>"$TICK_LOG" 2>&1 || {
    REBASE_NOTE="git fetch origin failed; not rebased"; return 0; }

  head_local="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  remote_head="$(git -C "$wt" rev-parse --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null)"
  if [ -z "$head_local" ] || [ -z "$remote_head" ]; then
    REBASE_NOTE="cannot resolve HEAD or origin/$branch; not rebased"; return 0
  fi
  if [ "$head_local" != "$remote_head" ]; then
    REBASE_NOTE="worktree HEAD is out of sync with the PR head; not rebased"; return 0
  fi

  if [ "$mode" = dry ]; then
    REBASE_STATE=would
    REBASE_NOTE="WOULD rebase onto origin/$base ($behind behind) and force-push -- $wt"
    return 0
  fi

  # rebase.autoStash is true in the user's global config; force it off so a file
  # that appears between the check above and here fails loudly instead of being
  # silently stashed away.
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
      # --abort did not take us home.  The worktree was verified clean before we
      # started, so nothing of the user's can be lost by putting it back by hand.
      git -C "$wt" rebase --quit >>"$TICK_LOG" 2>&1
      git -C "$wt" reset --hard "$head_local" >>"$TICK_LOG" 2>&1
      after="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
    fi
    if [ "$after" != "$head_local" ]; then
      REBASE_STATE=conflict
      REBASE_NOTE="REBASE FAILED AND COULD NOT BE UNWOUND -- fix $wt by hand"
      log "$repo#$pr: could not restore $wt to $head_local after a failed rebase"
      notify "$repo#$pr: rebase could not be unwound -- fix $wt by hand"
      return 0
    fi
    REBASE_STATE=conflict
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
  if [ "$new_head" = "$head_local" ]; then
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

# Sourcing the script for tests stops here; below is the tick itself.
if [ "${PR_SWEEP_LIB:-0}" = 1 ]; then return 0; fi

# --- the tick -----------------------------------------------------------------
if [ "$mode" != dry ]; then
  take_lock || { log "another run is in progress; skipping tick"; exit 0; }
fi
collect_live_sessions

prs="$(gh search prs --author @me --state open --owner "$OWNER" --limit "$MAX_PRS_PER_TICK" \
         --json number,repository 2>>"$TICK_LOG")" || { log "gh search prs failed"; exit 1; }
[ -n "$prs" ] || { log "no open PRs"; exit 0; }

if [ -n "$only_pr" ]; then
  prs="$(jq --argjson n "$only_pr" '[.[] | select(.number == $n)]' <<<"$prs")"
  [ "$(jq 'length' <<<"$prs")" -gt 0 ] || { say "PR $only_pr is not an open PR of yours in $OWNER"; exit 1; }
fi

ROWS="$RUN_TMP/rows"; : >"$ROWS"
ACT="$RUN_TMP/actionable"; : >"$ACT"
n_total=0 n_rebased=0 n_conflict=0 n_behind=0 n_would=0
n_red=0 n_pending=0 n_ready=0 n_stale=0 n_merge=0
rebases_done=0

while IFS=$'\t' read -r pr repo; do
  [ -n "$pr" ] || continue
  n_total=$((n_total + 1))

  meta="$(gh pr view "$pr" --repo "$OWNER/$repo" --json \
            number,title,url,isDraft,body,headRefName,baseRefName,headRefOid,isCrossRepository,headRepositoryOwner,reviewDecision,mergeable,commits,comments,reviews 2>>"$TICK_LOG")"
  if [ -z "$meta" ] || ! jq -e . <<<"$meta" >/dev/null 2>&1; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' '?' '?' '?' '?' "#$pr $repo" "gh pr view failed" >>"$ROWS"
    log "$repo#$pr: gh pr view failed"
    continue
  fi

  title="$(jq -r '.title // ""' <<<"$meta")"
  url="$(jq -r '.url // ""' <<<"$meta")"
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

  # --- CI, reported only.  ci-red-watch.sh owns reruns; we stay out of its lane ---
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
  conf_head="$(jq -r '.conflict.head // ""' <<<"$prev")"
  conf_base="$(jq -r '.conflict.base // ""' <<<"$prev")"
  conf_paths="$(jq -r '.conflict.paths // ""' <<<"$prev")"
  conf_since="$(jq -r '.conflict.since // ""' <<<"$prev")"

  # --- decide, then act ---------------------------------------------------------
  rb_state=none; note=""; cpaths_out="$conf_paths"
  if [ "$cmp_ok" = 0 ]; then
    rb_state=skip; note="could not compare against $base; behind-ness unknown"
  elif [ "$behind" -eq 0 ]; then
    rb_state=insync
  elif [ "$cross" = true ]; then
    rb_state=skip; note="head is a fork ($head_owner); not rebased"
  elif [ "$mode" = seed ]; then
    rb_state=skip; note="$behind behind $base (seeded, not rebased)"
  elif [ -n "$conf_head" ] && [ "$conf_head" = "$head_sha" ] && [ "$conf_base" = "$basetip" ] && [ "$mode" != manual ]; then
    # Nothing has moved since the conflict, so the rebase would fail identically.
    # Skipping keeps an unchanged tick cheap and silent.
    rb_state=conflict
    note="conflict unchanged since ${conf_since:-earlier}${conf_paths:+ ($conf_paths)}"
  else
    rdir="$(repo_dir "$repo")"
    if [ -z "$rdir" ]; then
      rb_state=skip; note="$behind behind $base; no local clone under \$CLONE_ROOTS"
    else
      wtp="$(wt_path_for_branch "$rdir" "$repo" "$branch")"
      if [ -z "$wtp" ] || [ ! -d "$wtp" ]; then
        rb_state=skip; note="$behind behind $base; no wt worktree for $branch"
      elif is_live "$wtp"; then
        rb_state=skip; note="$behind behind $base; a live Claude session is in that worktree"
      elif [ "$mode" != manual ] && [ "$attempts" -ge "$MAX_ATTEMPTS_PER_PR" ]; then
        rb_state=skip; note="$behind behind $base; hit MAX_ATTEMPTS_PER_PR=$MAX_ATTEMPTS_PER_PR (clear $(state_file "$repo" "$pr"))"
      elif [ "$rebases_done" -ge "$MAX_REBASES_PER_TICK" ]; then
        rb_state=skip; note="$behind behind $base; MAX_REBASES_PER_TICK=$MAX_REBASES_PER_TICK reached this tick"
      else
        do_rebase "$repo" "$pr" "$branch" "$base" "$wtp" "$behind"
        rb_state="$REBASE_STATE"; note="$REBASE_NOTE"
        [ -n "$REBASE_CONFLICTS" ] && cpaths_out="$REBASE_CONFLICTS"
        [ "$rb_state" = rebased ] && { rebases_done=$((rebases_done + 1)); cpaths_out=""; }
        # a dry run burns the same budget, so its report matches a real tick
        [ "$rb_state" = would ] && rebases_done=$((rebases_done + 1))
        [ "$rb_state" = skip ] && [ -n "$note" ] && note="$behind behind $base; $note"
      fi
    fi
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

  # behind-ness AFTER this tick: a successful rebase clears it
  still_behind="$behind"
  [ "$rb_state" = rebased ] && still_behind=0

  # --- draft that looks ready -----------------------------------------------------
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

  # --- housekeeping: stale, mergeable ---------------------------------------------
  g_hk='.'
  conflicting_now=0
  [ "$mergeable" = CONFLICTING ] && conflicting_now=1
  # "predates this tick" = we already had it recorded before today's run
  old_conflict=0
  { [ "$conflicting_now" = 1 ] && [ -n "$conf_since" ]; } && old_conflict=1
  [ "$rb_state" = conflict ] && [ -n "$conf_since" ] && old_conflict=1

  if [ "$quiet_days" -gt "$STALE_DAYS" ] || [ "$old_conflict" = 1 ]; then
    g_hk='~'; n_stale=$((n_stale + 1))
    if [ "$quiet_days" -gt "$STALE_DAYS" ]; then
      note="${note:+$note; }stale: quiet for ${quiet_days}d"
    fi
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

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$g_rb" "$g_ci" "$g_dr" "$g_hk" \
         "$(printf '#%-6s %-16s %s' "$pr" "$repo" "$title")" "$note" >>"$ROWS"

  # --- persist ---------------------------------------------------------------------
  if [ "$mode" != dry ]; then
    bump=0
    case "$rb_state" in rebased|conflict) bump=1 ;; esac
    [ "$mode" = seed ] && bump=0
    f="$(state_file "$repo" "$pr")"
    jq -n --argjson prev "$prev" --arg repo "$repo" --arg pr "$pr" \
          --arg head "$head_sha" --arg basetip "$basetip" --arg st "$rb_state" \
          --arg url "$url" --arg now "$(date '+%F %T')" \
          --arg cpaths "$cpaths_out" \
          --arg note "$note" --argjson bump "$bump" \
          --argjson conflicting "$([ "$rb_state" = conflict ] && echo true || echo false)" '
        { repo: $repo, pr: ($pr | tonumber), url: $url, last_seen: $now,
          last_head: $head, last_base: $basetip, last_status: $st, last_note: $note,
          attempts: (if $st == "rebased" then 0 else (($prev.attempts // 0) + $bump) end),
          rebases: (($prev.rebases // 0) + (if $st == "rebased" then 1 else 0 end)),
          last_rebase: (if $st == "rebased" then $now else ($prev.last_rebase // null) end),
          conflict: (if $conflicting
                     then { head: $head, base: $basetip, paths: $cpaths,
                            since: ($prev.conflict.since // $now) }
                     else null end) }' >"$f" 2>>"$TICK_LOG"
  fi
done < <(jq -r '.[] | [(.number | tostring), .repository.name] | @tsv' <<<"$prs")

# --- render the digest ------------------------------------------------------------
stamp="$(date '+%F %T')"
D="$RUN_TMP/digest.md"
{
  printf '# PR sweep - %s%s\n\n' "$stamp" "$([ "$mode" = dry ] && printf ' (dry run)' || printf '')"
  printf '%s open PR(s) - ' "$n_total"
  if [ "$mode" = dry ]; then
    printf 'would rebase %s | ' "$n_would"
  else
    printf 'rebased %s | ' "$n_rebased"
  fi
  printf 'conflict %s | behind %s | CI red %s | pending %s | ready %s | stale %s | mergeable %s\n\n' \
    "$n_conflict" "$n_behind" "$n_red" "$n_pending" "$n_ready" "$n_stale" "$n_merge"
  printf '```\n'
  printf 'col 1  rebase   ^ rebased+pushed    ! conflict, needs you   v behind, skipped   . in sync\n'
  printf 'col 2  ci       + green             x red                   o pending           . no checks\n'
  printf 'col 3  draft    * ready to undraft  d still a draft         . not a draft\n'
  printf 'col 4  house    > mergeable         ~ stale / old conflict  . nothing\n'
  printf '```\n\n'
  if [ ! -s "$ROWS" ]; then
    printf '_no open PRs_\n'
  else
    while IFS=$'\t' read -r a b c d label note; do
      [ -n "$label" ] || continue
      if [ -n "$note" ]; then printf '    %s %s %s %s  %s  -- %s\n' "$a" "$b" "$c" "$d" "$label" "$note"
      else                    printf '    %s %s %s %s  %s\n'        "$a" "$b" "$c" "$d" "$label"; fi
    done <"$ROWS"
  fi
  printf '\n_%s - %s_\n' "$0" "$([ "$mode" = dry ] && printf 'nothing was changed' || printf 'mode=%s' "$mode")"
} >"$D"

if [ "$mode" = dry ]; then
  cat "$D"
  say ""
  say "dry run: nothing was fetched into a worktree, rebased, pushed or recorded."
  exit 0
fi

cp "$D" "$DIGEST"
{ printf '\n===== %s (%s) =====\n' "$stamp" "$mode"; cat "$D"; } >>"$LOG_DIR/sweep-$(date '+%Y-%m-%d').log"

# --- notify only when the actionable set actually changed ---------------------------
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

log "$mode done; PRs=$n_total rebased=$n_rebased conflict=$n_conflict behind=$n_behind ci_red=$n_red ready=$n_ready stale=$n_stale mergeable=$n_merge"

if [ "$changed" = 1 ] && [ -s "$RUN_TMP/act.sorted" ]; then
  summary=""
  [ "$n_rebased" -gt 0 ]  && summary="$summary${summary:+, }$n_rebased rebased"
  [ "$n_conflict" -gt 0 ] && summary="$summary${summary:+, }$n_conflict conflict"
  [ "$n_red" -gt 0 ]      && summary="$summary${summary:+, }$n_red CI red"
  [ "$n_ready" -gt 0 ]    && summary="$summary${summary:+, }$n_ready ready"
  [ "$n_merge" -gt 0 ]    && summary="$summary${summary:+, }$n_merge mergeable"
  [ "$n_stale" -gt 0 ]    && summary="$summary${summary:+, }$n_stale stale"
  [ -n "$summary" ] && notify "$summary - pr-sweep.sh --status"
fi

if [ "$INTERACTIVE" = 1 ]; then
  cat "$DIGEST"
elif [ "$changed" = 0 ]; then
  log "nothing actionable changed since the last tick"
fi
exit 0
