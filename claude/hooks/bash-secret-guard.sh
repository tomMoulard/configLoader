#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook — refuse a command that carries a literal secret.
#
# stdin  (JSON): {"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"...",
#                 "tool_input":{"command":"TOK='eyJ...'\ncurl ..."}}
# stdout (JSON): {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#                 "permissionDecision":"deny","permissionDecisionReason":"..."}}
# exit         : 0 = no opinion (command proceeds through the normal permission flow)
#                2 = blocked; Claude is shown permissionDecisionReason
#
# Why: a token pasted inline is written verbatim into the session transcript under
# ~/.claude/projects and is re-read into every future context window.  The fix is
# always to fetch the secret at call time — $(gcloud auth ... print-access-token),
# $(kubectl ... get secret ... | base64 -d), $(gh auth token) — and pass "$VAR".
#
# Precision beats recall here: a hook that cries wolf gets switched off.  Every rule
# requires a *literal* value of credential length; nothing that looks like a fetch
# ($(...)), a reference ($VAR), a path, or a git SHA can trip it.
#
# Escape hatches (documented in the block message):
#   CLAUDE_SECRET_GUARD=0            environment
#   # secret-guard: allow            anywhere in the command text
#
# Blocks are appended to ~/.claude/logs/secret-guard/blocks.log as
#   <ts> rule=<name> match=<first 8 chars>...(len=N) cwd=<dir> session=<id>
# The secret itself is never logged.
set -uo pipefail

# ---------------------------------------------------------------- fail-open helpers
# Anything unexpected in here must let the command through: breaking every Bash
# call is a far worse outcome than missing one paste.
allow() { exit 0; }

CLAUDE_SECRET_GUARD="${CLAUDE_SECRET_GUARD:-1}"
[ "$CLAUDE_SECRET_GUARD" = "0" ] && allow

GREP="/usr/bin/grep"
[ -x "$GREP" ] || GREP="grep"
command -v "$GREP" >/dev/null 2>&1 || allow

raw="$(cat 2>/dev/null)" || allow
[ -n "$raw" ] || allow

# ------------------------------------------------------------------- regex building
# Written for POSIX ERE (BSD grep on macOS, GNU grep elsewhere): no \b, no \d,
# no lookaround.  Case folding is spelled out so the case-sensitive prefixes
# (AKIA, AIza, sk-) stay case-sensitive.
SQ=\'
Q="[\"$SQ]?"                              # one optional quote character
WS='[[:space:]]*'

# --- distinctive literal credentials, boundary-guarded ---
R_JWT="eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\."
R_SK_ANT="(^|[^A-Za-z0-9_-])sk-ant-[A-Za-z0-9_-]{20,}"
R_SK="(^|[^A-Za-z0-9_-])sk-(proj-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}"
R_GOOG="(^|[^A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}"
R_GH="(^|[^A-Za-z0-9_-])gh[pousr]_[A-Za-z0-9]{36,}"
R_SLACK="(^|[^A-Za-z0-9_-])xox[baprs]-[A-Za-z0-9-]{8,}"
R_AWSID="(^|[^A-Za-z0-9])AKIA[0-9A-Z]{16}([^A-Za-z0-9]|$)"
R_PEM="-----BEGIN [A-Z ]*PRIVATE KEY-----"

# --- assignment-shaped: a named variable given a literal value ---
# The value classes below all exclude '$', so KEY=$(...) and KEY="$X" can never match.
V_HEX="[0-9a-fA-F]{32,}"
V_B64="[A-Za-z0-9+/]{32,}={0,2}"
V_AWS="[A-Za-z0-9/+=]{30,}"
V_PW="[^\"$SQ[:space:]\$;|&<>\`]{12,}"

M_APIKEY="[Aa][Pp][Ii][_.-]?[Kk][Ee][Yy]"
M_SECRETISH="([Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd])"
M_PW="([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd])"
M_AWSSEC="[Aa][Ww][Ss]_[Ss][Ee][Cc][Rr][Ee][Tt]_[Aa][Cc][Cc][Ee][Ss][Ss]_[Kk][Ee][Yy]"

