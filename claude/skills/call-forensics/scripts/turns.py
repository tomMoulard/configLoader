#!/usr/bin/env python3
"""turns.py - turn-by-turn latency timeline from a Cloud Logging call dump.

Input is whatever `gcloud logging read ... --format=json` produced:

    gcloud logging read "jsonPayload.call=\"$CALL\"" --project "$P" \
      --freshness 7d --limit 5000 --order asc --format=json > call.json
    turns.py call.json

Also accepts newline-delimited JSON, a {"entries": [...]} wrapper, and a dump
that was truncated mid-write (the tail is salvaged object by object).

Every field is optional. Schemas differ between orchestrator / conductor /
latency-router and between clusters, so a stage that cannot be located is
reported as "-" rather than guessed, and no missing key is ever fatal.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone

# --------------------------------------------------------------------------
# Stage table. Each stage is located by a substring match (lowercased) against
# jsonPayload.msg / .message, or by the presence of a payload key.
#
# The pipeline order below IS the latency decomposition:
#   user stop -> STT endpointing -> wait_reason hold -> intent gate
#             -> LLM TTFT -> TTS first audio -> agent speaks
# --------------------------------------------------------------------------

STAGES = [
    # key,          label,            msg substrings (lowercased),                        payload keys
    ("turn_start",  "turn start",     ("starting new turn", "user turn started"),          ()),
    ("user_stop",   "user stop",      ("ttft: user speech end time set",
                                       "flux: end of turn", "end of speech"),              ("speech_end_time",)),
    ("stt_final",   "STT final",      ("user said", "sending transcript", "transcript sent",
                                       "final transcript",
                                       "conversationmanager received transcript"),         ("full_transcript",)),
    ("wait_hold",   "wait hold",      ("waitformoreuserinput",
                                       "soniox <end> deferred",
                                       "number continuation window",
                                       "extending endpointing duration"),                  ("wait_reason", "waitForUserInputDuration")),
    ("inv_start",   "invocation",     ("starting invocation", "starting new invocation"),  ()),
    ("gate_done",   "gate released",  ("first token timer timeout set", "detected intent",
                                       "chosen intent"),                                   ()),
    ("llm_req",     "LLM request",    ("created request metadata",
                                       "chatcompletionrequest created"),                   ()),
    ("llm_ttft",    "LLM TTFT",       ("received answer from llmanswerstream",
                                       "received answer from invoker",
                                       "recorded ongoing ttft", "recorded initial ttft"),  ("ttft_ongoing_seconds", "ttft_initial_seconds")),
    ("tts_send",    "TTS send",       ("sending data to tts", "sending message to tts"),   ()),
    ("tts_audio",   "TTS 1st audio",  ("received first audio data", "read from tts provider",
                                       "received first frame"),                            ("time_to_first_audio_ms",)),
    ("agent_speak", "agent speaks",   ("bot said", "bot utterance", "started speaking"),   ()),
    ("turn_end",    "turn end",       ("stopping turn", "turn completed", "turn latency",
                                       "streaming latency"),                               ()),
]

STAGE_KEYS = [s[0] for s in STAGES]
STAGE_LABEL = {s[0]: s[1] for s in STAGES}

# name, from-stage (| = fallback chain), to-stage, human label.
# Boundaries are the ones the orchestrator actually logs, per the corpus:
#   gate = "First token timer timeout set" - "Starting invocation"
#   llm  = "Received answer from LLMAnswerStream" - "Created request metadata"
#   tts  = "Reader: Received first audio data" - "Sending data to TTS provider"
# Segments do not always tile the whole turn, so their sum can fall short of the
# measured total; `share` is therefore share of *accounted* time.
SEGMENTS = [
    ("stt",   "user_stop",           "stt_final",           "STT endpointing"),
    ("hold",  "wait_hold",           "inv_start|gate_done", "wait_reason hold"),
    ("gate",  "inv_start",           "gate_done|llm_req",   "intent gate"),
    ("llm",   "llm_req|gate_done",   "llm_ttft",            "LLM TTFT"),
    ("tts",   "tts_send|llm_ttft",   "tts_audio",           "TTS first audio"),
    ("speak", "tts_audio",           "agent_speak",         "audio out"),
]

# jsonPayload keys that may carry what the user said / what the agent replied.
USER_TEXT_KEYS = ("transcript", "full_transcript", "current_transcript", "user_message",
                  "user_transcript", "user_text")
AGENT_TEXT_KEYS = ("bot_message", "agent_text", "assistant", "response", "agent_message",
                   "llm_response", "text", "content")

TS_RE = re.compile(r"(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(\.\d+)?\s*(Z|[+-]\d{2}:?\d{2})?")


# --------------------------------------------------------------------------
# loading
# --------------------------------------------------------------------------

def _salvage(text):
    """Pull top-level objects out of a truncated / concatenated JSON dump."""
    out, depth, start, in_str, esc = [], 0, None, False, False
    for i, ch in enumerate(text):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    out.append(json.loads(text[start:i + 1]))
                except ValueError:
                    pass
                start = None
            elif depth < 0:
                depth = 0
    return out


def load_entries(path):
    if path == "-":
        text = sys.stdin.read()
    else:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    if not text.strip():
        return []
    try:
        doc = json.loads(text)
    except ValueError:
        rows = []
        ok = True
        for line in text.splitlines():
            line = line.strip().rstrip(",")
            if not line or line in "[]":
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                ok = False
                break
        return rows if (ok and rows) else _salvage(text)
    if isinstance(doc, dict):
        for key in ("entries", "logEntries", "items", "results"):
            if isinstance(doc.get(key), list):
                return doc[key]
        return [doc]
    return doc if isinstance(doc, list) else []


def parse_ts(value):
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(value / (1000.0 if value > 1e11 else 1.0), timezone.utc)
        except (ValueError, OSError, OverflowError):
            return None
    if not isinstance(value, str):
        return None
    m = TS_RE.search(value)
    if not m:
        return None
    date, clock, frac, tz = m.groups()
    micros = (frac or ".0")[1:7].ljust(6, "0")
    try:
        dt = datetime.strptime("%s %s" % (date, clock), "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None
    dt = dt.replace(microsecond=int(micros), tzinfo=timezone.utc)
    if tz and tz != "Z":
        tz = tz.replace(":", "")
        try:
            minutes = (int(tz[1:3]) * 60 + int(tz[3:5])) * (1 if tz[0] == "+" else -1)
            dt -= timedelta(minutes=minutes)
        except (ValueError, IndexError):
            pass
    return dt


def flatten(obj, prefix="", out=None, depth=0):
    """jsonPayload -> dotted keys, so config.Provider and turn.id both resolve."""
    if out is None:
        out = {}
    if depth > 6 or not isinstance(obj, dict):
        return out
    for key, val in obj.items():
        path = "%s%s" % (prefix, key)
        if isinstance(val, dict):
            flatten(val, path + ".", out, depth + 1)
        else:
            out[path] = val
    return out


def index(payload):
    """Case- and underscore-insensitive lookup table, built once per record so
    turn_id / turn.id / turnId / config.TurnID all resolve to the same entry."""
    table = {}
    for key, val in payload.items():
        if val in (None, "", [], {}):
            continue
        low = key.lower()
        tail = low.split(".")[-1]
        for alias in (low, tail, low.replace("_", ""), tail.replace("_", "")):
            table.setdefault(alias, val)
    return table


def _get(payload, *names):
    """First present, non-empty value among `names`. `payload` may be a raw
    flattened dict or a prebuilt index()."""
    table = payload if payload.get("__indexed__") else index(payload)
    for name in names:
        low = name.lower()
        for alias in (low, low.split(".")[-1], low.replace("_", "")):
            val = table.get(alias)
            if val is not None:
                return val
    return None


def as_float(val):
    if isinstance(val, bool):
        return None
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, str):
        try:
            return float(val.strip().rstrip("s"))
        except ValueError:
            return None
    return None


# --------------------------------------------------------------------------
# normalisation
# --------------------------------------------------------------------------

class Record(object):
    __slots__ = ("ts", "elapsed", "msg", "payload", "container", "namespace",
                 "severity", "stages")

    def __init__(self, ts, msg, payload, container, namespace, severity):
        self.ts = ts
        self.elapsed = None
        self.msg = msg
        self.payload = payload
        self.container = container
        self.namespace = namespace
        self.severity = severity
        self.stages = []


def normalise(entries):
    records = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        raw = entry.get("jsonPayload")
        if not isinstance(raw, dict):
            text = entry.get("textPayload")
            if isinstance(text, str):
                # prod sometimes wraps the whole JSON record in textPayload
                try:
                    raw = json.loads(text)
                except ValueError:
                    raw = {"msg": text}
                if not isinstance(raw, dict):
                    raw = {"msg": text}
            else:
                raw = entry          # a bare payload dict (jsonl of jsonPayloads)
        payload = index(flatten(raw))
        payload["__indexed__"] = True
        ts = (parse_ts(entry.get("timestamp"))
              or parse_ts(_get(payload, "ts", "time", "timestamp"))
              or parse_ts(entry.get("receiveTimestamp")))
        msg = _get(payload, "msg", "message", "event") or entry.get("textPayload") or ""
        if not isinstance(msg, str):
            msg = str(msg)
        labels = ((entry.get("resource") or {}).get("labels") or {}) if isinstance(entry.get("resource"), dict) else {}
        rec = Record(ts, msg, payload,
                     labels.get("container_name") or _get(payload, "service", "service.name") or "",
                     labels.get("namespace_name") or "",
                     entry.get("severity") or _get(payload, "level", "severity") or "")
        rec.elapsed = as_float(_get(payload, "elapsed"))
        rec.stages = classify(rec)
        records.append(rec)
    # sort by wall clock, tie-broken by in-call `elapsed` (same-millisecond bursts)
    records.sort(key=lambda r: (r.ts is None,
                                r.ts or datetime.min.replace(tzinfo=timezone.utc),
                                r.elapsed if r.elapsed is not None else 0.0))
    return records


def classify(rec):
    low = rec.msg.lower()
    hits = []
    for key, _label, needles, pkeys in STAGES:
        if any(n in low for n in needles) or any(_get(rec.payload, pk) is not None for pk in pkeys):
            hits.append(key)
    return hits


# --------------------------------------------------------------------------
# turn grouping
# --------------------------------------------------------------------------

class Turn(object):
    def __init__(self, tid):
        self.id = tid
        self.records = []
        self.marks = {}          # stage key -> first datetime seen
        self.turn_type = None
        self.wait_reason = None
        self.user_text = None
        self.agent_text = None
        self.ttft = None         # ttft_ongoing_seconds, straight from the log
        self.hold_seconds = None # waitForUserInputDuration, straight from the log
        self.errors = []

    @property
    def start(self):
        for r in self.records:
            if r.ts:
                return r.ts
        return None

    @property
    def end(self):
        for r in reversed(self.records):
            if r.ts:
                return r.ts
        return None

    def absorb(self, rec):
        self.records.append(rec)
        for key in rec.stages:
            if rec.ts and key not in self.marks:
                self.marks[key] = rec.ts
        self.turn_type = self.turn_type or _get(rec.payload, "turn_type", "turnType")
        self.wait_reason = self.wait_reason or _get(rec.payload, "wait_reason", "waitReason")
        if self.ttft is None:
            self.ttft = as_float(_get(rec.payload, "ttft_ongoing_seconds", "ttft_initial_seconds"))
        if self.hold_seconds is None:
            self.hold_seconds = as_float(_get(rec.payload, "waitForUserInputDuration",
                                              "wait_for_user_input_duration", "wait_duration_seconds"))
        if not self.user_text:
            val = _get(rec.payload, *USER_TEXT_KEYS)
            if isinstance(val, str) and val.strip():
                self.user_text = val.strip()
        if not self.agent_text:
            val = _get(rec.payload, *AGENT_TEXT_KEYS)
            if isinstance(val, str) and val.strip() and val.strip() != self.user_text:
                self.agent_text = val.strip()
        err = _get(rec.payload, "error", "err")
        sev = (rec.severity or "").upper()
        if err or sev in ("ERROR", "CRITICAL", "ALERT", "EMERGENCY"):
            note = err if isinstance(err, str) else (rec.msg or sev)
            if note and note not in self.errors:
                self.errors.append(note)

    def mark(self, spec):
        """First available mark among 'a|b' fallbacks."""
        for key in spec.split("|"):
            if key in self.marks:
                return self.marks[key]
        return None

    def segments(self):
        out = {}
        for name, src, dst, _label in SEGMENTS:
            a, b = self.mark(src), self.mark(dst)
            if a and b:
                delta = (b - a).total_seconds()
                if delta >= 0:
                    out[name] = delta
        if "llm" not in out and self.ttft is not None:
            out["llm"] = self.ttft
        if "hold" not in out and self.hold_seconds is not None:
            out["hold"] = self.hold_seconds
        return out

    def response_latency(self):
        """user stopped talking -> agent audio out. Falls back down the chain."""
        for src, dst in (("user_stop", "agent_speak|tts_audio"),
                         ("user_stop", "llm_ttft"),
                         ("stt_final", "agent_speak|tts_audio"),
                         ("turn_start", "turn_end")):
            a, b = self.mark(src), self.mark(dst)
            if a and b and (b - a).total_seconds() >= 0:
                return (b - a).total_seconds()
        if self.start and self.end:
            return (self.end - self.start).total_seconds()
        return None


def build_turns(records):
    turns, order, current = {}, [], None
    for rec in records:
        tid = _get(rec.payload, "turn_id", "turnId", "turn.id", "planner_turn_id")
        if tid is not None:
            tid = str(tid)
            current = tid
        else:
            tid = current           # untagged lines belong to the turn in flight
        if tid is None:
            tid = "(pre-turn)"
        if tid not in turns:
            turns[tid] = Turn(tid)
            order.append(tid)
        turns[tid].absorb(rec)
    return [turns[t] for t in order]


# --------------------------------------------------------------------------
# stats
# --------------------------------------------------------------------------

def pct(values, q):
    if not values:
        return None
    vals = sorted(values)
    if len(vals) == 1:
        return vals[0]
    pos = (len(vals) - 1) * q
    lo, hi = int(pos), min(int(pos) + 1, len(vals) - 1)
    return vals[lo] + (vals[hi] - vals[lo]) * (pos - lo)


def summarise(turns):
    lat = [t.response_latency() for t in turns]
    lat = [v for v in lat if v is not None]
    per_seg = {}
    for turn in turns:
        for name, val in turn.segments().items():
            per_seg.setdefault(name, []).append(val)
    seg_stats = {}
    for name, vals in per_seg.items():
        seg_stats[name] = {"n": len(vals), "p50": pct(vals, 0.5),
                           "p95": pct(vals, 0.95), "max": max(vals),
                           "total": sum(vals)}
    # Attribute blame by share of all the wall-clock the caller spent waiting:
    # that weighs a rare 3s stall against a per-turn 0.4s tax honestly, which
    # neither p50 (hides rare stalls) nor max (hides steady taxes) does alone.
    accounted = sum(st["total"] for st in seg_stats.values()) or 1.0
    for st in seg_stats.values():
        st["share"] = st["total"] / accounted
    dominant = None
    if seg_stats:
        dominant = max(seg_stats.items(), key=lambda kv: kv[1]["total"])[0]
    worst = None
    scored = [(t.response_latency(), t) for t in turns]
    scored = [(v, t) for v, t in scored if v is not None]
    if scored:
        worst = max(scored, key=lambda vt: vt[0])[1]
    return {
        "turns": len(turns),
        "measured": len(lat),
        "p50": pct(lat, 0.5), "p95": pct(lat, 0.95),
        "max": max(lat) if lat else None,
        "segments": seg_stats,
        "dominant": dominant,
        "dominant_label": dict((n, l) for n, _s, _d, l in SEGMENTS).get(dominant),
        "worst_turn": worst.id if worst else None,
    }


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def clip(text, width):
    if text is None:
        return "-"
    text = " ".join(str(text).split())
    return text if len(text) <= width else text[:width - 1] + "…"


def fmt(val, width=6):
    return "-".rjust(width) if val is None else ("%.2f" % val).rjust(width)


def render(turns, stats, top, show_text):
    lines = []
    seg_names = [n for n, _s, _d, _l in SEGMENTS]
    head = ["  #", "turn_id".ljust(22), "type".ljust(14)]
    head += [n.rjust(6) for n in seg_names]
    head += ["  total"]
    lines.append(" ".join(head))
    lines.append("-" * len(" ".join(head)))

    shown = turns
    note = ""
    if top and len(turns) > top:
        ranked = sorted(turns, key=lambda t: -(t.response_latency() or 0))[:top]
        keep = set(id(t) for t in ranked)
        shown = [t for t in turns if id(t) in keep]
        note = "(showing %d slowest of %d turns)" % (len(shown), len(turns))

    for idx, turn in enumerate(turns):
        if turn not in shown:
            continue
        segs = turn.segments()
        row = ["%3d" % (idx + 1), clip(turn.id, 22).ljust(22), clip(turn.turn_type, 14).ljust(14)]
        row += [fmt(segs.get(n)) for n in seg_names]
        row += [fmt(turn.response_latency(), 7)]
        lines.append(" ".join(row))
        if show_text:
            if turn.wait_reason:
                lines.append("      wait_reason: %s" % clip(turn.wait_reason, 90))
            if turn.user_text:
                lines.append("      user  > %s" % clip(turn.user_text, 100))
            if turn.agent_text:
                lines.append("      agent < %s" % clip(turn.agent_text, 100))
            for err in turn.errors[:2]:
                lines.append("      ERROR   %s" % clip(err, 100))
    if note:
        lines.append(note)

    lines.append("")
    lines.append("turns=%d  measured=%d  p50=%s  p95=%s  max=%s   (response latency, seconds)" % (
        stats["turns"], stats["measured"], fmt(stats["p50"]).strip(),
        fmt(stats["p95"]).strip(), fmt(stats["max"]).strip()))
    if stats["segments"]:
        lines.append("")
        lines.append("  segment            n     p50     p95     max   total  share*")
        for name, _s, _d, label in SEGMENTS:
            st = stats["segments"].get(name)
            if not st:
                continue
            lines.append("  %-16s %3d  %s  %s  %s  %s  %4.0f%%%s" % (
                label, st["n"], fmt(st["p50"]), fmt(st["p95"]), fmt(st["max"]),
                fmt(st["total"]), 100 * st["share"],
                "  <== dominant" if name == stats["dominant"] else ""))
    if stats["dominant"]:
        lines.append("")
        dom = stats["segments"][stats["dominant"]]
        lines.append("VERDICT: biggest latency contributor is %s - %.0f%% of accounted turn time "
                     "(%.2fs total, p50 %.2fs, max %.2fs over %d turns)%s" % (
                         stats["dominant_label"], 100 * dom["share"], dom["total"],
                         dom["p50"], dom["max"], dom["n"],
                         "; worst turn %s" % stats["worst_turn"] if stats["worst_turn"] else ""))
    else:
        lines.append("")
        lines.append("VERDICT: no stage boundaries were derivable from this dump "
                     "(missing turn_id / stage log lines?).")
    return "\n".join(lines)


def to_json(turns, stats):
    return {
        "summary": stats,
        "turns": [{
            "index": i + 1,
            "turn_id": t.id,
            "turn_type": t.turn_type,
            "wait_reason": t.wait_reason,
            "user_transcript": t.user_text,
            "agent_text": t.agent_text,
            "ttft_ongoing_seconds": t.ttft,
            "start": t.start.isoformat() if t.start else None,
            "end": t.end.isoformat() if t.end else None,
            "marks": {k: v.isoformat() for k, v in sorted(t.marks.items())},
            "segments": t.segments(),
            "response_latency": t.response_latency(),
            "errors": t.errors,
            "events": len(t.records),
        } for i, t in enumerate(turns)],
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dump", help="gcloud logging read --format=json output ('-' for stdin)")
    ap.add_argument("--json", action="store_true", dest="as_json",
                    help="emit machine-readable JSON instead of the table")
    ap.add_argument("--top", type=int, default=0, metavar="N",
                    help="only render the N slowest turns (summary still covers all)")
    ap.add_argument("--no-text", action="store_true",
                    help="omit transcript / agent-text lines")
    args = ap.parse_args(argv)

    try:
        entries = load_entries(args.dump)
    except (OSError, IOError) as exc:
        print("cannot read %s: %s" % (args.dump, exc), file=sys.stderr)
        return 2

    records = normalise(entries)
    if not records:
        print("no log entries parsed from %s (empty dump? wrong project? "
              "call older than the 7d retention window?)" % args.dump, file=sys.stderr)
        return 1

    turns = build_turns(records)
    stats = summarise(turns)

    if args.as_json:
        print(json.dumps(to_json(turns, stats), indent=2, default=str))
    else:
        print(render(turns, stats, args.top, not args.no_text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
