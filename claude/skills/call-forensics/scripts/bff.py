#!/usr/bin/env python3
"""bff.py - pull one call's record from the internal BFF and digest it.

    bff.py <call-uuid>                 # summary: status, telephony, latency, actions
    bff.py <call-uuid> --timeline      # + per-turn transcript with offsets
    bff.py <call-uuid> --config        # + the STT/TTS/VAD knobs the call ran with
    bff.py <call-uuid> --flow          # + SIP ladder (INVITE .. BYE, who hung up)
    bff.py <call-uuid> --all --save $SP

Endpoints (all GET, no auth, tailnet-only):

    https://bff.{us,eu}.synthflow.dev/calls/<id>
    https://bff.{us,eu}.synthflow.dev/calls/payload/<id>
    https://bff.{us,eu}.synthflow.dev/calls/flow/<id>?timestamp=<start_time_ms>
    https://bff.{us,eu}.synthflow.dev/calls/pcap/<id>?timestamp=<start_time_ms>

Region is probed us -> eu; the one that answers 200 tells you which fleet the
call ran on. The raw details response is ~125KB, 90% of it hard-coded action
config, so nothing here ever prints the raw body - use --save for that.

Every field is optional and missing ones render as "-": the BFF schema differs
between engines (go / python) and between inbound, outbound and web calls.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

REGIONS = ("us", "eu")
HOST = "https://bff.{region}.synthflow.dev"
TIMEOUT = 45

# Latency stages as the BFF reports them, in pipeline order.
LAT_STAGES = ("e2e", "stt", "llm", "tts", "action", "knowledge_base")

# /calls/payload keys worth reading when the timeline blames a stage. Grouped by
# the stage they explain; everything else in that 93-key blob is prompt config.
CONFIG_KEYS = [
    ("stt", ("transcriber_provider", "transcriber_deepgram_endpointing",
             "transcriber_utterance_end_ms", "transcriber_time_cutoff_seconds",
             "transcriber_min_words_to_interrupt", "transcriber_min_interrupt_confidence",
             "transcriber_noninterrupt_confidence_threshold", "transcriber_keywords",
             "transcriber_diarization", "transcriber_suppression_level")),
    ("vad", ("vad_is_enabled", "vad_interrupt_threshold", "vad_min_chunk_size",
             "background_noise")),
    ("tts", ("voice_synthesizer", "synthesizer_voice_engine", "voice_id",
             "synthesizer_optimise_streaming_latency", "synthesizer_eleven_labs_speed",
             "synthesizer_cartesia_speed", "synthesizer_text_to_speech_chunk_size_seconds",
             "synthesizer_fallback_provider", "synthesizer_fallback_model")),
    ("call", ("orchestrator_type", "language", "max_duration", "initial_pause_seconds",
              "ring_pause_seconds", "greeting_message_mode", "ivr_enabled",
              "is_recording", "janus_pod_name", "livekit", "is_widget")),
]


# --------------------------------------------------------------------------
# fetch
# --------------------------------------------------------------------------

def get(region, path, query=None):
    """GET one BFF path. Returns (status, parsed_json_or_None, error_string)."""
    url = HOST.format(region=region) + path
    if query:
        url += "?" + "&".join(f"{k}={v}" for k, v in query.items())
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8")), None
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        try:
            body = json.loads(body).get("message", body)
        except json.JSONDecodeError:
            pass
        return exc.code, None, str(body)[:160]
    except urllib.error.URLError as exc:
        return 0, None, (f"{exc.reason} - the BFF is tailnet-only, check the VPN "
                         f"is up (host {HOST.format(region=region)})")
    except json.JSONDecodeError as exc:
        return 200, None, f"response was not JSON: {exc}"


def fetch_details(call, region="auto"):
    """Probe regions for the call. Returns (region, details) or exits."""
    regions = REGIONS if region == "auto" else (region,)
    last = ""
    for reg in regions:
        status, data, err = get(reg, f"/calls/{call}")
        if status == 200 and data:
            return reg, data
        last = f"{reg}: HTTP {status} {err or ''}".strip()
        if status == 0:                      # network, not a miss - stop probing
            break
    sys.exit(f"bff: no record for {call} ({last})")


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def base_epoch(d):
    """Call start as epoch seconds, from start_time (ms) or telephony_start."""
    st = d.get("start_time")
    if isinstance(st, (int, float)) and st > 1e11:
        return st / 1000.0
    if isinstance(st, (int, float)) and st > 1e9:
        return float(st)
    ts = d.get("telephony_start")
    if isinstance(ts, str):
        try:
            return datetime.fromisoformat(ts).replace(tzinfo=timezone.utc).timestamp()
        except ValueError:
            pass
    return None


def offset(ts, base):
    """mm:ss since call start. Out-of-range stamps print as a date instead:
    pre-call and post-call actions carry timestamps days off the call."""
    if ts is None or base is None:
        return f"{'-':>11}"
    delta = ts - base
    if delta < -60 or delta > 24 * 3600:
        return f"{datetime.fromtimestamp(ts, timezone.utc):%m-%dT%H:%M}"
    sign = "-" if delta < 0 else " "
    delta = abs(delta)
    return f"{sign}{int(delta) // 60:02d}:{int(delta) % 60:02d}".rjust(11)


def val(d, key, default="-"):
    v = d.get(key)
    if v is None or v == "":
        return default
    return v


def clip(text, width):
    text = " ".join(str(text).split())
    return text if len(text) <= width else text[:width - 1] + "…"


def rule(title):
    return f"\n{title}\n" + "-" * max(len(title), 12)


# --------------------------------------------------------------------------
# sections
# --------------------------------------------------------------------------

def render_header(d, region, out):
    out.append(f"call        {val(d, 'call_id')}   [bff.{region}]")
    out.append(f"assistant   {val(d, 'assistant_name')} (v{val(d, 'assistant_version')})"
               f"  model {val(d, 'model_id')}")
    out.append(f"call        {val(d, 'type_of_call')} / campaign {val(d, 'campaign_name')}"
               f" / engine {val(d, 'voice_engine_type')} / tz {val(d, 'timezone')}")
    out.append(f"status      {val(d, 'call_status')}   end_call_reason "
               f"{val(d, 'end_call_reason')}   duration {val(d, 'duration')}s")
    if d.get("error_message"):
        out.append(f"error       {d['error_message']}")


def render_telephony(d, out):
    out.append(rule("telephony"))
    out.append(f"  {val(d, 'telephony_start')} -> {val(d, 'telephony_end')}"
               f"  ({val(d, 'telephony_duration')} ms)")
    ring = d.get("telephony_ringing_duration")
    out.append(f"  ringing {ring if ring is not None else '-'} ms"
               f"   hangup by {val(d, 'telephony_hangup')}"
               f"   reason {val(d, 'telephony_disconnect_reason')}")
    out.append(f"  lead {val(d, 'lead_phone_number')} ({val(d, 'lead_name')})"
               f"  ->  agent {val(d, 'agent_phone_number')}")
    hdrs = d.get("telephony_sip_headers") or {}
    for k in sorted(hdrs):
        out.append(f"    {k}: {clip(hdrs[k], 80)}")


def render_latency(d, out):
    lat = d.get("latency") or {}
    out.append(rule("latency (BFF, ms)"))
    if not lat:
        out.append("  (no latency block - old call or non-go engine)")
        return
    out.append(f"  {'stage':<16}{'n':>4}{'p50':>8}{'p90':>8}{'p95':>8}{'max':>8}")
    for stage in LAT_STAGES:
        s = lat.get(stage)
        if not isinstance(s, dict):
            out.append(f"  {stage:<16}{'-':>4}{'-':>8}{'-':>8}{'-':>8}{'-':>8}")
            continue
        out.append(f"  {stage:<16}{s.get('num', '-'):>4}{s.get('p50', '-'):>8}"
                   f"{s.get('p90', '-'):>8}{s.get('p95', '-'):>8}{s.get('max', '-'):>8}")
    for stage in LAT_STAGES:
        s = lat.get(stage)
        if isinstance(s, dict) and s.get("values"):
            out.append(f"    {stage} values: {s['values']}")
    out.append(f"  first_response_ms {lat.get('first_response_ms', '-')}"
               f"   interruptions {lat.get('interruption_count', '-')}")
    out.append("  NB these are the BFF's own aggregates, not turns.py's. They omit the"
               "\n  hold/gate split and, like the logs, understate ear-to-ear by ~1.3-1.7s.")


def render_actions(d, base, out, verbose=False):
    acts = d.get("executed_actions") or []
    out.append(rule(f"executed actions ({len(acts)})"))
    for a in acts:
        rv = a.get("return_value") if isinstance(a.get("return_value"), dict) else {}
        err = a.get("error_message") or rv.get("error_message") or ""
        status = clip(rv.get("status") or ("ERROR" if err else "-"), 20)
        dur = rv.get("duration_ms")
        out.append(f"  {offset(a.get('timestamp'), base)}  {clip(val(a, 'name'), 38):<38}"
                   f" {clip(val(a, 'action_type').replace('_action_type', ''), 16):<16}"
                   f" {status:<20} {str(dur) + 'ms' if dur is not None else '':>7}"
                   f" {clip(err, 40)}")
        llm = a.get("parameters_from_llm") or {}
        if llm:
            out.append(f"           args {clip(json.dumps(llm, ensure_ascii=False), 100)}")
        if rv.get("results_count") is not None:
            out.append(f"           rag  {rv.get('results_count')} results, similarity "
                       f"{rv.get('best_similarity_score')} .. {rv.get('worst_similarity_score')}")
        if verbose and rv:
            trimmed = {k: v for k, v in rv.items() if k != "results"}
            out.append(f"           ret  {clip(json.dumps(trimmed, ensure_ascii=False), 200)}")


def render_timeline(d, base, out):
    tl = d.get("timeline") or []
    out.append(rule(f"timeline ({len(tl)} events)"))
    for e in tl:
        kind = e.get("type")
        who = val(e, "sender_type")
        text = clip(val(e, "value"), 110)
        marker = "[action]" if kind == "action" else ""
        out.append(f"  {offset(e.get('timestamp'), base)}  {who:<6} {marker}{text}")


def render_judge(d, out, verbose=False):
    j = d.get("judge_results") or {}
    if not j:
        return
    checks = [k for k in j if not k.endswith("_feedback")]
    bad = [k for k in checks if str(j.get(k)).lower() in ("false", "partial")]
    out.append(rule(f"judge ({len(bad)} of {len(checks)} checks not clean)"))
    for k in sorted(bad if not verbose else checks):
        fb = j.get(k + "_feedback") or ""
        out.append(f"  {k:<28} {str(j.get(k)):<10} {clip(fb, 90)}")


def render_recording(d, out):
    url = d.get("recording_url")
    out.append(rule("recording"))
    if not url:
        out.append("  none on the record - fall back to the GCS lookup in log-fields.md")
        return
    out.append(f"  duration {val(d, 'recording_duration')}s")
    out.append(f"  {url}")
    out.append("  (pre-signed by the BFF - hand it over as-is, no gcloud sign-url needed)")


def render_config(payload, out):
    out.append(rule("runtime config (/calls/payload)"))
    if not payload:
        out.append("  (payload unavailable)")
        return
    for group, keys in CONFIG_KEYS:
        present = [(k, payload[k]) for k in keys
                   if k in payload and payload[k] not in (None, "")]
        if not present:
            continue
        out.append(f"  [{group}]")
        for k, v in present:
            out.append(f"    {k:<52} {clip(v, 60)}")


def render_flow(flow, base, out):
    out.append(rule("SIP flow"))
    data = (flow or {}).get("data") or {}
    rows = data.get("calldata") or []
    if not rows:
        out.append("  (no SIP capture for this call)")
        return
    for r in rows:
        ts = r.get("create_date")
        ts = ts / 1000.0 if isinstance(ts, (int, float)) and ts > 1e11 else ts
        method, text = str(val(r, "method")), str(val(r, "method_text", ""))
        out.append(f"  {offset(ts, base)}  {clip(val(r, 'aliasSrc'), 24):<24} -> "
                   f"{clip(val(r, 'aliasDst'), 24):<24} "
                   f"{method:<8} {clip(text, 40) if text != method else ''}")
    out.append("  (BYE side = who actually hung up; cross-check telephony_hangup)")


# --------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("call", help="call UUID")
    ap.add_argument("--region", choices=("auto", "us", "eu"), default="auto",
                    help="default auto: probe us then eu")
    ap.add_argument("--timeline", action="store_true", help="per-turn transcript")
    ap.add_argument("--config", action="store_true",
                    help="fetch /calls/payload and show the STT/TTS/VAD knobs")
    ap.add_argument("--flow", action="store_true", help="fetch the SIP ladder")
    ap.add_argument("--pcap", metavar="PATH", help="decode /calls/pcap into PATH")
    ap.add_argument("--all", action="store_true", help="timeline + config + flow")
    ap.add_argument("--verbose", action="store_true",
                    help="all judge checks, full action return values")
    ap.add_argument("--save", metavar="DIR", help="write the raw JSON responses here")
    ap.add_argument("--json", action="store_true", dest="as_json",
                    help="emit the assembled record as JSON instead of the digest")
    args = ap.parse_args(argv)

    want_timeline = args.timeline or args.all
    want_config = args.config or args.all
    want_flow = args.flow or args.all

    region, details = fetch_details(args.call, args.region)
    base = base_epoch(details)
    start_ms = details.get("start_time")
    saved = {"details": details}

    payload = None
    if want_config:
        status, payload, err = get(region, f"/calls/payload/{args.call}")
        if status != 200:
            payload = None
            print(f"bff: payload unavailable (HTTP {status} {err or ''})", file=sys.stderr)
        else:
            saved["payload"] = payload

    flow = None
    if want_flow:
        if not isinstance(start_ms, (int, float)):
            print("bff: no start_time on the record, cannot fetch the SIP flow",
                  file=sys.stderr)
        else:
            status, flow, err = get(region, f"/calls/flow/{args.call}",
                                    {"timestamp": int(start_ms)})
            if status != 200:
                flow = None
                print(f"bff: flow unavailable (HTTP {status} {err or ''})", file=sys.stderr)
            else:
                saved["flow"] = flow

    if args.pcap:
        if not isinstance(start_ms, (int, float)):
            print("bff: no start_time on the record, cannot fetch the pcap", file=sys.stderr)
        else:
            status, cap, err = get(region, f"/calls/pcap/{args.call}",
                                   {"timestamp": int(start_ms)})
            if status == 200 and cap and cap.get("pcap"):
                raw = base64.b64decode(cap["pcap"])
                with open(args.pcap, "wb") as fh:
                    fh.write(raw)
                print(f"bff: wrote {len(raw)} bytes of pcap to {args.pcap}", file=sys.stderr)
            else:
                print(f"bff: pcap unavailable (HTTP {status} {err or ''})", file=sys.stderr)

    if args.save:
        for name, blob in saved.items():
            path = f"{args.save.rstrip('/')}/bff_{name}_{args.call[:8]}.json"
            with open(path, "w") as fh:
                json.dump(blob, fh, indent=1)
            print(f"bff: saved {path}", file=sys.stderr)

    if args.as_json:
        json.dump({"region": region, **saved}, sys.stdout, indent=1)
        print()
        return 0

    out = []
    render_header(details, region, out)
    render_telephony(details, out)
    render_latency(details, out)
    render_actions(details, base, out, args.verbose)
    if want_timeline:
        render_timeline(details, base, out)
    if want_config:
        render_config(payload, out)
    if want_flow:
        render_flow(flow, base, out)
    render_judge(details, out, args.verbose)
    render_recording(details, out)
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
