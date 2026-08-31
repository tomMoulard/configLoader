#!/usr/bin/env bash
# Watch my open SynthFlowAI PRs for a RED required check and deal with it:
# rerun what is plainly infrastructure, and launch an unattended Claude session
# in the PR's own `wt` worktree when the failure is the code's fault.
#
#   ci-red-watch.sh                     one tick (what launchd runs)
#   ci-red-watch.sh --dry-run           classify every failure, change nothing
#   ci-red-watch.sh --dry-run --pr 1961 same, for one PR
#   ci-red-watch.sh --seed              record every current failure as handled
#   ci-red-watch.sh --pr 2024           handle one PR now, ignoring stored state
#   ci-red-watch.sh --status            show what is tracked
#
# Why the state key is (PR, head SHA, check name) and not just the PR: a red
# check stays red until something is pushed, so "PR 2024 has a failing check" is
# true on every tick for hours and would relaunch a session every 30 minutes.
# Keying on the head SHA *and* the check name means the same failure on the same
# commit is handled exactly once, while the next push -- a new SHA, so a new key
# -- is picked up again, which is exactly what you want when the fix itself
# fails. Same reasoning as coderabbit-watch.sh's handled-comment-IDs.
#
# Lane: this job owns *failures*. pr-sweep.sh owns rebasing and reports CI state
# without acting on it. A PR that is red because it is behind or conflicting
# with main is classified, reported, and left for the sweeper -- never rebased
# here.
set -uo pipefail

OWNER=SynthFlowAI
CLONE_ROOTS="$HOME/go/src/github.com/synthflowai $HOME/workspace/local-mode $HOME/workspace"
STATE_DIR="$HOME/.claude/state/ci-red-watch"
LOG_DIR="$HOME/.claude/logs/ci-red-watch"
RUNLOG_DIR="$LOG_DIR/runlogs"
PROMPT_FILE="$HOME/.claude/scripts/ci-red-fix-prompt.md"
DEFLAKE_SKILL="$HOME/.claude/skills/deflake"
LOCK_DIR="$STATE_DIR/.lock"
MAX_PRS_PER_TICK=1      # one session per tick: 30-min cadence, no thundering herd
MAX_RUNS_PER_PR=3       # runaway guard, in case the fix keeps failing CI
MAX_RERUNS_PER_TICK=3   # `gh run rerun` is cheap, but not unlimited
SESSION_TIMEOUT=45m
GH_TIMEOUT=180          # per gh log download
CLAUDE_BIN="${CLAUDE_BIN:-claude}"   # override to test the launch path with a stub
AUTO_RERUN="${AUTO_RERUN:-1}"        # 0 = classify and report, never rerun

# launchd hands us a bare PATH; claude, gh, wt, jq and timeout all live outside it.
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

mkdir -p "$STATE_DIR" "$LOG_DIR" "$RUNLOG_DIR"
TICK_LOG="$LOG_DIR/tick.log"
INTERACTIVE=0; [ -t 1 ] && INTERACTIVE=1
RUN_TAG="launchd:$$"; [ "$INTERACTIVE" = 1 ] && RUN_TAG="you:$$"
log()    { printf '%s  [%s] %s\n' "$(date '+%F %T')" "$RUN_TAG" "$*" >>"$TICK_LOG"
           [ "$INTERACTIVE" = 1 ] && printf '%s\n' "$*" >&2 || true; }
say()    { printf '%s\n' "$*"; }
notify() { osascript -e "display notification \"${1//\"/}\" with title \"CI red watch\"" >/dev/null 2>&1 || true; }

# --- flags ---------------------------------------------------------------------
mode=tick only_pr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tick)    ;;
    --dry-run) mode=dry ;;
    --seed)    mode=seed ;;
    --status)  mode=status ;;
    --pr)      shift; only_pr="${1:-}"
               [[ "$only_pr" =~ ^[0-9]+$ ]] || { say "usage: $0 --pr <number>"; exit 2; }
               [ "$mode" = tick ] && mode=manual ;;
    *)         say "usage: $0 [--dry-run] [--seed|--status] [--pr <number>]"; exit 2 ;;
  esac
  shift
