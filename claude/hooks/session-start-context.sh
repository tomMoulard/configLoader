#!/usr/bin/env bash
# Claude Code SessionStart hook — inject the environment the session would
# otherwise burn turns rediscovering: auth state, the GKE/GCP map, repo state,
# open PRs.
#
# stdin  (JSON): {"hook_event_name":"SessionStart","source":"startup",...}  (not read)
# stdout (JSON): {"hookSpecificOutput":{"hookEventName":"SessionStart",
#                                       "additionalContext":"..."}}
#
# Budget: ~2s wall clock. Every network fact is served from a TTL cache under
# ~/.claude/state/session-start/ and refreshed by a detached child, so a cold
# or slow cache degrades a section to "stale"/omitted, never to a delay.
# The whole script re-execs itself under `timeout` and always exits 0.
set -uo pipefail

# launchd-style explicit PATH: hooks inherit whatever Claude Code was started
# with, which on a GUI launch is a bare /usr/bin:/bin.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.cargo/bin:${PATH:-}"
export PATH

STATE_DIR="$HOME/.claude/state/session-start"
AUTH_CACHE="$STATE_DIR/auth.json"
PRS_CACHE="$STATE_DIR/prs.json"
# SSC_* env overrides exist so the degraded paths can be exercised by hand.
AUTH_TTL="${SSC_AUTH_TTL:-600}"   # 10 min — gcloud tokens live an hour
PRS_TTL="${SSC_PRS_TTL:-300}"     # 5 min
HARD_BUDGET="${SSC_HARD_BUDGET:-5}"   # outer timeout for the whole script, s
WAIT_TICKS="${SSC_WAIT_TICKS:-24}"    # 24 x 0.05s = 1.2s max foreground wait
REFRESH_TIMEOUT=15                # per-call cap inside the detached refresher
MAX_PRS=8
MAX_WORKTREES=5
GCLOUD_CFG_DIR="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"

usage() {
  cat <<'EOF'
session-start-context.sh — Claude Code SessionStart hook

  session-start-context.sh              emit the hook JSON on stdout
  session-start-context.sh --dry-run    emit the plain-text block (also the
  session-start-context.sh --plain      default when stdout is a terminal)
  session-start-context.sh --refresh auth|prs
                                        internal: warm one cache entry
  session-start-context.sh --status     show cache files and their age
  session-start-context.sh --help

Caches live in ~/.claude/state/session-start/ (auth.json, prs.json).
EOF
}

# ---------------------------------------------------------------- utilities

have() { command -v "$1" >/dev/null 2>&1; }

# Run a command under a wall-clock cap. Degrades to running it bare if GNU
# coreutils' timeout is not installed.
cap() {
  local secs="$1"; shift
  if have timeout; then timeout -s KILL "$secs" "$@"; else "$@"; fi
}

mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }

cache_age() { # seconds since $1 was written; huge number if absent
  local m; m="$(mtime "$1")"
  [ "$m" = "0" ] && { echo 999999; return; }
  echo $(( $(date +%s) - m ))
}

cache_fresh() { # $1 file, $2 ttl
  [ -s "$1" ] || return 1
  [ "$(cache_age "$1")" -lt "$2" ]
}

human_age() { # seconds -> "3m" / "2h"
  local s="$1"
  if   [ "$s" -lt 90 ];   then echo "${s}s"
  elif [ "$s" -lt 5400 ]; then echo "$(( s / 60 ))m"
  else                         echo "$(( s / 3600 ))h"
  fi
}

# Fire off a cache refresh that outlives us. Every fd is closed off /dev/null
# so the child never holds Claude Code's stdout pipe open.
spawn_refresh() {
  local what="$1"
  [ -f "$STATE_DIR/.lock-$what" ] && [ "$(cache_age "$STATE_DIR/.lock-$what")" -lt 60 ] && return 0
  mkdir -p "$STATE_DIR" 2>/dev/null
  : >"$STATE_DIR/.lock-$what" 2>/dev/null
  nohup bash "$0" --refresh "$what" >/dev/null 2>&1 </dev/null &
}

