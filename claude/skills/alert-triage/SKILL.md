---
name: alert-triage
description: >-
  Triage a fired Prometheus/Alertmanager alert end to end — parse the payload,
  find the rule behind it, confirm it against Mimir, correlate logs and traces,
  size the blast radius in calls, land a verdict. Use when the user pastes an
  Alertmanager or Grafana alert (a "Firing -" block, `*Status:* Firing`, a
  CamelCase alert name like `TTSAllProvidersFailed`, a `_total` counter
  "increased by N in the last 10m"), asks "is this alert real?", "did this
  self-resolve?", "our canary latency has shot up", or asks to add, tune or
  loosen an alert rule.
---

# Alert triage

Read-only by default: you are answering *is this real, how bad, what now*. Stay
in the main checkout, no worktree — only if the answer turns into a code or rule
change does `worktree-first` apply, and then `ship-pr` for the PR. Mimir is the
only Prometheus datasource: name `Mimir`, UID `aee98cu2bsfeoe`.
`references/alert-map.md` holds the cluster→namespace→GCP-project map, the alert
inventory, the Alertmanager routing table and a rule skeleton — read it when the
payload names a cluster, or when you have a symptom but no alert name.

```bash
INFRA=~/go/src/github.com/synthflowai/infrastructure-deployers
RULES=$INFRA/argocd-apps/gcp/synthflow-ops/helm/grafana-mimir/sources/rules
```

## 1. Parse the payload

The Slack card comes from `sources/alertmanager-templates/default-slack.tpl`, so
it always carries **Status, Severity, Region, Cluster, Owner, Description** and
Runbook / Dashboard buttons. Pull out first:

- **alert name** — card title, or the CamelCase token in the pasted text;
- **cluster + namespace** — they pick the environment *and* the GCP log project;
- **the varying label** — `provider`, `gen_ai_request_model`, `pod`, `environment`;
- **value and unit** — "0.17 turns/s" is a rate, "increased by 1" is a count;
- **firing time** (ask if absent) — everything downstream is scoped to that window;
- **runbook_url** — some alerts have a real runbook in `$INFRA/docs/`; read it first.

## 2. Find the rule

`$RULES/prod/` holds 8 files, `$RULES/testing/` 3. One Mimir namespace and one
group per file; alerts sit at 8-space indent.

```bash
grep -rn "alert: TTSAllProvidersFailed" $RULES/prod/     # -> orchestrator-rules.yaml:310
sed -n '310,340p' $RULES/prod/orchestrator-rules.yaml    # expr, for:, labels, annotations
grep -rn "tts_provider_used_total" $RULES/prod/          # every rule on that metric
```

State three things: the **`expr`** (what is actually measured), the
**threshold**, and **`for:`** — how long it must hold. `for: 0s` on
`WarmTransferHumanDetectionFailOpen` means a single event pages. That is what
lets you judge threshold-vs-system.

Then check the labels: `urgency` picks the incident.io lane, `slack_channel_name`
the channel, and a `critical` **inhibits** the matching `warning` — a silent
warning is not evidence of health. Dashboards live in `grafana-configs` (its
`exported-rules/` is a mimirtool mirror, never the source of truth);
`mcp__grafana__search_dashboards` + `get_panel_image` + `generate_deeplink`
produce a link to hand the user.

## 3. Confirm it against the data

Use the Grafana MCP, don't guess. Copy the rule's own `expr` verbatim for query
one — empty means it already resolved.

1. **Now** — `query_prometheus` instant, the rule's `expr`, `endTime: now`.
2. **The window** — `queryType: range` over `[firing-30m, firing+30m]`,
   `stepSeconds: 60`: the shape, and whether it recovered.
3. **Baseline** — same expr with `offset 1d` and `offset 7d`. A value that is
   normal for a Tuesday evening is a threshold problem, not an incident.
4. **Ownership** — drop the rule's `sum by (...)`, re-aggregate by whatever
   varies (`by (provider)`, `by (cluster)`, `by (pod)`). One provider owning
   100% is a different verdict from an even spread.
5. **Denominator** — a rate means nothing without traffic; divide by the total
   (`/ sum(rate(tts_provider_used_total[5m]))`) for a percentage.

