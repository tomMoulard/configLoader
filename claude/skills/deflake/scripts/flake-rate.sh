#!/usr/bin/env bash
# flake-rate.sh — measure how often a Go test actually fails.
#
# A flake is a rate, not a yes/no. This runs the same test N times in N fresh
# `go test` processes and reports the failure percentage, keeping the output of
# every failing run so you can diff a red iteration against a green one.
#
#   flake-rate.sh ./pkg/synthesizer/ TestTTSNode_ReadTimeout 50
#   flake-rate.sh ./pkg/transcriber/ TestBaseCallback_Flush 30 --race
#   flake-rate.sh ./pkg/synthesizer/ - 20 --shuffle      # '-' = whole package
#
# Exit status: 0 when every iteration passed, 1 when any failed, 2 on bad usage.
# bash 3.2 compatible (macOS system bash).

set -uo pipefail

PROG="${0##*/}"

usage() {
    cat <<'EOF'
Usage: flake-rate.sh <pkg> <TestName|-> [iterations] [options]

  <pkg>         Go package path, e.g. ./pkg/synthesizer/ or ./...
  <TestName>    exact test name (anchored as -run '^Name$'); '-' runs the whole package
  [iterations]  number of separate `go test` processes to run (default 20)

Options:
  --race              add -race (run this second; it changes scheduling)
  --shuffle           add -shuffle=on to catch inter-test ordering dependence
  --count N           -count=N *within* each process (default 1); catches state
                      leaking between repeats inside one binary
  --p N               -p N, package-level parallelism (try 1 and 4)
  --parallel N        -parallel N, t.Parallel() concurrency within a package
  --cpu LIST          -cpu LIST, e.g. 1,4
  --timeout D         -timeout D (default 300s)
  --tags LIST         -tags LIST
  --short             add -short (this is what CI runs: -count=1 -short -p 4)
  --stop-on-fail      stop at the first failing iteration
  --log-dir DIR       where to keep failing output (default: a fresh mktemp -d)
  -v, --verbose       stream each iteration's output instead of a progress line
  -h, --help          this text

Examples:
  flake-rate.sh ./pkg/synthesizer/ TestTTSNode_ReadTimeout 50
  flake-rate.sh ./pkg/synthesizer/ TestTTSNode_ReadTimeout 50 --race
  flake-rate.sh ./pkg/transcriber/ - 20 --shuffle --p 1
EOF
}

PKG=""
TEST_NAME=""
ITERATIONS=20
USE_RACE=0
USE_SHUFFLE=0
COUNT=1
P_FLAG=""
PARALLEL_FLAG=""
CPU_FLAG=""
TIMEOUT="300s"
TAGS=""
SHORT=0
STOP_ON_FAIL=0
LOG_DIR=""
VERBOSE=0

need_arg() {
    if [ -z "${2:-}" ]; then
        printf '%s: %s needs a value\n' "$PROG" "$1" >&2
        exit 2
    fi
}

POSITIONAL=0
take_positional() {
    case "$POSITIONAL" in
        0) PKG="$1" ;;
        1) TEST_NAME="$1" ;;
        2) ITERATIONS="$1" ;;
        *)
            printf '%s: unexpected argument %s\n' "$PROG" "$1" >&2
            exit 2
            ;;
    esac
    POSITIONAL=$((POSITIONAL + 1))
}

while [ $# -gt 0 ]; do
    case "$1" in
        --race)         USE_RACE=1; shift ;;
        --shuffle)      USE_SHUFFLE=1; shift ;;
        --short)        SHORT=1; shift ;;
        --stop-on-fail) STOP_ON_FAIL=1; shift ;;
        -v|--verbose)   VERBOSE=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        --count)        need_arg "$1" "${2:-}"; COUNT="$2"; shift 2 ;;
        --p)            need_arg "$1" "${2:-}"; P_FLAG="$2"; shift 2 ;;
        --parallel)     need_arg "$1" "${2:-}"; PARALLEL_FLAG="$2"; shift 2 ;;
        --cpu)          need_arg "$1" "${2:-}"; CPU_FLAG="$2"; shift 2 ;;
        --timeout)      need_arg "$1" "${2:-}"; TIMEOUT="$2"; shift 2 ;;
        --tags)         need_arg "$1" "${2:-}"; TAGS="$2"; shift 2 ;;
        --log-dir)      need_arg "$1" "${2:-}"; LOG_DIR="$2"; shift 2 ;;
        -)              take_positional "$1"; shift ;;
        -*)
            printf '%s: unknown option %s\n' "$PROG" "$1" >&2
            usage >&2
            exit 2
            ;;
        *)              take_positional "$1"; shift ;;
    esac
