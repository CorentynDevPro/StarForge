# Runbook — Postgres Connection Exhaustion

---

## Purpose

Immediate, actionable steps to diagnose and mitigate a `Postgres` (or managed `Postgres`) connection exhaustion incident
for StarForge. This runbook is for on-call `SREs` and `backend engineers` to restore service quickly and safely, then
remediate root causes.

---

## Scope

- Symptoms covered: new connections failing, application errors like "too many connections", high `pg_stat_activity`
  connection counts, `pgbouncer`/`connection-pool` saturation, or managed provider connection limits reached.
- Assumes metrics & logging per [docs/OBSERVABILITY.md](../OBSERVABILITY.md) are available and that you have access to
  DB admin credentials
  and the ability to scale/pause workers.

---

## Emergency summary (short)

1. Acknowledge the alert and notify stakeholders (#starforge-ops).
2. Quickly reduce incoming load (pause ingestion and scale down workers).
3. Identify & cancel long-running queries; prefer cancel over terminate.
4. If safe, increase connection resources (`pgbouncer` scaling or DB scaling) while preparing a long-term fix.
5. Run postmortem and implement permanent controls (connection pooler, limits, timeouts).

---

## Contacts / escalation

- Primary on-call `SRE`: #starforge-ops (`Pager`)
- Backend owner(s): from recent PR/migration
- Engineering lead / DB admin: `<engineering-lead@org>`
- Security contact: `security@org` (if suspicious activity)

---

## Triage checklist (first 5 minutes)

- [ ] Acknowledge `PagerDuty` / alert.
- [ ] Set a dedicated incident channel (e.g. `#incident-dbconn-<ts>)`.
- [ ] Find current symptom: application errors, `502/503`, DB-side rejects, or elevated queue length.
- [ ] If possible, temporarily block new writes / `API` ingestion (feature flag) and lower worker concurrency.

---

## Important safety note

Always avoid destructive actions you don't understand. Prefer conservative actions (pause, cancel, scale) and keep a
clear log of commands run. If unsure about a connection/user, consult the backend owner before terminating connections.

---

## Quick diagnostics (commands)

Run these from a bastion / `CI` / workstation with `psql` access (replace `DATABASE_URL` or connection params).

1) Check DB max connections and current counts

```sql
-- Show configured max connections
SHOW
max_connections;

-- Current active connection count
SELECT count(*) AS total_connections
FROM pg_stat_activity;

-- Breakdown by state
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state;

-- Connections by application_name / user / client_addr
SELECT application_name, usename, client_addr, count(*) AS c
FROM pg_stat_activity
GROUP BY application_name, usename, client_addr
ORDER BY c DESC LIMIT 50;
```

2) Find long-running queries / transactions

```sql
-- Longest running queries
SELECT pid, usename, application_name, client_addr, now() - query_start AS duration, state, query
FROM pg_stat_activity
WHERE state <> 'idle'
  AND query_start IS NOT NULL
ORDER BY duration DESC LIMIT 50;

-- Long transactions that may hold locks
SELECT pid, usename, now() - xact_start AS tx_duration, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY tx_duration DESC LIMIT 50;
```

3) Check locks and waiting queries

```sql
-- Waiting queries
SELECT pid, wait_event_type, wait_event, state, query_start, query
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
ORDER BY query_start;

-- Inspect pg_locks for blocking relationships
SELECT blocked_locks.pid         AS blocked_pid,
       blocked_activity.usename  AS blocked_user,
       blocking_locks.pid        AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocking_activity.query   AS blocking_query
FROM pg_locks blocked_locks
         JOIN pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
         JOIN pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT
FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT
FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT
FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT
FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT
FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT
FROM blocked_locks.transactionid
    JOIN pg_stat_activity blocking_activity
ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;
```

---

## Immediate mitigation steps (safe, prioritized)

Follow in order until connections recover.

