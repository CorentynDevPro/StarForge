# MIGRATIONS.md — Database Migrations Guide

> Version: 0.1  
> Date: 2025-12-03

---

## Purpose

- Provide a complete, practical guide for creating, testing, reviewing and applying database schema migrations for
  StarForge.
- Aligns with [docs/DB_MODEL.md](./DB_MODEL.md) (canonical schema) and [docs/ETL_AND_WORKER.md](./ETL_AND_WORKER.md) (
  `ETL` contracts).
- Target audience: `Backend engineers`, `SRE/DevOps`, `reviewers` and `release approvers`.

---

## Scope

- JavaScript migrations using `node-pg-migrate` (recommended).
- Preflight checks, CI integration, local developer workflows, production bootstrap workflow, rollback guidance,
  indexes, extensions, and operational runbooks.
- Includes sample migration templates and scripts you can adapt.

---

## Table of contents

1. [Principles & Goals](#1-principles--goals)
2. [Tooling & repo layout](#2-tooling--repo-layout)
3. [Naming & file conventions](#3-naming--file-conventions)
4. [Migration anatomy (up / down / idempotence)](#4-migration-anatomy-up--down--idempotence)
5. [Safe migration patterns (additive → backfill → enforce)](#5-safe-migration-patterns)
6. [Extensions & provider considerations (pgcrypto etc.)](#6-extensions--provider-considerations)
7. [Index creation & long-running operations (CONCURRENTLY)](#7-index-creation--long-running-operations)
8. [Partitioning strategy & archival-aware changes](#8-partitioning-strategy--archival-aware-changes)
9. [Preflight checks & CI jobs](#9-preflight-checks--ci-jobs)
10. [Local developer workflow (create / run / revert)](#10-local-developer-workflow)
11. [Production bootstrap workflow (manual, protected)](#11-production-bootstrap-workflow-manual-protected)
12. [Rollback & emergency restore strategy](#12-rollback--emergency-restore-strategy)
13. [Migration PR checklist & review criteria](#13-migration-pr-checklist--review-criteria)
14. [Seeding & catalog management](#14-seeding--catalog-management)
15. [Testing migrations (unit/integration/e2e)](#15-testing-migrations-unit--integration--e2e)
16. [Backfill & data-migration jobs coordination](#16-backfill--data-migration-jobs-coordination)
17. [Auditing & migration traceability](#17-auditing--migration-traceability)
18. [Examples: node-pg-migrate templates & preflight script](#18-examples-node-pg-migrate-templates--preflight-script)
19. [Runbooks & operational notes](#19-runbooks--operational-notes)
20. [References](#20-references)

---

## 1. Principles & Goals

- Safety first: migrations must not cause unexpected downtime or data loss.
- Small, focused changes: prefer many small migrations over large monolithic ones.
- Reversible where practical: provide `down` when safe; if not reversible, document strong rollback plan.
- Observable: migrations must produce logs and artifacts to audit what happened and when.
- Testable: migrations run in CI against ephemeral DBs; run preflight on staging before production.
- Manual approval for production: production schema changes are applied through a protected, manual workflow.

---

## 2. Tooling & repo layout

### Recommended tooling

- `node-pg-migrate` — JS migrations that integrate well with `Node` toolchain.
- `pg` (`node-postgres`) for direct DB access in scripts / preflight.
- `psql` for quick manual checks.
- testcontainers (or `docker-compose`) for integration tests in CI.

### Suggested repo layout

```
database/
  migrations/         # node-pg-migrate migration files
  seeds/              # idempotent seed files for catalogs
scripts/
  migrate-preflight.sh
  bootstrap-db.sh
docs/
  MIGRATIONS.md
  DB_MODEL.md
  ETL_AND_WORKER.md
```

### GitHub Actions

- CI job for migration preflight and tests.
- Manual `db-bootstrap.yml` workflow for production migrations (requires environment approval).

---

## 3. Naming & file conventions

### Filename pattern (required)

```
YYYYMMDDHHMMSS_description.[js|sql]
```

- Use `UTC` timestamp prefix for ordering.
- Example: `20251203T153000_add_hero_snapshots_table.js` (or numeric timestamp 20251203153000).

### Migration metadata

- Each migration should include header comments describing:
    - Purpose
    - Expected impact (approx row counts, index size)
    - Estimated index build time if large

### Commit messages

- Link migration file to PR and include `MIGRATION: <filename>` in PR and commit message.

---

## 4. Migration anatomy (up / down / idempotence)

Use `node-pg-migrate` export format with `exports.up = (pgm) => { ... }` and `exports.down = (pgm) => { ... }`.

### Guidelines

- Up should apply the change; down should revert when safe.
- Avoid irreversible actions in a single migration. If irreversible, document backup id and rollback plan in migration
  header.
- Migrations should be idempotent where possible and robust to partial re-runs in test environments.
- Keep migration files small (`~1–200 lines`) and focused.

### Example migration (skeleton)

```js
/* 20251203_create_hero_snapshots.js
 Purpose: create hero_snapshots table for raw ingestion
 Estimated rows: small initially
 */
exports.shorthands = undefined;

exports.up = ( pgm ) => {
  pgm.createTable( 'hero_snapshots', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func( 'gen_random_uuid()' ) },
    user_id: { type: 'uuid', references: 'users(id)', onDelete: 'SET NULL' },
    source: { type: 'varchar(64)', notNull: true },
    raw: { type: 'jsonb', notNull: true },
    size_bytes: { type: 'integer', notNull: true },
    content_hash: { type: 'varchar(128)', notNull: true },
    processing: { type: 'boolean', default: false },
    processed_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', default: pgm.func( 'now()' ) }
  } );
  pgm.createIndex( 'hero_snapshots', 'raw', { using: 'gin', method: 'jsonb_path_ops' } );
};

exports.down = ( pgm ) => {
  pgm.dropIndex( 'hero_snapshots', 'raw' );
  pgm.dropTable( 'hero_snapshots' );
};
```

---

## 5. Safe migration patterns

### Three-step safe approach for potentially disruptive changes (recommended)

1. Additive step: Add new nullable column / indexes / tables. No data movement, no exclusive locks.
    - Example: `ALTER TABLE user_profile_summary ADD COLUMN summary_v2 JSONB NULL;`
2. Backfill & verification: Deploy code that writes both old and new columns, backfill data asynchronously via `ETL`
   /backfill jobs, validate parity in staging.
3. Enforce & cleanup: Make column NOT NULL and drop old column in a later migration after backfill verification.

### Index changes

- Use `CREATE INDEX CONCURRENTLY` for large indexes to avoid table locks. When using `node-pg-migrate`, run raw SQL for
  CONCURRENTLY:

```js
pgm.sql( 'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hero_snapshots_raw_gin ON hero_snapshots USING GIN (raw jsonb_path_ops)' );
```

- Note: `CONCURRENTLY` cannot run inside a transaction — adjust migration runner accordingly (`node-pg-migrate` supports
  it with `pgm.sql` but you must not rely on transactional behavior).

### Avoid long exclusive operations

- Avoid `ALTER TABLE ... TYPE` or `ADD COLUMN ... DEFAULT <value>` that rewrite the table. Prefer add nullable column,
  backfill, then set default + NOT NULL.

---

## 6. Extensions & provider considerations

### Preferred extensions

- `pgcrypto` — preferred for `gen_random_uuid()`.
- `uuid-ossp` — fallback for some providers.

### CREATE EXTENSION strategy

- Put extension creation into its own migration at the top:
    - `20251203_create_pgcrypto_extension.js`
- Migration content:

```js
exports.up = ( pgm ) => {
  pgm.sql( "CREATE EXTENSION IF NOT EXISTS pgcrypto;" );
};
exports.down = ( pgm ) => {
  // do not drop extension on down in production-safe path; leave no-op or document
};
```

### Provider limitations

- Managed providers (`Supabase`, `RDS`) may refuse `CREATE EXTENSION`. Preflight must check extension availability;
  fallback:
    - Generate `UUIDs` application-side or use `gen_random_uuid()` only if available.
- Document required provider privileges in migration header and in [docs/MIGRATIONS.md](./MIGRATIONS.md).

---

## 7. Index creation & long-running operations

- Use `CREATE INDEX CONCURRENTLY` for large tables.
- For `node-pg-migrate`, run concurrent index creation via `pgm.sql(...)` outside a transaction. Note: some runners wrap
  migrations in transactions by default — use `pgm.sql` and configure properly.
- For Postgres large index estimate:
    - Estimate rows: `SELECT reltuples::bigint AS approx_rows FROM pg_class WHERE relname='hero_snapshots';`
    - Estimate size: `SELECT pg_relation_size('hero_snapshots')` or use `pgstattuple` if available.

### Index creation checklist

- Schedule during off-peak window.
- Kick off `CREATE INDEX CONCURRENTLY`, monitor progress.
- If using CONCURRENTLY, be aware it still consumes resources (`IO/CPU`).

---

## 8. Partitioning strategy & archival-aware changes

### When to partition

- High-volume append-only tables (`hero_snapshots`) over millions of rows.
- Partition by time (monthly) or by hash(`user_id`) if cardinality increases.

### Partition migration pattern

1. Create parent table with `PARTITION BY RANGE (created_at)` or hash.
2. Create partitions (monthly).
3. Add trigger or default partitioning strategy for new inserts.
4. Backfill older data into partitions in batches.
5. Adjust queries and indexes accordingly.

### Archival considerations

- If archival: create `snapshot_archives` table or mark partitions as archived before deletion.
- Migration to add `archived` metadata should be additive and reversible.

---

## 9. Preflight checks & CI jobs

**Purpose:** detect permission gaps, estimate costs and validate that migrations apply cleanly.

### Preflight script responsibilities (`scripts/migrate-preflight.sh`)

- Verify connectivity (`psql` connection).
- Check extension permissions:
    - `SELECT installed_version FROM pg_available_extensions WHERE name='pgcrypto';`
- Apply migrations to ephemeral test DB
    - Run `node-pg-migrate` against ephemeral DB and verify `schema_migrations` updated.
- Run smoke `ETL`: insert a small sample snapshot and run worker logic or `ETL` smoke script.
- Validate indexing and expected tables existence.

### CI integration

- Add CI job that:
    - Installs deps (`pnpm install --frozen-lockfile`)
    - Runs lint, unit tests
    - Runs `migrate:preflight` (applies migrations to a fresh ephemeral DB) and a smoke test
- Block merge if preflight fails.

### Example preflight checks (shell snippet)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Validate DB connectivity
psql "$DATABASE_URL" -c "SELECT 1"

# Check pgcrypto availability and privileges
psql "$DATABASE_URL" -t -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'pgcrypto';" | grep pgcrypto || echo "pgcrypto not installed"

# Run migrations against ephemeral DB (test)
DATABASE_URL="$TEST_DATABASE_URL" pnpm run migrate:up
# Run smoke queries
psql "$TEST_DATABASE_URL" -c "SELECT count(*) FROM hero_snapshots;"
```

---

## 10. Local developer workflow

### Create new migration

- Use standard filename pattern and put file under `database/migrations/`.
- Populate `exports.up` and `exports.down`.

### Run migrations locally

- Install deps: `pnpm install`
- Configure `.env.local` or `.env` with `DATABASE_URL` (local Postgres).
- Run:

```bash
pnpm run migrate:up -- --config database/migration-config.js
```

(or use your npm scripts wrapper)

### Rollback last migration locally

- `pnpm run migrate:down -- --count 1` (use carefully)

### Testing locally

- Run `./scripts/bootstrap-db.sh` to run migrations and seeds in a fresh local DB (script should be idempotent)
- Run `ETL` smoke: ingest sample file (docs/examples) and start worker to process snapshots.

---

## 11. Production bootstrap workflow (manual, protected)

### Principles

- Migrations for production MUST be applied via a manual, protected `CI` workflow (`db-bootstrap.yml`) requiring
  `GitHub Environment` approval.
- Always take a DB snapshot/backup *immediately before* running production migrations.

### Example GitHub Actions workflow (outline)

```yaml
name: db-bootstrap
on:
  workflow_dispatch:
jobs:
  bootstrap:
    runs-on: ubuntu-latest
    environment: production  # requires approval
    steps:
      - uses: actions/checkout@v3
      - name: Setup Node
        uses: actions/setup-node@v3
      - name: Install deps
        run: pnpm install --frozen-lockfile
      - name: Preflight check
        run: ./scripts/migrate-preflight.sh
        env:
          DATABASE_URL: ${{ secrets.STAGING_DATABASE_URL }}
      - name: Apply migrations (PROD)
        if: ${{ github.event.inputs.apply == 'true' }}
        run: pnpm run migrate:up -- --config database/migration-config.js --env production
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

### Pre-bootstrap checklist (must be done before approval)

- Recent backup id recorded and verified (snapshot successful and tested if possible).
- Migration preflight on staging passed and smoke `ETL` validated.
- `SRE` on-call available and aware of the maintenance window.
- PR includes migration file(s), changelog and rollback plan.
- Expected index creation & time estimates documented in PR.

### Post-bootstrap verification

- Run sanity queries to confirm expected tables & indexes exist.
- Run small sample ingest + end-to-end test.
- Monitor metrics & alerts for `30–120 minutes`.

---

## 12. Rollback & emergency restore strategy

### When to rollback

- Severe data corruption introduced by a migration.
- Production outage caused by migration (locks, incompatibility).
- If rollback migration is not feasible, prefer restore-from-backup.

### Rollback options

- Reversible migrations: run `pnpm run migrate:down` for the specific migration if down exists and verified.
- Restore DB from backup:
    1. Stop ingestion & workers to avoid further writes.
    2. Restore database from snapshot taken before migration.
    3. Re-apply safe migrations or fix code to align with restored schema.
    4. Re-run necessary `ETL`/backfill to bring normalized tables up-to-date.
- Always communicate with stakeholders and log actions in `audit_logs`.

### Emergency steps (short)

1. Pause workers and `API` writes (set read-only mode or flip feature flag).
2. Assess whether `down` migration is safe; if yes run down; if not, prepare restore.
3. If restoring: follow provider procedures for `PITR` or snapshot restore.
4. After restore, run smoke tests, then re-enable ingestion carefully.

---

## 13. Migration PR checklist & review criteria

### Every migration PR must include:

- Migration file(s) in `database/migrations/` with timestamped filenames.
- Description of change, rationale and expected impact (row counts, index costs).
- Preflight results (`CI` artifacts) from staging run.
- Backup id that will be used prior to production run (documented).
- Runbook / rollback steps documented or link to runbook.
- Tests: integration tests that exercise the migration (`CI` passing).
- Approvers: at least two reviewers, one must be `SRE/DevOps` for production-impacting migrations.

### Reviewers should verify:

- Migration is small and focused.
- No destructive changes without phased approach.
- Indexes using CONCURRENTLY are documented and scheduled.
- Required extensions are present or fallback documented.
- A clear rollback plan exists.

---

## 14. Seeding & catalog management

### Seeding

- Keep idempotent seed scripts under `database/seeds/`.
- Seeds should use `INSERT ... ON CONFLICT DO NOTHING` or `ON CONFLICT DO UPDATE` as appropriate.

### Catalog synchronization

- Catalogs (`troop_catalog`, `pet_catalog`, `spells`) should be seeded and versioned.
- When catalog changes require schema changes, coordinate migration and catalog updates in same PR where possible, with
  backfill plan.

### Backfill seeds

- If migration adds new columns requiring backfill, include backfill script as a separate job (not in migration up) and
  track in `backfill_jobs` table.

---

## 15. Testing migrations (unit / integration / e2e)

- Unit: test migration helper functions if any.
- Integration: apply migrations to ephemeral DB in `CI`; run smoke queries and run `ETL` against sample payloads.
- E2E: in staging, apply migrations, run backfills and full `ETL` to validate end-to-end system behavior.
- Include migration tests in PR gating.

---

## 16. Backfill & data-migration jobs coordination

- Backfill tasks are often long-running and should be performed by controlled background jobs, not by migration code
  itself.
- Backfill job steps:
    1. Create new column/table (migration)
    2. Launch backfill job (worker/backfill service) that populates new column in batches.
    3. Validate backfill results with sampling queries.
    4. Release final enforcement migration that sets NOT NULL or drops old columns.
- Track progress in `backfill_jobs` table with checkpoints for resume.

---

## 17. Auditing & migration traceability

- Record migration runs with:
    - migration id, timestamp, runner (`CI`/user), environment, backup id, logs.
- Store artifacts from production run (output logs) in `CI` artifacts storage for audit.
- Keep `schema_migrations` table consistent and never manually alter it except in documented emergency procedures.

---

## 18. Examples: node-pg-migrate templates & preflight script

### 18.1 Migration JS template (`node-pg-migrate`)

```js
// database/migrations/20251203T153000_add_example_table.js
exports.up = ( pgm ) => {
  pgm.createTable( 'example_table', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func( 'gen_random_uuid()' ) },
    name: { type: 'varchar(255)', notNull: true },
    data: { type: 'jsonb', default: pgm.func( "('{}'::jsonb)" ) },
    created_at: { type: 'timestamptz', default: pgm.func( 'now()' ) }
  } );
  pgm.createIndex( 'example_table', 'name' );
};

exports.down = ( pgm ) => {
  pgm.dropIndex( 'example_table', 'name' );
  pgm.dropTable( 'example_table' );
};
```

### 18.2 Preflight script (`scripts/migrate-preflight.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?Need DATABASE_URL}"
echo "Testing DB connectivity..."
psql "$DATABASE_URL" -c "SELECT now();"

echo "Checking pgcrypto extension..."
psql "$DATABASE_URL" -t -c "SELECT extname FROM pg_extension WHERE extname = 'pgcrypto';" | grep -q pgcrypto && echo "pgcrypto present" || echo "pgcrypto missing (provider may not support extension)"

echo "Applying migrations to test database..."
pnpm run migrate:up -- --config database/migration-config.js
echo "Running smoke ETL test..."
# optionally run a smoke script that inserts sample snapshot and triggers local worker
```

---

## 19. Runbooks & operational notes

- Link runbooks in `docs/OP_RUNBOOKS/`:
    - [APPLY_MIGRATIONS.md](./OP_RUNBOOKS/APPLY_MIGRATIONS.md) — exact steps and command lines for running the
      `GitHub Action` and verifying post-run checks.
    - [MIGRATION_ROLLBACK.md](./OP_RUNBOOKS/MIGRATION_ROLLBACK.md) — step-by-step rollback and restore runbook.
    - [BACKFILL.md](./OP_RUNBOOKS/BACKFILL.md) — schedule, throttle, and operator steps to run a backfill safely.

### Operational tip

- For critical migrations requiring owner approval, tag PR with `migration-impact: high` and schedule a 2nd approver.

---

## 20. References

- [docs/DB_MODEL.md](./DB_MODEL.md) (canonical schema)
- [docs/ETL_AND_WORKER.md](./ETL_AND_WORKER.md) (ETL contract)
- `node-pg-migrate`: https://github.com/salsify/node-pg-migrate
- `PostgreSQL` docs: https://www.postgresql.org/docs/
- `Prometheus`: https://prometheus.io/docs/
- `OpenTelemetry`: https://opentelemetry.io/

---
