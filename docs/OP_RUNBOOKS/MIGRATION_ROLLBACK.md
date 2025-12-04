# Runbook — Migration Rollback

---

## Purpose

Step-by-step procedure to roll back a problematic database migration in staging or production. This runbook covers
safe options (down migrations), when to restore from backups, coordinated actions (application revert, quarantine jobs),
and verification checks.

---

## Audience

- `SRE` / `Operations engineers` executing rollbacks
- Backend engineers owning migrations
- Incident commander and product/stakeholder contacts

---

## When to use

- A recently applied migration causes critical errors, data integrity issues, or service degradation.
- Post-migration validation detects major regressions.
- A destructive migration was applied by mistake.

---

## Guiding principles

- Prefer safe, non-destructive rollback: run the documented down migration only if it’s safe and tested.
- Never overwrite production in-place without restoring to a separate instance and validating first.
- Take an additional backup before performing corrective actions.
- Communicate clearly and continuously: who is acting, what is being done, and when.

---

## Quick terminology

- up migration: migration that applies changes.
- down migration: migration that reverts an up migration.
- restore: recover DB from snapshot/dump (see [./docs/DB_RESTORE.md](./DB_RESTORE.md)).
- cutover: switching application traffic to a restored or corrected DB.

---

## Initial triage (first 10 minutes)

1. Acknowledge alert and open an incident channel (e.g. `#incident-db-migration-<ts>`).
2. Identify the offending migration (file name / version in migration table).
3. Estimate scope/impact: affected queries, tables, rows, and whether data was deleted or transformed irreversibly.
4. Do not run irreversible operations before taking an extra snapshot/dump of current state.
5. Inform product/support and prepare approvers for rollback actions.

---

## Mandatory pre-action checklist

- [ ] Take a fresh snapshot or logical dump and record its ID.
- [ ] Confirm approvals are available (`SRE` + migration owner).
- [ ] Ensure down scripts are present and reviewed by a developer familiar with the migration.
- [ ] Schedule a maintenance window or notify users if user-impact is expected.
- [ ] Prepare a validation plan (list of queries / smoke tests to run after rollback).

---

## Choose rollback strategy

- Option A — Run the down migration
    - Use when:
        - A well-tested down migration exists and is non-destructive for critical data.
        - No irreversible data transformations were applied that the down cannot safely repair.
    - Pros: targeted and usually faster.
    - Cons: downs can be incomplete or leave inconsistent state if not carefully designed.

- Option B — Restore from backup (recommended for destructive changes)
    - Use when:
        - The migration performed irreversible destructive changes (`DROP TABLE`, `mass DELETE`, irreversible
          transforms).
        - No safe or reliable down exists.
    - Pros: returns to a known-good state.
    - Cons: restore time, and writes after the backup will be lost unless replayed or backfilled.

- Option C — Revert application deployment + apply corrective DB action
    - Use when:
        - The regression is caused by a coupled application change (schema + app code mismatch).
        - You need to stop the app from writing incompatible data before fixing DB.
    - Pattern: revert app first, then handle DB rollback or restore.

---

## Execute a down migration (recommended steps)

1. Validate in test/staging
    - Run the down migration on a test or restored copy to observe effects and verify no unexpected data loss.

2. Create an additional snapshot of the current production state
    - Even if you plan to run a down, snapshot current state to enable fallback.

3. Identify non-transactional steps
    - Note steps that cannot run inside a transaction (e.g., `CREATE INDEX CONCURRENTLY`) and plan to run them
      separately.

4. Run the down via `CI/CD` (preferred)
    - Prefer an auditable `CI` workflow that applies the down and records logs and artifacts.

5. Manual execution (if `CI` not available)
    - Example using node-pg-migrate:
      ```
      pnpm run migrate:down -- --count 1 -- --config database/migration-config.js --env production
      ```
        - Adjust `--count` to revert the needed number of migrations.

6. Monitor and verify migration table
    - Confirm the migration was recorded as reverted:
      ```sql
      SELECT * FROM node_pgmigrations_schema_version ORDER BY installed_on DESC LIMIT 20;
      ```

7. Run verification checks (see below).

---

## Restore from backup (recommended flow)

1. Restore to a new DB instance (do not overwrite prod)
    - Follow [docs/OP_RUNBOOKS/DB_RESTORE.md](./DB_RESTORE.md) for provider-specific restore steps.

2. Run smoke tests on the restored instance
    - Verify schema, critical row counts, and representative application flows.