R_AWSSEC="${M_AWSSEC}${WS}=${WS}${Q}${V_AWS}"
R_APIKEY="(^|[^A-Za-z0-9_])[A-Za-z0-9_]*${M_APIKEY}${WS}=${WS}${Q}${V_HEX}"
R_SECVAR="(^|[^A-Za-z0-9_])[A-Za-z0-9_]*${M_SECRETISH}[A-Za-z0-9_]*${WS}=${WS}${Q}${V_B64}"
R_PWLIT="(^|[^A-Za-z0-9_])[A-Za-z0-9_]*${M_PW}${WS}=${WS}${Q}${V_PW}"
# Values that are obviously placeholders, paths or fixtures — never a real password.
B_PWLIT="(^|[^A-Za-z0-9_])[A-Za-z0-9_]*${M_PW}${WS}=${WS}${Q}(<|\{|/|\.|~|[Tt][Ee][Ss][Tt]|[Mm][Oo][Cc][Kk]|[Ff][Aa][Kk][Ee]|[Dd][Uu][Mm][Mm][Yy]|[Ee][Xx][Aa][Mm][Pp][Ll][Ee]|[Ss][Aa][Mm][Pp][Ll][Ee]|[Cc][Hh][Aa][Nn][Gg][Ee][Mm][Ee]|[Yy][Oo][Uu][Rr]|[Xx][Xx][Xx]|[Rr][Ee][Dd][Aa][Cc][Tt])"

# --- context detectors ---
# Un-anchored cores, for asking "is this literal sitting in a credential slot?"
BARE_CORE="(eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[A-Za-z0-9-]{8,}|AKIA[0-9A-Z]{16})"
R_HOT="(=|[Bb]earer |[Bb]asic |--token[ =]|--password[ =]|-u )${WS}${Q}${BARE_CORE}"
M_FIXTURE="([Tt][Ee][Ss][Tt]|[Ff][Aa][Kk][Ee]|[Dd][Uu][Mm][Mm][Yy]|[Ee][Xx][Aa][Mm][Pp][Ll][Ee]|[Ss][Aa][Mm][Pp][Ll][Ee]|[Mm][Oo][Cc][Kk]|[Ee][Xx][Pp][Ii][Rr][Ee][Dd]|[Ii][Nn][Vv][Aa][Ll][Ii][Dd]|[Pp][Ll][Aa][Cc][Ee][Hh][Oo][Ll][Dd][Ee][Rr])"
R_TESTVAR="[A-Za-z0-9_]*${M_FIXTURE}[A-Za-z0-9_]*${WS}=${WS}${Q}${BARE_CORE}"

# The user greps their own transcripts; a JWT quoted there is data, not a new leak.
R_TRANSCRIPT="\.claude/(projects|history|shell-snapshots)|/scratchpad/|/tool-results/"
R_TESTPATH="_test\.go|/testdata/|/fixtures?/|test_[A-Za-z0-9_]*\.py|\.(test|spec)\.(ts|tsx|js|jsx)"
# ...unless the command can also put the value on the wire.
R_EGRESS="(^|[;&|(\`]|[[:space:]])(curl|wget|xh|httpie|nc|ncat|netcat|telnet|ssh|scp|sftp|rsync|ftp|openssl)([[:space:]]|$)|gh[[:space:]]+api|[Aa]uthorization[[:space:]]*:"

# --------------------------------------------------------------- cheap prefilter
# Runs on the raw JSON before jq is spawned, so the overwhelming majority of Bash
# calls cost exactly one grep.  Deliberately a superset of every rule above.
R_PREFILTER="eyJ[A-Za-z0-9_-]{10,}\.eyJ|(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{20}|AIza[0-9A-Za-z_-]{30}|gh[pousr]_[A-Za-z0-9]{30}|xox[baprs]-[A-Za-z0-9]|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|[Aa][Ww][Ss]_[Ss][Ee][Cc][Rr][Ee][Tt]_|[Kk][Ee][Yy]${WS}=[^\$[:space:]]{20}|[Tt][Oo][Kk][Ee][Nn]${WS}=[^\$[:space:]]{20}|[Ss][Ee][Cc][Rr][Ee][Tt]${WS}=[^\$[:space:]]{20}|[Pp][Aa][Ss][Ss][Ww]([Oo][Rr])?[Dd]?${WS}=[^\$[:space:]]{12}"

