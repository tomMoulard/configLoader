# Alert map — verified 2026-08-28

Everything below was read off disk / queried live, not remembered.

## Where things live

| Thing | Path |
|---|---|
| Prod alert rules | `infrastructure-deployers/argocd-apps/gcp/synthflow-ops/helm/grafana-mimir/sources/rules/prod/` |
| Testing alert rules | `.../sources/rules/testing/` (only `end-2-end`, `metrics-insight`, `telephony`) |
| Alertmanager config + Slack template | `.../sources/alertmanager-templates/{alertmanager-config.yaml,default-slack.tpl}` |
| Sync script | `.../grafana-mimir/mimir-helper.sh` (`--target rules diff\|apply`, `--target alertmanager sync`) |
| CI | `infrastructure-deployers/.github/workflows/mimir-rules.yaml` |
| Runbooks | `infrastructure-deployers/docs/*.md` |
| Dashboards | `grafana-configs/` — `e2e.json`, `rules/`, `exported-rules/` (mimirtool exports; read-only mirror) |
| Go metrics (orchestrator) | `orchestrator/pkg/metrics/metrics.go` — `var (...)` block + `MustRegister` in `init()` |

Mimir: `https://mimir.synthflow.dev`, tenant `anonymous`. Grafana:
`https://grafana.synthflow.dev`. Only Prometheus datasource: **Mimir**, UID
`aee98cu2bsfeoe` (default).

## File → Mimir namespace → group → alerts

Each rule file declares one `namespace:` and one group. Alerts sit at 8-space
indent, so `grep -n '^        - alert:' <file>` lists them.

| File | ns / group | Alerts |
|---|---|---|
| `orchestrator-rules.yaml` | `orchestrator` / `OrchestratorAlerts` | SlowGarbageCollection, OrchestratorPanic, STTCircuitBreakerOpen, STTCircuitBreakerSkippingCalls, STTProviderErrorRateHigh, STTInitRetryRateHigh, STTAllProvidersFailed, TTSCircuitBreakerOpen, TTSFailoverRateHigh, TTSCircuitBreakerSkippingCalls, TTSInitRetryRateHigh, TTSAllProvidersFailed, CallNoProgressionHigh, WarmTransferHumanDetectionFailOpen, WarmTransferHumanDetectionClassifierUnavailable |
| `end-2-end-rules.yaml` | `end-2-end` / `E2E` | `CallDuration<20sec`, `CallLatency>10seconds`, `CallDuration<20sec(warning)`, MissingMetricsMediabridge, MissingMetricsAPIWatchDogs, MissingMetricsOtherScripts, `BotAnswerLatency(P90)`, `BotAnswerLatency(P50)` |
| `latencies-rules.yaml` | `latencies` / `Latencies` | QdrantLatency, DeepgramLatency, 11LabsLatency, OpenAILatency, AzureOpenAILatency, SynthflowLatency |
| `latency-router-rules.yaml` | `latency-router` / `LatencyRouterAlerts` | LatencyRouterHighUserFacing5xxErrorRate{Critical,Warning}, LatencyRouterHighOutboundLlm4xxErrorRate{Critical,Warning} |
| `telephony-rules.yaml` | `telephony` / `TelephonyAlerts` | FreeswitchEventsDelay, TelephonyComponentNotRunning, NodeHigh{CPU,Memory}Utilization, `5xx&6xxSIPErrors`, RtpengineConnectionErrors, KamailioDispatcherReloadSlowRPCs, RTPEngineHighNetwork{Receive,Transmit}(+LATAM), HighSIPINVITEErrorRate, RTPengineAudioQualityDegraded, KamailioSharedMemoryHigh |
| `metrics-insight-rules.yaml` | `insight` / `MetricsInsight` | PodRestartOrTerminated, ContainerHigh{CPU,Memory}Usage, QdrantHighMemoryUsage, DeepgramHigh{Memory,CPU,GPU}Usage, DeepgramEngineHighActiveRequestUsageFlux, HighVolumeUsage, KEDAScaledObjectContinuousErrors, EphemeralStorageUsageHigh, CertManagerCertExpiringSoon |
| `message-queue-rules.yaml` | `message-queue` / `MessageQueue` | `RabbitMQReady>5000`, RabbitMQHighVolumeUsage, QueueCount |
| `rtpengine-vms.yaml` | `rtpengine-vms` / `RtpengineVMs` | NodeHigh{CPU,Memory}Utilization, RTPEngineHighNetwork{Receive,Transmit}, RTPengineAudioQualityDegraded |

**Symptom → file** when there is no alert name: canary / bot-answer latency →
`end-2-end`; a named provider being slow → `latencies`; LLM proxy 4xx/5xx →
`latency-router`; STT/TTS/warm-transfer/panic → `orchestrator`; SIP, RTP, audio
quality → `telephony` or `rtpengine-vms`; pod restarts, CPU/mem/GPU, certs →
`metrics-insight`.