done

if [ -z "$PKG" ] || [ -z "$TEST_NAME" ]; then
    usage >&2
    exit 2
fi

case "$ITERATIONS" in
    ''|*[!0-9]*)
        printf '%s: iterations must be a positive integer, got %s\n' "$PROG" "$ITERATIONS" >&2
        exit 2
        ;;
esac
if [ "$ITERATIONS" -lt 1 ]; then
    printf '%s: iterations must be >= 1\n' "$PROG" >&2
    exit 2
fi

if ! command -v go >/dev/null 2>&1; then
    printf '%s: go is not on PATH\n' "$PROG" >&2
    exit 2
fi

if [ -z "$LOG_DIR" ]; then
    LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/flake-rate.XXXXXX") || exit 2
else
    mkdir -p "$LOG_DIR" || exit 2
fi

# Build the go test argument list once.
set -- test "$PKG" "-count=$COUNT" "-timeout=$TIMEOUT"
if [ "$TEST_NAME" != "-" ]; then
    set -- "$@" "-run=^${TEST_NAME}\$"
fi
[ "$USE_RACE" -eq 1 ]       && set -- "$@" -race
[ "$USE_SHUFFLE" -eq 1 ]    && set -- "$@" -shuffle=on
[ "$SHORT" -eq 1 ]          && set -- "$@" -short
[ -n "$P_FLAG" ]            && set -- "$@" "-p=$P_FLAG"
[ -n "$PARALLEL_FLAG" ]     && set -- "$@" "-parallel=$PARALLEL_FLAG"
[ -n "$CPU_FLAG" ]          && set -- "$@" "-cpu=$CPU_FLAG"
[ -n "$TAGS" ]              && set -- "$@" "-tags=$TAGS"
GO_ARGS="$*"

printf 'flake-rate: go %s\n' "$GO_ARGS"
printf 'flake-rate: %s iterations, one fresh process each\n' "$ITERATIONS"
printf 'flake-rate: logs in %s\n\n' "$LOG_DIR"

FAILURES=0
PASSES=0
FIRST_FAIL_LOG=""
i=1
while [ "$i" -le "$ITERATIONS" ]; do
    LOG="$LOG_DIR/iter-$(printf '%03d' "$i").log"
    if [ "$VERBOSE" -eq 1 ]; then
        printf -- '--- iteration %s/%s ---\n' "$i" "$ITERATIONS"
        go "$@" 2>&1 | tee "$LOG"
        STATUS=${PIPESTATUS[0]}
    else
        go "$@" >"$LOG" 2>&1
        STATUS=$?
    fi

    if [ "$STATUS" -eq 0 ]; then
        PASSES=$((PASSES + 1))
        rm -f "$LOG"
        [ "$VERBOSE" -eq 0 ] && printf '.'
    else
        FAILURES=$((FAILURES + 1))
        [ -z "$FIRST_FAIL_LOG" ] && FIRST_FAIL_LOG="$LOG"
        [ "$VERBOSE" -eq 0 ] && printf 'F'
        if [ "$STOP_ON_FAIL" -eq 1 ]; then
            [ "$VERBOSE" -eq 0 ] && printf '\n'
            printf '\nflake-rate: stopping at first failure (iteration %s)\n' "$i"
            break
        fi
    fi
    i=$((i + 1))
done

RUN=$((PASSES + FAILURES))
[ "$VERBOSE" -eq 0 ] && printf '\n'

RATE=$(awk -v f="$FAILURES" -v n="$RUN" 'BEGIN { if (n == 0) print "0.0"; else printf "%.1f", (f * 100.0) / n }')

printf '\n=== flake rate ===\n'
printf 'test:       %s %s\n' "$PKG" "$TEST_NAME"
printf 'go flags:   %s\n' "$GO_ARGS"
printf 'iterations: %s (%s pass, %s fail)\n' "$RUN" "$PASSES" "$FAILURES"
printf 'rate:       %s%% failing\n' "$RATE"

if [ "$FAILURES" -gt 0 ]; then
    printf 'logs:       %s\n' "$LOG_DIR"
    printf '\nfirst failure (%s):\n' "$FIRST_FAIL_LOG"
    grep -E '^(---|    ---)? *(FAIL|--- FAIL|panic:|WARNING: DATA RACE|.*_test\.go:[0-9]+)' "$FIRST_FAIL_LOG" 2>/dev/null | head -25
    exit 1
fi

rmdir "$LOG_DIR" 2>/dev/null
printf 'result:     clean over %s runs\n' "$RUN"
exit 0
