---
name: call-forensics
description: >-
  Investigate one voice call end to end — work out which cluster it ran on, pull
  its Cloud Logging dump, and produce a per-turn latency timeline with a verdict
  naming the biggest contributor. Use whenever a prompt carries a call UUID
  (bare, several at once, or as a follow-up "and for <uuid>") or a
  `fine-tuner.ai/portal?...&call=...` link, and for phrasings like "analyse this
  call", "investigate this call", "can you checkout this call", "investigate the
  latency on these calls", "check this call", "why was this call slow", "this
  call happened today at 11:51:53", or "give me the link to download this call's
  recording". Also covers the Slack-ready TLDR the user asks for afterwards.
---

# Call forensics

One call in, one turn table and one verdict out. Always the same pipeline: parse
the input, pull the call record from the BFF, find the cluster, pull the logs
once, parse them with `turns.py`. Do not rebuild either parser as a heredoc —
both already exist under `scripts/`.

**Do not enter a worktree.** This is read-only investigation, which
`worktree-first` explicitly exempts. If it turns into a code fix, isolate *then*.

Set `SP` to the session scratchpad directory and keep every dump in it. Log
dumps are megabytes — they never go to stdout.

## 1. Parse the input

The call UUID is the only thing that matters. It arrives bare (sometimes several,
sometimes alone on a line as a follow-up: "and for <uuid>"), or inside
`https://fine-tuner.ai/portal?page=logs&log_type=call&workspace=<ws>&call=<uuid>`
— also `/portal/?...`, a `/version-8k1` path segment, and params in any order.
Read them out of the prompt yourself; the shape is
`[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}`, which a 32-hex trace id won't match:

```bash
CALLS=(429baf5b-3cb9-4600-b359-901a7e986466 d7601b12-862f-421d-af17-e8ee5b87f29c)
CALL=${CALLS[0]}
```

Grab `workspace=` if it is there — worth reporting, and it hints at region — but
it does **not** determine the project. Several UUIDs means a batch: run every
step below in parallel, one file per call.

## 2. The call record

Before any gcloud, ask the BFF. One unauthenticated GET, no cluster guessing,
and it answers half the questions on its own:

```bash
python3 ~/.claude/skills/call-forensics/scripts/bff.py "$CALL"
```

Out comes the assistant and version, `call_status` / `end_call_reason`, the
telephony leg (who hung up, ringing time, the carrier SIP headers), the BFF's
own per-stage latency percentiles with their raw samples, every executed action
with its status and `duration_ms`, the failed judge checks, and a **pre-signed
`recording_url`**. Flags: `--timeline` (stamped transcript), `--config` (the
STT/TTS/VAD knobs the call ran with), `--flow` (SIP ladder), `--pcap PATH`,
`--all`, `--save "$SP"`.

Three things it buys the next steps:

- **Region.** It probes `bff.us` then `bff.eu`; a US call 404s on the EU host.
  The region it reports halves the cluster probe below.
- **`start_time`.** Tells you immediately whether the call is inside the 7-day
  log-payload window, before you spend a pull on it.
- **A hypothesis.** The `latency` block already names the fat stage. The logs
  are then there to explain *why* — the BFF cannot see the `hold` / `gate` split.

It is a summary, not a substitute: it has no per-turn decomposition and no line
of Go. Never skip the log pull because the BFF looked fine, and never `curl` the
endpoint raw — the response is ~125KB of mostly hard-coded action config.
Endpoint list, field catalogue and quirks: `references/bff-api.md`.

The BFF is **tailnet-only**. If it will not connect, say so and carry on from
step 3 — every later step works without it.

## 3. Find the cluster

The user does not know which cluster a call is on, and neither do you. Probe all
four cheaply and in parallel — `--limit 2`, no payload.

```bash
for p in fine-tuner-386314 synthflow-prod-us synthflow-prod-eu synthflow-dev-us; do
  ( echo "=== $p ==="
    gcloud logging read "jsonPayload.call=\"$CALL\" OR jsonPayload.call_id=\"$CALL\"" \
      --project "$p" --freshness 30d --limit 2 \
      --format='value(timestamp,resource.labels.container_name,resource.labels.namespace_name,jsonPayload.msg)' 2>&1 | head -5
  ) &
done; wait
```

`fine-tuner-386314` is legacy prod and still carries most traffic — expect the
hit there, but never assume: the same workspace is served from different
clusters at different times, and the portal `workspace=` ID does not predict it.
If the user said "on prod" or "on dev", still probe — just order those first.