done

if [ "$mode" = status ]; then
  say "tracked PRs:"
  for f in "$STATE_DIR"/*.json; do
    [ -e "$f" ] || { say "  (none)"; break; }
    jq -r '"  \(.repo)#\(.pr)  runs=\(.runs)  handled=\(.handled|length)  reruns=\(.rerun_shas|length)  head=\(.last_head[0:7])  last=\(.last_run // "never")"' "$f"
  done
  exit 0
fi

for bin in gh jq wt timeout "$CLAUDE_BIN"; do
  command -v "$bin" >/dev/null 2>&1 || { log "FATAL: $bin not found in PATH"; say "$bin not found"; exit 1; }
done
[ -f "$PROMPT_FILE" ] || { log "FATAL: prompt file missing: $PROMPT_FILE"; exit 1; }

# --- single instance -----------------------------------------------------------
take_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then echo $$ >"$LOCK_DIR/pid"; return 0; fi
  local pid; pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 1; fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null && { echo $$ >"$LOCK_DIR/pid"; return 0; }
  return 1
}

# A per-PR lock, separate from the tick lock: `--pr N` run by hand must not fire
# a second session into a worktree a launchd tick is already driving.
PR_LOCK=""
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

state_file() { printf '%s/%s-%s.json' "$STATE_DIR" "$1" "$2"; }

# First checkout whose origin really is $OWNER/<repo>.  Repos live under the
# GOPATH tree; ~/workspace is kept as a fallback.
repo_dir() {
  local repo="$1" root dir
  for root in $CLONE_ROOTS; do
    dir="$root/$repo"
    [ -d "$dir/.git" ] || continue
    git -C "$dir" remote get-url origin 2>/dev/null | grep -qi "$OWNER/$repo\\(\\.git\\)\\?$" && { printf '%s' "$dir"; return 0; }
  done
  return 1
}

# --- state ---------------------------------------------------------------------
json_array() { # each argument becomes one string element; empties dropped
  local a; a=""
  for a in "$@"; do [ -n "$a" ] && printf '%s\n' "$a"; done | jq -R . | jq -s .
}

read_state() { # repo pr -> the json, or a fresh skeleton
  local f; f="$(state_file "$1" "$2")"
  if [ -f "$f" ]; then cat "$f"
  else printf '{"handled":[],"rerun_keys":[],"rerun_shas":[],"runs":0}'; fi
}

# handled/rerun lists are capped: they only need enough history to cover the
# SHAs still in play, and an unbounded list would grow for the life of the PR.
save_state() { # repo pr head bump handled_json rerun_keys_json rerun_shas_json
  jq -n --argjson prev "$(read_state "$1" "$2")" --arg repo "$1" --arg pr "$2" \
        --arg head "$3" --argjson bump "$4" --arg run "$(date '+%F %T')" \
        --argjson h "$5" --argjson rk "$6" --argjson rs "$7" \
    '{repo:$repo, pr:($pr|tonumber), last_head:$head, last_run:$run,
      runs: (($prev.runs // 0) + $bump),
      handled:     ((($prev.handled // []) + $h)      | unique | .[-400:]),
      rerun_keys:  ((($prev.rerun_keys // []) + $rk)  | unique | .[-400:]),
      rerun_shas:  ((($prev.rerun_shas // []) + $rs)  | unique | .[-40:])}' \
    >"$(state_file "$1" "$2")"
}

in_list() { # needle json_array
  jq -e --arg x "$1" 'index($x) != null' <<<"$2" >/dev/null 2>&1
}

# --- GitHub ---------------------------------------------------------------------
pr_meta() { # repo pr
  gh pr view "$2" --repo "$OWNER/$1" \
     --json headRefOid,headRefName,mergeStateStatus,mergeable,isDraft,url 2>/dev/null </dev/null
}

# Required checks if the branch is protected, every check otherwise.  Only the
# buckets that mean "red" -- pending and skipping are somebody else's problem.
failing_checks() { # repo pr -> name \t bucket \t link, one per line
  local out
  out="$(gh pr checks "$2" --repo "$OWNER/$1" --required --json name,bucket,link,workflow 2>/dev/null </dev/null)"
  [ -n "$out" ] && [ "$out" != "[]" ] || \
    out="$(gh pr checks "$2" --repo "$OWNER/$1" --json name,bucket,link,workflow 2>/dev/null </dev/null)"
  [ -n "$out" ] || return 0
  jq -r '.[]? | select(.bucket == "fail" or .bucket == "cancel")
         | [.name, .bucket, (.link // ""), (.workflow // "")] | @tsv' <<<"$out" 2>/dev/null
}

run_id() { # https://github.com/o/r/actions/runs/123/job/456 -> 123
  printf '%s' "$1" | sed -n 's#.*/actions/runs/\([0-9][0-9]*\).*#\1#p'
}

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

