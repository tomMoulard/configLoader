#!/usr/bin/env bash
# Test harness for ~/.claude/hooks/bash-secret-guard.sh.
#
# Feeds the hook real PreToolUse payloads and asserts the exit code:
#   0 = command allowed through, 2 = command blocked.
#
# Every "block" case uses a credential this script fabricates at run time — a
# JWT signed with nothing, keys built from a fixed alphabet.  No real secret is
# ever written into this file.
#
#   bash ~/.claude/hooks/tests/secret-guard-test.sh          # run
#   bash ~/.claude/hooks/tests/secret-guard-test.sh -v       # show hook stderr
set -uo pipefail

HOOK="${HOOK:-$HOME/.claude/hooks/bash-secret-guard.sh}"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

[ -x "$HOOK" ] || { printf 'hook not executable: %s\n' "$HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'jq required to build test payloads\n' >&2; exit 1; }

# Sandbox HOME so the suite does not append to the real blocks.log.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/secret-guard-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0; fail=0; failed_names=""

# ------------------------------------------------------------------ fake material
b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=\n'; }
JWT_H="$(b64url '{"alg":"HS256","typ":"JWT"}')"
JWT_P="$(b64url '{"email":"nobody@example.invalid","exp":0,"admin":false,"tier":"none","iss":"secret-guard-selftest"}')"
JWT_S="$(b64url 'this-signature-is-fabricated-by-the-secret-guard-test-harness')"
JWT="${JWT_H}.${JWT_P}.${JWT_S}"

A62='AbCdEfGhIjKlMnOpQrStUvWxYz0123456789ZyXwVuTsRqPoNmLkJiHgFeDcBa987654'
HEX40='a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4'
HEX32='0f1e2d3c4b5a69788796a5b4c3d2e1f0'
GITSHA='1bd770f9a40ea7c2d3e4f50617283940a5b6c7d8'
B64BLOB='QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVowMTIzNDU2Nzg5'

OPENAI_K="sk-proj-${A62:0:48}"
ANTHROPIC_K="sk-ant-api03-${A62:0:40}"
GOOGLE_K="AIza${A62:0:35}"
GITHUB_K="ghp_${A62:0:36}"
SLACK_K="xoxb-2109876543210-2109876543210-${A62:0:24}"
AWS_ID="AKIA${A62:0:16}"
AWS_ID="AKIA$(printf '%s' "${A62:0:16}" | tr 'a-z' 'A-Z')"
AWS_SEC="${A62:0:30}/${A62:30:9}+"

# ------------------------------------------------------------------------ runner
run_hook() { # $1 command text -> exit code on stdout, stderr captured in $ERRFILE
  ERRFILE="$SANDBOX/stderr"
  jq -n --arg c "$1" \
    '{hook_event_name:"PreToolUse",session_id:"secret-guard-test",cwd:"/tmp",
      permission_mode:"default",tool_name:"Bash",tool_use_id:"toolu_test",
      tool_input:{command:$c,description:"test"}}' |
    env HOME="$SANDBOX" bash "$HOOK" >"$SANDBOX/stdout" 2>"$ERRFILE"
  printf '%s' "$?"
}