printf '%s\n' "$raw" | "$GREP" -q -E -e "$R_PREFILTER" || allow

# ------------------------------------------------------------------- parse the input
parse_with_jq() {
  printf '%s' "$raw" | jq -r '(.tool_name // ""), (.session_id // ""), (.tool_input.command // "")' 2>/dev/null
}
parse_with_python() {
  printf '%s' "$raw" | python3 -c 'import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
ti = d.get("tool_input") or {}
sys.stdout.write((d.get("tool_name") or "") + "\n")
sys.stdout.write((d.get("session_id") or "") + "\n")
sys.stdout.write(ti.get("command") or "")
' 2>/dev/null
}

parsed=""
if command -v jq >/dev/null 2>&1; then
  parsed="$(parse_with_jq)"
fi
if [ -z "$parsed" ] && command -v python3 >/dev/null 2>&1; then
  parsed="$(parse_with_python)"
fi
[ -n "$parsed" ] || allow

nl=$'\n'
tool_name="${parsed%%$nl*}"
rest="${parsed#*$nl}"
[ "$rest" != "$parsed" ] || allow
session_id="${rest%%$nl*}"
case "$rest" in
  *"$nl"*) cmd="${rest#*$nl}" ;;
  *)       cmd="" ;;
esac

[ "$tool_name" = "Bash" ] || allow
[ -n "$cmd" ] || allow

# Explicit, deliberate opt-out written into the command itself.
printf '%s\n' "$cmd" | "$GREP" -q -i -E -e '#[[:space:]]*secret-guard:[[:space:]]*allow' && allow

# ------------------------------------------------------------------------ matching
# -e is mandatory: several patterns start with '-' (the PEM header) and would
# otherwise be swallowed as grep options.
has() { printf '%s\n' "$cmd" | "$GREP" -q -E -e "$1"; }
count() { printf '%s\n' "$cmd" | "$GREP" -o -E -e "$1" 2>/dev/null | wc -l | tr -d '[:space:]'; }

# Second stage: one combined pass.  Almost every command that survived the
# prefilter dies here, so the per-rule loop below is effectively never reached.
R_ANY="${R_JWT}|${R_SK_ANT}|${R_SK}|${R_GOOG}|${R_GH}|${R_SLACK}|${R_AWSID}|${R_PEM}|${R_AWSSEC}|${R_APIKEY}|${R_SECVAR}|${R_PWLIT}"
has "$R_ANY" || allow

egress=0
has "$R_EGRESS" && egress=1

# Fixture exemption: every literal credential in the command is assigned to an
# obviously-named test variable (TEST_JWT=, FAKE_TOKEN=, EXPIRED_KEY=...), and
# nothing here can put it on the wire.
n_hot="$(count "$R_HOT")"
if [ "$egress" -eq 0 ] && [ "${n_hot:-0}" -gt 0 ]; then
  n_test="$(count "$R_TESTVAR")"
  [ "${n_test:-0}" -eq "$n_hot" ] && allow
fi

# Transcript / fixture-file exemption: the literal is quoted as a search pattern,
# not handed to anything as a credential, and cannot leave the machine.
soft_exempt=0
if [ "$egress" -eq 0 ] && [ "${n_hot:-0}" -eq 0 ]; then
  if has "$R_TRANSCRIPT" || has "$R_TESTPATH"; then soft_exempt=1; fi
fi