# --- classification --------------------------------------------------------------
# A deterministic failure wins over an infra signal, because a cancellation is
# very often the *consequence* of another job going red (fail-fast cancels its
# siblings).  Look for something that is unambiguously the code's fault first.
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
  # Something failed, nothing in the log says what.  A session reads it better
  # than a regex does, so this goes to a human-shaped reader, not to a rerun.
  CLASS=real; REASON="unrecognised failure, needs reading"
}

# --- session --------------------------------------------------------------------
# no-commits | pushed | local-only  -- given the worktree and its pre-session HEAD
session_outcome() { # wtpath head_before
  local wt="$1" before="$2" after branch remote
  after="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  if [ -z "$after" ] || [ "$after" = "$before" ]; then printf 'no-commits'; return; fi
  git -C "$wt" fetch --quiet origin 2>/dev/null
  branch="$(git -C "$wt" branch --show-current 2>/dev/null)"
  if [ -n "$branch" ]; then
    remote="$(git -C "$wt" rev-parse --verify --quiet "origin/$branch" 2>/dev/null)"
    [ "$remote" = "$after" ] && { printf 'pushed'; return; }
  fi
  printf 'local-only'
}

sedsafe() { printf '%s' "$1" | tr -d '&|\\' | tr '\n' ' '; }

