# Call log reference

Everything here was read off real `gcloud logging read` output in past sessions.
Field presence varies by service and cluster — treat each as "may exist".

## Where a call can live

| GCP project | Cluster / context | Namespaces | Notes |
|---|---|---|---|
| `fine-tuner-386314` | `gke_fine-tuner-386314_us-east1_synthflow-prod` | `production` | LEGACY prod, still most traffic. Probe this first. |
| `synthflow-prod-us` | `gke_synthflow-prod-us_us-east1_prod-use1` | `production`, `synthflow` | ns `synthflow` logs under container `main`, not `orchestrator` |
| `synthflow-prod-eu` | `gke_synthflow-prod-eu_europe-west3_prod-euw3` | `production` | |
| `synthflow-dev-us` | `gke_synthflow-dev-us_us-east1_dev-use1` | `synthflow`, `synthflow-tomm` | ephemeral envs `synthflow-<name>` |

Observed project/container/namespace combinations, by frequency:

| project | container | namespace | n |
|---|---|---|---|
| `fine-tuner-386314` | `orchestrator` | unset / `production` | 217 / 47 |
| `fine-tuner-386314` | `latency-router` | unset / `production` | 33 / 4 |
| `synthflow-prod-us` | unset | — | 88 |
| `synthflow-prod-us` | `main` | `synthflow` | 9 |
| `synthflow-prod-eu` | `main` / `orchestrator` | `synthflow` / — | 6 / 6 |
| `synthflow-dev-us` | `orchestrator` | `synthflow-tomm` | 11 |
| `synthflow-dev-us` | `bff` | `synthflow` | 7 |

Project frequency across all `gcloud logging read` calls: `fine-tuner-386314`
794, `synthflow-dev-us` 390, `synthflow-prod-us` 388, `synthflow-prod-eu` 108,
`synthflow-ops` 63.

`GET https://bff.{us,eu}.synthflow.dev/calls/<id>` narrows this before you
probe: a US call 404s on the EU host. See `bff-api.md`.

The portal `workspace=` ID does **not** identify the project. This was checked
across the whole transcript corpus: there is no lookup table and no derivable
rule, and the same workspace (e.g. `1785155041901x604054236393802400`) was found
in `fine-tuner-386314`, `synthflow-prod-us` and `synthflow-prod-eu` in different
sessions. Always probe; use `workspace` only to pick which project to try first.

**Retention is 7 days** for the full `--format=json` pull. `--freshness 30d`
still matches on the cheap probe because the index outlives the payload, so a
probe can find a call whose body you can no longer download. If the probe hits
and the full pull is empty, the call is out of retention — say so and stop.

## jsonPayload fields (frequency across 240 transcripts)

| Field | n | Meaning |
|---|---|---|
| `msg` | 1079 | log message — the stage marker (see below) |
| `call` | 519 | call UUID. `call_id` (51) is legacy; OR both |
| `message` | 116 | `msg` under another name — `bff` and other Python services |
| `elapsed` | — | float seconds since call start; the axis to sort on |
| `ts` | 89 | in-payload timestamp; prefer the entry `timestamp` |
| `source_line` | 83 | `pkg/synthesizer/tts_node.go:214` — jumps you to the code |
| `ttft_ongoing_seconds` | 61 | LLM time-to-first-token, mid-conversation turn |
| `ttft_initial_seconds` | — | same, for the opening turn |
| `turn_id` | 56 | turn key. Also `turn.id`, `planner_turn_id`, `next_turn_id` |
| `error` | 31 | error string |
| `model` | 19 | LLM model id |
| `turn_type` | — | `user_response`, `agent_initiated`, … |
| `wait_reason` | — | why the turn held — e.g. `identifier_dictation` |
| `waitForUserInputDuration` | — | length of that hold, in seconds |
| `full_transcript`, `transcript`, `current_transcript` | — | what the user said |
| `bot_message`, `user_message` | — | agent / user text on some services |
| `estimated_tokens_in`, `prompt_tokens`, `cached_tokens` | — | prompt size — a TTFT driver |
| `reason`, `start_time`, `end_time`, `duration_ms` | — | assorted timing (see caveat on `end_time`) |
| `tool_name`, `action_name`, `intent`, `confidence` | — | tool / intent detail |
| `deployment`, `config.Provider`, `config.Model`, `config.AgentID`, `config.WorkspaceID`, `config.WaitForMoreUserInput` | — | agent config snapshot |

Resource labels: `resource.labels.container_name` (587 — `orchestrator`,
`conductor`, `latency-router`, `mediabridge`), `namespace_name` (235),
`pod_name` (61), `cluster_name` (39).

## Stage marker `msg` literals

Exact strings, as logged. `turns.py` matches them case-insensitively as
substrings — add new ones to its `STAGES` table rather than to a one-off script.
Match on `msg` **or** `message`: Go services emit `msg`, `bff` emits `message`,
and prod sometimes wraps the whole JSON record in `textPayload`.

The decomposition `turns.py` computes, and the boundaries it uses:

