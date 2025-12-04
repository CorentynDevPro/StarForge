# Runbook — Queue Backlog

---

## Purpose

Procedures to triage, mitigate and resolve sudden or sustained queue backlogs for StarForge. This covers `Redis`/
`BullMQ`
or DB-backed queues (`queue_jobs`), causes, quick mitigations, recovery steps, and long-term preventative measures so
the
system returns to steady-state with minimal customer impact.

---

## Audience

- `SRE` / `Platform engineers`
- `Backend engineers` owning queue consumers (`ETL workers`)
- `On-call responder` / `incident commander`
- `Data engineers` operating backfills

---

## Scope

- Backlog detection and triage for job queues used by `ETL` and background processing (`BullMQ` + `Redis` and DB
  `queue_jobs`).
- Applying short-term mitigations (throttles, scale changes, dead-lettering).
- Safe recovery and reprocessing guidance.
- Prevention and operational improvements.

---

## When to run this

- Alert: queue depth above threshold or long-running pending jobs (see metrics
  in [docs/OBSERVABILITY.md](../OBSERVABILITY.md)).
- Observed processing lag: processed rate << enqueue rate for sustained period.
- User-visible degradation (slow profiles, admin actions blocked).

---

## Quick summary (first 5 minutes)

1. Acknowledge pager and create incident channel (e.g. `#incident-queue-backlog-<ts>`).
2. Snapshot queue state (depth, oldest job age, types).
3. Determine root cause category: producer storm, consumer outage, slow processing, retry storms, poison messages, DB
   problems.
4. Apply conservative mitigations: stop new producers, reduce retry flood, scale consumers cautiously.
5. Collect logs, job samples and queue metrics for postmortem.

---

## Key signals to check (immediately)

- Queue depth / backlog:
    - `starforge_queue_jobs_waiting_total` or BullMQ waiting length (`Redis` keys).
- Job age:
    - Oldest job `run_after` or `BullMQ` job timestamp.
- Processing throughput:
    - `starforge_etl_snapshots_processed_total` (rate) vs `starforge_etl_snapshots_received_total`
- Failure rates:
    - `starforge_etl_snapshots_failed_total` and `etl_errors` table
- Consumer health:
    - Worker pod restarts, `CPU`, memory, DB connections
- DB health:
    - Connection exhaustion or long transactions (see [DB_CONNECTION_EXHAUST.md](./DB_CONNECTION_EXHAUST.md))

---

## Triage checklist (first 10 minutes)

- [ ] Acknowledge alert and create incident channel.
- [ ] Snapshot metrics from Prometheus/Grafana for the last `30–60 minutes`.
- [ ] Run quick queue inspection (`Redis`/`BullMQ` or DB):
    - For `BullMQ`: list waiting/active/failed job counts.
    - For DB `queue_jobs`: `SELECT status, COUNT(*) GROUP BY status`.
- [ ] Identify top job types causing backlog (e.g., `process_snapshot`, `backfill_range`).
- [ ] Identify oldest pending job (timestamp) and sample its payload.
- [ ] Check consumer logs (worker pods) for errors or `OOMs`.
- [ ] Decide immediate mitigation (throttle producers / scale consumers / pause backfills / dead-letter).

---

## Commands & queries (copy/paste)

```SQL
-- DB-backed queue (queue_jobs) snapshot
SELECT status, type, COUNT(*) AS cnt
FROM queue_jobs
GROUP BY status, type
ORDER BY cnt DESC;

-- Oldest pending jobs
SELECT id, type, payload, run_after, created_at
FROM queue_jobs
WHERE status = 'pending'
ORDER BY run_after ASC, created_at ASC LIMIT 50;

-- Failed jobs recent
SELECT id, type, attempts, last_error, updated_at
FROM queue_jobs
WHERE status = 'failed'
ORDER BY updated_at DESC LIMIT 100;
-- Top waiting jobs by type (BullMQ/Redis: use router/monitoring or Bull Board)
#
If you have redis-cli and bullmq key naming, inspect counts or use the queue UI.
```

---

## Causes and targeted actions

1) Consumer outage or insufficient consumers
    - Symptoms:
        - Consumer pods crashed or scaled to zero
        - `jobs processed` drops to 0 while `jobs enqueued` high
    - Actions:
        - Check and restart consumer workers:
            - Kubernetes:
              `kubectl -n starforge get deploy etl-worker`
              `kubectl -n starforge rollout restart deployment/etl-worker`
        - If pods are in `CrashLoopBackOff`, inspect logs and fix root cause (`OOM`, exception).
        - If healthy but overloaded, scale up consumers gradually (see safe scaling below).