launch() { # repo pr url branch head class checks logfile runurls
  local repo="$1" pr="$2" url="$3" branch="$4" head="$5" class="$6" checks="$7" logfile="$8" runurls="$9"
  local sha7="${head:0:7}" dir wtpath

  if ! take_pr_lock "$repo" "$pr"; then
    log "$repo#$pr: a session is already running for this PR; not launching another"; return 1
  fi
  if ! dir="$(repo_dir "$repo")"; then
    log "$repo#$pr: no local checkout of $OWNER/$repo found under: $CLONE_ROOTS"; drop_pr_lock; return 1
  fi

  git -C "$dir" fetch --quiet origin 2>>"$TICK_LOG" || log "$repo#$pr: fetch failed, continuing"

  wtpath="$(wt -C "$dir" switch "pr:$pr" --no-cd --format json -y 2>>"$TICK_LOG" | jq -r '.path // empty')"
  if [ -z "$wtpath" ] || [ ! -d "$wtpath" ]; then
    log "$repo#$pr: could not prepare a worktree; skipping"; drop_pr_lock; return 1
  fi

  # Never start on top of somebody's uncommitted work.
  if [ -n "$(git -C "$wtpath" status --porcelain 2>/dev/null)" ]; then
    log "$repo#$pr: worktree $wtpath is dirty; refusing to launch"; drop_pr_lock; return 1
  fi

  # Put the worktree on the PR head that CI actually failed on -- fast-forward
  # only, so local commits that are ahead of the PR are never stomped (and if we
  # are ahead, the red run is stale anyway and the next push re-triggers CI).
  git -C "$wtpath" fetch --quiet origin "$branch" 2>>"$TICK_LOG"
  local at; at="$(git -C "$wtpath" rev-parse HEAD 2>/dev/null)"
  if [ "$at" != "$head" ]; then
    if ! git -C "$wtpath" merge --ff-only "origin/$branch" >>"$TICK_LOG" 2>&1; then
      log "$repo#$pr: worktree is at ${at:0:7}, PR head is $sha7 and will not fast-forward; skipping"
      drop_pr_lock; return 1
    fi
    at="$(git -C "$wtpath" rev-parse HEAD 2>/dev/null)"
    [ "$at" = "$head" ] || { log "$repo#$pr: worktree at ${at:0:7} != PR head $sha7 after ff; skipping"; drop_pr_lock; return 1; }
  fi

  local note
  case "$class" in
    flaky) note="This check already went green once on this exact commit and a rerun did not clear it, so treat it as a flake: use the deflake skill at $DEFLAKE_SKILL/SKILL.md and measure the failure rate before changing anything." ;;
    *)     note="This is a deterministic failure: it fails the same way on every run of this commit." ;;
  esac

  local runlog="$LOG_DIR/${repo}-${pr}-${sha7}.log"
  local prompt
  prompt="$(sed -e "s|{{OWNER}}|$OWNER|g" -e "s|{{NAME}}|$repo|g" -e "s|{{REPO}}|$OWNER/$repo|g" \
                -e "s|{{PR}}|$pr|g" -e "s|{{URL}}|$url|g" -e "s|{{BRANCH}}|$(sedsafe "$branch")|g" \
                -e "s|{{HEAD}}|$head|g" -e "s|{{WORKTREE}}|$wtpath|g" \
                -e "s|{{CHECKS}}|$(sedsafe "$checks")|g" -e "s|{{LOG_FILE}}|$logfile|g" \
                -e "s|{{RUN_URLS}}|$(sedsafe "$runurls")|g" \
                -e "s|{{CLASS}}|$class|g" -e "s|{{CLASS_NOTE}}|$(sedsafe "$note")|g" \
                "$PROMPT_FILE")"

  local head_before; head_before="$(git -C "$wtpath" rev-parse HEAD 2>/dev/null)"

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
  local rc=$?

  local outcome; outcome="$(session_outcome "$wtpath" "$head_before")"
  local commits=0
  [ "$outcome" != no-commits ] && commits="$(git -C "$wtpath" rev-list --count "$head_before..HEAD" 2>/dev/null || echo 0)"

  log "$repo#$pr@$sha7: session exit=$rc outcome=$outcome commits=$commits worktree=$wtpath"
  if [ "$rc" -ne 0 ]; then
    notify "$repo#$pr: session FAILED (exit $rc) - see $runlog"
  elif [ "$outcome" = no-commits ]; then
    notify "$repo#$pr: session changed nothing - see $runlog"
  elif [ "$outcome" = pushed ]; then
    notify "$repo#$pr: $commits commit(s) pushed, CI should re-run"
  else
    notify "$repo#$pr: $commits commit(s) NOT pushed - review $wtpath"
  fi

  drop_pr_lock
  # A session that failed does not get its checks marked handled, so the next
  # tick retries them; runs still climbs, so MAX_RUNS_PER_PR ends the retrying.
  return $rc
}

# Sourcing the script for tests stops here; below is the tick itself.
if [ "${CI_RED_WATCH_LIB:-0}" = 1 ]; then return 0; fi

# --- the tick ----------------------------------------------------------------
if [ "$mode" != dry ]; then
  take_lock || { log "another run is in progress; skipping tick"; exit 0; }
  trap 'drop_pr_lock; rm -rf "$LOCK_DIR"' EXIT
fi

prs="$(gh search prs --author @me --state open --owner "$OWNER" --limit 50 \
         --json number,url,repository 2>>"$TICK_LOG")" || { log "gh search failed"; exit 1; }
[ -n "$prs" ] || { log "no open PRs"; exit 0; }

if [ -n "$only_pr" ]; then
  prs="$(jq --argjson n "$only_pr" '[.[] | select(.number == $n)]' <<<"$prs")"
  [ "$(jq 'length' <<<"$prs")" -gt 0 ] || { say "PR $only_pr is not an open PR of yours in $OWNER"; exit 1; }
fi