| Segment | From | To |
|---|---|---|
| STT endpointing | `TTFT: user speech end time set` | `User said` |
| wait_reason hold | `WaitForMoreUserInput...` | `Starting invocation` |
| intent gate | `Starting invocation` | `First token timer timeout set` |
| LLM TTFT | `Created request metadata` | `Received answer from LLMAnswerStream` |
| TTS first audio | `Sending data to TTS provider` | `Reader: Received first audio data, setting FirstAudioTime` |
| audio out | first audio | `Bot said` |

**User speech / STT / endpointing**
```
User said                          <- final user transcript; THE turn anchor
Bot said                              Bot utterance
TTFT: user speech end time set        Sending transcript / Sending transcript message
Transcript sent                       Final transcript
ConversationManager received transcript from transcriber
Received message from Transcriber Client     Received in progress transcript
Received Soniox response              Sending Flux response to callback
Flux: Start of turn                   Flux: End of turn (high confidence)
Checking our own endpointing          Extending endpointing duration for incomplete input
Speech classification result          Sliding window state
```
`Flux: End of turn` has suffix variants — match on the prefix.

**Wait-for-more-input / number-dictation hold**
```
WaitForMoreUserInput: Last word is a number or numeric word, waiting for more input
WaitForMoreUserInput: Single precursor word detected, waiting for more input
WaitForMoreUserInput timeout exceeded, flushing buffer
WaitForMoreUserInput: Extending
Soniox <end> deferred for number-context continuation window
Soniox number continuation window expired, flushing buffer
```
Carries `wait_reason` and `waitForUserInputDuration`.

**Intent classification gate**
```
Detected intent                       Chosen intent: VanillaIntent
Chosen intent: WaitForHumanIntent     Chosen intent: IVRIntent
Waking up to check if we still need to decide on intent for this turn
Choosing intent once decision is ready         Intent decision not ready yet
Received vanilla intent, continuing with current invocation
WaitForHumanIntentStream: Received WaitForHumanIntentStream, starting timer
WaitForHumanIntentStream: Timer expired, starting another invocation without user input action
```

**LLM request / first token**
```
Starting invocation                   Starting new invocation
First token timer timeout set      <- gate released, LLM clock starts
Created request metadata           <- request sent (carries model, estimated_tokens_in)
ChatCompletionRequest created
Received answer from LLMAnswerStream  <- first token
Received answer from invoker          TTFT: recorded ongoing TTFT / initial TTFT
Streaming latency                     llm.billing
ChatCompletionStream creation canceled / timed out
LLM invocation timed out waiting for first token
No choices received                   All invocations failed
Channel full, retrying to send LLMAnswer
proxy: all attempts failed, returning 502
```

**TTS / agent speaking**
```
Sending data to TTS provider          Read from TTS provider
Sending message to TTS                Resolved TTS provider chain
Reader: Received first audio data, setting FirstAudioTime
Received first frame, setting buffer turn id
Connecting to ElevenLabs              Successfully connected to ElevenLabs!
Popped connection from the pool       Adapter failed to connect to TTS provider
```

**Turn lifecycle / barge-in**
```
Starting new turn                     user turn started
Stopping turn / Stopping current turn turn completed / Turn latency
Received user interrupt               UserInterrupt sent
Received new turn before current turn completed, interrupting current turn
Skipping interim interrupt while bot is silent (nothing to barge in on)
Marking turn interrupted              call no progression: pipeline stage stalled
```

**Call bookends** (use for t0 / duration)
```
Handling inbound call                 Handling outbound call
Call answered                         Graph ready!  /  Graph stopped!
canceling Graph context            <- `elapsed` on this line = total call length
Sending post call config              Successfully downloaded recording
```

**IVR / transfer**
```
LLM response for IVR detection        Sending DTMF based on IVR detection
Warm transfer request received        Human detected, proceeding with warm transfer flow
Human detection enabled, waiting for human speech       Transfer failed
Detected language mismatch, translating transfer messages
```

## `source_line` as a stage key

More precise than message text, but brittle across releases. Useful when two
stages share a message. Seen in the corpus:

```
conversation/node.go:2326      USER SAID
conversation/node.go:2484      BOT SAID
llm/node.go:1267               LLM invocation start
llm/node.go:930                LLM stopping current turn
synthesizer/tts_node.go:430    TTS turn start
synthesizer/connections.go:1043  TTS connecting (new conn)
synthesizer/elevenlabs_adapter.go:98  TTS connected
bot_track/speaker_node.go:450  SPEAKER audio start
bot_track/speaker_node.go:2805 SPEAKER latch flip (stale turn)
tracing/turn_lifecycle.go:467  turn completed
transcriber/base_callback.go:1428  STT transcript released
transcriber/base_callback.go:1622  STT <end> deferred (number window)
waitforhuman/node.go:236       WaitForHuman intent sent
```

## Caveats that have burned past sessions

- **Log-derived latency understates true ear-to-ear by ~1.3-1.7s.** STT
  finalization and media transit are not logged. The recording is ground truth.
- **`end_time` is bogus on the `filtered_transcript` path** — anchor on the
  interim `current_transcript` instead.