2) Producer storm (sudden high enqueue rate)
    - Symptoms:
        - Enqueue rate >> processing rate; queues fill quickly
        - Often correlates with a campaign, bug, or external integration spike
    - Actions:
        - Throttle or pause producers:
            - `API`: return `429`/`503` for ingestion endpoints or flip ingestion flag.
            - Backfill: pause backfill jobs in `backfill_jobs` or `queue_jobs`.
        - Inform product/support of degraded ingestion.

3) Slow processing (heavy jobs or DB slowness)
    - Symptoms:
        - Consumers healthy but processing time per job increased
        - DB slow queries, `IO` saturation
    - Actions:
        - Temporarily scale consumers to increase parallelism only if DB can handle it.
        - Reduce per-worker concurrency and batch sizes to lower DB pressure.
        - Investigate and fix slow queries / missing indexes (`pg_stat_statements`).
        - If index builds are running, they may slow queries—avoid additional load.

4) Retry storms / exponential retries
    - Symptoms:
        - Jobs repeatedly requeued and failing, causing backlog growth
    - Actions:
        - Temporarily disable automatic retries or reduce `maxAttempts` for new jobs.
        - Move failing jobs to a dead-letter queue (`DLQ`) for manual inspection rather than retrying.
        - Inspect `etl_errors` for root failure and fix cause.

5) Poison messages (single job repeatedly failing and blocking throughput)
    - Symptoms:
        - One job failing repeatedly despite retries, may consume worker cycles
    - Actions:
        - Identify offending job id(s) and move them to `DLQ`:
            - For `BullMQ`: move job to failed manually or use `job.moveToFailed()` with reason.
            - For DB queue: update `queue_jobs` status to 'failed' or 'quarantined' and record details.
        - Quarantine payloads for developers to debug.

6) DB connection exhaustion or locks
    - Symptoms:
        - Consumers complain about DB connection failures or deadlocks
        - High `pg_stat_activity` or blocked queries
    - Actions:
        - Follow [DB_CONNECTION_EXHAUST.md](./DB_CONNECTION_EXHAUST.md): reduce concurrency, pause consumers, scale
          pooler/DB
        - Avoid scaling consumers up until DB healthy.

---

## Immediate mitigations (ordered, safe)

- Pause new producers (ingestion `API`/backfill enqueueing).
- Pause non-critical queues (`backfill_range`) and keep only critical job types running.
- Move failing/poison jobs to `DLQ` to stop thrashing.
- Scale consumers up only after verifying DB capacity; otherwise scale down to a safe level.
- Apply temporary rate limiting at `API` gateway for clients causing storm.

---

## How to move jobs to a Dead-Letter Queue (DLQ)

Goal: prevent repeated retries from blocking throughput and preserve payload for later debugging.

A) DB-backed `queue_jobs`

- Mark as failed/quarantined with reason and distinct queue type:
  ```sql
  UPDATE queue_jobs
  SET status = 'failed', last_error = jsonb_build_object('reason','quarantined for manual review','original_status',status), updated_at = now()
  WHERE id = '<job_id>';
  -- optionally insert into queue_jobs_dlq table with full payload and metadata
  INSERT INTO queue_jobs_dlq (id, original_job_id, type, payload, reason, created_at)
  VALUES (gen_random_uuid(), '<job_id>', '<type>', '<payload>'::jsonb, 'quarantined due to fail', now());
  ```

B) `BullMQ` (`Redis`)

- Use `Bull UI` (`Bull Board`) to find and move a job to failed or use worker `API`:
    - `await job.moveToFailed(new Error('quarantined'), true);`
- Alternatively, remove job and persist payload externally for later replay.

---

## Safe scaling guidance

- Don’t exceed DB connection budgets when scaling consumers. Example formula:
    - Max DB connections = DB capacity (from provider) - headroom (e.g. `20`)
    - Per-consumer pool size = configured `PG_POOL_MAX`
    - Max concurrent c`onsumers = floor( (Max DB connections - headroom) / PG_POOL_MAX )`
- Scale in small steps and observe:
    - Step 1: increase replicas by `1–2`, wait `1–2 minutes`, measure queue drain and DB metrics
    - Step 2: increase further if healthy
- If scaling causes DB pressure, revert and instead reduce per-worker concurrency and use more workers with smaller
  pools.

---

## Reprocessing strategy (safe recovery)

