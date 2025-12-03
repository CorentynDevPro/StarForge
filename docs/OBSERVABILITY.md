# Observability — StarForge

> Version: 0.1  
> Date: 2025-12-03

---

This document specifies the observability strategy, metrics, logging, tracing, dashboards and alerting for StarForge.
It is intended for engineers and `SREs` implementing and operating the `ETL/Worker`, `API`, `Bot` and `admin services`
described in the [docs/PRD.md](./PRD.md), [docs/ETL_AND_WORKER.md](./ETL_AND_WORKER.md)
and [docs/DB_MODEL.md](./DB_MODEL.md).

## Goals

- Provide actionable, low-noise monitoring for production and staging.
- Enable fast incident detection (`ETL` failure spikes, queue backlog, DB exhaustion).
- Provide structured logs and traces to speed root-cause analysis.
- Ensure observability respects privacy (`PII` redaction) and cost constraints.

---

## Audience

- `Backend engineers` (instrumentation)
- `SRE / DevOps` (dashboards, alerting, retention)
- `QA / Data engineers` (validate metrics, dashboards)
- `On-call responders` (runbooks & alerts)

---

## Contents

1. [Observability architecture overview](#1-observability-architecture-overview)
2. [Metrics (what to collect, names, labels)](#2-metrics--names-types-labels-and-meaning)
3. [Prometheus configuration & scraping guidance](#3-prometheus-configuration--scraping-guidance)
4. [Grafana dashboards (suggested panels & queries)](#4-grafana-dashboards-templates--panels)
5. [Alerting (rules, thresholds, playbooks)](#5-alerting--rules-thresholds--playbooks)
6. [Logging (structure, fields, samples, retention)](#6-logging--structure-fields-scrubbing--retention)
7. [Tracing (OpenTelemetry, spans, sampling, propagation)](#7-tracing--opentelemetry-spans-propagation-and-sampling)
8. [Sentry / Error tracking (configuration & scrubbing)](#8-sentry--error-tracking)
9. [Correlation & metadata (request_id, trace_id, snapshot_id)](#9-correlation--metadata--request_id-trace_id-snapshot_id)
10. [Security & PII handling in telemetry](#10-security--pii-handling-in-telemetry)
11. [Retention & storage policies](#11-retention--storage-policies)
12. [Testing observability in CI](#12-testing-observability-in-ci)
13. [Operational runbooks & playbook snippets](#13-operational-runbooks--playbooks-summary--links)
14. [Implementation checklist / example snippets](#14-implementation-checklist--example-snippets)
15. [References & next steps](#15-references--next-steps)

---

## 1. Observability architecture overview

### Components

- Instrumented services: `api-service`, `etl-worker`, `discord-bot`, `admin-ui`
- Metrics: `Prometheus` (scrape or push via exporters)
- Dashboards: `Grafana` (dashboards per service & cross-service)
- Traces: `OpenTelemetry` collector -> tracing backend (`Tempo`/`Jaeger`/`Tempo+Loki`)
- Error tracking: `Sentry` (exceptions, structured events) with scrubbing
- Logs: Structured JSON logs shipped to central log store (`Loki`/`ELK`/`Datadog`/`Logflare`)
- Alerts: `Prometheus Alertmanager` -> pager (`PagerDuty`) and `Slack` channels
- Long-term storage: Archive raw metrics/aggregates to cost-effective storage if required

---

### Design notes

- Favor pull-based metrics (`Prometheus` scrape) for services with stable endpoints; use pushgateway for ephemeral jobs
  when necessary.
- Ensure all instrumented services expose `/metrics` and `/health`.
- Propagate correlation ids (`X-Request-Id`) and trace context across requests and jobs to link logs, metrics and
  traces.

---

## 2. Metrics — names, types, labels, and meaning

### Naming conventions

- Prefix: `starforge_` for all app metrics.
- Suffix conventions:
    - `_total` for counters
    - `_seconds` / `_duration_seconds` for durations
    - `_gauge` for gauges
- Use `snake_case`.
- Avoid cardinality explosion in labels (limit label values and cardinality).

---

### Label guidance

- Common labels: `env`, `service`, `instance`, `job_type`, `snapshot_source`, `queue_name`, `error_type`
- Use `user_id` or `namecode` sparingly (avoid high-cardinality); prefer hashed or bucketed labels for analytics.

---

### Core metric categories and recommended metrics

#### A. ETL / Worker metrics (prefix: `starforge_etl_`)

- Counters
    - `starforge_etl_snapshots_received_total{env,service,job_type, snapshot_source}` — incremented when `API` enqueues
      a snapshot job.
    - `starforge_etl_snapshots_processed_total{env,service,result}` — result ∈ {success,failed,partial}.
    - `starforge_etl_snapshots_failed_total{env,service,error_type}` — categorize errors (`PARSE_ERROR`, `DB_ERROR`,
      `FK_VIOLATION`, `OOM`).
    - `starforge_etl_entity_upserts_total{env,service,entity}` — counts per entity (`users`, `user_troops`,
      `user_pets`, ...).
- Histograms / Summaries
    - `starforge_etl_processing_duration_seconds_bucket{le,env,service}` — processing latency histogram per snapshot.
    - `starforge_etl_upsert_batch_size` — batch sizes distribution used for multi-row upserts.
- Gauges
    - `starforge_etl_jobs_in_progress{env,service}` — currently processing jobs.
    - `starforge_etl_last_processed_timestamp{env,service}` — unix timestamp of last processed snapshot.

#### B. API metrics (prefix: `starforge_api_`)

- Counters
    - `starforge_api_requests_total{env,service,endpoint,method,status}`
- Histograms
    - `starforge_api_request_duration_seconds{env,service,endpoint}`
- Gauges
    - `starforge_api_inflight_requests{env,service}`

#### C. Queue & Redis metrics

- If using `BullMQ` / `Redis`:
    - `starforge_queue_jobs_waiting_total{env,queue_name}` — count of waiting jobs (pullable from `Redis`)
    - `starforge_queue_jobs_active_total{env,queue_name}`
    - `starforge_queue_jobs_failed_total{env,queue_name}`

#### D. Database metrics (collect from exporter)

- `pg_up` / `pg_connections` / `pg_active_queries` / `pg_longest_tx_seconds` / `pg_lock_count` (from `pg_exporter`)
- `starforge_db_tx_duration_seconds` (application-level)

#### E. Infrastructure metrics

- CPU, memory, disk, network per instance (`node exporter`)
- Pod-level metrics if `Kubernetes` (`kube-state-metrics`)

#### F. Business metrics (higher-level)

- `starforge_players_active_30d` — unique active players in 30 days (calculated/ingested)
- `starforge_bot_commands_total{command}`

### Suggested metric dimensions (labels)

- `env` (production/staging/local)
- `service` (api, etl-worker, bot)
- `instance` (host or pod name)
- `job_type` (process_snapshot, backfill_range)
- `snapshot_source` (fetch_by_namecode, login, cli_upload)
- `entity` (user_troops, user_pets, ...)

### Metric examples (Prometheus exposition style)

```text
# HELP starforge_etl_snapshots_processed_total Number of snapshots processed
# TYPE starforge_etl_snapshots_processed_total counter
starforge_etl_snapshots_processed_total{env="production",service="etl-worker",result="success"} 12345
```

---

## 3. Prometheus configuration & scraping guidance

### Scrape targets

- Each service exposes `/metrics` (`Prometheus` format) on an ephemeral port (e.g., 9091).
- For `Kubernetes`: use `ServiceMonitor` (`Prometheus` Operator) per service.

---

### Example `scrape_config` (prometheus.yml)

```yaml
scrape_configs:
  - job_name: 'starforge-api'
    metrics_path: /metrics
    static_configs:
      - targets: [ 'api-1.example.com:9091','api-2.example.com:9091' ]
    relabel_configs:
      - source_labels: [ '__address__' ]
        target_label: 'instance'

  - job_name: 'starforge-etl'
    metrics_path: /metrics
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [ __meta_kubernetes_pod_label_app ]
        regex: 'etl-worker'
        action: keep
```

---

### Scrape intervals

- Default: `scrape_interval: 15s` for application metrics.
- For high-volume metrics or high-cardinality series, consider `30s` to reduce load.

---

### Relabeling & security

- Add `relabel_configs` to attach `env` and `service` labels from pod metadata.
- Secure `Prometheus` scrapes with `mTLS` or allowlist internal networks.

---

### Pushgateway

- Use only for short-lived ephemeral jobs if necessary; prefer direct scraping and persistent worker processes.

---

## 4. Grafana dashboards (templates & panels)

### Build dashboards per audience:

- `ETL` / `Worker` dashboard (`SRE`, `backend`)
- `API` dashboard (latency, errors)
- DB dashboard (connections, slow queries)
- Bot dashboard (commands, success rate)
- Overall system health dashboard (top-level)

---

### Recommended ETL dashboard panels

- Snapshot throughput: `rate(starforge_etl_snapshots_processed_total[1m])` (timeseries)
- Processing latency:`histogram_quantile(0.95, sum(rate(starforge_etl_processing_duration_seconds_bucket[5m])) by (le))`
- Failure rate:
  `sum(rate(starforge_etl_snapshots_failed_total[5m])) / sum(rate(starforge_etl_snapshots_processed_total[5m]))`
- Queue depth: `starforge_queue_jobs_waiting_total`
- Jobs in progress: `starforge_etl_jobs_in_progress`
- Top error types pie: `sum by (error_type) (rate(starforge_etl_snapshots_failed_total[5m]))`
- DB connections and longest transactions (from `pg_exporter`)
- Worker restarts / `OOMs` count (kubernetes pod restarts)

---

### Sample `Grafana` panel queries (`PromQL`)

- `p95` processing time:

```promql
histogram_quantile(0.95, sum(rate(starforge_etl_processing_duration_seconds_bucket[5m])) by (le))
```

- `ETL` failure rate (5m):

```promql
(sum(rate(starforge_etl_snapshots_failed_total[5m])) by (service)) /
(sum(rate(starforge_etl_snapshots_processed_total[5m])) by (service))
```

- Queue depth per queue:

```promql
starforge_queue_jobs_waiting_total{env="production"}
```

### Dashboard tips

- Add annotations for deployments & migrations to correlate spikes.
- Show per-instance panels for troubleshooting, plus cluster-level aggregates.
- Provide drilldown links to logs (`Loki`/`ELK`) and traces (`Tempo`/`Jaeger`) with `snapshot_id` or `trace_id`.

---

## 5. Alerting — rules, thresholds & playbooks

### Design principles

- Keep alerts actionable and low-noise.
- Avoid alerting on single transient blips—use multi-window conditions or require sustained violations.
- Each alert should include: description, severity, likely causes, quick actions, runbook link.

### Suggested alert severities mapping

- `P0` (page): system outage / critical data-loss / DB down / `ETL` failure rate severe
- `P1` (notify): service degradation or resource saturation
- `P2` (ticket): non-urgent but actionable issues

### Alert examples (`Prometheus Alertmanager` rules format snippets)

#### A. `ETL` failure rate high (`P0`)

```yaml
- alert: StarforgeETLFailureRateHigh
  expr: |
    (
      sum(rate(starforge_etl_snapshots_failed_total[5m]))
      /
      sum(rate(starforge_etl_snapshots_processed_total[5m]))
    ) > 0.01
  for: 5m
  labels:
    severity: page
  annotations:
    summary: "ETL failure rate > 1% (5m)"
    description: "ETL failure rate is above 1% for the last 5 minutes. Check etl_errors table and recent logs. Runbook: docs/OP_RUNBOOKS/INCIDENT_RESPONSE.md"
```

#### B. Queue depth high (`P0`)

```yaml
- alert: StarforgeQueueDepthHigh
  expr: starforge_queue_jobs_waiting_total > 500
  for: 10m
  labels:
    severity: page
  annotations:
    summary: "ETL queue backlog > 500"
    description: "ETL queue backlog is high; scale workers or investigate job failure storms. Check Redis and worker heartbeats."
```

#### C. DB connection exhaustion (`P0`)

```yaml
- alert: PostgresConnectionsHigh
  expr: pg_stat_activity_count > (pg_settings_max_connections * 0.9)
  for: 2m
  labels:
    severity: page
  annotations:
    summary: "DB connections > 90%"
    description: "Database connections exceed 90% of max. Reduce worker concurrency or scale DB. See runbook DB_RESTORE.md / SCALING_UP.md."
```

#### D. Processing latency regression (`P1`)

```yaml
- alert: ETLProcessingLatencyHigh
  expr: histogram_quantile(0.95, sum(rate(starforge_etl_processing_duration_seconds_bucket[5m])) by (le)) > 30
  for: 10m
  labels:
    severity: paged (or notify)
  annotations:
    summary: "ETL p95 processing time > 30s"
```

#### E. Worker restarts (`P1`)

```yaml
- alert: WorkerPodRestartsHigh
  expr: increase(kube_pod_container_status_restarts_total{job="kube-state-metrics",pod=~"etl-worker.*"}[10m]) > 3
  for: 0m
  labels:
    severity: page
  annotations:
    summary: "ETL worker restarting frequently"
```

### Alert content: always include

- How to check: queries to run, which dashboards to view.
- Quick actions: pause backfill, scale workers, check DB connections, examine `etl_errors` for sample snapshot ids.
- Contact / escalations: on-call rotation or team.

### Playbook snippets (on alert)

- `ETL` failure rate high:
    1. Check `Grafana ETL` dashboard and `etl_errors`.
    2. Identify top error types and `snapshot_ids`.
    3. If parse error is widespread, pause ingestion, create task for update, and escalate to engineering lead.
    4. If DB errors, reduce worker concurrency immediately.

---

## 6. Logging — structure, fields, scrubbing & retention

### 6.1 Logging format & mandatory fields

- Use structured JSON logs. Each log MUST include:
    - `timestamp` (ISO 8601)
    - `service` (api | etl-worker | bot | admin-ui)
    - `env` (production | staging)
    - `level` (DEBUG | INFO | WARN | ERROR)
    - `message` (short human readable)
    - `request_id` or `job_id`
    - `trace_id` (optional, for trace linking)
    - `snapshot_id` (when relevant)
    - `worker_instance` or `pod`
    - `module` (component)
    - `details` (structured object for contextual fields)

#### Example log (info)

```json
{
  "timestamp": "2025-12-03T10:12:34Z",
  "service": "etl-worker",
  "env": "production",
  "level": "info",
  "message": "Snapshot processed",
  "snapshot_id": "a2f1c1b2-...-e4f9",
  "job_id": "bull-uuid-1234",
  "worker_instance": "worker-3",
  "duration_ms": 5432,
  "entities_upserted": {
    "users": 1,
    "user_troops": 120
  },
  "trace_id": "..."
}
```

#### Example log (error)

```json
{
  "timestamp": "2025-12-03T10:13:01Z",
  "service": "etl-worker",
  "env": "production",
  "level": "error",
  "message": "Failed to upsert user_troops batch",
  "snapshot_id": "...",
  "job_id": "...",
  "error_type": "DB_ERROR",
  "error_message": "duplicate key value violates unique constraint \"ux_user_troops_user_troop\"",
  "details": {
    "batch_size": 200
  }
}
```

### 6.2 Redaction & `PII` scrubbing

- Implement a scrubbing pipeline *before* logs leave the app:
    - Mask values for keys: `password`, `token`, `session`, `auth`, `api_key`, `access_token`.
    - Replace with `"[REDACTED]"` or hashed placeholder.
- For raw snapshots, log only `snapshot_id` and `s3_path` (if archived), not the raw JSON.
- Sentry events must be scrubbed similarly.

### 6.3 Log levels & sampling

- Use DEBUG in staging; in production use INFO for success events and WARN/ERROR for issues.
- Sample high-volume DEBUG logs (e.g., per-troop operations) or rate-limit them server-side (`1% sample`).
- For error logs related to a unique snapshot, keep full detailed logs for initial investigation, and then sample/purge
  as needed.

### 6.4 Log shipping & retention

- Ship logs to centralized log store with indexable fields: `service`, `env`, `snapshot_id`, `job_id`, `trace_id`.
- Retention policy (recommended baseline):
    - Hot (searchable) logs: 30 days
    - Warm (aggregated) logs: 90 days
    - Cold archive (compressed): 365+ days (for compliance needs)
- For `PII`-containing logs (rare), keep only as long as legally required and ensure encryption at rest.

---

## 7. Tracing — OpenTelemetry, spans, propagation, and sampling

### 7.1 Goals

- Provide end-to-end traces across `API` ingest -> queue -> worker -> DB upserts.
- Correlate traces with logs and metrics for fast `RCA`.

### 7.2 Instrumentation strategy

- Use `OpenTelemetry SDK` for `Node.js` (`api-service`, `etl-worker`, `bot`).
- Instrument:
    - HTTP servers/clients (incoming `API` requests and outgoing requests)
    - Queue interactions (enqueue / dequeue / job processing) — use semantic conventions to create spans `queue.enqueue`
      and `queue.process`
    - DB calls (`pg`) — create spans for queries/batches
    - Heavy processing spans (`parse_snapshot`, `upsert_user_troops_batch`)

### 7.3 Trace context propagation

- Propagate `traceparent` headers for HTTP requests.
- For queue jobs include `trace_id` and `parent_span` in job metadata to continue trace in worker.
- Use `X-Request-Id` as fallback correlation id.

### 7.4 Spans & recommended hierarchy (example)

- `http.server` (API: `POST /internal/snapshots`)
    - `queue.enqueue` (enqueue job)
        - job stored in `Redis` (span)
- `queue.worker.process` (worker dequeues)
    - `claim_snapshot` (DB update)
    - `parse_snapshot` (stream parsing)
        - `map_entity:users`
            - `db.upsert.users`
        - `map_entity:user_troops` (batched)
            - `db.upsert.user_troops.batch`
    - `commit_snapshot` (mark processed)

### 7.5 Sampling & retention

- Sample rate: initial default `10%` for production traces (adjust based on cost and utility).
- Always sample traces for errors (Sentry integration) or for admin-triggered runs (e.g., reprocess).
- Retention:
    - Full traces: 7 days
    - Sampled traces: 30 days

### 7.6 Collector & backend

- Use an `OpenTelemetry Collector` to receive spans and export to backend (`Tempo`/`Jaeger`/`Lightstep`).
- Collector responsibilities: batching, sampling, drop rules, and forwarding to `APM`.

---

## 8. Sentry / Error tracking

### 8.1 What to capture

- Unhandled exceptions, errors that result in failed jobs, parsing exceptions, DB errors flagged by worker
- Attach minimal context: `snapshot_id`, `job_id`, `worker_instance`, `env`, `user_id` (if non-`PII`), `trace_id`

### 8.2 Scrubbing & PII protection

- Configure `Sentry` before-send hooks to remove or mask `PII` from event payloads.
- Do not send full raw `raw` snapshot content to `Sentry` — instead include `snapshot_id` and `s3_path`.

### 8.3 Rate limiting & sampling

- Configure `Sentry` sampling to avoid being overwhelmed by noise (sample non-critical errors).
- For critical jobs or newly introduced code, temporarily increase sampling to get better coverage.

### 8.4 Alerts & integration

- Use `Sentry` alert rules to create issues in ticketing systems for high-severity errors.
- Integrate `Sentry` with Slack for immediate visibility on new critical errors.

---

## 9. Correlation & metadata — request_id, trace_id, snapshot_id

### 9.1 Correlation ids

- `X-Request-Id`: set by client or `API` gateway; if absent, generate `UUID` at `API` ingress and return to client in
  response.
- Include `request_id` in logs and metrics where possible.

### 9.2 Trace ids

- Standard `OpenTelemetry` `trace_id` propagated through HTTP and queue.
- Ensure worker reads `trace_id` from job payload and continues trace.

### 9.3 Snapshot id

- Include `snapshot_id` label in relevant metrics, logs and traces to pivot troubleshooting to the raw payload.
- Avoid using `snapshot_id` as a high-cardinality `Prometheus` label in cardinal series; use it in logs and as trace
  attribute.

---

## 10. Security & PII handling in telemetry

### 10.1 Policy highlights

- Telemetry must not leak secrets or raw credentials.
- Keep list of sensitive keys (`password`, `token`, `access_token`, `session`, `auth`) and scrub them in telemetry
  pipelines.
- Use hashed identifiers if you must include user identifiers in metrics (e.g., hash(namecode) -> low-card label
  buckets).

### 10.2 Scrubbing implementation points

- Application-level: sanitize before logging/attaching to traces/`Sentry`.
- Collector-level: run additional redaction rules in `OpenTelemetry Collector`.
- Logging pipeline-level: final redaction step in log shipper (`Loki`/`Logstash`).

### 10.3 DSR & telemetry

- When a `Data Subject Request` (`DSR`) requires deletion of personal data:
    - Search logs and provide redaction or proof of removal as per policy (logs may be immutable; keep a record of
      attempted purge and apply legal process).
    - For archived traces / logs in cold storage, follow legal guidance.

---

## 11. Retention & storage policies

### Recommended baseline (configurable by org policy)

- Metrics (`Prometheus`):
    - Raw samples: 30 days
    - Aggregated rollups: 365 days
- Traces:
    - Full fidelity: 7 days
    - Sampled: 30 days
- Logs:
    - Hot searchable: 30 days
    - Warm/archived compressed: 365 days
- `Sentry` / errors: 90 days (or provider plan)

### Cost controls

- Use metric relabeling to drop or reduce cardinality of high-cardinality labels in `Prometheus`.
- Use trace sampling and error-only retention to control trace storage.
- Use log lifecycle rules to move older logs to cheaper storage tiers.

---

## 12. Testing observability in CI

### 12.1 Unit & integration asserts

- Unit tests should assert that metrics are emitted for key code paths (use fake `Prometheus` registry).
- Integration tests should:
    - Spin up services, call endpoints that produce metrics, and query `/metrics` to assert presence.
    - Insert a sample snapshot and assert worker emits `starforge_etl_snapshots_processed_total`.

### 12.2 Performance and load tests

- Simulate realistic load in staging and validate dashboards (`ETL` throughput, `p95` processing, DB connections).
- Validate alert thresholds in a controlled manner (e.g., create synthetic failures to trigger alerts in staging).

### 12.3 Health checks

- Include `curl /health` checks in `CI` smoke tests for service liveness and DB connectivity.

---

## 13. Operational runbooks & playbooks (summary + links)

### Each alert should point to a runbook with step-by-step instructions. Key runbooks:

- `ETL` failure spike — [docs/OP_RUNBOOKS/ETL_FAILURE_SPIKE.md](./OP_RUNBOOKS/ETL_FAILURE_SPIKE.md)
- Queue backlog — [docs/OP_RUNBOOKS/QUEUE_BACKLOG.md](./OP_RUNBOOKS/QUEUE_BACKLOG.md)
- DB connection exhaustion — [docs/OP_RUNBOOKS/DB_CONNECTION_EXHAUST.md](./OP_RUNBOOKS/DB_CONNECTION_EXHAUST.md)
- `Worker OOM` / Crash — [docs/OP_RUNBOOKS/WORKER_OOM.md](./OP_RUNBOOKS/WORKER_OOM.md)
- Migration rollback — [docs/OP_RUNBOOKS/MIGRATION_ROLLBACK.md](./OP_RUNBOOKS/MIGRATION_ROLLBACK.md)
- Secrets compromise — [docs/OP_RUNBOOKS/SECRET_COMPROMISE.md](./OP_RUNBOOKS/SECRET_COMPROMISE.md)

### Include runbook essentials in each alert:

- Quick triage steps
- Targeted queries and dashboards
- Suggested mitigation (scale down workers, pause backfills, flip feature flag)
- Escalation path and contacts

### Example quick-playbook for ETL failure spike (short)

1. Check Grafana ETL dashboard and `etl_errors` table for top `error_type` (PARSE vs DB).
2. If DB errors: scale down worker concurrency and check DB metrics (connections, locks).
3. If parse errors: sample failing `snapshot_ids` (select last 10 from `etl_errors`) and save to `docs/examples` for dev
   debugging.
4. Pause ingestion if necessary and notify product & engineering.
5. Re-enable ingestion and monitor.

---

## 14. Implementation checklist / example snippets

### Checklist for instrumenting a service

- [ ] Expose `/metrics` in `Prometheus` format (use `prom-client` / `prom-client-exporter`)
- [ ] Expose `/health` and readiness probes
- [ ] Instrument core paths: `API` ingest, queue enqueue, job start/end
- [ ] Emit metrics with appropriate labels (`env`, `service`, `job_type`)
- [ ] Add structured logging with required fields (`request_id`, `trace_id`)
- [ ] Integrate `OpenTelemetry` tracing and propagate context into job payload
- [ ] Sanitize and scrub `PII` before sending logs or events to `Sentry`
- [ ] Add unit tests asserting metrics emitted
- [ ] Add end-to-end tests validating /metrics counters after processing a sample snapshot

### Prometheus client (Node) snippet example

```js
const client = require( 'prom-client' );
const Registry = client.Registry;
const register = new Registry();

const snapshotsProcessed = new client.Counter( {
  name: 'starforge_etl_snapshots_processed_total',
  help: 'Snapshots processed',
  labelNames: [ 'env', 'service', 'result' ],
} );
register.registerMetric( snapshotsProcessed );

// expose metrics
app.get( '/metrics', async ( req, res ) => {
  res.set( 'Content-Type', register.contentType );
  res.end( await register.metrics() );
} );
```

### OpenTelemetry (Node) basic initialization (example)

```js
const { NodeTracerProvider } = require( '@opentelemetry/sdk-trace-node' );
const { registerInstrumentations } = require( '@opentelemetry/instrumentation' );
const { JaegerExporter } = require( '@opentelemetry/exporter-jaeger' );
const provider = new NodeTracerProvider();
const exporter = new JaegerExporter( { serviceName: 'starforge-etl' } );
provider.addSpanProcessor( new SimpleSpanProcessor( exporter ) );
provider.register();
// instrument HTTP, pg, etc.
registerInstrumentations( { tracerProvider: provider, instrumentations: [ ... ] } );
```

---

## 15. References & next steps

- [docs/ETL_AND_WORKER.md](./ETL_AND_WORKER.md) — `ETL` worker contract (instrumentation targets referenced throughout
  this doc)
- [docs/DB_MODEL.md](./DB_MODEL.md) — canonical schema (for DB-local metrics)
- [docs/MIGRATIONS.md](./MIGRATIONS.md) — migration conventions (alert to add annotations for migrations)
- Prometheus docs: https://prometheus.io/docs/
- OpenTelemetry: https://opentelemetry.io/
- Grafana best practices: https://grafana.com/docs/grafana/latest/

---