3. Plan cutover
    - Put application in read-only mode or pause ingestion.
    - Update `DATABASE_URL` via secrets manager, rotate connection strings or switch `DNS`/`Proxy` to point to restored
      DB.

4. Gradual traffic shift
    - Start a small set of app instances pointed to restored DB, validate, then shift more traffic.

5. Handle lost writes
    - If writes occurred after the backup time, plan a manual replay or backfill for missing data (
      see [./docs/BACKFILL.md](./BACKFILL.md)).

---

## Revert application deployment (if needed)

- Revert the application to the previous stable release using your deployment tool (`kubectl`, `Helm`, `Cloud Run UI`).
- Disable any feature flags that enable the new schema-dependent flows.
- After app rollback, apply the DB rollback path (down or restore), depending on situation.

---

## Post-rollback verification (minimum)

- Migration table:
  ```sql
  SELECT version, installed_on FROM node_pgmigrations_schema_version ORDER BY installed_on DESC LIMIT 10;
  ```
- Sanity checks:
    - `SELECT count(*) FROM users;`
    - `SELECT count(*) FROM hero_snapshots;`
    - `SELECT to_regclass('public.hero_snapshots');`
- Health endpoints:
    - `GET /api/health` returns 200.
- Application smoke tests:
    - Read profile summary for sample users.
    - If write tests are allowed, insert a small test snapshot and ensure ETL processes it.
- Monitor metrics for `30–60 minutes`:
    - `API` latency, `ETL` failure rate, DB connections.

---

## Communication & coordination

- Initial notice:
    - "Rollback of migration `<file or version>` initiated. Snapshot saved: `<id>`. `ETA: ~<X> minutes`."
- Status updates: every `15–30 minutes` with progress and any issues encountered.
- Resolution message:
    - "Rollback complete. Validation passed. Link to incident ticket and artifacts."

---

## Common scenarios & specific guidance

1. Destructive migration (`DROP/DELETE`)
    - Do not attempt a down unless it was specifically designed to restore data. Prefer restore from backup.

2. `CREATE INDEX CONCURRENTLY` or other non-transactional `DDL`
    - These steps must be run separately outside transactional migration steps. Re-run or reverse as appropriate in
      isolated migrations.

3. Partial down failure
    - Stop further automated actions. Capture diagnostics, run the down on a test copy to reproduce, and restore from
      backup if state cannot be reliably recovered.

4. App-schema regression
    - Revert the app first to stop writes to the new schema. Then address DB rollback.

---

## Recovery & controlled re-enable

1. Bring back workers and ingestion gradually:
    - Start with a small worker pool (`concurrency=1`) and observe.
    - If stable, scale up incrementally.

2. Run targeted backfills for any missing or inconsistent data.

3. Keep enhanced monitoring and alerts for an observation window.

---

## Condensed rollback checklist (playbook)

- [ ] Snapshot/dump taken and ID recorded
- [ ] Incident channel open and approvers available
- [ ] Strategy chosen: down / restore / revert app
- [ ] Down tested on staging (if using)
- [ ] Action executed via `CI` (preferred) or manually with logs recorded
- [ ] Post-rollback verification passed
- [ ] Communication/incident documentation completed

---

## Useful SQL snippets

```SQL
-- Recent migrations
SELECT *
FROM node_pgmigrations_schema_version
ORDER BY installed_on DESC LIMIT 20;

-- Check table existence
SELECT to_regclass('public.hero_snapshots') AS hero_snapshots_exists;

-- Quick counts
SELECT COUNT(*)
FROM users;
SELECT COUNT(*)
FROM hero_snapshots;

-- Long running transactions (diagnostic)
SELECT pid, usename, now() - xact_start AS duration, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY duration DESC LIMIT 20;
```

---

## Post-incident: postmortem & corrective actions

- Produce a postmortem with timeline, root cause, detection & mitigation actions, and permanent fixes.
- Typical corrective actions:
    - Improve migration tests and preflight procedures.
    - Enforce backup-before-migration policy and verify restore steps.
    - Adopt migration patterns: add → backfill → enforce.
    - Add guardrails for destructive operations and limit automatic backfills.

---

## References

- [docs/OP_RUNBOOKS/DB_RESTORE.md](./DB_RESTORE.md) — backup & restore procedures
- [docs/OP_RUNBOOKS/APPLY_MIGRATIONS.md](./APPLY_MIGRATIONS.md) — migration apply runbook
- [docs/MIGRATIONS.md](../MIGRATIONS.md) — migration conventions and safe patterns
- [docs/OP_RUNBOOKS/BACKFILL.md](./BACKFILL.md) — backfill procedure

---