# ------------------------------------------------------------------ refresh

gcloud_cfg() { # $1 = account|project, read straight off disk (no gcloud spawn)
  local active cfg
  active="${CLOUDSDK_ACTIVE_CONFIG_NAME:-}"
  [ -n "$active" ] || active="$(cat "$GCLOUD_CFG_DIR/active_config" 2>/dev/null)"
  [ -n "$active" ] || active="default"
  cfg="$GCLOUD_CFG_DIR/configurations/config_$active"
  [ -f "$cfg" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$cfg" 2>/dev/null | head -1
}

json_str() { # minimal JSON string escaping for the small values we cache
  printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n'
}

refresh_auth() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  local acct proj user_tok adc gh_login tmp d
  acct="$(gcloud_cfg account)"
  proj="$(gcloud_cfg project)"

  user_tok=unknown
  adc=unknown
  gh_login=""

  # The three probes are ~0.5-1.0s each and independent; bash 3.2 has no
  # `wait -n`, so fan out into files and join on a plain `wait`.
  d="$STATE_DIR/.probe.$$"
  mkdir -p "$d" 2>/dev/null || return 1

  if have gcloud; then
    # `gcloud logging read` and kubectl-via-gke-auth-plugin use the *user*
    # credential; Go clients and terraform use ADC. They rot independently.
    (
      if cap "$REFRESH_TIMEOUT" gcloud auth print-access-token >/dev/null 2>&1
      then echo valid; else echo stale; fi
    ) >"$d/user" 2>/dev/null &
    (
      if [ ! -f "$GCLOUD_CFG_DIR/application_default_credentials.json" ]; then
        echo missing
      elif cap "$REFRESH_TIMEOUT" gcloud auth application-default print-access-token >/dev/null 2>&1
      then echo valid; else echo stale; fi
    ) >"$d/adc" 2>/dev/null &
  else
    echo absent >"$d/user"; echo absent >"$d/adc"
  fi

  if have gh; then
    (
      cap "$REFRESH_TIMEOUT" gh auth status 2>&1 |
        sed -n 's/.*Logged in to [^ ]* account \([^ ]*\).*/\1/p' | head -1
    ) >"$d/gh" 2>/dev/null &
  fi
  wait

  user_tok="$(cat "$d/user" 2>/dev/null)"; [ -n "$user_tok" ] || user_tok=unknown
  adc="$(cat "$d/adc" 2>/dev/null)";       [ -n "$adc" ]      || adc=unknown
  gh_login="$(cat "$d/gh" 2>/dev/null)"
  rm -rf "$d" 2>/dev/null

  tmp="$AUTH_CACHE.$$"
  {
    printf '{"gcloud_account":"%s","gcloud_project":"%s",' \
      "$(json_str "$acct")" "$(json_str "$proj")"
    printf '"gcloud_user":"%s","adc":"%s","gh_login":"%s"}\n' \
      "$(json_str "$user_tok")" "$(json_str "$adc")" "$(json_str "$gh_login")"
  } >"$tmp" 2>/dev/null && mv -f "$tmp" "$AUTH_CACHE" 2>/dev/null
  rm -f "$tmp" "$STATE_DIR/.lock-auth" 2>/dev/null
}

# One GraphQL round-trip for every open PR the user owns, anywhere. Slower than
# `gh pr list` (mergeStateStatus makes GitHub compute mergeability) but this
# runs detached, so the cost is never on the session's clock.
PR_QUERY='{viewer{login pullRequests(states:OPEN,first:30,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{number title isDraft mergeStateStatus baseRefName headRepository{name owner{login}} commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}}'

refresh_prs() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  have gh || { rm -f "$STATE_DIR/.lock-prs" 2>/dev/null; return 1; }
  local tmp
  tmp="$PRS_CACHE.$$"
  if cap "$REFRESH_TIMEOUT" gh api graphql -f query="$PR_QUERY" >"$tmp" 2>/dev/null &&
     [ -s "$tmp" ] && jq -e '.data.viewer.login' "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$PRS_CACHE" 2>/dev/null
  fi
  rm -f "$tmp" "$STATE_DIR/.lock-prs" 2>/dev/null
}