check() { # $1 expected-exit  $2 name  $3 command
  local got; got="$(run_hook "$3")"
  if [ "$got" = "$1" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$2"
  else
    fail=$((fail + 1)); failed_names="${failed_names}
    - $2 (want exit $1, got $got)"
    printf '  FAIL %s  (want exit %s, got %s)\n' "$2" "$1" "$got"
    [ "$VERBOSE" = "1" ] && /usr/bin/sed 's/^/       | /' "$ERRFILE"
  fi
}
blocks() { check 2 "$1" "$2"; }
allows() { check 0 "$1" "$2"; }

printf '\n== should BLOCK ==\n'

blocks "jwt assigned inline (the real leak, 15x in transcripts)" \
"TOK='${JWT}'
BASE=https://fe-tomm-dev-us.fine-tuner.ai/_api
curl -s -H \"Authorization: Bearer \$TOK\" \"\$BASE/agents\""

blocks "jwt pasted straight into an Authorization header" \
"curl -s -H 'Authorization: Bearer ${JWT}' https://fe-tomm-dev-us.fine-tuner.ai/_api/agents"

blocks "jwt exported" \
"export ADMIN_JWT=${JWT}"

blocks "openai sk-proj- key" \
"OPENAI_API_KEY=${OPENAI_K} go test ./internal/llm/..."

blocks "anthropic sk-ant- key" \
"export ANTHROPIC_API_KEY=${ANTHROPIC_K}"

blocks "google AIza key" \
"curl 'https://maps.googleapis.com/maps/api/geocode/json?key=${GOOGLE_K}&address=x'"

blocks "github token" \
"echo ${GITHUB_K} | gh auth login --with-token"

blocks "slack token" \
"SLACK_BOT_TOKEN=${SLACK_K} python3 post.py"

blocks "aws access key id" \
"AWS_ACCESS_KEY_ID=${AWS_ID} aws s3 ls"

blocks "aws secret access key" \
"aws_secret_access_key=${AWS_SEC}"

blocks "deepgram-style 40-hex key on a *_API_KEY var" \
"DEEPGRAM_API_KEY=${HEX40} go run ./cmd/stt-probe"

blocks "elevenlabs-style 32-hex key on a *_API_KEY var" \
"ELEVENLABS_API_KEY='${HEX32}' curl -s https://api.elevenlabs.io/v1/voices"

blocks "pem private key header" \
"cat > /tmp/k.pem <<'EOF'
-----BEGIN RSA PRIVATE KEY-----
${B64BLOB}
-----END RSA PRIVATE KEY-----
EOF"

blocks "base64 blob on a *_SECRET var" \
"BFF_SECRET=${B64BLOB} python3 -m app"

blocks "literal password= value" \
"PGPASSWORD=Hunter2Hunter2Hunter2 psql -h localhost -U app"

blocks "transcript path cannot smuggle an assignment" \
"cd ~/.claude/projects && TOK='${JWT}' && echo grepping"

blocks "transcript grep that also has egress" \
"grep -c '${JWT}' ~/.claude/projects/*/*.jsonl && curl -s -H \"Authorization: Bearer ${JWT}\" https://x.invalid/"

blocks "testdata path cannot launder a credential header" \
"cd internal/auth/testdata && curl -s -H 'Authorization: Bearer ${JWT}' https://fine-tuner.ai/_api/me"

printf '\n== should ALLOW (the frictionless set) ==\n'

allows "gcloud print-access-token substitution" \
"TOK=\$(gcloud auth application-default print-access-token)
curl -s -H \"Authorization: Bearer \$TOK\" https://fe-tomm-dev-us.fine-tuner.ai/_api/agents"

allows "kubectl get secret | base64 -d substitution" \
"CLUSTER_KEY=\$(kubectl --context gke_synthflow-dev-us_us-east1_dev-use1 -n synthflow get secret conductor-environment -o jsonpath='{.data.INTERNAL_API_KEY}' | base64 -d)
echo \"\${#CLUSTER_KEY}\""

allows "gh auth token substitution" \
"GH=\$(gh auth token); curl -s -H \"Authorization: bearer \$GH\" https://api.github.com/user"

allows "pass substitution" \
"PGPASSWORD=\$(pass show synthflow/db/prod) psql -h localhost -U app"

allows "1password op read substitution" \
"OPENAI_API_KEY=\$(op read 'op://Private/openai/credential') go test ./..."

allows "variable reference in a header" \
"curl -s -H \"Authorization: Bearer \$TOK\" -H 'Content-Type: application/json' https://fine-tuner.ai/_api/me"

allows "braced variable reference and --token flag" \
"gh api -H \"Authorization: token \${GH_TOKEN}\" /user && kubectl --token=\"\$TOK\" get pods"

allows "kubectl get secret with jsonpath, nothing decoded inline" \
"kubectl --context gke_synthflow-prod-us_us-east1_prod-use1 -n production get secret bff-environment -o jsonpath='{.data}' | jq -r 'keys[]'"

allows "reading a key out of .env with grep -m1" \
"BFF_API_KEY=\$(grep -m1 -E '^BFF_API_KEY=' /Users/tommoulard/go/src/github.com/synthflowai/orchestrator/.env | cut -d= -f2-)
BFF_BASE_URL=\$(grep -E '^BFF_BASE_URL=' .env | cut -d= -f2-)
echo \"\${#BFF_API_KEY}\""

allows "plain .env inspection" \
"grep -E '^(DEEPGRAM|SONIOX|CARTESIA)_API_KEY=' .env | cut -d= -f1"

allows "gcloud auth commands" \
"gcloud auth list && gcloud auth application-default login --no-launch-browser"

allows "gh auth status" \
"gh auth status && gh api /rate_limit"

allows "git sha in a variable" \
"SHA=\$(git rev-parse HEAD); git log --oneline -5"

allows "40-hex git sha passed to a workflow input" \
"gh workflow run deploy-ephemeral.yaml --ref fix/ENG-1234-thing -f environment=tomm -f deploy_commit=${GITSHA}"

allows "grepping transcripts for a jwt prefix only" \
"grep -rl 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' ~/.claude/projects | head"

allows "grepping transcripts for a full jwt, no egress" \
"grep -c '${JWT}' ~/.claude/projects/-Users-tommoulard--claude/*.jsonl"

allows "obviously-named test fixture variable" \
"TEST_JWT='${JWT}'
go test ./internal/auth -run TestExpiredToken"

allows "the bare words token and key" \
"echo 'refresh the token' && kubectl get secret --all-namespaces -o name | head && echo key"

allows "sk-test sentinel in a test env var" \
"OPENAI_API_KEY=sk-test go test ./internal/llm/... -run TestFallback"

allows "PASSWORD=test" \
"PASSWORD=test docker compose -f compose.test.yaml up -d"

allows "placeholder password" \
"POSTGRES_PASSWORD=changeme123456 docker run -e POSTGRES_PASSWORD postgres:16"

allows "a long filesystem path in PWD-ish variable" \
"KEYFILE=/Users/tommoulard/go/src/github.com/synthflowai/orchestrator/testdata/keys/ed25519.pub; ls -l \"\$KEYFILE\""

allows "base64 -d pipeline on fetched data" \
"kubectl -n synthflow get secret conductor-environment -o jsonpath='{.data.INTERNAL_API_KEY}' | base64 -d | wc -c"

allows "ordinary dash0 query" \
"DASH0_AGENT_MODE=1 dash0 spans query --dataset production --filter 'service.name=orchestrator' --last 15m"

allows "ordinary go build" \
"cd /Users/tommoulard/go/src/github.com/synthflowai/orchestrator && go build ./... && go test ./internal/turn/..."

printf '\n== escape hatches and non-Bash input ==\n'

allows "inline '# secret-guard: allow' comment" \
"TOK='${JWT}'  # secret-guard: allow
curl -s -H \"Authorization: Bearer \$TOK\" https://fine-tuner.ai/_api/me"

got="$(jq -n --arg c "TOK='${JWT}'" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:"t",tool_input:{command:$c}}' |
  env HOME="$SANDBOX" CLAUDE_SECRET_GUARD=0 bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")"
if [ "$got" = "0" ]; then pass=$((pass+1)); printf '  ok   CLAUDE_SECRET_GUARD=0 env override\n'
else fail=$((fail+1)); failed_names="${failed_names}
    - CLAUDE_SECRET_GUARD=0 env override (want 0, got $got)"; printf '  FAIL CLAUDE_SECRET_GUARD=0 env override (got %s)\n' "$got"; fi

got="$(jq -n --arg c "TOK='${JWT}'" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",session_id:"t",tool_input:{file_path:"/tmp/x",content:$c}}' |
  env HOME="$SANDBOX" bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")"
