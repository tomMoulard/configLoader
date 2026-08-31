#!/usr/bin/env bash
# Watch my open SynthFlowAI PRs for CodeRabbit review feedback and launch an
# unattended Claude session to address it, in the PR's own `wt` worktree.
#
#   coderabbit-watch.sh              one tick (what launchd runs)
#   coderabbit-watch.sh --dry-run    report what a tick would do, launch nothing
#   coderabbit-watch.sh --seed       record all current feedback as handled
#   coderabbit-watch.sh --pr 2030    handle one PR now, ignoring stored state
#   coderabbit-watch.sh --status     show what is tracked
#
# Why handled-comment-IDs and not a fingerprint: the sessions never resolve
# threads (the human owns all PR communication), so "has unresolved CodeRabbit
# threads" stays true forever and would re-trigger on every tick. Tracking the
# comment IDs we have already handed to a session means only genuinely new
# CodeRabbit comments wake it up again.
set -uo pipefail

OWNER=SynthFlowAI
CLONE_ROOTS="$HOME/go/src/github.com/synthflowai $HOME/workspace/local-mode"
STATE_DIR="$HOME/.claude/state/coderabbit-watch"
LOG_DIR="$HOME/.claude/logs/coderabbit-watch"
PROMPT_FILE="$HOME/.claude/scripts/coderabbit-autofix-prompt.md"
LOCK_DIR="$STATE_DIR/.lock"
MAX_PRS_PER_TICK=1     # one PR per tick: 30-min cadence, no thundering herd
MAX_RUNS_PER_PR=5      # runaway guard, in case a fix keeps drawing new comments
SESSION_TIMEOUT=45m
CLAUDE_BIN="${CLAUDE_BIN:-claude}"   # override to test the launch path with a stub
RESOLVE_THREADS=1      # resolve the threads the session reports as addressed (0 = never)

# launchd hands us a bare PATH; claude, gh, wt and jq all live outside it.
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

mkdir -p "$STATE_DIR" "$LOG_DIR"
TICK_LOG="$LOG_DIR/tick.log"
INTERACTIVE=0; [ -t 1 ] && INTERACTIVE=1
RUN_TAG="launchd:$$"; [ "$INTERACTIVE" = 1 ] && RUN_TAG="you:$$"
log()    { printf '%s  [%s] %s\n' "$(date '+%F %T')" "$RUN_TAG" "$*" >>"$TICK_LOG"
           [ "$INTERACTIVE" = 1 ] && printf '%s\n' "$*" >&2 || true; }
say()    { printf '%s\n' "$*"; }
notify() { osascript -e "display notification \"${1//\"/}\" with title \"CodeRabbit autofix\"" >/dev/null 2>&1 || true; }

mode=tick only_pr=""
case "${1:-}" in
  ""|--tick) ;;
  --dry-run) mode=dry ;;
  --seed)    mode=seed ;;
  --status)  mode=status ;;
  --pr)      mode=manual; only_pr="${2:-}"
             [[ "$only_pr" =~ ^[0-9]+$ ]] || { say "usage: $0 --pr <number>"; exit 2; } ;;
  *)         say "usage: $0 [--dry-run|--seed|--status|--pr <number>]"; exit 2 ;;
esac

