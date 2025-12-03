# Runbook — Apply Database Migrations

---

## Purpose

This runbook describes the safe, repeatable procedure to apply schema migrations to production (and staging)
environments for the StarForge project. It consolidates the guidance in [docs/MIGRATIONS.md](../MIGRATIONS.md) and
provides a concise,
actionable checklist, commands, verification queries and troubleshooting steps for operators and engineers.

---

## Audience

- `SRE` / `Ops engineers` executing production changes
- `Backend engineers` owning migration PRs
- `Release approvers` and on-call engineers

---

## When to use

- To apply migration PRs to staging or production.
- To run emergency schema changes after appropriate approvals.
- To validate migrations that were applied by `CI` (post-apply verification).

---

## Principles (short)

- Always be safe: take a backup before applying production migrations.
- Use the protected `CI` workflow (`db-bootstrap`) for production when possible — it enforces approvals and records
  artifacts.
- Prefer additive, phased migrations: add → backfill → enforce.
- Monitor system health during and after migration; be prepared to rollback or restore.

---

## Pre-flight checklist (must pass before apply)

1. Backup & snapshot
    - Create and record a DB backup/snapshot ID. Verify the backup was successful.
    - Document the backup ID in the migration ticket/PR.

2. Approvals
    - Confirm the GitHub `db-bootstrap` workflow will run under a protected environment (requires approval).
    - Ensure required approvers (`Engineering` + `SRE`) are available during the window.

3. `CI` Preflight & Tests
    - Ensure `CI` `migrate:preflight` job passed for the migration PR (applied against ephemeral DB).
    - Confirm unit/integration tests and migration tests passed in `CI`.

4. Runbook & Impact
    - Confirm the migration PR includes impact estimates (row counts, index build time).
    - Confirm any required maintenance window or low-traffic window is scheduled if the change is heavy.

5. Communication
    - Notify stakeholders (product, support) of the planned maintenance window and expected `ETA`.
    - Post the planned change with contact / pager information.

6. Operational readiness
    - Ensure `SRE` on-call is available.
    - Confirm ability to pause ingestion and workers (feature flag or scaledown commands).
    - Confirm you can run the rollback / restore plan and have the runbook open.

---

## How to apply (recommended: GitHub Actions / db-bootstrap)

Use the repository's protected `db-bootstrap` GitHub Actions workflow. This is the preferred and auditable path.

1. Open the PR with migration files and ensure it includes `MIGRATION: <filename>` in commit message.
2. From the repository Actions tab, locate `db-bootstrap` (or run `workflow_dispatch`).
3. Provide required inputs (if any) and kick off the workflow.
4. Approver(s): Approve the environment prompt to let the workflow run against production.
    - The workflow will run preflight checks, run migrations, and surface logs.

> Notes:
> - The workflow requires the secret `DATABASE_URL` in `GitHub environment` and the `apply` confirmation input to
    actually apply.
> - The workflow logs and artifacts will be retained in `GitHub Actions` and should be saved for audit.

---

## How to apply (alternative: manual via CLI)

Only use if GitHub Actions is not available. Prefer scripted, idempotent commands.

1. Pause ingestion & workers
    - Disable ingestion if possible (`API` feature flag) or scale down workers to 0.
    - Example (`Kubernetes`): scale down `etl worker` deployment:
        - `kubectl scale deployment etl-worker --replicas=0 -n starforge`
    - For non-`K8s`: stop worker processes or toggle feature flag.

2. Ensure you have a recent backup.

3. Run preflight locally (optional but recommended)
    - `./scripts/migrate-preflight.sh`
    - Validate `pgcrypto` availability, connectivity, and run a smoke `ETL`.

4. Run migrations
    - From repo root:
        - `pnpm install --frozen-lockfile`
        - `pnpm run migrate:up -- --config database/migration-config.js --env production`
    - If migrations require `CONCURRENTLY` for indexes, follow documented instructions — they may run outside a
      transaction.

5. Collect logs and proceed to verification.

---

## Post-apply verification (smoke & health checks)

Immediately after migrations finish, run the following checks before re-enabling full traffic:

1. Schema migration table
    - Verify applied migrations:
        - `SELECT * FROM node_pgmigrations_schema_version ORDER BY installed_on DESC;`
    - (or check `schema_migrations` / the table created by `node-pg-migrate` in your setup)

2. Basic DB health
    - Active connections:
        - `SELECT count(*) FROM pg_stat_activity;`
    - Long running transactions:
        -
        `SELECT pid, now() - xact_start AS duration, query FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY duration DESC LIMIT 10;`

3. Verify key tables/indexes exist (examples)
    - Check table existence:
        - `SELECT to_regclass('public.hero_snapshots');`
    - Check index existence:
        - `SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'hero_snapshots';`

4. Run a smoke `ETL`
    - Insert a small test snapshot (or use sample fixture) into `hero_snapshots` and enqueue a processing job.
    - Verify worker processes it (if workers are still paused, re-enable a single worker instance temporarily).
    - Confirm `user_profile_summary` and `user_troops` upserts succeed.
    - Helpful SQL:
        -
        `SELECT id, processed_at, error_count, last_error FROM hero_snapshots WHERE created_at > now() - interval '10 minutes' ORDER BY created_at DESC LIMIT 20;`