Two traps. **There are two prod fleets**: ns `production` / container
`orchestrator` in `fine-tuner-386314`, *and* ns `synthflow` / container `main`
in `synthflow-prod-us` — pinning `container_name="orchestrator"` silently hides
half of prod, so never filter on it in the probe. And `jsonPayload.call` only
exists on Go services; `bff` and `mediabridge` log the id in the message body,
so if a project looks empty or you need those services, retry the bare full-text
match `"\"$CALL\""`.

## 4. Pull the logs

`--freshness 30d` is for the probe only. **The full payload is retained 7 days**,
so a probe can match a call whose body is already gone. One file per call,
backgrounded, never to stdout — the loop covers the single-call case too:

```bash
P=fine-tuner-386314
for c in "${CALLS[@]}"; do
  ( gcloud logging read "jsonPayload.call=\"$c\"" --project "$P" \
      --freshness 7d --limit 5000 --order asc --format=json \
      > "$SP/call_${c:0:8}.json" 2>"$SP/call_${c:0:8}.err" ) &
done; wait
wc -c "$SP"/call_*.json
```

A file that comes back `[]` means the call is out of the 7-day window — say so
and stop, rather than guessing from the probe's two lines.

## 5. Build the timeline

```bash
python3 ~/.claude/skills/call-forensics/scripts/turns.py "$SP/call_${CALL:0:8}.json"
```

It sorts by timestamp, groups events by `turn_id` (untagged lines fold into the
turn in flight), and prints one row per turn decomposing the wait:

```
stt    user stop ("TTFT: user speech end time set") -> STT final ("User said")
hold   "WaitForMoreUserInput..."     -> "Starting invocation"      (wait_reason hold)
gate   "Starting invocation"         -> "First token timer timeout set" / "Chosen intent"
llm    "Created request metadata"    -> "Received answer from LLMAnswerStream"
tts    "Sending data to TTS provider"-> "Reader: Received first audio data..."
speak  first audio                   -> "Bot said"
```

plus p50/p95/max response latency and a `VERDICT:` line naming the segment with
the largest share of accounted turn time. Flags: `--top N` (only the N slowest
turns), `--json` (feed it to something else), `--no-text` (drop transcripts).

Missing fields print `-` and never crash it. If a stage reads `-` on every
turn, that service does not emit the marker — add the literal to the `STAGES`
table in `turns.py`, don't write a throwaway parser. Marker strings and the full
field catalogue: `references/log-fields.md`.

Once a turn is named, zoom into its window with a timestamped `gcloud logging
read` on `source_line` + `msg` (recipe in the reference) to get from "the LLM
took 2.6s" to the line of Go responsible.

## 6. Report

Lead with the turn table, then a short verdict naming the single biggest
contributor with its number. Say which project the call was in and how many
turns were measured. Flag anything anomalous per turn — a `wait_reason` hold, a
502 from the LLM proxy, a turn with no agent audio, a failed action from step 2.

Quote one set of numbers, not two. `turns.py` is the one to report; reach for
the BFF's percentiles only when they *disagree* with it, and then say so
explicitly — a stage that looks fine to the BFF and slow in the logs is a real
finding, usually a hold the BFF cannot see.

One caveat to carry into the verdict: **log-derived latency understates true
ear-to-ear by roughly 1.3-1.7s** (STT finalization and media transit are not
logged). Quote the measured numbers, but if the user is comparing against what
they heard, say the real figure is higher — the recording is the ground truth.

The user usually asks next for a **1-2 line Slack-ready TLDR**. Offer it: plain
prose, the one number that matters, the call link. Never post it anywhere
without asking first.

## 7. Second pass — optional

Neither is required; reach for them when the timeline is ambiguous or the user
asks.

**dash0 traces** — cross-check the stage boundaries against real spans, with
`DASH0_AGENT_MODE=1`. Honeycomb is dead, never use it. The gotcha: only the root
`call` span carries `call.id`, so pull the trace id off it first and filter every
child by `otel.trace.id`. Both queries: `references/log-fields.md`.

**The recording** — "give me the link to download this call's recording" is a
regular follow-up, and step 2 already answered it: `recording_url` from the BFF
is a signed GCS URL, hand it over as-is. The `recording_url:<callID>` in the
*logs* is something else — an in-process cache key, dead after the fact. Only if
the BFF is unreachable or the field is empty, go to GCS by call id:

```bash
gcloud storage ls "gs://ai-agent-recording/**${CALL:0:8}**" --project fine-tuner-386314
gcloud storage sign-url "gs://ai-agent-recording/${OBJ}" --duration=7d
```

Bucket per environment, object naming, and the `cp` fallback when `sign-url` has
no service-account key: `references/log-fields.md`.
