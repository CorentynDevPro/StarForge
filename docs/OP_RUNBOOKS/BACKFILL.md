# Runbook — Backfill Historical Snapshots (BACKFILL.md)

## Purpose

This runbook explains how to safely run a backfill of historical `hero_snapshots` into the normalized schema
(`user_troops`, `user_pets`, `user_artifacts`, `user_profile_summary`, etc.). It covers planning, preflight checks, safe
execution (staging → canary → production), verification, throttling recommendations and troubleshooting.

---

## Audience

- `SRE` / `DevOps` running backfill jobs
- `Backend` / `Data engineers` implementing backfill jobs
- `QA engineers` validating results
- On-call engineers responding to backfill incidents

---

## When to use

- Populate normalized tables from archived or historical `hero_snapshots`.
- Rebuild derived tables after schema or `ETL` mapping changes.
- Resume or resume a previously interrupted backfill.

---

## High-level strategy

1. Use the same `ETL` worker codepath for backfill as for real-time processing to guarantee parity.
2. Run backfill in small, resumable batches; track progress in a `backfill_jobs` / `queue_jobs` table.
3. Run backfill on an isolated worker pool (separate from real-time workers) and throttle to protect the primary DB.
4. Validate results via sample parity checks and automated queries; keep raw snapshots immutable for replay.

---

## Prerequisites & assumptions

- You have a recent DB backup (required before production backfills).
- `hero_snapshots` contains raw JSONB payloads to process.
- `ETL` worker code is tested and supports idempotent reprocessing.
- A `backfill_jobs` / `queue_jobs` mechanism exists to schedule and track jobs (
  see [docs/MIGRATIONS.md](../MIGRATIONS.md)).
- Observability: `Prometheus` metrics and logs are configured for `ETL`, DB, and workers.

---

## Preflight checklist (must pass)

- [ ] Backup taken and backup ID recorded.
- [ ] Approvals obtained (`Engineering + SRE`; product if user-impacting).
- [ ] Run dry-run in staging with representative sample payloads.
- [ ] Verify worker code handles large snapshots with streaming parsing.
- [ ] Confirm catalog seed coverage (`troop_catalog`, `pet_catalog`) or fallback behavior (placeholders).
- [ ] Confirm capacity limits: DB max connections, `CPU`, `IO`, and estimated snapshot throughput.
- [ ] Confirm monitoring dashboards and alerts are active (`ETL` failure rate, queue depth, DB connections).
- [ ] Communication: inform support and stakeholders of planned windows and contact points.

---

## Planning & capacity estimation

### Estimate runtime:

- Measure average processing time per snapshot (`t_avg`) from staging dry-run (seconds).
- Total snapshots (N).
- Desired wall time (`T_target`) and concurrency (C) estimate:
    - `T_estimate = (N * t_avg) / C`
    - Pick C so DB connection usage and IO remain under safe thresholds.

### Example:

- `t_avg = 12s`, `N = 10,000 snapshots`, `C = 10` → `T_estimate ≈ (10_000 * 12) / 10 = 12,000s ≈ 3.3 hours`.

### Batch sizing

- Use per-user or per-snapshot batches; recommended batch sizes: `50–500 snapshots` per DB transaction depending on
  payload size and DB load.
- For very large snapshots (`2–3MB`) prefer smaller batches (`10–50`).

---

## Execution modes

- Dry-run (staging): run backfill on a representative sample and validate outputs.
- Canary (production small slice): run backfill for a small time range or subset of users (e.g., last 7 days or
  whitelisted namecodes).
- Gradual production: increase coverage and concurrency in controlled steps with monitoring gates.
- One-shot (not recommended): only for tiny datasets or pre-approved maintenance windows.

---

## How to schedule a backfill (examples)

> Note: adjust commands to your orchestration (Kubernetes, systemd, or runbooks).

A) Enqueue via `queue_jobs` (DB-backed job table)

- Insert a backfill-range job row:

```sql
INSERT INTO queue_jobs (id, type, payload, priority, attempts, max_attempts, status, run_after, created_at, updated_at)
VALUES (gen_random_uuid(),
        'backfill_range',
        jsonb_build_object(
                'from_created_at', '2024-01-01T00:00:00Z',
                'to_created_at', '2024-06-01T00:00:00Z',
                'batch_size', 250,
                'owner', 'data-team'
        )::jsonb,
        0,
        0,
        5,
        'pending',
        now(),
        now(),
        now());
```

- Workers configured to process `backfill_range` should pick jobs and create internal `backfill_jobs` checkpoints.

