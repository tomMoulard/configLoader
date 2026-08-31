#!/usr/bin/env bash
# Claude Code PostToolUse(Edit|Write) hook — format the Go file that was just
# written, vet its package, and flag the two Go test conventions this user
# always ends up correcting by hand.
#
# stdin (JSON): {"hook_event_name":"PostToolUse","tool_name":"Edit",
#                "tool_input":{"file_path":"/abs/x.go",...},"tool_response":{...}}
# exit 0, silent        : nothing to say — and the only path a non-Go edit takes.
# exit 2, text on stderr: diagnostics Claude reads next to the tool result and
#                         can act on in the same turn (docs: "To surface a
#                         warning to Claude from a PostToolUse hook, exit 2").
#
# Advisory only.  The write already happened; exit 2 in PostToolUse cannot undo
# it, it only attaches the diagnostics.  Anything unexpected in here exits 0
# rather than wedging the session.
#
#   go-post-edit.sh --file pkg/x/y.go     run it by hand, no JSON needed
#
# Formatting is applied, not reported: gofmt-class fixes are mechanical, so the
# file is rewritten and Claude is told to re-read it.  Everything else is
# reported only — this hook never runs `go build ./...` or `go test`.
set -uo pipefail

VET_TIMEOUT="${GO_POST_EDIT_VET_TIMEOUT:-5}"   # seconds; over budget => skipped
STATE_DIR="${GO_POST_EDIT_STATE_DIR:-$HOME/.claude/state/go-post-edit}"
MAX_VET_LINES=40

# --- 0. the cheap exit -------------------------------------------------------
# This fires after *every* Edit/Write in every project, and most of them are not
# Go (the user's React/TS PWA, YAML, Terraform...).  Fork nothing — not even jq
# — until the raw payload at least mentions a ".go" path.
file=""
payload=""
case "${1:-}" in
  "")        payload="$(cat)"   # `read -d ""` byte-loops a 60 KB React Write; cat blocks
             case "$payload" in *.go*) ;; *) exit 0 ;; esac ;;
  --file)    file="${2:-}"; [ -n "$file" ] || exit 0 ;;
  --help|-h) sed -n '2,22p' "$0"; exit 0 ;;
  *)         exit 0 ;;
esac

# Hooks inherit a minimal PATH; the Go toolchain and the formatters live outside
# it.  Prepend rather than replace so a repo-local shim still wins, and pin the
# system dirs on the end so grep/head/rm resolve even from a stripped env.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/bin:${PATH:-}:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

# --- 1. the edited file ------------------------------------------------------
if [ -z "$file" ]; then
  if command -v jq >/dev/null 2>&1; then
    file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)"
  elif [[ "$payload" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    file="${BASH_REMATCH[1]}"
  fi
fi
[ -n "$file" ] || exit 0
case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
case "$file" in *.go) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0   # edited then deleted, or a path we cannot see

# --- 2. generated code is not ours to format ---------------------------------
case "$file" in */vendor/*) exit 0 ;; esac
base="${file##*/}"
case "$base" in
  *.pb.go|*_pb.go|*.gen.go|*_gen.go|*_mock.go|*_mock_test.go|mock_*.go) exit 0 ;;
esac
# `// Code generated ... DO NOT EDIT.` may sit under a build tag or licence
# header, so look at the first few lines, not just the first.  No forks.
n=0
while [ "$n" -lt 6 ] && IFS= read -r line; do
  case "$line" in '// Code generated '*'DO NOT EDIT.'*) exit 0 ;; esac
  n=$((n + 1))
done < "$file"

# --- 3. locate the module / repo, from the FILE, never from cwd --------------
# `wt` puts worktrees in .worktrees/<branch>, whose root holds a .git *file*;
# walking up from the file lands inside the worktree, which is what we want.
dir="${file%/*}"; [ -n "$dir" ] || dir="/"
mod_dir=""; cfg=""; cfg_dir=""; mk=""; tools=""; repo_root=""
d="$dir"; depth=0
while [ -n "$d" ] && [ "$d" != "/" ] && [ "$depth" -lt 40 ]; do
  if [ -z "$mod_dir" ] && [ -f "$d/go.mod" ]; then mod_dir="$d"; fi
  if [ -z "$cfg" ]; then
    for c in .golangci.yml .golangci.yaml .golangci.toml .golangci.json; do
      if [ -f "$d/$c" ]; then cfg="$d/$c"; cfg_dir="$d"; break; fi
    done
  fi
  if [ -z "$mk" ] && [ -f "$d/Makefile" ]; then mk="$d/Makefile"; fi
  if [ -z "$tools" ] && [ -f "$d/tools.go" ]; then tools="$d/tools.go"; fi
  if [ -e "$d/.git" ]; then repo_root="$d"; break; fi
  d="${d%/*}"; depth=$((depth + 1))
