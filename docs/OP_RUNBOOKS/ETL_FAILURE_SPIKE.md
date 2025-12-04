# Runbook — ETL Failure Spike

---

## Purpose

This runbook describes how to triage, mitigate and resolve a sudden spike in `ETL` worker failures (processing
snapshots)
for StarForge. It's intended for `SREs` and `backend engineers` responding to an incident where many `ETL` jobs fail in
a
short window (alerts triggered by the `ETL` failure-rate rule).

---

## Scope

- Rapid triage of spikes in `starforge_etl_snapshots_failed_total`.
- Short-term mitigation to protect production systems.
- Root-cause investigation patterns (parse errors, DB errors, schema/migration regressions, upstream changes).
- Post-incident actions and hardening.

---

## Audience

- `On-call SRE` / `Platform engineer`
- Backend engineer owning `ETL`/worker
- Data team (if backfill or mapping changes implicated)

---

## When to run this

- Alert: `ETL` failure rate > configured threshold (for example `>1% over 5m`) — see `Prometheus` alert
  `StarforgeETLFailureRateHigh`.
- Rapid increase in `etl_errors` rows, repeated worker crashes, or queue failure storm.

---

## Quick summary (first 5 minutes)

1. Acknowledge alert and create incident channel (e.g., `#incident-etl-<ts>`).
2. Find scope: how many snapshots failing, which `error_type`(s), which worker instances.
3. Apply protective mitigations: slow or pause backfills, reduce worker concurrency, pause ingestion if needed.
4. Collect artifacts (recent worker logs, `etl_errors` rows, failing snapshot ids) and attach to incident.
5. Escalate to Backend owner if upstream schema change or deploy suspected.

---

## Contacts / escalation

- Primary on-call SRE: `#starforge-ops` (pager)
- Backend `ETL` owner: Check migration/backfill PR or owner tag
- Data team alias: `data-team@org`
- Engineering lead: `engineering-lead@org`

---

## Triage checklist (first 10 minutes)

- [ ] Acknowledge pager and create incident Slack channel.
- [ ] Determine severity (`P0` if consumer-facing outages, `P1` if degraded).
- [ ] Query `Prometheus` for failure-rate and throughput:
    - failure rate, processed rate, backlog length, worker restarts.
- [ ] Identify most frequent `error_type` in `etl_errors` (example: `PARSE_ERROR`, `DB_ERROR`, `FK_VIOLATION`, `OOM`).
- [ ] Collect recent worker logs (last `30 minutes`) and a small sample of failing snapshot ids.
- [ ] Decide immediate mitigation: throttle backfills or reduce worker concurrency.

---

## Key Prometheus queries (examples)

Use `Prometheus` / `Grafana` console.

- `ETL` failure rate (`5m`):
  ```promql
  sum(rate(starforge_etl_snapshots_failed_total[5m])) / sum(rate(starforge_etl_snapshots_processed_total[5m]))
  ```
- `ETL` processed and failed rates:
  ```promql
  sum(rate(starforge_etl_snapshots_processed_total[5m]))
  sum(rate(starforge_etl_snapshots_failed_total[5m]))
  ```
- Queue depth:
  ```promql
  starforge_queue_jobs_waiting_total
  ```
- Worker restarts:
  ```promql
  increase(kube_pod_container_status_restarts_total{pod=~"etl-worker.*"}[10m])
  ```

---

## Immediate mitigations (choose appropriate)

Pick minimally invasive options first; escalate if needed.

1. Throttle or pause heavy backfills
    - If a backfill job or bulk reprocess is running, pause it immediately.
    - If backfill is queued in `queue_jobs` or `backfill_jobs`, set `status='paused'` or remove pending jobs.

2. Reduce worker concurrency (fast, safe)
    - If workers run in `Kubernetes`:
      ```bash
      kubectl -n starforge scale deployment etl-worker --replicas=0
      # or reduce replicas gradually to 1 then observe
      kubectl -n starforge scale deployment etl-worker --replicas=1
      ```
    - If using env var for concurrency, update and restart a small number of pods.

3. Pause ingestion (if failures originate from recent incoming snapshots)
    - Flip ingestion feature flag to stop new snapshots being created/queued.
    - Inform support: "ingestion paused".

4. Prevent requeues / retries flood
    - Temporarily stop automatic requeueing of failing jobs if queue system supports it, or set `maxAttempts` lower for
      new jobs to avoid storm.

5. Isolate canary workers
    - Start a small isolated worker instance with debug logging to reproduce failure without affecting main pool.

---

## Data collection (essential artifacts)

Collect and attach to incident:

- Top 50 `etl_errors` rows for the last 30–60 minutes:
  ```sql
  SELECT id,snapshot_id,error_type,message,details,created_at
  FROM etl_errors
  WHERE created_at >= now() - interval '60 minutes'
  ORDER BY created_at DESC LIMIT 50;
  ```

- Recent failing snapshot ids and their sizes:
  ```sql
  SELECT id, size_bytes, created_at, source
  FROM hero_snapshots
  WHERE id IN (<sample_failed_ids>);
  ```

- Worker pod logs (last 1000 lines) for affected pods:
  ```bash
  kubectl -n starforge logs <worker_pod> --since=30m
  ```

- Job queue state:
  ```sql
  SELECT * FROM queue_jobs WHERE status IN ('pending','running') ORDER BY run_after LIMIT 200;
  ```

---

## Common failure classes & targeted actions

1) `PARSE_ERROR` or shape mismatch (most frequent after upstream change)
    - Symptoms:
        - Many errors with `PARSE_ERROR` or "unexpected field" in logs.
        - Failures concentrated after a recent fetch or upstream change.
    - Actions:
        - Capture a sample raw payload (`hero_snapshots.raw`) and save to `S3` (quarantine) for developer analysis.
        - Start an isolated worker with updated tolerant parsing (if available).
        - If changes are wide-ranging, pause ingestion and notify product/integration owner to confirm upstream change.
        - Short-term: implement tolerant `ETL` mapping (store unknown fields into `extra` JSONB) and re-run.

