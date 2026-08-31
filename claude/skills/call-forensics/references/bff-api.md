# BFF call API

The internal BFF holds the post-call record: what the orchestrator decided, not
what it logged. Everything below was read off live responses.

## Hosts

| Host | Serves |
|---|---|
| `https://bff.us.synthflow.dev` | US calls (legacy prod + `synthflow-prod-us`) |
| `https://bff.eu.synthflow.dev` | EU calls (`synthflow-prod-eu`) |

Both resolve to `100.96.0.0/16` — **tailnet only**. No auth header, no API key:
a plain `curl` works from the VPN and hangs/refuses off it. `bff.synthflow.dev`
does not resolve; `.dev` is the internal domain for every environment, prod
included, so a `.dev` host is not a dev-environment host.

**A US call 404s on the EU host and vice versa.** That 200/404 is the cheapest
region signal available — it splits the four-project gcloud probe in half before
you run it.

**GET only.** The same service exposes `POST /calls/{id}/hangup`,
`DELETE /calls/{id}`, `POST /calls/outbound` and the batch dispatcher. Those act
on live production calls. Never issue one while investigating.

## Endpoints

| Endpoint | Extra params | Gives |
|---|---|---|
| `GET /calls/{id}` | `serialize_actions=true` (opt) | the record — metadata, `latency`, `timeline`, `executed_actions`, `judge_results`, `recording_url`, telephony |
| `GET /calls/payload/{id}` | — | the runtime config the call was dispatched with (93 keys: transcriber, VAD, synthesizer, `janus_pod_name`) |
| `GET /calls/flow/{id}` | `timestamp=<start_time>` **required** | SIP ladder — INVITE/100/180/183/200/ACK/BYE with ms stamps |
| `GET /calls/pcap/{id}` | `timestamp=<start_time>` **required** | `{"pcap": "<base64>"}` — decodes to a real `.pcap` |
| `GET /openapi.json` | — | 214 paths, if you need something not listed here |

`timestamp` is the **epoch-milliseconds `start_time` from the details response**,
passed verbatim. Seconds return `404 Call not found`; a missing one returns
`422 Field required`. So `/calls/{id}` always comes first.

The listing endpoints (`GET /calls`, `GET /api/calls`) require a token and are
not usable here — you need a call id to start.

## Use the script, not curl

```bash
python3 ~/.claude/skills/call-forensics/scripts/bff.py "$CALL"                 # summary
python3 ~/.claude/skills/call-forensics/scripts/bff.py "$CALL" --timeline      # + transcript
python3 ~/.claude/skills/call-forensics/scripts/bff.py "$CALL" --config        # + STT/TTS/VAD knobs
python3 ~/.claude/skills/call-forensics/scripts/bff.py "$CALL" --flow          # + SIP ladder
python3 ~/.claude/skills/call-forensics/scripts/bff.py "$CALL" --all --save "$SP"
python3 ~/.claude/skills/call-forensics/scripts/bff.py "$CALL" --pcap "$SP/call.pcap"
```

It probes us then eu, prints the region it hit, and renders only the useful
fields. `--json` for the assembled record, `--save DIR` for the raw responses,
`--verbose` for every judge check and full action return values.

**The raw details response is ~125KB and ~90% of it is
`executed_actions[].parameters_hard_coded`** — availability windows, transfer
messages, RAG result bodies. Never `cat` it and never let it reach stdout; if
you must go outside the script, `jq` a named path out of a `--save`d file.

## The `latency` block

```json
"latency": {
  "e2e":  {"p50":2715,"p90":6216,"p95":6963,"p99":7561,"min":940,"max":7710,"num":4,
           "values":[940,2700,2730,7710]},
  "stt": {...}, "llm": {...}, "tts": {...},
  "action": null, "knowledge_base": {...},
  "first_response_ms": 1480, "interruption_count": 4
}
```

Milliseconds. `values` is every raw sample, so you can see the shape rather than
trust a p95 over `num: 4`. `null` for a stage means the call never used it.

This is an **independent measurement from `turns.py`**, not a copy of it, and
the two answer different questions:

- The BFF gives you per-stage percentiles in one request, before you know which
  cluster the call is on. Use it to decide whether a deep dive is even warranted.
- `turns.py` gives you the per-turn decomposition and the `hold` / `gate`
  segments the BFF has no concept of — a call whose BFF `stt` p95 is 4.7s is
  usually an endpointing hold, and only the log timeline can prove it.

When they disagree, the logs win for causality, the recording wins for absolute
numbers. The ~1.3-1.7s ear-to-ear understatement applies to both.

## Fields worth knowing

**Identity** — `assistant_name`, `assistant_version`, `model_id` (the assistant,
not the LLM), `campaign_name`, `type_of_call` (`inbound`/`outbound`/web),
`voice_engine_type`.

`voice_engine_type` is `go` or `python`, and it is worth carrying into the log
probe: `jsonPayload.call` is emitted by the Go services (see
`log-fields.md`), so a non-`go` record is a hint that you will need the
free-text fallback.

**Outcome** — `call_status`, `end_call_reason` (e.g. `human_pick_up_cut_off`),
`duration`, top-level `error_message`.

**Telephony** — `telephony_start` / `telephony_end` / `telephony_duration` (ms),
`telephony_ringing_duration`, `telephony_hangup` (`caller` / `agent`),
`telephony_disconnect_reason`, `telephony_sip_headers`. The Zoom / Twilio
headers carry the original dialed number, the forwarding extension and the
carrier source IP — that is how you tell a carrier-side drop from an agent hangup.

**`timeline`** — `{sender_type, type, value, timestamp, timestamp_datetime}`,
messages and actions interleaved. `type: "message"` carries the utterance;
`type: "action"` carries the action name only. Same content as `transcript`,
but stamped.

**`executed_actions`** — per action: `name`, `action_type`, `error_message`,
`parameters_from_llm` (what the model actually passed — the interesting half),
`parameters_hard_coded` (the config — the huge half), `return_value`
(`status`, `duration_ms`, and for RAG `results_count` /
`best_similarity_score` / `worst_similarity_score`).

**`judge_results`** — post-call eval. Every value is the **string** `"true"` /
`"false"` / `"partial"`, never a bool, and each check `X` has an `X_feedback`
sibling. Only the non-`true` ones are worth reading.

**`recording_url`** — an already-signed GCS URL with a ~100-year expiry. This is
the fastest answer to "give me the recording link": no `gcloud storage ls` glob,
no `sign-url`, no service-account key. `recording_sid` is usually `null`.

## Quirks that will bite

- **Pre-call actions carry a nonsense timestamp.** An action with
  `run_action_before_call_start: true` is stamped when its config was created —
  observed two days before the call it appears on. Its offset in any timeline is
  meaningless; the action still ran at call start.
- `error_message` is `null` on records that clearly failed. A failed transfer
  shows up as `executed_actions[].return_value.status:
  "transfer-failed-timeout"`, not at the top level.
- `fsm_log`, `hs_contact_id`, `hs_callback_id`, `agents_used` and `labels` are
  empty on most calls — they populate only for FSM agents, HubSpot-linked calls
  and multi-agent setups.
- The record survives past the 7-day Cloud Logging payload retention. A call the
  BFF answers for is not necessarily a call you can still pull logs for.