1) Pause ingestion / reduce incoming traffic (very high impact but safe)
    - Flip feature flag that accepts new snapshots (`API`) to OFF, or configure `API` to return `503` for ingestion
      endpoints.
    - Announce to support: "ingestion paused, attempting mitigation".

2) Scale down background workers (free DB connections)
    - If using `Kubernetes`:
      ```bash
      # reduce worker replicas quickly (example)
      kubectl -n starforge scale deployment etl-worker --replicas=0
      kubectl -n starforge scale deployment api --replicas=<safe-count>  # careful if API needs DB
      ```
    - If non-`K8s`: stop or pause worker processes/containers, or set worker concurrency env var to `0/1` then restart.

3) If using `pgbouncer` or a pooler, check / scale pooler
    - For `pgbouncer`: check stats and connection usage; if `pgbouncer` itself is saturated, increase instances or pool
      size.
    - If using managed pooling (`Supabase`, `RDS proxy`), consider scaling that layer.

4) Cancel long-running queries (non-destructive)
    - Prefer `pg_cancel_backend(pid)` first to politely cancel the query:
      ```sql
      SELECT pg_cancel_backend(<pid>);
      ```
    - Only use `pg_terminate_backend(pid)` if cancel fails or the backend is stuck in an unresponsive state:
      ```sql
      SELECT pg_terminate_backend(<pid>);
      ```
    - Before terminating, confirm the `pid` is not a replication or monitoring connection (`usename`/system user).

5) Reduce application DB pool sizes (short-term)
    - Update worker/app environment to smaller `PG_POOL_MAX` and restart a small number of instances.
    - Example: if workers use `PG_POOL=20`, reduce to `2–4` and restart.

6) Re-enable ingestion carefully once headroom exists
    - Gradually bring workers back online and observe connections; do not immediately restore full concurrency.

---

## If you must increase capacity

- For managed DB: request a temporary vertical scale (larger instance) or increase connection limit if provider supports
  it.
- Add or scale `pgbouncer`/`proxy` to front the DB.
- These are medium-impact and require change control: document actions and monitor costs.

---

## Investigations & deeper diagnostics (post-stabilize)

Once service is restored to a stable state:

1) Correlate with metrics
    - Check `Prometheus` for connection spikes:
        - `pg_connections`, `pg_active_queries`, `starforge_etl_jobs_in_progress`, `starforge_queue_jobs_waiting_total`
    - Look at timeline to find the spike origin (deploy, backfill, large import, `DDoS`).

2) Identify offending clients
    - From the `pg_stat_activity` breakdown, find `application_name`, user or host contributing the most connections.
    - Common culprits: misconfigured worker pool size, runaway backfill, `CI` job, monitoring tool misconfigured, bulk
      `ETL`.

3) Inspect recent deployments & migrations
    - Was a migration or deploy pushed around the time of the spike? See `GitHub Actions` run and PR link.
    - A broken change may cause connection leaks or extremely slow queries.

4) Examine slow queries & missing indexes
    - Use `pg_stat_statements` (if available) to find expensive queries and top query-by-total-time.
    - Consider adding or rebuilding indexes or rewriting queries to reduce execution time.

5) Check `pgbouncer` / pooler settings
    - Pooling mode (session / transaction / statement), `max_client_conn`, `default_pool_size` and `reserve_pool_size`.
    - Use transaction pooling if the app is compatible (no session-level temp tables).

---

## Permanent remediation (next actions)

- Implement or tune a connection pooler (`pgbouncer`) in front of `Postgres`; use transaction pooling if application
  permits.
- Enforce sensible per-worker connection pool sizes and cap total connections via orchestration.
- Add and enforce statement and transaction timeouts:
    - `SET statement_timeout = '30s';` in application session or via DB role.
- Harden `ETL`:
    - Make workers use smaller per-process pools (`PG_POOL_MAX=2–4`) and limit concurrency.
    - Add resource-aware parsing (streaming) to avoid long transactions.
- Add soft quotas and backpressure:
    - Throttle ingestion at `API` level when queue depth grows.
    - Implement admission control for backfill jobs.