done
root="${mod_dir:-${cfg_dir:-${repo_root:-$dir}}}"

# --- 4. which formatter does THIS repo actually use? -------------------------
# Cached per module root: re-deriving it from the Makefile and .golangci.yaml on
# every keystroke-sized edit is the one avoidable cost here.  The cache is stale
# the moment any of those files is newer than it (`-nt` is a shell builtin, so
# checking costs nothing).
FMT_KIND=""; FMT_DIR=""; FMT_CFG=""
key="${root#/}"; key="${key//\//%}"
[ "${#key}" -gt 180 ] && key="${key:${#key}-180}"
cache="$STATE_DIR/$key.conf"
if [ -f "$cache" ]; then
  fresh=1
  for f in "$cfg" "$mk" "$tools"; do
    if [ -n "$f" ] && [ "$f" -nt "$cache" ]; then fresh=0; fi
  done
  if [ "$fresh" = 1 ]; then
    while IFS='=' read -r k v; do
      case "$k" in fmt) FMT_KIND="$v" ;; dir) FMT_DIR="$v" ;; cfg) FMT_CFG="$v" ;; esac
    done < "$cache"
    [ "$FMT_CFG" = "$cfg" ] || FMT_KIND=""
  fi
fi

if [ -z "$FMT_KIND" ]; then
  FMT_KIND=gofmt; FMT_DIR="${mod_dir:-$dir}"
  # golangci-lint v2 owns formatting when the repo configures `formatters:`
  # (orchestrator, latency-router and conductor all do: gci + gofmt[+gofumpt]).
  # `make format` in those repos is exactly `golangci-lint fmt`.
  if [ -n "$cfg" ] && command -v golangci-lint >/dev/null 2>&1 &&
     grep -q '^formatters:' "$cfg" 2>/dev/null; then
    FMT_KIND=golangci; FMT_DIR="$cfg_dir"
  else
    hay=""
    [ -n "$mk" ]    && hay="$hay $(grep -oE 'golangci-lint fmt|gofumpt|goimports|gci' "$mk" 2>/dev/null | tr '\n' ' ')"
    [ -n "$tools" ] && hay="$hay $(grep -oE 'gofumpt|goimports|gci' "$tools" 2>/dev/null | tr '\n' ' ')"
    [ -n "$cfg" ]   && hay="$hay $(grep -oE 'gofumpt|goimports|gci' "$cfg" 2>/dev/null | tr '\n' ' ')"
    if [ -n "${hay// /}" ]; then
      case "$hay" in
        *"golangci-lint fmt"*) command -v golangci-lint >/dev/null 2>&1 &&
                               { FMT_KIND=golangci; FMT_DIR="${cfg_dir:-$FMT_DIR}"; } ;;
      esac
      if [ "$FMT_KIND" = gofmt ]; then
        case "$hay" in *gofumpt*)   command -v gofumpt   >/dev/null 2>&1 && FMT_KIND=gofumpt ;; esac
      fi
      if [ "$FMT_KIND" = gofmt ]; then
        case "$hay" in *goimports*) command -v goimports >/dev/null 2>&1 && FMT_KIND=goimports ;; esac
      fi
    fi
  fi
  mkdir -p "$STATE_DIR" 2>/dev/null &&
    printf 'fmt=%s\ndir=%s\ncfg=%s\n' "$FMT_KIND" "$FMT_DIR" "$cfg" > "$cache" 2>/dev/null
fi