1. Stabilize system (mitigations applied).
2. Move failing/poison jobs to `DLQ` and fix root cause.
3. Create a controlled reprocessing plan:
    - Re-enqueue `DLQ` jobs to a dedicated "reprocess" queue with limited concurrency.
    - Use canary reprocessing: `10–50` jobs first, validate, then increase.
    - For backfills, use small batch sizes and capacity-aware windowing (see [BACKFILL.md](./BACKFILL.md)).

---

## Long-term remediation & prevention

- Enforce producer rate-limits at `API` level to avoid storms.
- Use short-lived concurrency-controlled worker pools and small per-worker DB pools.
- Add `DLQ` automation and observability (ageing `DLQ` alerts).
- Improve job idempotency and ensure payloads are safe to retry.
- Add circuit breakers:
    - If failure rate for a job type exceeds threshold, automatically pause enqueues for that type and notify owners.
- Create admin tools:
    - Web UI to inspect queues, move jobs to `DLQ`, replay jobs safely.
- Improve metrics and alerts:
    - Alert on job age > threshold, failed job ratio, and `DLQ` growth.
- Harden `ETL` processing to fail fast on unrecoverable errors and move payload to `DLQ`.

---

## Monitoring queries & alerts to add

- Queue depth per type:
    - `starforge_queue_jobs_waiting_total{type!=""}` → alert if `> X` for `5m`.
- Oldest job age:
    - Gauge or query to alert if oldest pending job > threshold (e.g., `30m` for real-time, `24h` for backfills).
- `DLQ` growth:
    - `starforge_queue_jobs_dlq_total` → alert if growing unexpectedly.
- Failed rate:
    - `rate(starforge_etl_snapshots_failed_total[5m]) / rate(starforge_etl_snapshots_processed_total[5m]) > 0.01` →
      page.

---

## Post-incident: RCA & follow-up actions

- Produce postmortem with:
    - Timeline, root cause, mitigation actions, reprocessing plan, and lessons learned.
- Track remediation tasks:
    - Rate-limiting, DLQ improvements, consumer autoscaling and DB capacity planning, job schema improvements.
- Run a game-day exercise simulating queue storms and recovery.
- Update runbooks (this file) with any newly discovered steps or commands.

---

## Playbook — condensed operational checklist

- [ ] Acknowledge and open incident channel.
- [ ] Snapshot queue state and collect metrics.
- [ ] Identify cause (consumer, producer, DB, retries, poison).
- [ ] Pause producers / backfills if needed.
- [ ] Move offending jobs to `DLQ` / quarantine payloads.
- [ ] Scale consumers safely if DB allows; otherwise tune worker concurrency.
- [ ] Reprocess `DLQ` in a controlled canary pattern.
- [ ] Monitor for stabilization and verify functional health.
- [ ] Postmortem and implement long-term fixes.

---

## Useful snippets & examples

```SQL
-- Pause enqueues at API level (example flag)
UPDATE feature_flags
SET data = jsonb_set(data, '{ingest_paused}', 'true'::jsonb)
WHERE name = 'ingest_control';

-- Move job to DLQ (DB example)
INSERT INTO queue_jobs_dlq (id, original_job_id, type, payload, reason, created_at)
SELECT gen_random_uuid(), id, type, payload, 'quarantined', now()
FROM queue_jobs
WHERE id = '<job_id>';
UPDATE queue_jobs
SET status     = 'failed',
    updated_at = now()
WHERE id = '<job_id>';

-- Inspect oldest pending snapshot jobs
SELECT id, payload ->>'snapshot_id' AS snapshot_id, run_after, created_at
FROM queue_jobs
WHERE type = 'process_snapshot' AND status = 'pending'
ORDER BY run_after ASC LIMIT 50;
```

---

## Escalation & contacts

- On-call `SRE`: #starforge-ops (pager)
- `ETL`/`Worker` owner(s): owner listed in job payload or PR

References
----------

- [docs/ETL_AND_WORKER.md](../ETL_AND_WORKER.md) — worker design, claim semantics and upsert patterns
- [docs/BACKFILL.md](./BACKFILL.md) — controlled backfill strategy
- [docs/OBSERVABILITY.md](../OBSERVABILITY.md) — metrics and alert definitions
- [docs/OP_RUNBOOKS/DB_CONNECTION_EXHAUST.md](./DB_CONNECTION_EXHAUST.md) — DB connection exhaustion runbook
- [docs/OP_RUNBOOKS/ETL_FAILURE_SPIKE.md](./ETL_FAILURE_SPIKE.md) — `ETL` failure triage

---