- **Two prod fleets.** ns `production` + container `orchestrator` in
  `fine-tuner-386314`, and ns `synthflow` + container `main` in
  `synthflow-prod-us`. Filtering `container_name="orchestrator"` hides half of prod.
- **`jsonPayload.call`, not `call_id`.** `call_id` exists but is legacy; OR both
  on the probe. `bff` / `mediabridge` log the id only in the message body — for
  those, a bare full-text `"$CALL"` match is the only thing that works.
- Sort by `(timestamp, elapsed)`. `jsonPayload.elapsed` is seconds-since-call-start
  and disambiguates same-millisecond bursts.

## gcloud cookbook

Aggregate one stage across many calls (find a pattern, not one call):

```bash
gcloud logging read 'resource.labels.namespace_name="production"
    AND resource.labels.container_name="orchestrator"
    AND jsonPayload.msg="TTFT: recorded ongoing TTFT"' \
  --project=fine-tuner-386314 --freshness=3h --limit=40 \
  --format="table(jsonPayload.call, jsonPayload.turn_id, jsonPayload.ttft_ongoing_seconds)"
```

Everyone who hit a given `wait_reason` recently:

```bash
gcloud logging read 'jsonPayload.wait_reason="identifier_dictation"' \
  --project synthflow-prod-us --freshness 3h --limit 4000 \
  --format='value(jsonPayload.call,jsonPayload.full_transcript)'
```

Zoom into one window once `turns.py` names the bad turn — this is where
`source_line` earns its keep:

```bash
gcloud logging read "jsonPayload.call=\"$CALL\"
    AND timestamp>=\"2026-08-03T15:26:43.7Z\" AND timestamp<=\"2026-08-03T15:26:46.0Z\"" \
  --project=fine-tuner-386314 --freshness=7d --limit=300 --order=asc \
  --format="value(timestamp, jsonPayload.turn_id, jsonPayload.source_line, jsonPayload.msg)"
```

Free-text fallback when the call is not in `jsonPayload.call` (some services
only ever log the id inside the message body):

```bash
gcloud logging read "\"$CALL\"" --project="$P" --freshness=7d --limit=200 --order=asc \
  --format="value(timestamp,resource.labels.container_name,jsonPayload.msg)"
```

## dash0 (second pass)

`DASH0_AGENT_MODE=1` for machine-readable output. Datasets: `dev`, `prod`
(`dash0 datasets list`). Honeycomb is dead — never reach for it.

**Only the root `call` span carries `call.id`.** Child spans do not: get the
trace id from the root span first, then filter every child by `otel.trace.id`.

```bash
export DASH0_AGENT_MODE=1
# 1. root span -> trace id
dash0 spans query --dataset prod --filter "call.id is $CALL" --from now-30d --limit 5 \
  -o csv --column otel.trace.id --column otel.span.name --column otel.span.duration
# 2. every span on that trace, in time order
dash0 spans query --dataset prod --filter "otel.trace.id is $TRACE" --from now-30d \
  --limit 300 --precision disabled \
  --column timestamp --column duration --column "span name" --column turn.id -o csv
```

Useful span names: `conversation.turn` (per-turn root), `tts.turn`, `llm.turn`,
`tts.audio.receive`, `rag.query`. Useful attributes: `turn.id`, `turn.type`,
`turn.sequence`, `tts.time_to_first_audio_ms`.

Logs through dash0 instead of gcloud (profiles `prod` / `dev`):

```bash
dash0 logs query --profile prod --dataset prod --filter "call is $CALL" \
  --from now-168h --limit 200 -o csv --column timestamp --column body
```

## Recordings

First try the BFF: `GET /calls/<id>` returns a **pre-signed** `recording_url`
with a ~100-year expiry (`references/bff-api.md`). Everything below is the
fallback for when that is empty or the tailnet is down.

The `recording_url:<callID>` the services log is an **in-process cache key**, not
a URL you can fetch later — it is gone once the pod recycles. Go to GCS.

| Env | Bucket | Project |
|---|---|---|
| legacy prod | `gs://ai-agent-recording` | `fine-tuner-386314` |
| prod US | `gs://ai-agent-recording-use1` | `synthflow-prod-us` |
| prod EU | `gs://ai-agent-recording-euw3` | `synthflow-prod-eu` |
| dev | `gs://ai-agent-recording-dev`, `gs://ai-agent-recording-dev-use1` | `synthflow-dev-us` |
| conductor dev | `gs://conductor-recordings-dev-use1` | `synthflow-dev-us` |

Objects are `<callUUID>_<from>_<to>_<YYYYMMDDTHHMMSS>.wav`, sometimes
`<name>.cleaned-stereo.wav`. Find and share:

```bash
gcloud storage ls "gs://ai-agent-recording/**${CALL:0:8}**" --project fine-tuner-386314
gcloud storage sign-url "gs://ai-agent-recording/${OBJ}" --duration=7d
gcloud storage cp "gs://ai-agent-recording/${OBJ}" "$SP/call.wav" --project fine-tuner-386314
```

`sign-url` needs a service-account key; if it refuses, fall back to `cp` and
hand over the local path.