# ------------------------------------------------------------------ sections

section_auth() {
  local note acct proj user_tok adc gh_login
  note=""
  if cache_fresh "$AUTH_CACHE" "$AUTH_TTL"; then
    :
  elif [ -s "$AUTH_CACHE" ]; then
    note=" (cached $(human_age "$(cache_age "$AUTH_CACHE")") ago)"
  else
    echo "AUTH   unknown - no cached probe yet; treat gcloud/gh auth as unverified."
    return 0
  fi

  acct="$(jq -r '.gcloud_account // ""' "$AUTH_CACHE" 2>/dev/null)"
  proj="$(jq -r '.gcloud_project // ""' "$AUTH_CACHE" 2>/dev/null)"
  user_tok="$(jq -r '.gcloud_user // "unknown"' "$AUTH_CACHE" 2>/dev/null)"
  adc="$(jq -r '.adc // "unknown"' "$AUTH_CACHE" 2>/dev/null)"
  gh_login="$(jq -r '.gh_login // ""' "$AUTH_CACHE" 2>/dev/null)"

  printf 'AUTH   gcloud %s (project %s) user-cred:%s adc:%s | gh %s%s\n' \
    "${acct:-none}" "${proj:-none}" "$user_tok" "$adc" \
    "${gh_login:-NOT-LOGGED-IN}" "$note"

  case "$user_tok" in
    stale|absent)
      echo "ACTION gcloud user credential is not usable -> before any \`gcloud logging read\` or"
      echo "       kubectl call, ask the user to run \`! gcloud auth login\` in their prompt."
      echo "       Do not run it yourself: it opens a browser and will hang the tool call." ;;
  esac
  case "$adc" in
    stale|missing|absent)
      echo "ACTION Application Default Credentials are ${adc} -> Go clients / terraform will 401."
      echo "       Ask the user to run \`! gcloud auth application-default login\` in their prompt." ;;
  esac
  [ -n "$gh_login" ] || echo "ACTION gh is not authenticated -> ask the user to run \`! gh auth login\`."
}

section_infra() {
  cat <<'EOF'
GKE contexts (kubectl --context=NAME):
  gke_synthflow-dev-us_us-east1_dev-use1         dev; ns synthflow, ephemeral ns synthflow-<name>
  gke_synthflow-prod-us_us-east1_prod-use1       prod US; ns production and synthflow
  gke_fine-tuner-386314_us-east1_synthflow-prod  LEGACY prod cluster - still carries most traffic
  gke_synthflow-prod-eu_europe-west3_prod-euw3   prod EU
  gke_synthflow-ops_us-east1_synthflow-ops       ops / observability
GCP log projects (gcloud logging read --project=), by usage:
  fine-tuner-386314 (legacy prod, most used), synthflow-prod-us, synthflow-dev-us,
  synthflow-prod-eu, synthflow-ops
`tomm` = the user's personal ephemeral dev env: namespace `synthflow-tomm` on the dev cluster.
Observability: dash0 (`dash0 spans|logs|traces|metrics`, DASH0_AGENT_MODE=1) + Grafana MCP.
Honeycomb is DEPRECATED - never reach for it.
EOF
}