sessions=0 reruns=0 checked=0 red=0 already=0
while IFS=$'\t' read -r pr repo url; do
  [ -n "$pr" ] || continue
  [ "$mode" = tick ] && [ "$sessions" -ge "$MAX_PRS_PER_TICK" ] && break

  checked=$((checked + 1))

  fails="$(failing_checks "$repo" "$pr")"
  [ -n "$fails" ] || continue
  red=$((red + 1))

  meta="$(pr_meta "$repo" "$pr")"
  head="$(jq -r '.headRefOid // empty' <<<"$meta")"
  branch="$(jq -r '.headRefName // empty' <<<"$meta")"
  mss="$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$meta")"
  mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$meta")"
  [ -n "$head" ] || { log "$repo#$pr: could not read head SHA; skipping"; continue; }
  sha7="${head:0:7}"

  # pr-sweep.sh owns "behind main" and merge conflicts.  Classify and report so
  # the dry-run still tells the whole story, but take no action.
  lane_skip=""
  case "$mss" in
    BEHIND) lane_skip="behind main (mergeStateStatus=BEHIND) - pr-sweep's lane" ;;
    DIRTY)  lane_skip="conflicts with main (mergeStateStatus=DIRTY) - pr-sweep's lane" ;;
  esac
  [ -z "$lane_skip" ] && [ "$mergeable" = CONFLICTING ] && lane_skip="conflicts with main (mergeable=CONFLICTING) - pr-sweep's lane"

  st="$(read_state "$repo" "$pr")"
  handled_json="$(jq -c '.handled // []' <<<"$st")"
  rkeys_json="$(jq -c '.rerun_keys // []' <<<"$st")"
  rshas_json="$(jq -c '.rerun_shas // []' <<<"$st")"
  runs="$(jq -r '.runs // 0' <<<"$st")"
  sha_reran=0; in_list "$head" "$rshas_json" && sha_reran=1

  [ "$mode" = dry ] && say "$repo#$pr  head=$sha7  runs=$runs"
  [ "$mode" = dry ] && [ -n "$lane_skip" ] && say "  ! $lane_skip; classifying only"

  new_keys=(); seed_keys=(); rerun_rids=(); rerun_keys_new=()
  session_checks=""; session_class=""; session_logs=""; session_urls=""
  giveup_keys=()

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
    if [ "$cls" = real ] && prior_success "$repo" "$cwf" "$head" "$rid" "$cname"; then
      cls=flaky; why="passed on another run of $sha7; $why"
    fi

    known=0
    if [ "$mode" != manual ] && in_list "$key" "$handled_json"; then known=1; fi

    action=""
    if [ "$known" = 1 ]; then
      action="nothing (already handled)"
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
            session_class=flaky
            new_keys+=("$key")
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
          new_keys+=("$key")
          ;;
      esac
    fi
    [ "$known" = 1 ] && already=$((already + 1))

    if [ "$mode" = dry ]; then
      # the lane rule only overrides an action we would otherwise have taken
      case "$action" in nothing*) ;; *) [ -n "$lane_skip" ] && action="nothing (deferred to pr-sweep)" ;; esac
      say "  - $cname  [$bucket -> $cls: $why]  would: $action"
    fi
  done <<<"$fails"

  case "$mode" in
    seed)
      save_state "$repo" "$pr" "$head" 0 "$(json_array ${seed_keys[@]+"${seed_keys[@]}"})" '[]' '[]'
      say "seeded $repo#$pr (${#seed_keys[@]} current failure(s) marked handled)"
      continue ;;
    dry)
      continue ;;
  esac

  [ -n "$lane_skip" ] && { log "$repo#$pr: $lane_skip; no action"; continue; }

  # Reruns first, and they take the whole tick for this PR: a session must not
  # race a rerun of the same commit.  The session, if any, comes next tick.
  if [ "${#rerun_rids[@]}" -gt 0 ]; then
    if [ "$AUTO_RERUN" != 1 ]; then
      log "$repo#$pr@$sha7: AUTO_RERUN=0, not rerunning ${#rerun_rids[@]} run(s)"
      continue
    fi
    if [ "$reruns" -ge "$MAX_RERUNS_PER_TICK" ]; then
      log "$repo#$pr@$sha7: hit MAX_RERUNS_PER_TICK=$MAX_RERUNS_PER_TICK; leaving for the next tick"
      continue
    fi
    done_rids=""
    for rid in "${rerun_rids[@]}"; do
      case " $done_rids " in *" $rid "*) continue ;; esac
      done_rids="$done_rids $rid"
      if gh run rerun "$rid" --repo "$OWNER/$repo" --failed >>"$TICK_LOG" 2>&1 </dev/null; then
        log "$repo#$pr@$sha7: reran failed jobs of run $rid (transient failure)"
        reruns=$((reruns + 1))
      else
        log "$repo#$pr@$sha7: rerun of $rid failed (still running, or no rerunnable jobs)"
      fi
    done
    save_state "$repo" "$pr" "$head" 0 '[]' \
      "$(json_array ${rerun_keys_new[@]+"${rerun_keys_new[@]}"})" "$(json_array "$head")"
    notify "$repo#$pr: reran transient CI failure"
    continue
  fi

  # Infra that survived its one rerun: stop looking at it, tell the human.
  if [ "${#giveup_keys[@]}" -gt 0 ] && [ -z "$session_checks" ]; then
    save_state "$repo" "$pr" "$head" 0 "$(json_array ${giveup_keys[@]+"${giveup_keys[@]}"})" '[]' '[]'
    log "$repo#$pr@$sha7: infra failure survived its rerun; marked handled, needs a human"
    notify "$repo#$pr: CI infra failure survived a rerun - look at it"
    continue
  fi

  [ -n "$session_checks" ] || continue

  # Infra keys that already burned their rerun ride along with the session's
  # keys, so they are not re-evaluated (and re-reported) on every later tick.
  for k in ${giveup_keys[@]+"${giveup_keys[@]}"}; do new_keys+=("$k"); done

  if [ "$mode" = tick ] && [ "$runs" -ge "$MAX_RUNS_PER_PR" ]; then
    log "$repo#$pr: hit MAX_RUNS_PER_PR=$MAX_RUNS_PER_PR; skipping (clear $(state_file "$repo" "$pr") to resume)"
    continue
  fi

  # One combined log for the session: every failing job of this commit.
  combined="$LOG_DIR/${repo}-${pr}-${sha7}.failed.log"
  : >"$combined"
  for lf in $session_logs; do
    printf '\n===== %s =====\n' "$lf" >>"$combined"
    cat "$lf" >>"$combined" 2>/dev/null
  done

  if launch "$repo" "$pr" "$url" "$branch" "$head" "$session_class" \
            "$session_checks" "$combined" "$session_urls"; then
    save_state "$repo" "$pr" "$head" 1 "$(json_array ${new_keys[@]+"${new_keys[@]}"})" '[]' '[]'
    sessions=$((sessions + 1))
  else
    save_state "$repo" "$pr" "$head" 1 '[]' '[]' '[]'
  fi
done < <(jq -r '.[] | [(.number|tostring), .repository.name, .url] | @tsv' <<<"$prs")

if [ "$mode" = tick ] || [ "$mode" = manual ]; then
  log "$mode done; checked=$checked red=$red sessions=$sessions reruns=$reruns"
fi
if [ "$mode" = dry ]; then
  say ""
  say "checked $checked open PR(s); $red with a red check. Nothing above was executed."
fi

if [ "$INTERACTIVE" = 1 ] && [ "$mode" != dry ] && [ "$mode" != seed ]; then
  if [ "$sessions" -eq 0 ] && [ "$reruns" -eq 0 ]; then
    if [ "$mode" = manual ]; then
      say "PR $only_pr has nothing red that this job can act on."
    else
      say "Checked $checked open PR(s), $red with a red check: nothing new to act on."
      [ "$already" -gt 0 ] && say "$already failing check(s) were already handled once. Force one with: $0 --pr <number>"
      say "(new CI failures are picked up on their own, every 30 min)"
    fi
  fi
fi
exit 0