2) `DB_ERROR` (connection, deadlock, constraint)
    - Symptoms:
        - Errors like "duplicate key", "deadlock detected", "cannot connect".
    - Actions:
        - Check DB health and connection exhaustion (see [DB_CONNECTION_EXHAUST.md](./DB_CONNECTION_EXHAUST.md)).
        - If DB is overloaded: reduce worker concurrency and scale DB or `pgbouncer`.
        - For constraint errors (FK violation): capture offending snapshot ids and create placeholder catalog rows or
          pause processing and notify Data/Backend team.

3) `FK_VIOLATION` (missing catalog entries)
    - Symptoms:
        - ON CONFLICT/insert failures referencing catalog FK.
    - Actions:
        - Option A: Create placeholder catalog rows with `meta -> { "placeholder": true }` so `ETL` can proceed (
          low-risk).
        - Option B: Pause processing of affected batches; coordinate with Data team to seed catalogs.
        - Record all placeholder IDs to reconcile later.

4) `OOM` / Worker crashes
    - Symptoms:
        - Worker pods restart, `OOMKilled` logs, or memory spike in metrics.
    - Actions:
        - Immediately stop workers; start a debug worker with increased memory or streaming parser.
        - Reduce batch size and enforce streaming parsing for large snapshots.
        - Implement per-snapshot size guard (skip/ quarantine very large payloads and notify owners).

5) Code regression (recent deploy)
    - Symptoms:
        - Failure spike begins right after a deploy.
    - Actions:
        - Roll back the deploy to previous working version if rollback safe.
        - If rollback not possible, fix and patch quickly; consider an emergency patch and redeploy to a fixed worker
          set.
        - Confirm `CI` preflight and add tests to prevent recurrence.

6) Retry storm / exponential backoff misconfiguration
    - Symptoms:
        - Many retries flood system, growing failure counts.
    - Actions:
        - Temporarily disable automatic retries in the queue or reduce attempts/backoff.
        - Throttle re-enqueueing and manually reprocess after fix.

---

## Reproduction & debug (developer steps)

- Reproduce locally using sample failing snapshot(s):
    1. Retrieve raw snapshot:
       ```sql
       SELECT raw::text FROM hero_snapshots WHERE id = '<snapshot_id>';
       ```
    2. Save raw JSON to file and run worker locally in debug mode (stream parser) to surface parse stack traces.
- Attach stack traces and `details` fields from `etl_errors` to PR/issue for engineering to resolve.

---

## Communication (stakeholders & users)

- Notify: Product, Support, Data, and any affected external integrators.
- Customer-facing message (if public):
    - Short message: "We're investigating an issue causing snapshot processing delays and failures. We're pausing
      ingestion and will update in 30 minutes."
- Keep incident channel updated every `15–30 minutes` with status, actions taken, `ETA`.

---

## Recovery & gradual re-enable

1. Fix root cause (deploy patch, seed catalogs, increase DB capacity, or handle upstream change).
2. Start a small canary worker pool (`1–2 pods`) and process a handful of snapshots while monitoring errors.
3. If stable over observation window (e.g., `15–30 minutes`), slowly scale workers back to normal concurrency.
4. Re-enable ingestion (feature flag) and monitor closely for regression.

---

## Post-incident: RCA and hardening

- Produce a postmortem within agreed `SLA` (e.g., `72 hours`) with:
    - Timeline, root cause, detection & mitigation actions, and permanent fixes (change requests).
- Permanent mitigations may include:
    - Add more robust schema/version detection and tolerant parsing to `ETL`.
    - Better catalog seeding and validation checks.
    - Stronger preflight for migrations and backfills.
    - Connection & resource limits for backfill jobs.
    - Enhanced alerts that include sample failing snapshot ids for faster triage.

---

## Useful SQL snippets (for triage)

- Top error types last hour:
  ```sql
  SELECT error_type, count(*) FROM etl_errors WHERE created_at >= now() - interval '1 hour' GROUP BY error_type ORDER BY count DESC;
  ```
- Recent failing snapshot ids:
  ```sql
  SELECT snapshot_id, created_at, error_type FROM etl_errors WHERE created_at >= now() - interval '30 minutes' ORDER BY created_at DESC LIMIT 100;
  ```
- Sample payload for investigation:
  ```sql
  SELECT id, raw::text FROM hero_snapshots WHERE id = '<snapshot_id>';
  ```

---

## Playbook summary (flow)

1. Acknowledge & create incident channel.
2. Triage: identify error type & scope.
3. Mitigate: pause backfills, reduce worker concurrency, or pause ingestion.
4. Collect artifacts (logs, `etl_errors`, sample snapshots).
5. Fix / patch (code, catalog seed, DB scaling).
6. Canary: test fix on isolated worker(s).
7. Gradual re-enable & monitor.
8. Postmortem & implement long-term fixes.

---

## References

- [docs/ETL_AND_WORKER.md](../ETL_AND_WORKER.md) — worker design & upsert patterns
- [docs/OBSERVABILITY.md](../OBSERVABILITY.md) — metrics and dashboards
- [docs/MIGRATIONS.md](../MIGRATIONS.md) — migration preflight & safe patterns
- [docs/OP_RUNBOOKS/BACKFILL.md](./BACKFILL.md) — backfill runbook
- [docs/OP_RUNBOOKS/DB_CONNECTION_EXHAUST.md](./DB_CONNECTION_EXHAUST.md) — DB connection exhaustion runbook

---