REPO_NAME=""
REPO_ROOT=""
section_repo() {
  local root common main_root repo branch dirty base counts behind ahead flags
  root="$REPO_ROOT"
  [ -n "$root" ] || return 1

  common="$(git rev-parse --git-common-dir 2>/dev/null)"
  case "$common" in /*) ;; *) common="$root/${common:-.git}" ;; esac
  main_root="$(dirname "$common")"
  repo="$(basename "$main_root")"
  REPO_NAME="$repo"

  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"
  [ -n "$branch" ] || branch="$(git rev-parse --short HEAD 2>/dev/null) (detached)"

  flags=""
  case "$root" in
    */.worktrees/*) flags=" [wt worktree]" ;;
    *) [ "$root" != "$main_root" ] && flags=" [linked worktree]" ;;
  esac

  dirty="$(cap 2 git status --porcelain 2>/dev/null | grep -c . )"
  [ -n "$dirty" ] || dirty="?"

  base=""
  for b in origin/main origin/master; do
    git rev-parse --verify --quiet "$b" >/dev/null 2>&1 && { base="$b"; break; }
  done
  if [ -n "$base" ]; then
    counts="$(cap 2 git rev-list --left-right --count "$base...HEAD" 2>/dev/null)"
    behind="$(printf '%s' "$counts" | awk '{print $1+0}')"
    ahead="$(printf '%s' "$counts" | awk '{print $2+0}')"
    printf 'REPO   %s @ %s%s | %s dirty | %s ahead / %s behind %s\n' \
      "$repo" "$branch" "$flags" "$dirty" "${ahead:-?}" "${behind:-?}" "$base"
  else
    printf 'REPO   %s @ %s%s | %s dirty | no origin/main to compare against\n' \
      "$repo" "$branch" "$flags" "$dirty"
  fi
}

# `wt list` costs ~1s (it hits the network for CI state); git gives the same
# branch/path facts in ~40ms, so read them from git and only gate on wt's
# worktree layout.
section_worktrees() {
  have wt || return 0
  local wts n listed
  wts="$(cap 2 git worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{p=substr($0,10)} /^branch /{b=substr($0,8); sub("refs/heads/","",b); print b"\t"p}' |
    grep '/\.worktrees/' | cut -f1)"
  [ -n "$wts" ] || return 0
  n="$(printf '%s\n' "$wts" | grep -c .)"
  # order by last commit date so "active" means recently worked on
  listed="$(cap 2 git for-each-ref --sort=-committerdate \
      --format='%(refname:short)|%(committerdate:relative)' refs/heads 2>/dev/null |
    while IFS='|' read -r br rel; do
      printf '%s\n' "$wts" | grep -qxF "$br" && printf '  %s  (%s)\n' "$br" "$rel"
    done | head -"$MAX_WORKTREES")"
  printf 'WT     %s wt worktrees under .worktrees/ (`wt list` for all, `wt switch <b>` to enter);\n' "$n"
  printf '       most recently committed:\n'
  [ -n "$listed" ] && printf '%s\n' "$listed"
  [ "$n" -gt "$MAX_WORKTREES" ] && printf '  ... and %s more\n' "$(( n - MAX_WORKTREES ))"
  return 0
}

section_prs() {
  local note age
  if cache_fresh "$PRS_CACHE" "$PRS_TTL"; then
    note=""
  elif [ -s "$PRS_CACHE" ]; then
    note=" (cached $(human_age "$(cache_age "$PRS_CACHE")") ago)"
  else
    return 0   # no data yet: omit the block rather than guess
  fi

  local body
  body="$(jq -r --arg repo "$REPO_NAME" --argjson max "$MAX_PRS" '
    def check: (.commits.nodes[0].commit.statusCheckRollup.state // "NONE") as $s
      | if   $s == "SUCCESS" then "pass"
        elif $s == "FAILURE" or $s == "ERROR" then "FAIL"
        elif $s == "PENDING" or $s == "EXPECTED" then "pending"
        else "none" end;
    def flags: [ (if .isDraft then "draft" else empty end),
                 (if .mergeStateStatus == "BEHIND" then "behind main" else empty end),
                 (if .mergeStateStatus == "DIRTY" then "CONFLICTS" else empty end),
                 (if .baseRefName == "main" or .baseRefName == "master" then empty
                  else "stacked on " + .baseRefName end) ];
    def line: "  #\(.number) \(.headRepository.name)  \(.title[0:52])  [checks: \(check)]"
              + (flags | if length == 0 then "" else "  [" + join(", ") + "]" end);
    (.data.viewer.pullRequests.nodes // [])
      | sort_by(if .headRepository.name == $repo then 0 else 1 end)
      | (.[0:$max] | map(line) | .[]),
        (if length > $max then "  ... and \(length - $max) more" else empty end)
  ' "$PRS_CACHE" 2>/dev/null)"
  [ -n "$body" ] || return 0
  printf '\nPRs    open, authored by you%s:\n%s\n' "$note" "$body"
}

# ------------------------------------------------------------------ assembly

build_block() {
  echo "# Session environment (SessionStart hook) - already resolved, do not re-discover."
  section_auth
  echo
  section_infra
  # Repo/worktree/PR ordering matters: section_repo sets REPO_NAME, which
  # section_prs uses to float the current repo's PRs to the top. Both must run
  # in this shell, not a subshell, for that to survive.
  REPO_ROOT="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && cap 2 git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$REPO_ROOT" ]; then
    cd "$REPO_ROOT" 2>/dev/null || REPO_ROOT=""
  fi
  if [ -n "$REPO_ROOT" ]; then
    echo
    section_repo
    section_worktrees
  fi
  section_prs
}

static_fallback() {
  echo "# Session environment (SessionStart hook, degraded - probes timed out)."
  section_infra
}

emit() { # $1 = text
  if [ "${PLAIN:-0}" = "1" ]; then
    printf '%s\n' "$1"
  elif have jq; then
    printf '%s' "$1" | jq -Rs \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
  else
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.stdin.read()}}))'
  fi
}

# ---------------------------------------------------------------------- main

PLAIN=0
MODE=run
REFRESH_WHAT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|--plain) PLAIN=1 ;;
    --refresh) MODE=refresh; REFRESH_WHAT="${2:-}"; shift ;;
    --status)  MODE=status ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'session-start-context.sh: unknown flag %s\n' "$1" >&2; usage >&2; exit 0 ;;
  esac
  shift
done
[ -t 1 ] && PLAIN=1

if [ "$MODE" = "refresh" ]; then
  case "$REFRESH_WHAT" in
    auth) refresh_auth ;;
    prs)  refresh_prs ;;
    *)    printf 'session-start-context.sh: --refresh needs auth|prs\n' >&2 ;;
  esac
  exit 0
fi

if [ "$MODE" = "status" ]; then
  for f in "$AUTH_CACHE" "$PRS_CACHE"; do
    if [ -s "$f" ]; then
      printf '%-50s %s old\n' "$f" "$(human_age "$(cache_age "$f")")"
    else
      printf '%-50s absent\n' "$f"
    fi
  done
  exit 0
fi

# Outer guard: re-exec under a hard timeout so no code path below can ever
# stall session start. If the guarded run produces nothing, fall back to the
# static half, which needs no processes at all.
if [ -z "${SSC_GUARDED:-}" ]; then
  out="${TMPDIR:-/tmp}/session-start-context.$$"
  export SSC_GUARDED=1
  if [ "$PLAIN" = "1" ]; then
    cap "$HARD_BUDGET" bash "$0" --plain >"$out" 2>/dev/null
  else
    cap "$HARD_BUDGET" bash "$0" >"$out" 2>/dev/null
  fi
  if [ -s "$out" ]; then cat "$out"; else emit "$(static_fallback)"; fi
  rm -f "$out" 2>/dev/null
  exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null

cache_fresh "$AUTH_CACHE" "$AUTH_TTL" || spawn_refresh auth
cache_fresh "$PRS_CACHE"  "$PRS_TTL"  || spawn_refresh prs

# Wait only on auth: it is the section worth a second, and it lands in ~1s.
# PRs need ~4s upstream, so they are read from cache or skipped this round.
i=0
while [ "$i" -lt "$WAIT_TICKS" ]; do
  cache_fresh "$AUTH_CACHE" "$AUTH_TTL" && break
  sleep 0.05
  i=$(( i + 1 ))
done

emit "$(build_block)"
exit 0