B) Use admin API (if implemented)

```http
POST /api/v1/admin/backfill
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "from": "2024-01-01T00:00:00Z",
  "to": "2024-06-01T00:00:00Z",
  "batch_size": 250,
  "concurrency": 8,
  "owner": "data-team"
}
```

---

## Dry-run (staging) procedure

1. Select sample snapshots (small, medium, large, malformed cases). Example SQL to pick samples:

```sql
-- 10 random snapshots across size buckets
WITH sizes AS (SELECT id, size_bytes, ntile(3) OVER (ORDER BY size_bytes) AS bucket
               FROM hero_snapshots
               WHERE created_at < now())
SELECT id
FROM sizes
WHERE bucket = 1
ORDER BY random() LIMIT 3
UNION ALL
SELECT id
FROM sizes
WHERE bucket = 2
ORDER BY random() LIMIT 3
UNION ALL
SELECT id
FROM sizes
WHERE bucket = 3
ORDER BY random() LIMIT 4;
```

2. Start a staging worker cluster with the same code and configuration you will use in production (but reduced
   concurrency).
3. Enqueue these sample snapshot ids as backfill jobs (or trigger reprocess) and observe:
    - Memory usage, processing time, and DB operations.
    - ETL emits `snapshot_processed` events and no unhandled exceptions.

---

## Canary procedure (production small slice)

1. Pick a narrow range (e.g., 1 day or 500 users) or whitelisted namecodes.
2. Run the backfill job for the slice with conservative concurrency (C = 1–4).
3. Monitor for `30–60 minutes`:
    - `ETL` failure rate (should be near zero).
    - DB `CPU/IO` and connection count (no spike above safe thresholds).
    - Application latencies and errors.

---

## Production rollout (gradual)

1. Start with a small concurrency and slice.
2. If gate checks pass after observation window, scale up:
    - Increase number of concurrent workers or batch size incrementally.
    - Expand the date range or number of users processed.
3. Continue until full coverage achieved.

---

## Progress tracking & resume

- Maintain a `backfill_jobs` table with fields:
    - job_id, owner, from_ts, to_ts, batch_size, concurrency, status (pending|running|paused|failed|done),
      processed_count, error_count, last_checkpoint, started_at, finished_at.
- Use `processed_count` and `last_checkpoint` to resume from last successful snapshot on failure.

Sample SQL to inspect progress:

```sql
SELECT job_id, status, processed_count, error_count, started_at, finished_at
FROM backfill_jobs
ORDER BY started_at DESC LIMIT 50;
```

---

## Validation & verification (sample queries)

Run automated checks during and after backfill to validate correctness.

1. Processed counts:

```sql
SELECT COUNT(*)
FROM hero_snapshots
WHERE processed_at IS NOT NULL
  AND processed_at >= now() - interval '1 day';
```

2. Etl errors (investigate top error types):

```sql
SELECT error_type, count(*)
FROM etl_errors
WHERE created_at >= now() - interval '1 hour'
GROUP BY error_type
ORDER BY count DESC;
```

3. Spot-check data parity for example snapshot:

- Extract a small piece of truth from raw JSON and compare to normalized table.

```sql
-- Raw: retrieve troop entries for a snapshot (example JSON path may vary)
SELECT raw - > 'ProfileData' - > 'Troops' AS troops
FROM hero_snapshots
WHERE id = '<snapshot_id>';

-- Normalized: compare total troop rows for the user
SELECT count(*)
FROM user_troops
WHERE user_id = (SELECT user_id FROM hero_snapshots WHERE id = '<snapshot_id>');
```

4. Uniqueness checks:

```sql
-- Ensure no duplicate user_troops per (user_id, troop_id)
SELECT user_id, troop_id, COUNT(*)
FROM user_troops
GROUP BY user_id, troop_id
HAVING COUNT(*) > 1 LIMIT 50;
```

5. Summary generation validation:

```sql
-- Ensure profile_summary exists for sampled users
SELECT u.id, ups.user_id IS NOT NULL AS has_summary
FROM users u
         LEFT JOIN user_profile_summary ups ON u.id = ups.user_id
WHERE u.id IN (<sample_user_ids>);
```

---

## Monitoring & alerts (what to watch)

- `ETL` metrics:
    - `starforge_etl_snapshots_processed_total` (throughput)
    - `starforge_etl_snapshots_failed_total` (failures)
    - `starforge_etl_processing_duration_seconds` (latency)