# --- 5. format, in place ------------------------------------------------------
notes=""
add() { notes="$notes$1
"; }

formatted=""
case "$FMT_KIND" in
  golangci)
    # Gate on stdout, not exit status: rc=1 means "would reformat", but rc=3
    # (bad config) also leaves stdout empty and must not be reported as a fix.
    if [ -n "$( (cd "$FMT_DIR" 2>/dev/null && golangci-lint fmt --diff "$file") 2>/dev/null )" ]; then
      (cd "$FMT_DIR" 2>/dev/null && golangci-lint fmt "$file") >/dev/null 2>&1 &&
        formatted="golangci-lint fmt"
    fi
    ;;
  gofumpt|goimports|gofmt)
    # `-l` prints the path only when the file would change; a syntax error goes
    # to stderr and leaves stdout empty, so a broken file is simply not touched.
    if [ -n "$("$FMT_KIND" -l "$file" 2>/dev/null)" ]; then
      "$FMT_KIND" -w "$file" >/dev/null 2>&1 && formatted="$FMT_KIND"
    fi
    ;;
esac
[ -n "$formatted" ] &&
  add "- auto-formatted with \`$formatted\` (the file on disk changed; re-read it before editing it again)"

# --- 6. go vet, this package only --------------------------------------------
# Never ./... — that is minutes on orchestrator.  A cold build cache can still
# blow the budget, so it runs under a timeout and is dropped silently if it does.
TIMEOUT_BIN=""
for t in timeout gtimeout; do command -v "$t" >/dev/null 2>&1 && { TIMEOUT_BIN="$t"; break; }; done

run_timed() {  # <secs> <outfile> <cmd...> -> 124 on timeout
  local secs="$1" out="$2"; shift 2
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$secs" "$@" >"$out" 2>&1
    return $?
  fi
  "$@" >"$out" 2>&1 &
  local pid=$! rc=0
  { sleep "$secs"; kill -TERM "$pid"; sleep 1; kill -KILL "$pid"; } >/dev/null 2>&1 &
  local wd=$!
  wait "$pid"; rc=$?
  kill -TERM "$wd" >/dev/null 2>&1; wait "$wd" >/dev/null 2>&1
  [ "$rc" -ge 128 ] && return 124
  return "$rc"
}

if [ -n "$mod_dir" ] && command -v go >/dev/null 2>&1; then
  vet_out="${TMPDIR:-/tmp}/go-post-edit.$$.vet"
  trap 'rm -f "$vet_out"' EXIT
  # `go -C <dir> vet .` keeps the module resolution anchored on the file's own
  # directory, so this is correct inside a .worktrees/<branch> checkout too.
  run_timed "$VET_TIMEOUT" "$vet_out" go -C "$dir" vet .
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ -s "$vet_out" ]; then
    pkg="${dir#"$mod_dir"/}"
    if [ "$pkg" = "$dir" ]; then pkg="."; else pkg="./$pkg"; fi
    add "- \`go vet $pkg\` (this package only):"
    while IFS= read -r line; do
      [ -n "$line" ] && add "    $line"
    done < <(head -n "$MAX_VET_LINES" "$vet_out")
    [ "$(wc -l <"$vet_out")" -gt "$MAX_VET_LINES" ] && add "    ... (truncated)"
  fi
fi

# --- 7. the two test conventions this user always corrects -------------------
case "$base" in
  *_test.go)
    # Verbatim standing correction: "t.context() must be used in tests instead
    # of context.Background()".
    hits="$(grep -nF 'context.Background()' "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//')"
    if [ -n "$hits" ]; then
      lines="$(printf '%s' "$hits" | cut -d: -f1 | tr '\n' ',')"
      add "- test convention: use \`t.Context()\`, not \`context.Background()\` (line ${lines%,}) — unless it is TestMain, which has no *testing.T"
    fi
    hits="$(grep -nE '(^|[^.[:alnum:]_])time\.Sleep\(' "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//')"
    if [ -n "$hits" ]; then
      lines="$(printf '%s' "$hits" | cut -d: -f1 | tr '\n' ',')"
      add "- test convention: bare \`time.Sleep(\` in a test is a flake source (line ${lines%,}) — wait on a channel, \`sync\`, or \`require.Eventually\` instead"
    fi
    ;;
esac

# --- 8. report ---------------------------------------------------------------
[ -n "$notes" ] || exit 0
short="${file#"$root"/}"
printf 'go-post-edit: %s\n%s' "$short" "$notes" >&2
exit 2