- Alerting & dashboards:
    - Add alert: `pg_connections > 0.8 * max_connections` for `2m`.
    - Add alert on `pg_stat_activity` long-running tx count > threshold.
- `CI` / deploy guard:
    - Include migration and backfill preflight tests and throttling defaults with any code that touches DB connection
      behavior.

---

## Useful SQL snippets for remediation & postmortem

```SQL
-- Show max connections and current usage
SELECT name, setting
FROM pg_settings
WHERE name IN ('max_connections', 'superuser_reserved_connections');

-- Top users by connection
SELECT usename, count(*)
FROM pg_stat_activity
GROUP BY usename
ORDER BY count DESC;

-- Top application names
SELECT application_name, count(*)
FROM pg_stat_activity
GROUP BY application_name
ORDER BY count DESC;

-- Identify connections from a given host
SELECT pid, usename, application_name, client_addr, state, backend_start, query
FROM pg_stat_activity
WHERE client_addr = '1.2.3.4';

-- Cancel a query
SELECT pg_cancel_backend(<pid>);

-- Terminate a backend (last resort)
SELECT pg_terminate_backend(<pid>);
```

---

## Playbook for a common scenario (worker storm)

1. Observation: queue depth spikes and DB connections hit max.
2. Actions:
    - Pause enqueueing from API (if addable) OR reduce `API` acceptance.
    - Scale down worker replicas to zero (or to 1) to immediately drain new DB connections.
    - In `Kubernetes`:
      ```bash
      kubectl -n starforge scale deployment etl-worker --replicas=0
      ```
    - Watch `pg_stat_activity` drop; cancel any long-running queries if necessary.
3. Recovery:
    - Fix root cause (e.g., buggy worker job loop).
    - Increase worker rollout gradually:
        - set `replicas=1`, observe.
        - if safe, scale to normal count.

---

## Post-incident: RCA & follow-up

1. Document timeline: when the spike started, mitigation steps, who approved actions.
2. Root cause analysis:
    - Identify the exact code path / job / deploy that caused the spike.
    - Capture query texts and stack traces if available.
3. Remediation tasks (track as tickets):
    - Add/adjust connection pooling and default pool sizes.
    - Add `statement_timeout` and `idle_in_transaction_session_timeout`.
    - Harden workers to backoff on DB errors and avoid retry storms.
    - Improve monitoring and add guardrails (circuit-breakers, ingestion throttles).
4. Validate fix in staging and schedule a controlled rollout.

---

## Appendix: Helpful commands & references

- Inspect active connections:
  ```sql
  SELECT pid, usename, application_name, client_addr, state, now()-query_start AS duration, query
  FROM pg_stat_activity ORDER BY duration DESC LIMIT 50;
  ```

- Cancel & terminate:
  ```sql
  SELECT pg_cancel_backend(12345);  -- polite
  SELECT pg_terminate_backend(12345); -- kills session
  ```

- Check max connections:
  ```sql
  SHOW max_connections;
  SHOW superuser_reserved_connections;
  ```

- Check `pgbouncer` (if present):
  ```sql
  # Connect to pgbouncer and run:
  SHOW POOLS;
  SHOW CLIENTS;
  SHOW SERVERS;
  SHOW STATS;
  ```

- `Kubernetes` example to reduce DB client pods:
  ```bash
  kubectl -n starforge scale deployment etl-worker --replicas=0
  ```

---

## Related docs

- [docs/OBSERVABILITY.md](../OBSERVABILITY.md) — metrics and alert guidance
- [docs/MIGRATIONS.md](../MIGRATIONS.md) — migration preflight (ensure migrations don't create connection spikes)
- [docs/ETL_AND_WORKER.md](../ETL_AND_WORKER.md) — worker concurrency and connection budgeting
- [docs/OP_RUNBOOKS/APPLY_MIGRATIONS.md](./APPLY_MIGRATIONS.md) — safe migration runbook

---