## Cluster → namespace → GCP project

From `count by (cluster, namespace, job) (up{job=~".*orchestrator.*"})`:

| `cluster` label | namespace | Prometheus `job` | GCP logging project |
|---|---|---|---|
| `synthflow-prod` | `production` | `orchestrator` | `fine-tuner-386314` (legacy, most traffic) |
| `prod-use1` | `synthflow` | `synthflow/orchestrator` | `synthflow-prod-us` |
| `prod-euw3` | `synthflow` | `synthflow/orchestrator` | `synthflow-prod-eu` |
| `dev-use1` | `synthflow`, `synthflow-<name>` | `synthflow-<ns>/orchestrator` | `synthflow-dev-us` |

Hence the near-universal rule selector
`{job=~"orchestrator|synthflow/orchestrator", namespace=~"production|synthflow"}` —
it deliberately covers legacy prod and both dedicated regions at once, and also
matches dev. Alerts scope to prod with `environment: production` /
`cluster=~"synthflow-prod|prod*"`.

## Routing (from `alertmanager-config.yaml`)

- `incident_routing="true"` + `urgency="high"` → incident.io **High**.
- `incident_routing="true"` + `urgency="low"` → incident.io **Low**.
- `slack_channel_name` → the matching Slack receiver (`alerts-metrics-prod`,
  `alerts-metrics-test`, `alerts-e2e-prod`, `alerts-e2e-test`,
  `telephony-alerts`, `on-call-canary`, `dev-ops-alerts` — the default). Every
  Slack card gets Runbook and Dashboard buttons from the same-named annotations.
- `group_by: [alertname, cluster, service, container]`, `group_wait 30s`,
  `group_interval 2m`, `repeat_interval 1h`.
- **Inhibit rule**: a `severity=critical` suppresses a `severity=warning` with
  the same `alertname`/`cluster`/`service`. A silent warning proves nothing.
- PagerDuty routes exist but are commented out; incident.io is live.

## Standard rule skeleton

```yaml
- alert: SomethingBadHappened
  expr: |-
    sum by (cluster, namespace, provider) (
      rate(some_metric_total{job=~"orchestrator|synthflow/orchestrator", namespace=~"production|synthflow"}[5m])
    ) > 0.05
  for: 2m
  labels:
    incident_routing: "true"
    severity: critical          # critical | warning | info
    urgency: high               # high -> incident.io High, low -> Low
    slack_channel_name: alerts-metrics-prod
    environment: production
    component: tts
    cluster: "{{ $labels.cluster }}"
    region: "{{ $labels.region }}"
  annotations:
    description: >
      What broke, in `{{ $labels.namespace }}`, at `{{ printf "%.2f" $value }}`.
      What the customer experiences. What to check. The log line to grep.
    summary: >
      One line for the Slack title.
    runbook_url: "https://github.com/SynthFlowAI/infrastructure-deployers/blob/main/docs/<runbook>.md#<anchor>"
    dashboard_url: "https://grafana.synthflow.dev/a/grafana-metricsdrilldown-app/drilldown?var-ds=aee98cu2bsfeoe&from=now-1h&to=now&timezone=browser&search_txt=some_metric_total"
    owner: "<!subteam^S0A0BE2U1FH>"
    escalation_path_id: "01KGHKHANF0WDWNVEAGZ8QEVQJ"
```

The `description` is what the user pastes back into a session at 2am. Write it
so triage can start from that text alone: impact, then the first three checks,
then the log string.

## Rule PRs

`infrastructure-deployers` overrides the default conventions — check its
`CLAUDE.md` too (cross-region parity: a us-east1 change mirrors in eu-west3 in
the *same* PR).

- Branch: `(INF|ENG)-<number>/<short-description>` — e.g. `INF-1644/add-pr-title-validator`.
- PR title: must match `^(INF|ENG|PRO|TEL|COM|INC|RELEASE)-[0-9]+: description`
  (`.github/workflows/validate-pr-title.yml`). Use `INF-0000:` with no ticket.
- `mimir-rules.yaml` runs `rules diff` on the PR — read its log, it is the
  authoritative preflight. On merge to `main` it runs `rules apply` and
  `alertmanager sync`; there is no ArgoCD sync step for rules.
- Local `bash mimir-helper.sh --target rules diff` (from the `grafana-mimir/`
  dir) needs `mimirtool`, **not installed on this machine** — install it or lean
  on CI.
- `sources/rules/testing/` is the staging ground: a rule there uses
  `incident_routing_testing: "true"` (whose PagerDuty route is commented out, so
  it pages nobody) and `slack_channel_name: alerts-{metrics,e2e}-test`. Land a
  noisy new rule there first, watch it for a few days, then promote to `prod/`
  by flipping those two labels.