if [ "$mode" = status ]; then
  say "tracked PRs:"
  for f in "$STATE_DIR"/*.json; do
    [ -e "$f" ] || { say "  (none)"; break; }
    jq -r '"  \(.repo)#\(.pr)  runs=\(.runs)  handled=\(.handled_ids|length)  last=\(.last_run // "never")"' "$f"
  done
  exit 0
fi

for bin in gh jq wt "$CLAUDE_BIN"; do
  command -v "$bin" >/dev/null 2>&1 || { log "FATAL: $bin not found in PATH"; say "$bin not found"; exit 1; }
done

# --- single instance -----------------------------------------------------------
take_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then echo $$ >"$LOCK_DIR/pid"; return 0; fi
  local pid; pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 1; fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null && { echo $$ >"$LOCK_DIR/pid"; return 0; }
  return 1
}
state_file() { printf '%s/%s-%s.json' "$STATE_DIR" "$1" "$2"; }

# First checkout whose origin really is $OWNER/<repo>.  Repos live under the
# GOPATH tree; ~/workspace/local-mode is kept as a fallback.
repo_dir() {
  local repo="$1" root dir
  for root in $CLONE_ROOTS; do
    dir="$root/$repo"
    [ -d "$dir/.git" ] || continue
    git -C "$dir" remote get-url origin 2>/dev/null | grep -qi "$OWNER/$repo\\(\\.git\\)\\?$" && { printf '%s' "$dir"; return 0; }
  done
  return 1
}

# CodeRabbit's unresolved threads on a PR, plus the head SHA.
feedback() { # owner repo pr
  gh api graphql -F owner="$1" -F repo="$2" -F pr="$3" -f query='
    query($owner:String!,$repo:String!,$pr:Int!){
      repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
        headRefOid
        reviewThreads(first:100){ nodes{
          id isResolved isOutdated
          comments(first:1){ nodes{ databaseId author{login} path } } } } } } }' 2>/dev/null
}

unresolved_ids() { # graphql json -> one comment id per line
  jq -r '[.data.repository.pullRequest.reviewThreads.nodes[]?
          | select(.isResolved == false)
          | select(.comments.nodes[0].author.login | test("coderabbit";"i"))
          | .comments.nodes[0].databaseId] | sort | .[]' <<<"$1" 2>/dev/null
}

record() { # repo pr head ids... (marks ids handled, bumps run count)
  local repo="$1" pr="$2" head="$3"; shift 3 || true
  local f; f="$(state_file "$repo" "$pr")"
  local prev='{"handled_ids":[],"runs":0}'
  [ -f "$f" ] && prev="$(cat "$f")"
  jq -n --argjson prev "$prev" --arg repo "$repo" --arg pr "$pr" --arg head "$head" \
        --arg run "$(date '+%F %T')" --argjson new "$(for i in "$@"; do [ -n "$i" ] && printf '%s\n' "$i"; done | jq -R . | jq -s .)" \
        --argjson bump "$([ "$mode" = seed ] && echo 0 || echo 1)" \
    '{repo:$repo, pr:($pr|tonumber), last_head:$head, last_run:$run,
      runs: (($prev.runs // 0) + $bump),
      handled_ids: (($prev.handled_ids // []) + $new | unique)}' >"$f"
}

# --- handle one PR ------------------------------------------------------------
# Resolve the CodeRabbit threads the session reports as addressed.
#
# The session writes {"addressed":[commentId,...],"skipped":[...]} and never
# touches GitHub itself: a thread it deliberately skipped (outdated, or the
# comment was wrong) must stay open, otherwise "resolved" stops meaning
# anything to the humans reading the PR.  No file, or an empty list, resolves
# nothing.
RESOLVED_N=0
resolve_threads() { # repo pr result_file
  local repo="$1" pr="$2" rf="$3" addressed fb did tid
  RESOLVED_N=0
  [ "$RESOLVE_THREADS" = 1 ] || return 0
  if [ ! -s "$rf" ]; then
    log "$repo#$pr: session left no result file ($rf); resolving nothing"; return 0
  fi
  addressed="$(jq -c '[.addressed[]? | tostring]' "$rf" 2>/dev/null)"
  if [ -z "$addressed" ] || [ "$addressed" = "[]" ]; then
    log "$repo#$pr: session addressed nothing it could name; resolving nothing"; return 0
  fi
  fb="$(feedback "$OWNER" "$repo" "$pr")"
  local open_ids
  open_ids="$(jq -c '[.data.repository.pullRequest.reviewThreads.nodes[]?
                      | select(.isResolved == false)
                      | (.comments.nodes[0].databaseId|tostring)]' <<<"$fb" 2>/dev/null)"
  [ -n "$open_ids" ] || open_ids='[]'
  while IFS="$(printf '\t')" read -r did tid; do
    [ -n "$tid" ] || continue
    jq -e --arg id "$did" 'index($id) != null' <<<"$addressed" >/dev/null 2>&1 || continue
    if gh api graphql -F tid="$tid" -f query='
        mutation($tid:ID!){ resolveReviewThread(input:{threadId:$tid}){ thread{ isResolved } } }' \
        >/dev/null 2>&1; then
      RESOLVED_N=$((RESOLVED_N + 1))
    else
      log "$repo#$pr: could not resolve thread $tid (comment $did)"
    fi
  done < <(jq -r '.data.repository.pullRequest.reviewThreads.nodes[]?
                  | select(.isResolved == false)
                  | select(.comments.nodes[0].author.login | test("coderabbit";"i"))
                  | [(.comments.nodes[0].databaseId|tostring), .id] | @tsv' <<<"$fb")
  # CodeRabbit resolves its own threads once it sees the fix, so "resolved 0" is
  # usually "nothing left to do" rather than a failure.  Name the difference.
  local gone; gone="$(jq -n --argjson a "$addressed" --argjson o "$open_ids" \
                        '[$a[] as $x | select(($o | index($x)) == null)] | length')"
  if [ "$RESOLVED_N" -gt 0 ]; then
    log "$repo#$pr: resolved $RESOLVED_N CodeRabbit thread(s)"
  elif [ "$gone" -gt 0 ]; then
    log "$repo#$pr: nothing to resolve - all $gone addressed thread(s) were already resolved (CodeRabbit does this itself once it sees the fix)"
  else
    log "$repo#$pr: resolved 0 thread(s)"
  fi
}

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

handle() { # repo pr url head ids...
  local repo="$1" pr="$2" url="$3" head="$4"; shift 4
  local ids_n=$#
  local ids=("$@")
  local dir
  if ! dir="$(repo_dir "$repo")"; then
    log "$repo#$pr: no local checkout of $OWNER/$repo found under: $CLONE_ROOTS"; return 1
  fi

  git -C "$dir" fetch --quiet origin 2>>"$TICK_LOG" || log "$repo#$pr: fetch failed, continuing"

  local wtpath
  wtpath="$(wt -C "$dir" switch "pr:$pr" --no-cd --format json -y 2>>"$TICK_LOG" | jq -r '.path // empty')"
  if [ -z "$wtpath" ] || [ ! -d "$wtpath" ]; then
    log "$repo#$pr: could not prepare a worktree; skipping"; return 1
  fi

  local stamp; stamp="$(date '+%Y%m%d-%H%M%S')"
  local runlog="$LOG_DIR/${repo}-${pr}-${stamp}.log"
  local resultfile="$LOG_DIR/${repo}-${pr}-${stamp}.result.json"
  local prompt
  prompt="$(sed -e "s|{{REPO}}|$OWNER/$repo|g" -e "s|{{OWNER}}|$OWNER|g" \
                -e "s|{{NAME}}|$repo|g" -e "s|{{PR}}|$pr|g" -e "s|{{URL}}|$url|g" \
                -e "s|{{RESULT_FILE}}|$resultfile|g" "$PROMPT_FILE")"

  local head_before; head_before="$(git -C "$wtpath" rev-parse HEAD 2>/dev/null)"

  log "$repo#$pr: $ids_n new CodeRabbit comment(s); session -> $runlog"
  notify "$repo#$pr: addressing $ids_n CodeRabbit comment(s)"
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

  # A session that failed does not get its comments marked handled, so the next
  # tick retries them; runs still climbs, so MAX_RUNS_PER_PR ends the retrying.
  if [ "$rc" -eq 0 ]; then
    record "$repo" "$pr" "$head" ${ids[@]+"${ids[@]}"}
  else
    record "$repo" "$pr" "$head" ""
  fi

  if [ "$rc" -eq 0 ] && [ "$outcome" = pushed ]; then
    resolve_threads "$repo" "$pr" "$resultfile"
  elif [ "$RESOLVE_THREADS" = 1 ]; then
    log "$repo#$pr: not pushed ($outcome), so threads stay open"
  fi

  log "$repo#$pr: session exit=$rc outcome=$outcome commits=$commits resolved=$RESOLVED_N worktree=$wtpath"
  if [ "$rc" -ne 0 ]; then
    notify "$repo#$pr: session FAILED (exit $rc) - see $runlog"
  elif [ "$outcome" = no-commits ]; then
    notify "$repo#$pr: session made no changes - see $runlog"
  elif [ "$outcome" = pushed ]; then
    notify "$repo#$pr: $commits commit(s) pushed, $RESOLVED_N thread(s) resolved"
  else
    notify "$repo#$pr: $commits commit(s) NOT pushed - review $wtpath"
  fi
  return 0
}

# Sourcing the script for tests stops here; below is the tick itself.
if [ "${CODERABBIT_WATCH_LIB:-0}" = 1 ]; then return 0; fi

# --- the tick ----------------------------------------------------------------
if [ "$mode" != dry ]; then
  take_lock || { log "another run is in progress; skipping tick"; exit 0; }
  trap 'rm -rf "$LOCK_DIR"' EXIT
fi


prs="$(gh search prs --author @me --state open --owner "$OWNER" --limit 50 \
         --json number,url,repository 2>>"$TICK_LOG")" || { log "gh search failed"; exit 1; }
[ -n "$prs" ] || { log "no open PRs"; exit 0; }

if [ -n "$only_pr" ]; then
  prs="$(jq --argjson n "$only_pr" '[.[] | select(.number == $n)]' <<<"$prs")"
  [ "$(jq 'length' <<<"$prs")" -gt 0 ] || { say "PR $only_pr is not an open PR of yours in $OWNER"; exit 1; }
fi

handled=0 checked=0 already=0
while IFS=$'\t' read -r pr repo url; do
  [ -n "$pr" ] || continue
  [ "$mode" = tick ] && [ "$handled" -ge "$MAX_PRS_PER_TICK" ] && break

  checked=$((checked + 1))
  fb="$(feedback "$OWNER" "$repo" "$pr")"
  head="$(jq -r '.data.repository.pullRequest.headRefOid // empty' <<<"$fb")"
  ids=(); ids_n=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    ids+=("$id"); ids_n=$((ids_n + 1))
  done < <(unresolved_ids "$fb")

  f="$(state_file "$repo" "$pr")"
  known='[]'; runs=0
  if [ -f "$f" ]; then known="$(jq -c '.handled_ids // []' "$f")"; runs="$(jq -r '.runs // 0' "$f")"; fi

  # In manual mode every unresolved comment counts as new: --pr is the "do it
  # now" escape hatch, and filtering it against handled state would make it a
  # silent no-op on any PR the watcher has already seen.
  new=(); new_n=0
  for id in ${ids[@]+"${ids[@]}"}; do
    [ -n "$id" ] || continue
    if [ "$mode" = manual ] || ! jq -e --arg id "$id" 'index($id) != null' <<<"$known" >/dev/null 2>&1; then
      new+=("$id"); new_n=$((new_n + 1))
    fi
  done

  case "$mode" in
    seed)
      record "$repo" "$pr" "$head" ${ids[@]+"${ids[@]}"}
      say "seeded $repo#$pr ($ids_n existing comment(s) marked handled)"
      continue ;;
    dry)
      if [ "$new_n" -gt 0 ]; then
        say "WOULD RUN  $repo#$pr  $new_n new CodeRabbit comment(s)  ${new[*]}"
      else
        say "skip       $repo#$pr  ($ids_n unresolved, all handled; runs=$runs)"
      fi
      continue ;;
  esac

  if [ "$new_n" -eq 0 ]; then
    [ "$ids_n" -gt 0 ] && already=$((already + 1))
    continue
  fi
  if [ "$mode" = tick ] && [ "$runs" -ge "$MAX_RUNS_PER_PR" ]; then
    log "$repo#$pr: hit MAX_RUNS_PER_PR=$MAX_RUNS_PER_PR; skipping (clear its state file to resume)"
    continue
  fi

  handle "$repo" "$pr" "$url" "$head" ${new[@]+"${new[@]}"} && handled=$((handled + 1))
done < <(jq -r '.[] | [(.number|tostring), .repository.name, .url] | @tsv' <<<"$prs")

if [ "$mode" = tick ] || [ "$mode" = manual ]; then
  log "$mode done; checked=$checked handled=$handled"
fi

if [ "$INTERACTIVE" = 1 ] && [ "$handled" -eq 0 ]; then
  if [ "$mode" = manual ]; then
    say "PR $only_pr has no unresolved CodeRabbit threads - nothing to fix."
  else
    say "Checked $checked open PR(s): no new CodeRabbit comments."
    if [ "$already" -gt 0 ]; then
      say "$already PR(s) carry unresolved threads that were already handled once."
      say "Force one anyway with:  $0 --pr <number>"
    fi
    say "(new CodeRabbit comments are picked up on their own, every 30 min)"
  fi
fi
exit 0