# Rule table: name <TAB> regex <TAB> benign-regex-or-'-' <TAB> soft-exemptible <TAB> hint
TAB=$'\t'
RULES=(
"private_key_pem${TAB}${R_PEM}${TAB}-${TAB}1${TAB}a PEM private key block pasted inline"
"jwt_inline${TAB}${R_JWT}${TAB}-${TAB}1${TAB}a three-segment JWT (header.payload.signature) pasted inline"
"anthropic_api_key${TAB}${R_SK_ANT}${TAB}-${TAB}1${TAB}an Anthropic sk-ant- API key"
"openai_api_key${TAB}${R_SK}${TAB}-${TAB}1${TAB}an OpenAI-style sk- / sk-proj- API key"
"google_api_key${TAB}${R_GOOG}${TAB}-${TAB}1${TAB}a Google AIza... API key"
"github_token${TAB}${R_GH}${TAB}-${TAB}1${TAB}a GitHub gh*_ personal/app token"
"slack_token${TAB}${R_SLACK}${TAB}-${TAB}1${TAB}a Slack xox*- token"
"aws_access_key_id${TAB}${R_AWSID}${TAB}-${TAB}1${TAB}an AWS AKIA... access key id"
"aws_secret_access_key${TAB}${R_AWSSEC}${TAB}-${TAB}0${TAB}an inline aws_secret_access_key= value"
"api_key_hex_literal${TAB}${R_APIKEY}${TAB}-${TAB}0${TAB}a long hex API key assigned to a *_API_KEY variable"
"secret_var_literal${TAB}${R_SECVAR}${TAB}-${TAB}0${TAB}a literal blob assigned to a SECRET/TOKEN/KEY/PASSWORD variable"
"password_literal${TAB}${R_PWLIT}${TAB}${B_PWLIT}${TAB}0${TAB}a literal password= value"
)

rule=""; hint=""; excerpt=""; mlen=0
for entry in "${RULES[@]}"; do
  IFS="$TAB" read -r r_name r_re r_benign r_soft r_hint <<EOF
$entry
EOF
  has "$r_re" || continue
  if [ "$r_benign" != "-" ]; then
    n_all="$(count "$r_re")"
    n_ben="$(count "$r_benign")"
    [ "${n_ben:-0}" -ge "${n_all:-0}" ] && continue
  fi
  [ "$r_soft" = "1" ] && [ "$soft_exempt" -eq 1 ] && continue
  m="$(printf '%s\n' "$cmd" | "$GREP" -o -E -e "$r_re" 2>/dev/null | head -n 1)"
  m="${m%%$nl*}"
  mlen="${#m}"
  # Redact: keep only a short, character-sanitised prefix so the log can never
  # become a second copy of the secret.
  excerpt="$(printf '%s' "${m:0:10}" | tr -c 'A-Za-z0-9_.:=/+-' '.')"
  rule="$r_name"; hint="$r_hint"
  break
done

[ -n "$rule" ] || allow

# ---------------------------------------------------------------------- log + deny
log_dir="${HOME}/.claude/logs/secret-guard"
mkdir -p "$log_dir" 2>/dev/null &&
  printf '%s rule=%s match=%s...(len=%s) cwd=%s session=%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$rule" "$excerpt" "$mlen" "$PWD" "${session_id:-unknown}" \
    >>"$log_dir/blocks.log" 2>/dev/null

reason="secret-guard: this Bash command contains ${hint}.

  rule    : ${rule}
  matched : ${excerpt}... (${mlen} chars, redacted)

A pasted credential is written verbatim into the session transcript on disk and
is re-read into every future context window. Do not retry with the value moved,
shortened, or split up — fetch it at call time instead:

  TOK=\$(gcloud auth application-default print-access-token)
  KEY=\$(kubectl --context <ctx> -n <ns> get secret <name> -o jsonpath='{.data.<FIELD>}' | base64 -d)
  KEY=\$(grep -m1 -E '^BFF_API_KEY=' .env | cut -d= -f2-)
  GH=\$(gh auth token)

then reference it as \"\$TOK\" / \"\$KEY\" — never re-paste the value itself.
If the credential is already live in a transcript, rotate it.

Deliberate exception: append '# secret-guard: allow' to the command, or run with
CLAUDE_SECRET_GUARD=0."

emit_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  elif command -v python3 >/dev/null 2>&1; then
    REASON="$reason" python3 -c 'import json,os
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":os.environ["REASON"]}}))'
  fi
}
emit_json
printf '%s\n' "$reason" >&2
exit 2
