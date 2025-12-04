# Runbook — Database Restore / Recovery

---

## Purpose

Step-by-step guidance to restore the StarForge `PostgreSQL` database from backups or perform a point-in-time restore
(`PITR`). This runbook is the authoritative operational procedure to recover from catastrophic failures caused by
destructive migrations, accidental deletes, or provider incidents.

---

## Scope

- Full database restore from backup snapshot / dump.
- Point-In-Time Recovery (`PITR`) to a specific timestamp (if `WAL` / `PITR` enabled).
- Promoting a replica as primary (when applicable).
- Validation and smoke checks after restore.
- Communication, escalation and post-restore actions.

---

## Audience

- `SRE` / `DevOps engineers` executing restores
- `Backend engineers` assisting with verification and data integrity checks
- `Incident commander` during recovery

---

## Prerequisites & assumptions

- You have access to cloud provider console or backups location (`S3`/`GCS`) and DB admin credentials.
- A known-good backup snapshot ID or a backup file is available.
- For `PITR` you must have `WAL` archive enabled and accessible for the target window.
- You have documented restore permissions and an incident channel for coordination.
- Pre-restore backup (freeze point) was taken as part of migration/backfill safety steps (recommended practice).

---

## Emergency summary (short)

1. Pause writes and ingestion (stop workers & `API` writes).
2. Identify reliable backup (snapshot id or latest consistent backup).
3. Restore to a new DB instance (do NOT overwrite primary unless planned).
4. Run smoke tests and validation queries.
5. Promote restored instance to primary or remap application connections.
6. Resume services in controlled manner and monitor.

---

## Pre-restore checklist (must complete)

- [ ] Notify stakeholders & open an incident channel (`#incident-db-restore`).
- [ ] Record the current state (timestamps, error messages, affected services).
- [ ] Pause ingestion and stop workers: scale worker replica count to `0` or stop processes.
- [ ] Capture diagnostics: `pg_stat_activity`, `error logs`, `recent migrations`, `last successful backup id`, and current `WAL` position if available.
- [ ] Confirm backup availability (snapshot id or path) and estimated time-to-restore.
- [ ] Confirm access to secrets and credentials required for restore (cloud console, DB admin).
- [ ] Confirm rollback/contingency plan and that approvers are available.

---

## Types of restores

1. Provider snapshot restore (managed DB snapshot)
   - Fastest option; provider restores an instance from snapshot.
   - Use when you have a full snapshot taken previously (recommended before migrations).

2. Restore from logical dump (`pg_dump` / `pg_restore`)
   - Required when snapshots not available or when restoring specific schema/data.
   - Slower for large DBs; use for targeted restores.

3. Point-In-Time Recovery (`PITR`)
   - Restore base backup and apply `WAL` logs up to target timestamp.
   - Use when you need to recover to a specific moment (e.g., before accidental DELETE).

4. Promote read-replica
   - If a healthy read-replica exists and is up-to-date, promote it to primary.
   - Quick and safe if replica is suitable.

---

## Restore workflow (recommended safest flow)

### A. Preparation (operator)

1. Pause writers:
   - Pause ingestion `API` or flip feature flag.
   - Scale down `ETL` worker replicas:
     ```bash
     kubectl -n starforge scale deployment etl-worker --replicas=0
     ```
2. Ensure no scheduled jobs are running that will write to DB.

3. Select restore target:
   - Option 1: New instance for restored DB (recommended).
   - Option 2: Restore into staging cluster first for verification (strongly recommended if time allows).

### B. Execute restore (provider snapshot example)

1. In provider console (`Supabase` / `RDS` / `Cloud SQL`):
   - Locate snapshot id (or automated backup).
   - Click "Restore" and choose a new instance name (e.g., `starforge-restore-2025-12-03`).
   - Choose same region and compatible instance size. If under load, consider a larger instance temporarily.

2. Wait for restore to complete. Time depends on DB size and provider speed.

3. Obtain the new `DATABASE_URL` for the restored instance and restrict access (whitelist operator IPs).

### C. Execute restore (logical dump example)

1. Upload dump file to the restore host or use direct streaming.

2. Create a blank DB on target host:
   ```bash
   psql -h <host> -U <admin> -c "CREATE DATABASE starforge_restore;"
   ```

3. Restore schema & data:
   ```bash
   pg_restore --verbose --no-owner --role=<role> -h <host> -U <admin> -d starforge_restore /path/to/backup.dump
   ```

4. Monitor restore progress and `pg_restore` output for errors.

### D. Execute PITR (when WAL available)

`PITR` is advanced; follow provider docs or below high-level steps.

1. Restore base backup to a new instance (base backup).
2. Configure `recovery.conf` or restore settings to point to `WAL` archive.
3. Set recovery target time:
   ```bash
   recovery_target_time = '2025-12-03 14:23:00+00'
   ```
4. Start instance and wait until recovery completes and database is consistent.
5. Verify recovered state matches expected time.

---

### E. Promote & cutover

1. Test the restored DB with a read-only smoke test.
    - Run sanity queries: count of essential tables, sample user lookup, basic `API` health with read-only endpoint.

2. Plan cutover strategy:
    - `DNS`/connection string swap:
        - Update application `DATABASE_URL` to point to restored DB (best done via secrets manager or config).
    - Alternatively, change read/write roles and promote the restored host to primary (provider option).

3. Minimize downtime:
    - Use a rolling approach: bring up a small application replica pointing to restored DB, validate, then gradually switch traffic.

---