`list_prometheus_metric_names` / `list_prometheus_label_values` when a name
doesn't resolve, `query_prometheus_histogram` for `_bucket` (latency) alerts,
`list_alert_groups` / `get_alert_group` for what Alertmanager holds open.

## 4. Correlate logs and traces

Scope `--freshness` to the alert's own window, never a blind `7d`; pick the
project from the cluster.

```bash
gcloud logging read --project fine-tuner-386314 --freshness=2h --limit=50 \
  --format='value(timestamp, jsonPayload.call, jsonPayload.msg, jsonPayload.error)' \
  'resource.labels.namespace_name="production"
   AND resource.labels.container_name="orchestrator"
   AND jsonPayload.msg=~"TTS provider chain exhausted"'

DASH0_AGENT_MODE=1 dash0 spans query --from now-2h --limit 100 \
  --filter "service.name is orchestrator" --filter "otel.span.status.code is ERROR"
```

Alert descriptions often name the log line to grep for; when they don't, pull
the error string from the Go source (`errTTSChainExhausted`, in
`orchestrator/pkg/synthesizer/tts_node.go`).

## 5. Blast radius

For voice alerts the question is always **how many calls, and did callers hear it**.

- Distinct calls from logs: the same query with `--format='value(jsonPayload.call)' | sort -u | wc -l`.
- Or from Mimir: `sum(increase(<counter>[<firing window>]))` over
  `sum(increase(call_duration_seconds_count[<same window>]))` for a share of calls.
- Take **one** representative `call` UUID to **`call-forensics`**
  (`~/.claude/skills/call-forensics/`) for the per-turn story. One real call
  beats a paragraph of aggregates.
- **Cross-reference deploys** — a spike starting at a rollout is a regression, not
  a provider outage:
  `max by (pod) (kube_pod_created{namespace="production", pod=~"orchestrator-.*"})`,
  `gh run list --repo SynthFlowAI/orchestrator --workflow build-deploy.yaml --limit 10`.

## 6. The verdict

Every triage ends with these four lines, in this order, nothing padded between:

1. **Classification** — real incident / threshold too tight / known-and-expected.
2. **Blast radius** — calls or turns, with the window. "Unknown" is allowed; a hedge is not.
3. **Self-resolved?** — yes at HH:MM / still firing / flapping.
4. **Next action** — exactly one, and who does it.

Then *offer*: "want a Linear issue (ENG/VOI/PRO/TEL) or a Slack draft?" **Never
create the issue or send the message without being asked** — draft it in the
reply and let the user say go.

## 7. Authoring and tuning rules

This half *is* a code change: `worktree-first`, then `ship-pr`.

**New counter → new alert.** Metric first, in `orchestrator/pkg/metrics/metrics.go`:
a `prometheus.NewCounterVec` in the `var (...)` block *and* an entry in the
`prometheus.MustRegister(...)` list in `init()` — an unregistered metric never
reaches Mimir. Keep cardinality low (`provider`, `state`; never `call_id`). Ship
and deploy that first: you cannot threshold a series that was never scraped.

**The rule.** Append to the matching `$RULES/prod/<area>-rules.yaml` group,
copying an adjacent rule wholesale — every rule carries `incident_routing`,
`severity`, `urgency`, `slack_channel_name`, `environment`, `component`,
`cluster`, `region` labels; `description`, `summary`, `runbook_url`,
`dashboard_url`, `owner`, `escalation_path_id` annotations; and the selector
`{job=~"orchestrator|synthflow/orchestrator", namespace=~"production|synthflow"}`.
Validate the `expr` against live Mimir *before* opening the PR, and state in the
PR body how often it would have fired over the last 7d.

**Loosening a threshold** needs the same evidence: a 7–30d range query showing
the `expr` crossing the current threshold N times with no real impact. Prefer
raising `for:` over raising the threshold when the signal is spiky but real.
Threshold in one commit, runbook update in another.

**CI and naming.** `.github/workflows/mimir-rules.yaml` runs `rules diff` on PRs
touching `sources/rules/**` and `rules apply` on merge to `main` — that diff is
the real preflight. This repo overrides the usual branch and PR-title
conventions: see "Rule PRs" in `references/alert-map.md` before you push.