- Queue metrics: queue depth and job age
- DB metrics: active connections, long-running transactions, `CPU`, `IOPS`
- Worker metrics: memory usage, restarts
- Alerts:
    - Failure rate > `1%` sustained → page on-call.
    - Queue depth growing unexpectedly → investigate consumer capacity.
    - DB connections > `80%` of max → pause backfill and scale DB or reduce concurrency.

---

## Throttling & safety knobs

- Reduce concurrency (worker count) if DB connections climb.
- Reduce batch size if individual transactions are slow or if FK violations appear.
- Pause the backfill job(s) by updating `backfill_jobs.status = 'paused'` or removing pending queue entries.
- Temporarily scale down real-time workers to free DB capacity (do this carefully to avoid service disruption).

---

## Common failure modes & remediation

- Worker `OOM` / restarts
    - Action: reduce batch size, process large snapshots separately, increase worker memory for dedicated backfill pool.
- FK violations (missing catalog rows)
    - Action: either create safe placeholder rows in catalogs (`troop_catalog`, `pet_catalog`) or capture failing
      snapshot ids for manual review; do not delete other processed data.
- DB connection exhaustion
    - Action: pause backfill, scale DB or pgbouncer, reduce per-worker pool size, resume with lower concurrency.
- High `etl_errors` rate (`PARSE_ERROR`)
    - Action: capture sample failing snapshot raw JSON to `docs/examples/quarantine` or S3 for developer analysis; pause
      automated reprocessing until fix.
- Long-running index builds or blocking operations
    - Action: monitor `pg_stat_activity` and cancel offending queries if safe; consider scheduling heavy DDL for
      maintenance windows.

---

## Rollback & recovery

Backfill itself is idempotent; use these steps if unacceptable data changes happen:

1. Pause backfill (stop workers).
2. If corruption is localized and fixable by reprocessing (mapping bug),:
    - Fix `ETL` code.
    - Re-enqueue affected snapshot ids or run targeted reprocessing.
3. If destructive corruption occurred (rare), restore DB from pre-backfill backup:
    - Follow [DB_RESTORE.md](./DB_RESTORE.md) runbook.
    - Re-run controlled backfill with corrected process.
4. Document actions and notify stakeholders.

---

## Post-backfill tasks

- Run full validation suite (sampling and aggregates) and record reports/artifacts.
- Mark `backfill_jobs` as `done` and record `finished_at`.
- Incrementally remove any temporary placeholder catalog rows if created and update catalog with authoritative data.
- Update dashboards to reflect production read usage from the normalized tables.
- Archive logs and push final reports into PR or release artifacts.

---

## Artifacts & audit

Store the following artifacts for auditing and troubleshooting:

- Backup snapshot ID used before backfill.
- Backfill job records (`backfill_jobs` rows).
- `ETL` logs for the backfill period (worker logs).
- A report with sample verification queries and their results.
- Links to any `S3` objects for quarantined snapshots.

---

## Contacts & escalation

- Primary `SRE` / on-call: (replace with team alias) `#starforge-ops` / pager
- Backend owner(s): check migration/backfill PR
- Data owner: `data-team` (as recorded in job payload)
- Security contact: (security officer alias)

---

## Appendix: helpful SQL snippets

```SQL
-- Pause future job processing by marking pending backfill jobs paused
UPDATE backfill_jobs
SET status = 'paused'
WHERE status = 'pending';

-- Resume a paused backfill job
UPDATE backfill_jobs
SET status = 'running'
WHERE job_id = '<job_id>'
  AND status = 'paused';

-- Find snapshots not processed (candidate for backfill)
SELECT id, created_at, size_bytes
FROM hero_snapshots
WHERE processed_at IS NULL
ORDER BY created_at ASC LIMIT 1000;

-- Get top ETL error types in last 24h
SELECT error_type, COUNT(*)
FROM etl_errors
WHERE created_at >= now() - interval '24 hours'
GROUP BY error_type
ORDER BY COUNT DESC;

-- Check long-running transactions
SELECT pid, usename, now() - xact_start AS duration, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > interval '1 minute'
ORDER BY duration DESC LIMIT 20;
```

---

## Related documents

- [docs/MIGRATIONS.md](../MIGRATIONS.md) — migration conventions and safe patterns
- [docs/ETL_AND_WORKER.md](../ETL_AND_WORKER.md) — ETL worker contract and upsert patterns
- [docs/DB_MODEL.md](../DB_MODEL.md) — canonical schema and table definitions
- [docs/OP_RUNBOOKS/APPLY_MIGRATIONS.md](./APPLY_MIGRATIONS.md) — apply migrations runbook
- `scripts/migrate-preflight.sh` — preflight helper

---