5. Check `etl_errors` and logs
    - Recent errors:
        - `SELECT * FROM etl_errors ORDER BY created_at DESC LIMIT 50;`
    - Check application logs and `Prometheus` metrics (`starforge_etl_snapshots_processed_total`,
      `starforge_etl_snapshots_failed_total`).

6. Monitor metrics & dashboards
    - Watch `ETL` processing rate and failure rate for at least `30–60 minutes`.
    - Verify DB CPU, IO, and connection metrics are within expected ranges.

---

## Rollback & emergency restore (decision flow)

If migration causes critical failures or data corruption, follow this decision flow:

1. If migration has a safe `down` script, and you are confident its execution will restore safe state:
    - Run the down migration for the offending change:
        - `pnpm run migrate:down -- --count 1 -- --config database/migration-config.js`
    - Note: downs may not be safe for destructive changes. Ensure you understand side effects.

2. If `down` is unsafe, perform a DB restore from the backup created before the migration:
    - Stop ingestion and workers immediately.
    - Restore the DB from the backup snapshot ID recorded earlier (follow provider-specific restore steps).
    - Notify stakeholders and follow restore verification steps (same as post-apply verification).
    - After recovery, coordinate re-deploy of any fixes and controlled re-apply if required.

3. Communicate clearly:
    - Open an incident ticket and notify on-call and stakeholders.
    - Document timeline and actions taken in the migration PR or incident system.

---

## Common failure modes & mitigations

- CREATE EXTENSION / pgcrypto permission denied
    - Symptom: migration fails on CREATE EXTENSION.
    - Mitigation: check provider support. If unsupported, use application-side `UUID` generation or request provider
      privileges. Revert/skip extension creation if planned.

- Long-running CONCURRENTLY index builds causing resource exhaustion
    - Symptom: elevated IO/CPU, slowed queries.
    - Mitigation: monitor index build, spread index creation to off-peak hours, throttle background jobs, or create
      indexes on replicas if available.

- Migration wrapped in transaction (CONCURRENTLY disallowed)
    - Symptom: failure when attempting CREATE INDEX CONCURRENTLY inside transaction.
    - Mitigation: separate that step into a non-transactional migration (use `pgm.sql` outside a transaction) as
      documented in [docs/MIGRATIONS.md](../MIGRATIONS.md).

- DB connection exhaustion
    - Symptom: connection errors, failed migrations.
    - Mitigation: reduce migration concurrency, pause workers, increase DB capacity temporarily, use pgbouncer.

- Partial backfill failures
    - Symptom: backfill job errors after schema change.
    - Mitigation: investigate error, re-run backfill with smaller batches, record failures in `backfill_jobs` for
      resume.

---

## Recommended verification queries (copy/paste)

```SQL
-- Check last applied migrations (adjust to your migration table name)
SELECT *
FROM schema_migrations
ORDER BY installed_on DESC LIMIT 20;

-- Check hero_snapshots presence
SELECT to_regclass('public.hero_snapshots') as hero_snapshots_exists;

-- Check GIN index presence for hero_snapshots.raw
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'hero_snapshots'
  AND indexdef ILIKE '%gin%';

-- Show recent etl_errors
SELECT id, snapshot_id, error_type, message, created_at
FROM etl_errors
ORDER BY created_at DESC LIMIT 50;

-- Recent processed snapshots
SELECT id, user_id, processed_at, error_count
FROM hero_snapshots
WHERE processed_at IS NOT NULL
ORDER BY processed_at DESC LIMIT 20;
```

---

## Operational checklist (concise)

- [ ] Backup created and backup ID recorded
- [ ] Approvals obtained
- [ ] `CI` preflight passed
- [ ] Maintenance window & communications sent
- [ ] Workers paused / ingestion throttled
- [ ] Run migrations via `CI` (preferred) or manual `CLI`
- [ ] Run post-apply verification queries
- [ ] Run smoke `ETL` and confirm no errors
- [ ] Monitor metrics for `30–60 minutes`
- [ ] Re-enable workers and normal traffic
- [ ] Record migration outcome and attach logs/artifacts to PR

---

## Audit & artifacts

- Keep GitHub Actions logs and artifacts (workflow run ID) attached to the migration PR.
- Record backup snapshot ID and any run IDs (backfill job IDs) in the PR and change log.
- Save verification query outputs into the PR comments or incident log for traceability.

---

## Contacts & escalation

- Primary `SRE`: (fill with on-call contact or team alias)
- Backend owner(s): from migration PR
- Pager / Slack channel: `#starforge-ops`
- If severe outage: page `SRE` and Engineering leads immediately.

---

## References

- [docs/MIGRATIONS.md](../MIGRATIONS.md) — migration conventions and patterns
- [docs/ETL_AND_WORKER.md](../ETL_AND_WORKER.md) — `ETL` contract and smoke test guidance
- [docs/DB_MODEL.md](../DB_MODEL.md) — canonical schema
- `scripts/migrate-preflight.sh` — preflight helper script
- `GitHub Actions` workflow: `.github/workflows/db-bootstrap.yml`

---

## Notes

- This runbook is intended to be concise and actionable. For complex or high-risk migrations (large table rewrites,
  partitioning, destructive changes), prepare a migration plan that includes a rehearsal run in staging, detailed
  backfill scripts, and extended monitoring windows.
- Keep the runbook updated with contact details and any provider-specific restore steps.