if [ "$got" = "0" ]; then pass=$((pass+1)); printf '  ok   ignores non-Bash tool_name\n'
else fail=$((fail+1)); failed_names="${failed_names}
    - ignores non-Bash tool_name (want 0, got $got)"; printf '  FAIL ignores non-Bash tool_name (got %s)\n' "$got"; fi

got="$(printf 'not json at all' | env HOME="$SANDBOX" bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")"
if [ "$got" = "0" ]; then pass=$((pass+1)); printf '  ok   fails open on unparseable stdin\n'
else fail=$((fail+1)); failed_names="${failed_names}
    - fails open on unparseable stdin (want 0, got $got)"; printf '  FAIL fails open on unparseable stdin (got %s)\n' "$got"; fi

printf '\n== deny contract ==\n'
jq -n --arg c "TOK='${JWT}'" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:"contract",tool_input:{command:$c}}' |
  env HOME="$SANDBOX" bash "$HOOK" >"$SANDBOX/deny.json" 2>"$SANDBOX/deny.err"
for expect in \
  '.hookSpecificOutput.hookEventName == "PreToolUse"' \
  '.hookSpecificOutput.permissionDecision == "deny"' \
  '(.hookSpecificOutput.permissionDecisionReason | test("print-access-token"))' \
  '(.hookSpecificOutput.permissionDecisionReason | test("secret-guard: allow"))' \
  '(.hookSpecificOutput.permissionDecisionReason | test("rule    : jwt_inline"))'
do
  if jq -e "$expect" "$SANDBOX/deny.json" >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok   json %s\n' "$expect"
  else
    fail=$((fail+1)); failed_names="${failed_names}
    - json $expect"; printf '  FAIL json %s\n' "$expect"
  fi
done
if [ -s "$SANDBOX/deny.err" ]; then pass=$((pass+1)); printf '  ok   reason also written to stderr\n'
else fail=$((fail+1)); failed_names="${failed_names}
    - reason also written to stderr"; printf '  FAIL reason also written to stderr\n'; fi

LOG="$SANDBOX/.claude/logs/secret-guard/blocks.log"
if [ -s "$LOG" ] && /usr/bin/grep -q 'rule=jwt_inline' "$LOG"; then
  pass=$((pass+1)); printf '  ok   block logged with rule name\n'
else
  fail=$((fail+1)); failed_names="${failed_names}
    - block logged with rule name"; printf '  FAIL block logged with rule name\n'
fi
if [ -f "$LOG" ] && ! /usr/bin/grep -qF "$JWT_P" "$LOG"; then
  pass=$((pass+1)); printf '  ok   log never contains the secret itself\n'
else
  fail=$((fail+1)); failed_names="${failed_names}
    - log never contains the secret itself"; printf '  FAIL log leaked the secret\n'
fi
if ! /usr/bin/grep -qF "$JWT_P" "$SANDBOX/deny.json" "$SANDBOX/deny.err" 2>/dev/null; then
  pass=$((pass+1)); printf '  ok   deny message never echoes the secret back\n'
else
  fail=$((fail+1)); failed_names="${failed_names}
    - deny message never echoes the secret back"; printf '  FAIL deny message echoed the secret\n'
fi

printf '\n---------------------------------------------\n'
printf 'passed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || printf 'failures:%s\n' "$failed_names"
[ "$fail" -eq 0 ]