## Validation & verification (post-restore)

Run these checks immediately and for the monitoring window that follows.

1. Basic connectivity
   ```bash
   psql <restored_DATABASE_URL> -c "SELECT 1;"
   ```

2. Schema sanity
   ```sql
   SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';
   SELECT to_regclass('public.hero_snapshots');
   ```

3. Critical row counts / sample checks
    - Users:
      ```sql
      SELECT count(*) FROM users;
      SELECT id FROM users ORDER BY created_at DESC LIMIT 5;
      ```
    - Hero snapshots:
      ```sql
      SELECT count(*) FROM hero_snapshots;
      SELECT id, created_at FROM hero_snapshots ORDER BY created_at DESC LIMIT 5;
      ```

4. Application smoke test (read & write)
    - With a staging `API` instance, call:
        - `GET /api/health`
        - `GET /api/v1/profile/summary/<sample_namecode>`
        - (If read-write allowed) insert a small test snapshot and ensure it processes.

5. `ETL` smoke test
    - Start a single worker against restored DB and process a sample snapshot:
        - Confirm `hero_snapshots.processed_at` is set and `user_profile_summary` updated.
    - Ensure worker logs show no fatal errors.

6. Consistency checks
    - Referential integrity:
      ```sql
      SELECT count(*) FROM user_troops WHERE user_id IS NULL;
      ```
    - Uniqueness constraints:
      ```sql
      SELECT user_id, troop_id, count(*) FROM user_troops GROUP BY user_id, troop_id HAVING count(*) > 1 LIMIT 10;
      ```

7. Application-scale verification
    - Monitor metrics: `API` latency, DB connections, `ETL` error rate for at least `30–60 minutes` before full cutover.

---

## Rollback & contingency during restore

- Do not overwrite the original primary instance immediately. Always restore to a new instance first.
- If restored DB is invalid, abort the cutover and iterate (try a different snapshot or time).
- If primary must be reinstated, you can revert application connection strings to the original `DATABASE_URL`.

---

## Post-restore steps and follow-up

- Document the restore: snapshot id, who executed, timestamps, and verification outputs. Attach to incident ticket.
- Run a full application regression test in staging, then in production for critical flows.
- Re-enable workers and ingestion progressively:
    - Start a small number of workers (`concurrency=1`), monitor, then scale.
- Rebuild or re-apply any migrations that are required and were not present in the restored point (coordinate migration history).
- Run a backfill for any missing or late data if necessary (use [docs/OP_RUNBOOKS/BACKFILL.md](./BACKFILL.md)).

---

## Security & access considerations

- Rotate credentials if restore was caused by a security incident (see [docs/OP_RUNBOOKS/SECRET_COMPROMISE.md](./SECRET_COMPROMISE.md) runbook).
- Audit who accessed backups and restoration artifacts.
- Limit access to restored instance until verified.

---

## Troubleshooting common issues

- Restore taking too long:
    - Option: restore into a larger instance type to speed `IO`.
    - For logical restores, use parallel restore with `pg_restore -j <n>`.

- `WAL` unavailable for `PITR`:
    - If `WAL` segment missing, `PITR` cannot reach target time. Consider restoring to the last available `WAL` and then applying compensating actions.
    - Consult provider's support for `WAL` retrieval if they archive it.

- Errors during `pg_restore` (permission, role problems):
    - Re-run with `--no-owner --role=<desired_role>` and ensure roles exist.
    - Create missing roles temporarily or adjust dump options.

- Post-restore replication / replica issues:
    - If promoting a replica, ensure replication slots are cleaned and standby configs updated.
    - If using pgbouncer, update its server config to point to the new primary.

---

## Communication template (incident updates)

- Initial alert (short):
    - "Incident: DB outage — starting restore. Using snapshot `<id>`. `ETA` to service: `~<X> minutes`. Channel: `#incident-db-restore`."

- Progress update:
    - "Restore progress: snapshot restore completed / `pg_restore` at `40%` / `PITR` applying `WALs` — `ETA ~20m`. Next: smoke tests."

- Resolution:
    - "Restore complete. Restored instance: `<host>`. Smoke tests passed. Cutover started at <time>. Services resumed."
    - Provide link to incident ticket with timeline & artifacts.

---

## References & related docs

- [docs/MIGRATIONS.md](../MIGRATIONS.md) — migration preflight & safe patterns
- [docs/OP_RUNBOOKS/APPLY_MIGRATIONS.md](./APPLY_MIGRATIONS.md) — runbook for applying migrations
- [docs/OP_RUNBOOKS/BACKFILL.md](./BACKFILL.md) — backfill procedures for populating missing data
- Provider docs:
    - `Supabase`: https://supabase.com/docs
    - `AWS RDS` snapshot & `PITR`: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html
    - `Google Cloud SQL` backups & `PITR`: https://cloud.google.com/sql/docs/postgres/backup-recovery

---

## Appendix: Useful commands (examples)
```SQL
-- Check current active queries
SELECT pid, usename, application_name, client_addr, state, now()-query_start AS duration, query FROM pg_stat_activity ORDER BY duration DESC LIMIT 50;

-- Create DB on target host
psql -h <host> -U <admin> -c "CREATE DATABASE starforge_restore;"

-- Restore from dump (parallel)
pg_restore -h <host> -U <admin> -d starforge_restore -j 8 /path/to/backup.dump

-- Promote read replica (AWS RDS example)
# Use AWS Console or:
aws rds promote-read-replica --db-instance-identifier my-replica
```
---
