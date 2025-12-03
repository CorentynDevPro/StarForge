# ETL & Worker — StarForge

> Version: 0.1  
> Date: 2025-12-02

---

## Table of contents

1. [Executive summary](#1-executive-summary)
2. [Scope & audience](#2-scope--audience)
3. [High-level architecture](#3-high-level-architecture)
4. [Input contract (hero_snapshots row & job payload)](#4-input-contract-hero_snapshots-row--job-payload)
5. [Queue design & job payload schema](#5-queue-design--job-payload-schema)
6. [Worker claim semantics & concurrency model](#6-worker-claim-semantics--concurrency-model)
7. [Processing pipeline — end-to-end](#7-processing-pipeline--end-to-end)
8. [Upsert patterns & SQL examples](#8-upsert-patterns--sql-examples)
9. [Error handling, retry policy & poison messages](#9-error-handling-retry-policy--poison-messages)
10. [Monitoring & metrics (what to emit)](#10-monitoring--metrics-what-to-emit)
11. [Logging, tracing & structured events](#11-logging-tracing--structured-events)
12. [Backfill, bulk processing & rate-control](#12-backfill-bulk-processing--rate-control)
13. [Admin APIs & operational endpoints](#13-admin-apis--operational-endpoints)
14. [Testing strategy (unit / integration / e2e / perf)](#14-testing-strategy-unit--integration--e2e--perf)
15. [Security & privacy controls](#15-security--privacy-controls)
16. [Common incidents & runbook actions](#16-common-incidents--runbook-actions)
17. [Configuration / example env](#17-configuration--example-env)
18. [Appendix](#18-appendix)
    - Example job payloads
    - Example TypeScript worker skeleton (BullMQ + pg)
    - Helpful SQL queries
    - References

---

## 1. Executive summary

This document defines the `ETL` (Extract-Transform-Load) worker design for StarForge. It specifies:

- the contract between ingestion (`hero_snapshots`) and worker jobs,
- queue and retry semantics,
- idempotent upsert patterns to normalize `raw player JSON` into relational tables,
- monitoring and logging conventions,
- operational runbooks for common incidents,
- testing & migration considerations.

> Goal: provide a deterministic, observable, and safe pipeline that can process large (2–3MB) `JSON snapshots`, scale
> horizontally, and be re-run (idempotent) for repair/backfill.

---

## 2. Scope & audience

**Primary audience:**

- Backend engineers implementing worker & queue code
- DevOps/SRE running workers and scaling infrastructure
- QA engineers writing integration & performance tests
- Data engineers validating normalized outputs

**Scope:**

- Processing snapshots stored in `hero_snapshots` (JSONB).
- Upserting normalized tables (`users`, `user_troops`, `user_pets`, `user_artifacts`, `user_teams`, `guilds`,
  `user_profile_summary`, `etl_errors`).
- Supporting reprocessing, retries, and safe backfills.
- Instrumentation requirements for observability.

**Out of scope (for this doc):**

- UI or bot behavior (only how they observe `ETL` status).
- Detailed catalog seeding (see [docs/DB_MODEL.md](./DB_MODEL.md)).
- `Non-ETL` background jobs (e.g., exports) beyond brief notes.

---

## 3. High-level architecture

### Textual diagram (components):

- Client (CLI / Bot / API) -> API Service (ingest endpoint)
    - writes `hero_snapshots` (raw JSONB)
    - enqueues job to `Redis/BullMQ` with `snapshot_id`
      -> Redis / Queue
      -> `ETL Worker Pool` (n instances)
        - claim snapshot (atomic DB update)
        - stream parse `JSONB`
        - per-entity upserts to `Postgres`
        - mark snapshot processed / write `etl_errors`
        - emit metrics to `Prometheus`, errors to `Sentry`
          -> `Postgres` (normalized tables + `hero_snapshots`)
          -> `S3` (archive older snapshots) [optional]

### Key constraints & goals:

- _Idempotency:_ reprocessing same snapshot must not duplicate rows.
- _Memory-safety:_ do not load full large JSON into heap; stream arrays.
- _Observability:_ job metrics, `ETL` duration, error categories.
- _Safety:_ per-entity transactions to avoid monolithic long transactions that block DB.

---

## 4. Input contract (hero_snapshots row & job payload)

### 4.1 hero_snapshots canonical row (DB contract)

- _Table:_ `hero_snapshots`
- _Important columns (read-only contract for workers):_
    - `id` UUID (snapshot id)
    - `user_id` UUID (optional)
    - `namecode` VARCHAR(64) (optional)
    - `source` VARCHAR (fetch_by_namecode | login | cli_upload | ui_fetch)
    - `raw` JSONB (full get_hero_profile payload)
    - `size_bytes` INTEGER
    - `content_hash` VARCHAR (SHA256 hex)
    - `processing` BOOLEAN
    - `processing_started_at` TIMESTAMPTZ
    - `processed_at` TIMESTAMPTZ
    - `error_count` INTEGER
    - `last_error` JSONB
    - `created_at` TIMESTAMPTZ

Workers MUST treat `raw` as authoritative payload for that job.

### 4.2 Job payload (queue message)

- Minimal job payload should be small and stable:

```json
{
  "snapshot_id": "uuid",
  "correlation_id": "uuid",
  // request trace id, optional
  "enqueue_ts": "2025-12-02T12:00:00Z"
}
```

- Avoid embedding the full JSON in the job; workers read `raw` from DB by `snapshot_id`.
- Job `TTL`: worker should drop jobs older than configurable threshold (e.g., 30d) unless reprocessing older snapshots
  is explicitly allowed.

### 4.3 Input validation rules

- Worker must validate:
    - `raw` is JSON and contains expected top-level keys (e.g., `NameCode`, `ProfileData`) before attempting mapping.
    - `size_bytes` matches `octet_length(raw::text)` (optional sanity check).
- If `raw` is malformed JSON: record `ETL` error, increment `error_count` and stop; do not set `processed_at`.

---

## 5. Queue design & job payload schema

### 5.1 Choice: Redis + BullMQ (recommended)

- Advantages:
    - job retries
    - delayed jobs
    - job priorities
    - concurrency control
    - job inspection

- Use a short job payload referencing `snapshot_id` and correlation metadata only.

### 5.2 Queue naming & priorities

- queue: `etl:snapshots` (default)
- priority levels:
    - **high** (interactive, e.g., single-player fetch): `priority = 10`
    - **normal** (background ingestion): `priority = 0`
    - **low** (bulk backfill): `priority = -10`
- Use separate queues for reprocess/backfill jobs (e.g., `etl:backfill`) to throttle separately.

### 5.3 Retry & backoff strategy (BullMQ config)

- Attempts: `maxAttempts = configurable` (default 5)
- Backoff: exponential with `jitter`: `backoff = Math.min(2^attempt * baseMs, maxMs)` with jitter
    - `baseMs = 1000ms, maxMs = 5 minutes`
- On transient DB errors: let queue retry.
- On permanent errors (parse error, invalid shape): mark as failed and do not retry automatically (see section 9).

### 5.4 Poison message handling

- If a job hits maxAttempts: move to "failed" and record `ETL` error row with `permanent: true`. Admins can re-enqueue
  after manual fix.

### 5.5 Job visibility & admin tools

- Persist job metadata to `queue_jobs` table optionally for auditing (`job_id`, `snapshot_id`, `type`, `status`).
- Build admin UI to list recent jobs, failures, and reprocess actions.

---

## 6. Worker claim semantics & concurrency model

### 6.1 Atomic claim (DB-first)

- Use DB to claim a snapshot to avoid race conditions across worker instances:

```sql
WITH claimed AS (
UPDATE hero_snapshots
SET processing            = true,
    processing_started_at = now()
WHERE id = $1
  AND (processing = false OR processing IS NULL) RETURNING id
)
SELECT id
FROM claimed;
```

- If no rows returned: someone else claimed it, skip job.

### 6.2 Reasoning

- Use DB atomic update so job coordination remains consistent even if the queue loses a lease.
- Avoid advisory locks unless necessary; if you need cross-DB locking for multi-step workflows, use
  `pg_advisory_lock(key)` carefully and always release locks.

### 6.3 Worker concurrency & DB connection budgeting

- Configure worker concurrency so total DB connections (`workers * per-worker connections + app connections) < DB max`
  connections minus headroom for `pgbouncer`.
- Suggested defaults:
    - per-worker concurrency: 4 (tune by instance size)
    - pg pool max per worker: 2–4
- Use pooled DB client (pg.Pool) and reuse connections.

### 6.4 Claim TTL & stuck job detection

- If a worker crashes after claiming, a snapshot may remain with `processing=true`. Use a watchdog that detects
  snapshots
  with `processing=true` and `processing_started_at` older than `claim_ttl` (e.g., 30 minutes) and:
    - either mark `processing=false` and increment `error_count` OR
    - reassign via admin requeue after human review.

---

## 7. Processing pipeline — end-to-end

This section describes the sequential steps the worker executes for each snapshot. Each step has failure handling notes.

### 7.1 High-level steps

1. Dequeue job (`snapshot_id`).
2. Attempt atomic DB claim (see 6.1).
3. Read `hero_snapshots.raw JSONB`.
4. Validate schema & compute a lightweight fingerprint if needed.
5. Parse using streaming parser for large arrays (troops, pets, artifacts).
6. Per-entity transformations & upserts in recommended order:
    - `users` / `heroes`
    - `guilds` & `guild_members`
    - `user_troops` (batch upserts)
    - `user_pets` (batch upserts)
    - `user_artifacts` (batch upserts)
    - `user_teams` & `team_troops`
    - `user_profile_summary` (calculate denormalized summary)
7. Mark snapshot processed (`processed_at=now()`, `processing=false`) and write metrics.
8. If errors occurred:
    - Log error, write `etl_errors` row(s), update `hero_snapshots.last_error` and `error_count`.
    - Respect retry semantics (for transient errors allow queue retry).
9. Emit telemetry (events, metrics).

### 7.2 Streaming & memory-safe parsing

- Use `stream-json` or equivalent to iterate over large arrays in `raw` without converting to a full `JS object`.
- Strategy:
    - If `raw` is already in DB as `JSONB`, get it as string via `raw::text` and stream-parse.
    - Alternatively, parse top-level shallow object into memory (small) and stream large fields (troops arrays).
- When mapping arrays to upserts, batch them (e.g., 100–500 troops per batch) to avoid many small DB roundtrips.

### 7.3 Per-entity transaction boundaries

- Use small per-entity transactions instead of a single one across all entities.
- Example:
    - Begin transaction for user upsert -> commit.
    - Begin transaction for batch of `user_troops` (multi-row upsert) -> commit.
- Rationale: limits lock time; allows partial progress and easier reprocessing of failed entities.

### 7.4 Ordering rationale

- Upsert users first so other entities can reference `user_id`.
- Upsert `guilds`/`guild_members` before guild-specific lookups.
- Upsert `troops`/`pets`/`artifacts` in batches; summary is derived last.

### 7.5 Summary generation

- Build `user_profile_summary` with most-used fields needed by API (top troops, equipped pet, pvp tier, guild).
- Upsert summary with `ON CONFLICT (user_id) DO UPDATE SET ...` and update `cached_at`.

---

## 8. Upsert patterns & SQL examples

### 8.1 Safe multi-row upsert (user_troops)

- Use multi-row insert + ON CONFLICT DO UPDATE for batches:

```sql
INSERT INTO user_troops (user_id, troop_id, amount, level, rarity, fusion_cards, traits_owned, extra, last_seen,
                         updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, now(), now()), ...
    ON CONFLICT (user_id, troop_id) DO
UPDATE
    SET amount = EXCLUDED.amount,
    level = EXCLUDED.level,
    rarity = EXCLUDED.rarity,
    fusion_cards = EXCLUDED.fusion_cards,
    traits_owned = EXCLUDED.traits_owned,
    extra = COALESCE (user_troops.extra, '{}'::jsonb) || EXCLUDED.extra,
    last_seen = EXCLUDED.last_seen,
    updated_at = now();
```

### 8.2 Upsert users (idempotent)

```sql
INSERT INTO users (id, namecode, username, discord_user_id, email, created_at, updated_at)
VALUES (COALESCE($id, gen_random_uuid()), $namecode, $username, $discord_user_id, $email, now(),
        now()) ON CONFLICT (namecode) DO
UPDATE
    SET username = COALESCE (EXCLUDED.username, users.username),
    discord_user_id = COALESCE (EXCLUDED.discord_user_id, users.discord_user_id),
    email = CASE WHEN users.email IS NULL THEN EXCLUDED.email ELSE users.email
END
,
    updated_at = now()
RETURNING id;
```

- Prefer returning `id` to link `user_id` where needed.

### 8.3 Upsert summary

```sql
INSERT INTO user_profile_summary (user_id, namecode, username, level, top_troops, equipped_pet, pvp_tier, guild_id,
                                  last_seen, cached_at, extra)
VALUES ($user_id, $namecode, $username, $level, $top_troops::jsonb, $equipped_pet::jsonb, $pvp_tier, $guild_id,
        $last_seen, now(), $extra::jsonb) ON CONFLICT (user_id) DO
UPDATE
    SET namecode = EXCLUDED.namecode,
    username = EXCLUDED.username,
    level = EXCLUDED.level,
    top_troops = EXCLUDED.top_troops,
    equipped_pet = EXCLUDED.equipped_pet,
    pvp_tier = EXCLUDED.pvp_tier,
    guild_id = EXCLUDED.guild_id,
    last_seen = EXCLUDED.last_seen,
    cached_at = now(),
    extra = user_profile_summary.extra || EXCLUDED.extra;
```

### 8.4 Use partial updates for `extra` JSONB fields

- Merge semantics: `existing.extra || new.extra` appends/replaces keys; use `jsonb_set` when needing deep replace.

---

## 9. Error handling, retry policy & poison messages

### 9.1 Error classification

- Transient (retryable):
    - DB connection issues, deadlocks, temporary external API failures, network timeouts.
    - Action: allow automatic retry (queue backoff).
- Permanent (non-retryable):
    - Malformed JSON, missing required fields, FK constraint due to missing catalog and policy is to fail.
    - Action: write an `etl_errors` row with `permanent: true`, set `hero_snapshots.processing=false`,
      `processed_at=NULL` (or optionally `processed_at` to indicate attempted), increment `error_count` and alert
      maintainers.

### 9.2 Recording errors

- Always record structured errors in `etl_errors`:
    - `snapshot_id`, `error_type`, `message` (sanitized), `details` (JSON with limited size), `created_at`.
- Update `hero_snapshots`: increment `error_count`, set `last_error` to summary (short), and (optionally) add
  `error_history` append.

### 9.3 Retry policy

- Default max attempts: 5 (configurable).
- Backoff: exponential with jitter (1s, 2s, 4s, 8s… capped at 5 min).
- For bulk backfills, allow higher `maxAttempts` but with lower concurrency.

### 9.4 Poison queue handling

- After `maxAttempts` reached:
    - Mark job failed in queue
    - Create a monitoring alert and create an admin work item (via issue/alerting channel)
    - Provide reprocess endpoint for manual re-enqueue after fix

### 9.5 Partial failures & compensating actions

- If one entity fails (e.g., `user_troops` batch fails due to FK), worker should:
    - Rollback the entity-level transaction, write an `etl_errors` row specifying which entity failed and why.
    - Continue processing other entities (if safe and configured).
    - Consider marking snapshot with `partial_failure = true` in `hero_snapshots` or `etl_errors` with entity details.

---

## 10. Monitoring & metrics (what to emit)

### 10.1 Metric naming conventions

- Prefix: `starforge_etl_` for worker metrics.
- Labels: `worker_instance`, `job_type`, `env`, `snapshot_source`, `error_type` where applicable.

### 10.2 Required metrics (Prometheus)

- Counters:
    - `starforge_etl_snapshots_received_total{source="", job_type=""}`
    - `starforge_etl_snapshots_processed_total{result="success|failed|partial"}`
    - `starforge_etl_snapshots_failed_total{error_type=""}`
- Gauges:
    - `starforge_etl_processing_jobs_in_progress`
    - `starforge_etl_queue_depth{queue=""}` (prefer scraped from `BullMQ` or `Redis` exporter)
- Histograms / Summaries:
    - `starforge_etl_processing_duration_seconds` (observe by `job_type`)
    - `starforge_etl_batch_upsert_size` (distribution of batch sizes)
- DB related:
    - `starforge_etl_db_tx_duration_seconds`
    - `starforge_etl_db_connection_count` (from app pool)

### 10.3 Alerting rules (suggested)

- **P0:** `ETL` failure spike:
    - Condition: `rate(starforge_etl_snapshots_failed_total[5m]) / rate(starforge_etl_snapshots_processed_total[5m]) >
      0.01 (i.e., >1%)` -> page on-call
- **P0:** Queue depth high:
    - `queue_depth > threshold for 10m` -> page
- **P1:** Avg processing time regression:
    - `p95 processing duration > 2x baseline for 10m` -> notify
- **P1:** `Worker OOM or restarts > N` -> notify

### 10.4 Events & traces

- Emit `snapshot_processed` event with `snapshot_id`, `user_id`, counts of upserts and duration.
- Trace flow: API ingest -> enqueue -> worker -> DB upserts. Propagate `X-Request-Id` or `trace_id`.

---

## 11. Logging, tracing & structured events

### 11.1 Logging guidelines (structured JSON)

- Always log JSON objects with keys:
    - `timestamp`, `service`: "etl-worker", `env`, `level`, `message`, `snapshot_id`, `job_id`, `user_id` (if
      available), `correlation_id`, `trace_id`, `module`, `duration_ms`, `details` (sanitized).
- Examples:

```json
{
  "timestamp": "2025-12-02T12:00:00Z",
  "service": "etl-worker",
  "env": "production",
  "level": "info",
  "message": "claimed snapshot",
  "snapshot_id": "uuid",
  "job_id": "bull-job-uuid",
  "worker_instance": "worker-1"
}
```

### 11.2 Sensitive data redaction

- NEVER log raw tokens, passwords or full player credentials.
- Mask / redact fields matching patterns (token, password, session) prior to logging.
- For debugging, store pointers (`snapshot_id`, `s3_path`) to full raw payload rather than including it in logs.

### 11.3 Tracing

- Use OpenTelemetry (recommended) to propagate trace ids across API -> queue -> worker -> DB.
- Create spans for:
    - `claim_snapshot` (DB update)
    - `parse_snapshot` (streaming)
    - `upsert_<entity_group>` (e.g., `upsert_user_troops`)
    - `commit_snapshot` (final update)

### 11.4 Error telemetry

- Send errors to Sentry with minimal context: `snapshot_id`, `job_id`, `short_message`, `error_type`, `sanitized_stack`.
- Avoid including raw snapshot or `PII` in error events.

---

## 12. Backfill, bulk processing & rate-control

### 12.1 Backfill principles

- Use the same worker code as real-time processing to avoid mapping differences.
- Run backfills on an isolated worker pool with controlled concurrency and DB throttle.
- Recommended initial concurrency: small (e.g., few workers x 2 concurrency) and increase gradually while monitoring DB
  metrics.

### 12.2 Batch sizing & parallelism

- For large arrays (troops), process in batches of 100–500 rows (tunable).
- Use upsert multi-row inserts to reduce round-trips.

### 12.3 Rate limiting and safe windows

- Backfills should honor a DB load budget:
    - Max write `IOPS` per second or max DB CPU utilization.
- Implement a backfill controller that:
    - queries DB metrics
    - adjusts worker concurrency or sleeps between batches accordingly

### 12.4 Resume & checkpointing

- Record per-snapshot backfill progress in a `backfill_jobs` or `queue_jobs` table with:
    - `job_id`, `start_ts`, `last_processed_snapshot_id`, `processed_count`, `error_count`
- On interruption, resume from last recorded snapshot id or job cursor.

---

## 13. Admin APIs & operational endpoints

### 13.1 Reprocess snapshot

- Endpoint: `POST /api/v1/admin/snapshots/:id/reprocess`
- Requirements: `admin auth` & `RBAC`
- Behavior:
    - Validate snapshot exists and not currently processing.
    - Reset `hero_snapshots.error_count = 0; last_error = NULL; processing = false`
    - Enqueue job (high priority if needed)
    - Return `202` Accepted with `job_id` and `ETA` estimate.
- Audit: create an `audit_logs` entry with requester id & reason.

### 13.2 Snapshot status

- Endpoint: `GET /api/v1/admin/snapshots/:id/status`
- Returns: processing `flag`, `processed_at`, `error_count`, `last_error`

### 13.3 Health & metrics endpoints

- `/health` (readiness & liveness)
- `/metrics` (Prometheus) protected by IP or scrape token in production

### 13.4 Job management

- Admin UI to list failed jobs and re-enqueue or inspect `etl_errors`.

---

## 14. Testing strategy (unit / integration / e2e / perf)

### 14.1 Unit tests

- Functions: parse helpers, mapping logic (e.g., mapTroopToRow), hash calculation, idempotency helpers.
- Mock DB & queue; keep fast tests.

### 14.2 Integration tests

- Use testcontainers or ephemeral `Postgres` + `Redis`.
- Tests:
    - migration up -> insert example snapshot -> run worker -> assert normalized tables
    - idempotency: process same snapshot twice -> assert no duplicate rows
    - malformed JSON snapshot -> worker writes `etl_errors` and does not crash

### 14.3 End-to-end tests

- Staging-like environment with real services.
- Scenario: API ingest -> verify snapshot inserted -> wait for worker processing -> query `user_profile_summary` via
  API -> assert fields.

### 14.4 Performance tests

- Tools: `k6`, `Artillery`
- Scenarios:
    - Burst ingestion of N snapshots per minute
    - Worker processing of large snapshots (2–3MB) with constrained memory to validate streaming parser
- Goals:
    - measure p95 processing times, memory usage, DB connection utilization
    - tune batch size & concurrency

### 14.5 Test fixtures

- Keep synthetic example payloads in `docs/examples/`:
    - small, medium, large (`~2–3MB`), malformed sample
- Use these fixtures in `CI` integration tests.

### 14.6 CI gating

- PRs must pass unit + integration tests.
- Migration PRs must run a migration preflight job (apply migrations to ephemeral DB and run a smoke `ETL`).

---

## 15. Security & privacy controls

### 15.1 Data minimization

- Do not persist user passwords. If upstream includes tokens, `ETL` must redact them before storing in normalized tables
  or logs unless storing is absolutely required and approved.

### 15.2 Logging policy

- Redact known sensitive keys in snapshots and logs (e.g., token, password, session).
- Implement automatic scrubbing function that walks `JSON` and masks keys matching configured patterns.

### 15.3 Access control

- Admin endpoints require `RBAC` and auth tokens with least privilege.
- Raw snapshot access is restricted to operators and SREs — prefer return of pointers (`snapshot_id`) rather than full
  raw JSON.

### 15.4 Secrets & rotation

- Use secrets manager or `GitHub Secrets` for connections (`DATABASE_URL`, `REDIS_URL`).
- Rotate worker credentials periodically and automate via provider `OIDC` where possible.

### 15.5 Audit

- Write `audit_logs` for admin actions (reprocess, manual job enqueue, retention runs).

---

## 16. Common incidents & runbook actions

### 16.1 Worker OOM (out of memory)

- Symptoms: worker process restarted, `OOM` logs, repeated restarts.
- Immediate actions:
    1. Scale down worker concurrency or stop worker pool.
    2. Check last logs for snapshot size that caused `OOM` (`snapshot_id`).
    3. If large snapshot: move snapshot to quarantine (mark `hero_snapshots.processing=false`, add `etl_errors`),
       re-enqueue under dedicated high-memory worker or reprocess after parser fixes.
    4. Increase instance memory temporarily and redeploy.
- Preventive:
    - Use streaming parser and batch sizes, set per-worker memory limits and monitor.

### 16.2 DB connection exhaustion

- Symptoms: DB refuses connections, new connections fail.
- Immediate actions:
    1. Pause / scale down worker concurrency.
    2. Check pg pool stats (`pg_stat_activity`) and `pgbouncer` (if used).
    3. Reduce per-worker pool size and restart workers.
- Preventive:
    - Use `pgbouncer`, cap total workers, keep per-worker pool small.

### 16.3 Queue storm / sudden backlog

- Symptoms: queue depth spikes, processing lag increases.
- Immediate actions:
    1. Evaluate if sudden ingestion spike expected (event).
    2. Scale worker pool carefully (respect DB connections).
    3. If risk of overload, throttle ingestion at `API` (return `202` with `ETA`).
- Preventive:
    - Rate limit ingestion clients and use backpressure strategy.

### 16.4 Frequent ETL parse errors (new upstream schema)

- Symptoms: many snapshots failing with parse errors after upstream change.
- Immediate actions:
    1. Pause auto-retries.
    2. Sample failing raw payloads and store examples for developer analysis.
    3. Create a temporary `ETL` mapping patch that ignores unknown fields and records extras.
    4. Plan `migration/ETL` update and backfill as necessary.

### 16.5 Retention/archival job failed (S3 unavailable)

- Immediate actions:
    1. Retry with exponential backoff.
    2. If persistent, pause archival deletion and alert `SRE`.
    3. Ensure DB not purging snapshots until archive confirmed.

---

## 17. Configuration / example env

Example env vars (worker)

```
DATABASE_URL=postgres://user:pass@host:5432/starforge?sslmode=require
REDIS_URL=redis://:password@redis-host:6379
NODE_ENV=production
WORKER_CONCURRENCY=4
PG_POOL_MAX=4
ETL_BATCH_SIZE=250
ETL_MAX_RETRIES=5
ETL_BACKOFF_BASE_MS=1000
ETL_BACKOFF_MAX_MS=300000
CLAIM_TTL_MINUTES=30
METRICS_PORT=9091
SENTRY_DSN=...
```

---

## 18. Appendix

### 18.1 Example job payloads

- Single snapshot job (minimal):

```json
{
  "snapshot_id": "a2f1c1b2-...-e4f9",
  "correlation_id": "req-1234",
  "enqueue_ts": "2025-12-02T12:00:00Z"
}
```

- Backfill job:

```json
{
  "job_type": "backfill_range",
  "from_created_at": "2025-01-01T00:00:00Z",
  "to_created_at": "2025-06-01T00:00:00Z",
  "batch_size": 500,
  "owner": "data-team"
}
```

### 18.2 Example TypeScript worker skeleton (`BullMQ` + `pg` + `stream-json`)

> NOTE: this is a skeleton to illustrate patterns, not production-ready code. Add proper error handling, metrics, config
> management before use.

```ts
// sketch-worker.ts
import { Queue, Worker, Job } from 'bullmq';
import { Pool } from 'pg';
import { parser } from 'stream-json';
import { streamArray } from 'stream-json/streamers/StreamArray';
import { Readable } from 'stream';
import Pino from 'pino';

const logger = Pino();

const redisConnection = { host: process.env.REDIS_HOST, port: Number( process.env.REDIS_PORT ) };
const queue = new Queue( 'etl:snapshots', { connection: redisConnection } );

const pgPool = new Pool( { connectionString: process.env.DATABASE_URL, max: Number( process.env.PG_POOL_MAX || 4 ) } );

const worker = new Worker( 'etl:snapshots', async ( job: Job ) => {
  const { snapshot_id } = job.data;
  const client = await pgPool.connect();
  try {
    // 1. atomic claim
    const res = await client.query(
      `UPDATE hero_snapshots SET processing = true, processing_started_at = now()
       WHERE id = $1 AND (processing = false OR processing IS NULL)
       RETURNING id, raw::text as raw_text`, [ snapshot_id ] );
    if ( res.rowCount === 0 ) {
      logger.info( { snapshot_id }, 'snapshot already claimed, skipping' );
      return;
    }
    const rawText = res.rows[0].raw_text;
    // 2. streaming parse example: if troops is large array
    const jsonStream = Readable.from( [ rawText ] ).pipe( parser() );
    // You would then stream into proper handlers; for brevity we show full parse fallback:
    const payload = JSON.parse( rawText ); // fallback only when safe
    // 3. process entities (use helper functions to batch upserts)
    await processUserAndUpserts( client, payload, snapshot_id );
    // 4. mark processed
    await client.query(
      `UPDATE hero_snapshots SET processed_at = now(), processing = false, last_error = NULL WHERE id = $1`,
      [ snapshot_id ] );
    logger.info( { snapshot_id }, 'processed snapshot' );
  } catch ( err ) {
    logger.error( { err, snapshot_id }, 'processing failed' );
    // write etl_errors and update hero_snapshots
    await client.query(
      `INSERT INTO etl_errors (id, snapshot_id, error_type, message, details, created_at)
       VALUES (gen_random_uuid(), $1, $2, $3, $4::jsonb, now())`,
      [ snapshot_id, 'PROCESSING_ERROR', String( ( err && err.message ) || 'unknown' ), JSON.stringify( { stack: err && err.stack } ) ] );
    await client.query( `UPDATE hero_snapshots SET error_count = COALESCE(error_count,0)+1, last_error = to_jsonb($2::text) WHERE id = $1`,
      [ snapshot_id, `Processing error: ${ err && err.message }` ] );
    throw err; // let BullMQ retry according to its policy
  } finally {
    client.release();
  }
}, { connection: redisConnection, concurrency: Number( process.env.WORKER_CONCURRENCY || 4 ) } );

async function processUserAndUpserts( client: any, payload: any, snapshot_id: string ) {
  // Implement mapping and batch upserts, following SQL patterns in this doc.
}
```

### 18.3 Helpful SQL queries

- Find latest processed snapshot for a user:

```sql
SELECT *
FROM hero_snapshots
WHERE user_id = $1
  AND processed_at IS NOT NULL
ORDER BY created_at DESC LIMIT 1;
```

- List failed snapshots (recent):

```sql
SELECT id, created_at, error_count, last_error
FROM hero_snapshots
WHERE error_count > 0
ORDER BY created_at DESC LIMIT 100;
```

- Count queue depth (`BullMQ` stores in `Redis`, but if DB-backed queue):

```sql
SELECT count(*)
FROM queue_jobs
WHERE status = 'pending';
```

---

References

- [docs/DB_MODEL.md](./DB_MODEL.md) (canonical schema)
- [docs/MIGRATIONS.md](./MIGRATIONS.md) (migration conventions)
- [docs/OBSERVABILITY.md](./OBSERVABILITY.md) (metrics & alerts)
- BullMQ docs: https://docs.bullmq.io/
- stream-json: https://github.com/uhop/stream-json
- OpenTelemetry for Node: https://opentelemetry.io/

---
