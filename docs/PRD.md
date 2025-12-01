# Product Requirement Document (PRD) — StarForge

---

## 🔒 Confidentiality Notice

![SENSITIVE](https://img.shields.io/badge/SENSITIVE-DO%20NOT%20SHARE-red?style=for-the-badge)
> ⚠️ This document may contain sensitive information. Do not share outside the approved group.
> Moreover, this is a living document and will be updated as the project evolves.

---

## 🏷 Versioning & Metadata

![Version](https://img.shields.io/badge/version-0.1-blue?style=for-the-badge)
![Date](https://img.shields.io/badge/date-2025--11--26-lightgrey?style=for-the-badge)
![Status](https://img.shields.io/badge/status-Draft-yellow?style=for-the-badge)

### Document Version

- **Version:** `0.1`
- **Date:** `2025-11-26`
- **Status:** **Draft**

### Authors & Contacts

| Role              | Person / Contact                                                                                                                      |
|-------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| Product Owner     | ![PO](https://github.com/CorentynDevPro.png?size=20) **Star Tiflette** — GitHub: [@CorentynDevPro](https://github.com/CorentynDevPro) |
| Technical Lead    | _TBD_                                                                                                                                 |
| Engineering Owner | _TBD_                                                                                                                                 |
| Design Lead       | _TBD_                                                                                                                                 |
| QA Lead           | _TBD_                                                                                                                                 |
| DevOps / SRE      | _TBD_                                                                                                                                 |
| Stakeholders      | **Project Maintainers, small test community**                                                                                         |

> Note: "TBD" stands for "To Be Determined" — role/person not yet assigned.

---

### 📜 Revision History

<details>
<summary>Click to expand revision history</summary>

| Version |       Date | Author                                                                 | Changes Made                                           |
|---------|-----------:|------------------------------------------------------------------------|--------------------------------------------------------|
| 0.1     | 2025-11-26 | Product Owner ([`@CorentynDevPro`](https://github.com/CorentynDevPro)) | Initial draft: metadata, executive summary, objectives |

</details>

---

## **1. Executive Summary**

### **1.1 Purpose of this document**

This PRD describes scope, objectives, functional and non‑functional requirements, and success criteria for StarForge
focusing initially on the player-profile ingestion & database foundation: `migrations`, `safe DB bootstrap`,
`snapshot ingestion`, and `ETL` to normalized tables.

### **1.2 Background & context**

- The game backend provides rich `JSON snapshots` (e.g. `get_hero_profile`). When fetched
  with the `--login` flow these payloads can reach ~2–3 MB per player.
- The repository already contains source for a Discord bot, backend, CI flows, an historical `schema.sql`, and several
  extractor script (`get_hero_profile.sh` / `get_hero_proile.bat` / `get_hero_profile.ps1`).
- We moved sensitive values into **GitHub Actions Secrets** (`DATABASE_URL`, `DISCORD_TOKEN`, etc.) and `sketched CI` +
  a `manual DB bootstrap` workflow.
- We need to replace the ad‑hoc schema approach with a robust migration system (`node-pg-migrate`), implement a
  safe/manual bootstrap, and design a `data model` + `ETL` to handle large profile `JSON` efficiently.

### **1.3 Problem statement**

- Player profile payloads are large and nested; storing them only as raw `JSON` makes querying and analytics slow and
  awkward.
- Current DB bootstrap and schema management is manual and risky for production.
- No formal ETL process to reliably transform snapshots into normalized, indexed tables for common queries.
- Need a versioned migration workflow to safely evolve schema.

### **1.4 Proposed solution (high-level)**

- Adopt `node-pg-migrate` for versioned JS migrations and create an initial migration that:
    - Adds normalized tables (`users`, `hero_snapshots`, `user_troops`, `user_pets`, `user_artifacts`, `user_teams`,
      `guilds`, `guild_members`, `feature_flags`, `profile_summary`, etc.)
    - Creates indexes and enables `pgcrypto` for `gen_random_uuid()`
- Store raw snapshots in `hero_snapshots` (`JSONB`) for audit and reprocessing.
- Provide an idempotent bootstrap script (`scripts/bootstrap-db.sh`) and a manual GitHub Actions workflow (
  `db-bootstrap.yml`) running in a protected environment requiring approval.
- Implement a background ETL worker (queue + worker) that consumes `hero_snapshots` and upserts normalized tables.
  Worker marks snapshots as processed and supports retries.
- Define retention / archive policy for snapshots (e.g. keep N last snapshots per user or 90 days; archive older
  snapshots to `S3`).

### **1.5 Key benefits & value proposition**

- Fast, indexed queries for common needs (who owns troop X, leaderboard queries, quick profile read).
- Reproducible and safer schema evolution via migrations and manual production approval.
- Ability to replay ETL from stored snapshots when mapping changes or bugs require reprocessing.
- Improved observability and operational safety.

### **1.6 Decisions already made / constraints**

- Migration tool: `node-pg-migrate` (JS).
- UUID generation: prefer `pgcrypto` + `gen_random_uuid()` for cloud compatibility (Supabase).
- DB bootstrap workflow: manual (`workflow_dispatch`) and run in a GitHub Environment (e.g., production) to require
  approval.
- Snapshots stored as `JSONB` in Postgres (TOAST compression) with a `GIN` index for search.
- Secrets remain in **GitHub Actions Secrets** (`DATABASE_URL`, `PGSSLMODE`, `DISCORD_TOKEN`, `GOOGLE_SA_JSON`, etc.).

## **2. Objectives & Success Criteria**

### **2.1 Business objectives**

- Enable backend and bot features based on player profiles (team recommendations, inventory tracking, analytics) with
  acceptable latencies.
- Reduce onboarding time for new devs by documenting and automating DB bootstrap and migrations.
- Prevent accidental production schema changes by requiring manual approval for migrations applied to prod.

### **2.2 Product objectives (OKRs)**

> Note: OKRs means Objectives and Key Results. Objectives are high-level goals, and Key Results are measurable outcomes
> that indicate progress toward those goals.

- `O1`: Deliver the migration pipeline and a manual DB bootstrap workflow within 2 sprints.
- `O2`: Implement ETL worker that normalizes at least 90% of the useful fields from get_hero_profile (troops, pets,
  teams, guild info) in the next sprint.
- `O3`: Achieve sub-200ms median response times for core read queries (after normalization and indexing).

### 2.3 Key performance indicators (KPIs) / success metrics

- _Migration reproducibility:_ `100%` success rate for manual runs in staging.
- _ETL throughput:_ baseline `X snapshots/hour` (to be measured), with `target >Y` after optimizations.
- _Storage growth:_ `MB/day` for snapshots; alert when rate exceeds threshold.
- _Query latency:_ `p95` for primary queries `<200ms`.
- _ETL error rate:_ `<1%` (with automated retries and alerting).

### 2.4 Non-goals / Out of scope

- **Full reimplementation** of the game data catalog (troop stats) — catalogs will be added **incrementally**.
- **Automatic application of migrations** on merge to main (deliberately out of scope to keep production safe).
- **Full BI reporting** and **historical analytics** in initial phase (phase 2).

---

## **3. Users & Personas**

This section details the primary and secondary personas for the Player Profile & DB Foundation project, their _goals_
and _pain points_, and the _top-level user journeys_ (main flows and edge/error flows). Use these personas and journeys
to derive user stories, acceptance criteria and implementation priorities.

---

### **3.1 Primary personas**

**Persona: Alex — End Player (Gamer)**

- **Role:** Regular player of the game who expects the bot / web UI to show up-to-date profile information (inventory,
  teams, PvP stats).
- **Motivations:**
    - Quickly view own profile, teams and troop counts inside Discord or web UI.
    - Get recommendations based on current troops and items.
    - Keep track of progress (Guild contributions, PvP rank).
- **Pain points:**
    - Long loading times when the system queries raw JSON or does on-the-fly parsing.
    - Inaccurate or stale information if snapshot ingestion is delayed or fails.
    - Concern about privacy if login flows are used insecurely.
- **Success for this feature:**
    - Profile and quick summary are available in <200ms p95 after ETL has completed (or served from summary cache).
    - The player can request a fresh snapshot and get predictable results.
    - No loss or leak of credentials when using login-based fetches.

**Persona: Gwen — Guild Leader / Moderator**

- **Role:** Community leader using summaries/analytics to manage guild activity and rewards.
- **Motivations:**
    - Quickly see guild members’ contribution and top performers.
    - Identify members missing required troops or assets.
- **Pain points:**
    - Hard-to-run queries that require parsing raw JSON every time.
    - Difficulty getting a consistent, searchable view of all guild members.
- **Success for this feature:**
    - Ability to query and generate guild-level reports from normalized data (e.g. total troop counts, top
      contributors).
    - Dashboard or commands return results with low latency and consistent data freshness.

**Persona: Dev (Backend Engineer) — Jordan**

- **Role:** Maintains backend services and ETL worker, writes migrations, debugs ingestion problems.
- **Motivations:**
    - Clear, versioned migrations and safe bootstrap for local/staging/prod.
    - Idempotent ETL tasks and clear logs / retries when things go wrong.
    - Fast developer onboarding (scripts, .env.example, sample data).
- **Pain points:**
    - Fragile manual schema application (schema.sql) that is hard to evolve.
    - Inconsistent or undocumented ETL transformations causing regressions.
- **Success for this feature:**
    - Migrations applied reproducibly in staging and safely in production using manual approval.
    - Comprehensive tests and example flows (sample JSON -> ETL -> normalized tables).
    - Worker is idempotent and can reprocess snapshots safely.

**Persona: Data Analyst — Morgan**

- **Role:** Runs analytics, builds reports and dashboards on player behavior and inventory distributions.
- **Motivations:**
    - Query normalized tables instead of messy JSON blobs.
    - Get fresh data for near-real-time analytics.
- **Pain points:**
    - Needing to write complex JSON path queries over JSONB instead of simple SQL aggregations.
    - Unclear or inconsistent schema mapping from snapshots to normalized tables.
- **Success for this feature:**
    - Clean schema with indexes and documented fields for analytics.
    - ETL produces consistent, dated snapshots and retains historic progress for time-series analysis.

**Persona: Bot Operator / Community Tools Admin — Riley**

- **Role:** Operates the Discord bot, runs slash command deployments and maintenance.
- **Motivations:**
    - Bot commands return profile data quickly and reliably.
    - Simple process to deploy updated slash commands and react to data model changes.
- **Pain points:**
    - Backend downtime or schema mismatches causing bot failures.
    - Lack of a safe workflow to update DB schema used by bot.
- **Success for this feature:**
    - Bot continues to function across releases thanks to stable APIs and profile_summary table.
    - Admins have runbooks to re-run ETL or roll back schema changes.

---

### 3.2 Secondary personas / stakeholders

- **Product Owner (PO)**
    - _Responsibilities:_ prioritize features, define acceptance criteria, sign off releases.
    - _Interest:_ business value, time-to-market, cost.

- **DevOps / SRE**
    - _Responsibilities:_ CI/CD, infrastructure, environment protection, backups.
    - _Interest:_ safe migrations, secrets management, monitoring & alerts.

- **QA Engineer**
    - _Responsibilities:_ test plans, test data, acceptance testing for migrations and ETL.
    - _Interest:_ reproducible test environments, sample payloads, rollback tests.

- **Security Officer / Privacy Officer**
    - _Responsibilities:_ ensure credentials & PII handled correctly, audits and compliance (GDPR).
    - _Interest:_ secrets lifecycle, encryption, data retention policy.

- **Legal / Compliance**
    - _Responsibilities:_ privacy policies, data residency constraints.
    - _Interest:_ retention rules and user consent flows.

- **Integration Providers (Supabase, Discord)**
    - _Responsibilities:_ external services support and limits (extensions, rate limits).
    - _Interest:_ compatibility, permissioning (e.g. CREATE EXTENSION restrictions).

- **Community Manager**
    - _Responsibilities:_ communicates changes to users, organizes beta testers.
    - _Interest:_ rollout plan, user-facing docs.

---

### 3.3 User journeys (top-level)

Below are the **primary user journeys** grouped by actor. Each journey contains `preconditions`, `main flow`,
`success criteria`,
`typical metrics to monitor`, and common `edge/error flows` & recovery steps.

**Journey A — Player requests profile snapshot by NameCode (interactive fetch)**

- _Actor(s):_ Player (Alex), System (API script / backend)
- _Preconditions:_
    - Player has a `NameCode` / `invite code`.
    - The fetch script or frontend has access to a stable `API endpoint` (pcmob.parse.gemsofwar.com or internal proxy).
    - No secrets required from the player for NameCode fetch.
- _Trigger:_
    - Player issues a request via the `CLI` script, `web UI` or a `bot command` to fetch profile by NameCode.
- _Main flow:_
    1. Client calls `API function get_hero_profile` with NameCode.
    2. Response (`JSON`) saved to `hero_snapshots` as a new row (`raw JSONB`, source="fetch_by_namecode", size_bytes
       recorded).
    3. Push `snapshot id` to `ETL queue`.
    4. `ETL worker` picks up job, parses `JSON`, upserts `users`, `user_troops`, `user_pets`, `user_teams`, `guilds`,
       etc.
    5. `ETL` updates or creates `user_profile_summary` with denormalized quick-read fields.
    6. Bot or UI fetches `profile_summary` (or `hero_snapshots.latest` if needed) and returns to player.
- _Success criteria:_
    - Snapshot saved and queued within X seconds of `API response`.
    - `ETL worker` processes snapshot and updates summary within `configurable SLA` (e.g., < 30s for interactive flows;
      asynchronous acceptable for larger loads).
    - Player sees consistent, accurate data in the bot/UI.
- _Metrics:_
    - Snapshot `ingestion time`, `queue latency`, `ETL processing time`, `API latency`, `summary query latency`.
- _Edge / error flows:_
    - `API` returns partial or malformed `JSON` → snapshot saved but `ETL` fails; mark `snapshot.processing=false`,
      processed_at=NULL, create error record with `logs`; notify DevOps/Dev.
    - Snapshot size large but within expected range → worker uses `stream/parsing memory-safety`; if memory spike →
      worker OOM: automatic retry with smaller memory footprint, escalate.
    - `Rate-limited` by upstream: schedule retry and notify user about delay.

**Journey B — Player login flow (--login) that produces larger payloads**

- _Actor(s):_ Player (Alex), System (login endpoint), Security Officer (policy)
- _Preconditions:_
    - Player provides credentials interactively (local script) — must never be committed in scripts.
    - Credentials used only locally or via a `secure ephemeral agent`; we do not store user passwords in our DB.
- _Trigger:_
    - Player runs `get_hero_profile.sh --login` and authenticates with game backend.
- _Main flow:_
    1. Script posts `login_user` payload; upstream returns a large result `JSON` (2–3MB).
    2. Script stores login response (`login_user_*.json`) and may extract NameCode automatically using `jq`.
    3. If NameCode found, the script runs `get_hero_profile` with the NameCode to obtain final profile.
    4. Save snapshot to `hero_snapshots` and follow `ETL` as in Journey A.
- _Success criteria:_
    - Login and fetch complete without exposing credentials.
    - `ETL` processes large payloads without timeouts / resource exhaustion.
- _Special concerns:_
    - Privacy & credentials: never store passwords; if tokens are produced by upstream (session tokens), only store them
      if required and encrypted — prefer not to store service tokens in hero_snapshots.
    - Big payload handling: ETL must be resource-aware and possibly chunk processing (avoid loading whole payload into
      memory when unnecessary).
- _Edge / error flows:_
    - Upstream blocks extension creation during subsequent DB operations (see `migrations`) — worker must log the issue
      and the bootstrap must offer fallback.
    - If `jq` not present locally, script must inform user how to extract NameCode manually — include instructions in
      README.

**Journey C — Developer local setup & bootstrap DB**

- _Actor(s):_ Dev (Jordan)
- _Preconditions:_
    - Developer cloned repository, has `Node/PNPM` installed, has a local Postgres instance or connection string.
    - .env.example filled with `DATABASE_URL` and `PGSSLMODE` if necessary.
- _Trigger:_
    - Developer runs `./scripts/bootstrap-db.sh` or `pnpm run db:bootstrap` to initialize schema and seeds.
- _Main flow:_
    1. Script checks env vars and tools (`pnpm`, `psql`).
    2. Runs `pnpm install --frozen-lockfile`.
    3. Runs migrations via `node-pg-migrate up --config database/migration-config.js`.
    4. Runs seed `SQL` files idempotently.
    5. Optionally inserts sample snapshot(s) from `examples/get_hero_profile_*.json` to test `ETL`.
    6. Start worker locally (e.g., `pnpm run worker`) to process snapshots.
- _Success criteria:_
    - Migrations run without errors on local DB.
    - Seeds applied idempotently.
    - Example snapshot processed, normalized tables populated.
- _Edge / error flows:_
    - Missing dependencies (`pnpm`) → script fails with clear guidance to install.
    - CREATE EXTENSION `uuid-ossp` / `pgcrypto` permission denies → script explains fallback and documents manual DBA
      steps (ask provider to enable extension or use `gen_random_uuid()`).
    - Migration partially applied and fails halfway → migrations are transactional; if not, document manual rollback
      steps and ensure tests cover this.

**Journey D — Admin applies DB bootstrap in production (manual GitHub Action)**

- _Actor(s):_ DevOps / PO / Authorized Engineer
- _Preconditions:_
    - Repository secrets configured (`secrets.DATABASE_URL`, `secrets.PGSSLMODE`).
    - Environment protection set up (GitHub Environments) and access to approve runs.
- _Trigger:_
    - Authorized user triggers GitHub Action workflow (`workflow_dispatch`) to bootstrap DB.
- _Main flow:_
    1. Workflow runs checkout, setup `node` & `pnpm`, installs deps.
    2. It sets `DATABASE_URL` and `PGSSLMODE` from secrets into environment.
    3. Runs `pnpm run migrate:up` (`node-pg-migrate`) to apply migrations.
    4. Runs seeds and validates by listing tables or running sanity queries.
    5. Logs and artifacts stored; if environment requires approval, job waits until approved.
- _Success criteria:_
    - Migrations applied and verified via post-run sanity checks.
    - No destructive operations performed without explicit manual approval.
- _Edge / error flows:_
    - Migration fails due to missing extension permission → abort and log cause; provide remediation steps (request
      extension enabling from provider or run alternate migration).
    - Secrets are misconfigured → workflow fails early with clear error; do not leak secrets in logs.
    - If workflow times out: workflow status = failed, notify stakeholders and provide snapshot of DB state.

**Journey E — ETL Worker processes snapshots**

- _Actor(s):_ `ETL` Worker (background service), `Queue system` (Redis/BullMQ)
- _Preconditions:_
    - Snapshot saved in `hero_snapshots` with `processing=false`.
    - Queue and worker services are running and have access to `DATABASE_URL`/`PGSSLMODE`.
- _Main flow:_
    1. On insertion of hero_snapshots row, enqueue snapshot id.
    2. Worker atomically marks `row.processing=true` (optimistic lock) to claim job.
    3. Worker parses raw JSON in stream-safe manner and upserts:
        - `users` (namecode, username, summary)
        - `user_troops` (upsert per troop_id)
        - `user_pets`, `user_artifacts`
        - `guilds` & `guild_members`
        - `user_profile_summary` (denormalized)
    4. Worker writes audit/log entries for changes and sets `processed_at` timestamp and `processing=false`.
    5. Worker emits telemetry: `processed_count`, `duration`, `errors`.
- _Success criteria:_
    - Worker marks snapshot processed and normalized tables reflect data consistently.
    - Worker is idempotent: reprocessing same snapshot does not duplicate or corrupt data.
- _Edge / error flows:_
    - Snapshot `JSON` malformed → worker logs error, writes to error queue and marks snapshot with error metadata (
      `error_message`, `error_count`). Trigger alert if error rate exceeds threshold.
    - Partial failure during upsert (e.g., FK violation due to missing catalog row) → worker should roll back the
      transaction for that entity and optionally continue with others; record failure for manual review.
    - Upstream likely to produce new fields → worker should ignore unknown fields by default and write the raw snapshot
      so reprocessing is possible.

**Journey F — Bot command / UI reads profile summary**

- _Actor(s):_ Bot Operator (Riley), Player (Alex)
- _Preconditions:_
    - `user_profile_summary` row exists for the user (`ETL` completed).
    - `API route` or DB read permission in place for the bot server.
- _Main flow:_
    1. User triggers bot command /profile or web UI loads profile.
    2. Backend queries `user_profile_summary`; on cache miss, fallback to latest `hero_snapshots` processed row and
       render minimal view.
    3. Return formatted data (teams, equipped pet, top troops).
- _Success criteria:_
    - Bot command responds within target latency (`p95 < 200ms`).
    - Data is consistent with latest processed snapshot.
- _Edge / error flows:_
    - No `profile_summary` exists → fall back to latest processed `hero_snapshots` or respond with friendly message (
      e.g., "Profile not processed yet; try again in a minute").
    - DB query times out → bot returns an error and logs to monitoring.

**Journey G — Data analyst / reporting flow**

- _Actor(s):_ Data Analyst (Morgan)
- _Preconditions:_
    - Normalized data present in tables; historical `user_progress` snapshots exist.
    - Access controls and read-only DB users available for analytics queries.
- _Main flow:_
    1. Analyst runs queries/aggregations on normalized tables (e.g., troop distribution, top players).
    2. Queries use indexes and materialized views if provided.
    3. For heavier `BI` runs, analyst may extract data to a warehouse.
- _Success criteria:_
    - Queries complete in reasonable time (depends on dataset size); heavy analytics offloaded to dedicated worker or
      snapshot export.
- _Edge / error flows:_
    - Analyst needs a field not yet normalized → request to dev team to extend `ETL` or use `JSONB` queries as a 
      stopgap.
    - Very large scans → recommend creating materialized views or exporting to data warehouse.

---

## Edge flows and error handling (cross-cutting)

Below are generalized edge/error conditions that affect multiple journeys, with recommended recovery/mitigation steps.

1. Malformed or truncated JSON
    - Behavior: ETL fails to parse; worker records error and marks snapshot with error metadata.
    - Mitigation:
        - Keep raw snapshot for debugging.
        - Worker writes detailed error logs and a searchable error table.
        - Provide a rerun endpoint / worker command to reattempt reprocessing after fixes.

2. Upstream rate limiting or timeouts
    - Behavior: fetch scripts fail intermittently.
    - Mitigation:
        - Implement exponential backoff and retry policies in the fetch client.
        - Expose an ETA to user when request is delayed.
        - Respect upstream rate limits, log upstream status.

3. Large payload memory pressure (2–3MB or more)
    - Behavior: Worker OOM or degraded latency.
    - Mitigation:
        - Stream JSON parsing where possible; avoid loading whole payload as a single in-memory object.
        - Break ETL into smaller per-entity transactions; publish partial progress.
        - Monitor memory usage and provide autoscaling for worker pool.

4. CREATE EXTENSION permission denied (uuid-ossp / pgcrypto)
    - Behavior: migration fails on extension creation.
    - Mitigation:
        - Use pgcrypto/gen_random_uuid() by default (less often blocked on Supabase).
        - Document fallback steps in bootstrap script and MIGRATIONS.md.
        - For providers that forbid extension creation, document required provider-side ops or use alternative ID
          generation.

5. Missing or misconfigured secrets (DATABASE_URL, PGSSLMODE)
    - Behavior: bootstrap workflow fails early; logs should not leak secrets.
    - Mitigation:
        - Validate secrets in workflow pre-check step and fail fast with actionable message.
        - Use GitHub-enforced environments and secrets policies; rotate keys periodically.

6. Concurrent migrations / long-running migration locks
    - Behavior: schema upgrades might block workers or queries.
    - Mitigation:
        - Make migrations idempotent and short; avoid long-running table rewrites where possible.
        - Use maintenance windows for high-risk changes and communicate to stakeholders.
        - Provide migration rollback plan and DB backups.

7. Duplicate snapshot submissions
    - Behavior: same snapshot inserted multiple times (identical raw content).
    - Mitigation:
        - Compute and store content hash (e.g., SHA256) on hero_snapshots and use uniqueness constraints to avoid
          duplicates; still support duplicates if needed but mark as duplicates.
        - ETL idempotency: worker uses snapshot id to ensure a single processed outcome.

8. Data privacy & credential leakage
    - Behavior: login flows may produce tokens or personal info.
    - Mitigation:
        - Never persist user passwords. If upstream returns session tokens, treat them as secrets and only store if
          strictly required and encrypted.
        - Mask PII in logs; redact tokens and other sensitive fields.
        - Document retention and deletion policy (Data Retention doc).

9. Partial ETL due to schema mismatch
    - Behavior: new fields are added upstream that worker doesn’t understand; upsert can fail due to FK references.
    - Mitigation:
        - Worker should ignore unknown fields by default and capture them under an `extra` JSONB column.
        - Maintain comprehensive tests with sample payloads (cover old and new payload shapes).
        - Provide a reprocessing flow after migration to populate new columns.

---

## Acceptance criteria & "done" checklist for journeys

These criteria should be used by QA/Product to mark features done for the Player Profile & DB Foundation scope:

- hero_snapshots creation:
    - [ ] Raw snapshots inserted reliably for both NameCode fetch and login fetch.
    - [ ] size_bytes recorded and a content hash stored.
- ETL worker:
    - [ ] Worker processes snapshots and sets processed_at on completion.
    - [ ] Upserts are idempotent: reprocessing a snapshot produces no duplicate rows.
    - [ ] Worker writes meaningful logs on success/failure and emits metrics.
- Normalized schema:
    - [ ] users, user_troops, user_pets, user_artifacts, user_teams, guilds, guild_members, user_profile_summary exist
      with indexes.
    - [ ] A small sample JSON (provided) can be processed end-to-end in local setup.
- Developer experience:
    - [ ] scripts/bootstrap-db.sh runs locally, applies migrations and seeds idempotently.
    - [ ] .env.example documents required variables and example values (non-sensitive).
- Operational safety:
    - [ ] db-bootstrap GitHub Action is manual, reads secrets only from GitHub Secrets and runs in protected environment
      requiring approval.
    - [ ] Backups and rollback runbooks exist and tested.
- Security & privacy:
    - [ ] No credentials are stored in plaintext; logging redacts tokens/PII.
    - [ ] Data retention policy documented.

---

## 4. User Stories & Use Cases

This section translates the product goals, personas and user journeys into concrete epics, prioritized user stories with
acceptance criteria (Given/When/Then) and detailed use cases. Use this section to populate backlog tickets and to drive
implementation, QA and acceptance.

---

### 4.1 Epics

Each epic groups related functionality into a deliverable area. Use them as high‑level backlog buckets.

- EPIC-DB-FOUNDATION
    - Goal: Establish a reproducible, versioned database foundation (migrations, bootstrap, seeds) and developer
      onboarding.
    - Includes: node-pg-migrate integration, bootstrap scripts, CI workflow for manual/protected bootstrap, seed data
      and sample payloads.

- EPIC-SNAPSHOT-INGESTION
    - Goal: Reliably store raw player profile snapshots (JSONB) with metadata and deduplication, and provide
      retention/archival policy.
    - Includes: hero_snapshots table, content hashing, source attribution, size and server_time capture, duplicate
      detection.

- EPIC-ETL-WORKER
    - Goal: Background worker that normalizes snapshots into indexed relational tables, is idempotent, resilient and
      observable.
    - Includes: queue design, claim/processing semantics, per-entity upserts (users, user_troops, user_pets,
      user_artifacts, user_teams, guilds), error handling and reprocess API.

- EPIC-API-BACKEND & BOT
    - Goal: Provide low-latency read APIs and bot commands that use denormalized summary tables with graceful fallback
      to raw snapshots.
    - Includes: /profile/summary endpoint, bot slash command, admin endpoints (reprocess, health).

- EPIC-ANALYTICS & EXPORTS
    - Goal: Enable analysts to query normalized data, create materialized views for heavy aggregations and export data
      for BI.
    - Includes: materialized views, export jobs, schema documentation.

- EPIC-DEVEX & DOCS
    - Goal: Developer experience and onboarding documentation to run migrations, local bootstrap, worker and test ETL
      with sample payloads.
    - Includes: docs/DB_MIGRATIONS.md, docs/ETL_AND_WORKER.md, scripts/bootstrap-db.sh, ingest-sample.sh.

- EPIC-SECURITY & PRIVACY
    - Goal: Ensure credentials and PII are never leaked or stored insecurely, document retention and GDPR
      considerations, redact secrets in logs.
    - Includes: logging rules, retention policy implementation, secrets handling guidelines.

- EPIC-OBSERVABILITY & OPERATIONS
    - Goal: Provide metrics, alerts and runbooks for ETL and DB bootstrap operations, enable safe on-call operations.
    - Includes: Prometheus metrics, health endpoints, runbooks/incident procedures.

---

### 4.2 User stories (with acceptance criteria)

Stories are grouped by epic and prioritized (P0 = must-have, P1 = important, P2 = nice-to-have). Each story includes a
short description and acceptance criteria formatted as Given/When/Then.

EPIC-DB-FOUNDATION

- STORY-DB-001 — Add versioned migrations using node-pg-migrate (P0)
    - Description: Add node-pg-migrate configuration and initial migration(s) creating normalized schema and
      hero_snapshots table, using pgcrypto/gen_random_uuid().
    - Acceptance:
        - Given a fresh Postgres instance and a valid DATABASE_URL, when the dev runs `pnpm migrate:up`, then migrations
          complete without error and expected tables (users, hero_snapshots, user_troops, user_pets, user_artifacts,
          user_teams, guilds, guild_members, user_profile_summary, feature_flags) exist.

- STORY-DB-002 — Add bootstrap script & protected GitHub Action (P0)
    - Description: Provide scripts/bootstrap-db.sh and a manual GitHub Action workflow (workflow_dispatch) that runs
      migrations and seeds using repository secrets and environment protection.
    - Acceptance:
        - Given secrets configured and approver permissions, when a maintainer triggers the workflow, then it completes
          successfully and runs a sanity check query (e.g., lists expected tables) and stores logs as artifacts.

- STORY-DB-003 — Provide idempotent seed and schema validation (P1)
    - Description: Ensure seed scripts are idempotent and include schema validation checks to confirm critical indexes
      and extensions.
    - Acceptance:
        - Given seeds run multiple times, when executed again, then database state remains consistent and idempotent
          without duplicate rows.

EPIC-SNAPSHOT-INGESTION

- STORY-SNAP-001 — Persist raw snapshot with metadata (P0)
    - Description: On every fetch/login response, persist the raw JSON into hero_snapshots JSONB along with size_bytes,
      content_hash (SHA256), source, server_time (if present).
    - Acceptance:
        - Given a valid response JSON, when backend inserts snapshot, then hero_snapshots contains a row with raw JSON,
          size_bytes > 0, content_hash set and created_at timestamp present.

- STORY-SNAP-002 — Duplicate detection / short-window dedupe (P1)
    - Description: If identical snapshot payload (same content_hash) is submitted within a configurable short window (
      e.g., 60s), mark as duplicate instead of inserting a full second row.
    - Acceptance:
        - Given identical payloads submitted twice within the dedupe window, when the second insertion occurs, then a
          duplicate record link or duplicate_count is recorded and no duplicate raw row is inserted.

- STORY-SNAP-003 — Snapshot ingest API and CLI integration (P0)
    - Description: Provide backend endpoint and client scripts that call it; CLI (get_hero_profile.sh) should save
      output and optionally POST to ingestion endpoint or store locally.
    - Acceptance:
        - Given a successful get_hero_profile result, when CLI runs in non-login mode, then file is saved locally and
          optionally posted to ingestion endpoint when configured.

EPIC-ETL-WORKER

- STORY-ETL-001 — Background worker: claim/process/update (P0)
    - Description: Implement a queue+worker which atomically claims a snapshot (processing flag), parses it, upserts
      normalized tables and sets processed_at. Worker must be idempotent.
    - Acceptance:
        - Given hero_snapshots row with processing=false, when worker processes it, then processed_at is set,
          processing=false and normalized tables reflect parsed data; re-running worker on the same snapshot does not
          create duplicates.

- STORY-ETL-002 — Stream-aware parsing for large payloads (P1)
    - Description: ETL must handle large payload arrays (troops) without fully loading JSON into memory; use streaming
      or chunked processing where applicable.
    - Acceptance:
        - Given a ~3MB snapshot processed on a low-memory instance, when worker runs, then process completes without
          memory OOM and within a reasonable time.

- STORY-ETL-003 — Preserve unmapped fields to `extra` JSONB (P1)
    - Description: Unknown/new fields in upstream payload are stored under `extra` JSONB fields in relevant normalized
      rows to allow later reprocessing/analysis.
    - Acceptance:
        - Given a snapshot contains fields not mapped in the schema, when worker upserts, then those fields are saved
          under `extra` on the appropriate entity row and do not cause failures.

- STORY-ETL-004 — Partial-upsert strategy & compensating actions (P1)
    - Description: ETL should perform per-entity transactions so a failure on one entity does not roll back unrelated
      entities; capture failed entity errors for manual review.
    - Acceptance:
        - Given a snapshot where user_troops upsert fails due to unexpected FK, when worker processes snapshot, then
          user and other entities are still upserted and an error record is created for the failing entity.

- STORY-ETL-005 — Reprocess API for admins (P1)
    - Description: Admin endpoint to enqueue a snapshot for reprocessing; endpoint requires authentication and logs the
      action.
    - Acceptance:
        - Given snapshot id exists, when an admin posts reprocess request, then snapshot is enqueued and a job id or 202
          response is returned.

EPIC-API-BACKEND & BOT

- STORY-API-001 — Fast profile summary endpoint (P0)
    - Description: Implement GET /api/profile/summary/:namecode returning denormalized fields from user_profile_summary;
      fallback to latest hero_snapshot processed row.
    - Acceptance:
        - Given a processed profile, when GET /profile/summary/:namecode is called, then the service returns the summary
          and p95 response time is <200ms in staging.

- STORY-API-002 — Bot slash command `/profile <namecode>` (P0)
    - Description: Bot command which calls the summary API and formats a short embed for Discord (level, top troops,
      equipped pet).
    - Acceptance:
        - Given summary exists, when player executes slash command, then bot replies with formatted embed within the bot
          command timeout window.

- STORY-API-003 — Friendly fallback when profile pending (P1)
    - Description: If a summary is not available, API returns 202 with an ETA message or returns best-effort data from
      latest processed snapshot and indicates freshness.
    - Acceptance:
        - Given no summary yet, when API invoked, then response communicates status (202 or best-effort) and includes
          next estimated processing ETA.

EPIC-ANALYTICS & EXPORTS

- STORY-AN-001 — Materialized view for troop ownership (P2)
    - Description: Build a materialized view summarizing troop ownership counts and last_updated times to speed
      analytics queries.
    - Acceptance:
        - Given data in user_troops, when view is refreshed, then queries for top owners return in acceptable query time
          and reflect recent data after refresh.

- STORY-AN-002 — Export job to S3 (P2)
    - Description: Implement job to export normalized tables (CSV/Parquet) to S3 for BI ingestion.
    - Acceptance:
        - Given an export request, when the job runs, then export files appear in S3 and contain expected columns, with
          an audit entry.

EPIC-DEVEX & DOCS

- STORY-DEV-001 — Provide sample JSONs and ingest script (P0)
    - Description: Include representative get_hero_profile JSON samples and a script to insert them into a local DB and
      trigger local worker.
    - Acceptance:
        - Given local DB and worker, when developer runs ingest sample script, then normalized tables populate and
          manual verification queries succeed.

- STORY-DEV-002 — Developer onboarding doc (P0)
    - Description: docs/DB_MIGRATIONS.md and docs/ETL_AND_WORKER.md with step-by-step local setup, env vars, and common
      troubleshooting.
    - Acceptance:
        - A new developer following docs can bootstrap local DB and process a sample snapshot without outside help.

EPIC-SECURITY & PRIVACY

- STORY-SEC-001 — Redact tokens and never persist passwords (P0)
    - Description: Ensure scripts and worker never persist raw credentials; redact tokens in logs and redact PII
      according to policy.
    - Acceptance:
        - Given a snapshot containing tokens/PII, when storing or logging, then passwords are never saved, tokens are
          redacted and logs do not contain raw secret strings.

- STORY-SEC-002 — Implement snapshot retention & archival job (P1)
    - Description: Background job to archive or delete snapshots older than retention threshold (e.g., 90 days) and
      document policy.
    - Acceptance:
        - Given snapshots older than retention, when retention job runs, then snapshots are archived to S3 (or deleted)
          and audit entries exist.

EPIC-OBSERVABILITY & OPERATIONS

- STORY-OPS-001 — ETL metrics & health endpoint (P1)
    - Description: Worker exposes metrics (processed_count, failure_count, duration_histogram) and a /health endpoint
      for orchestration.
    - Acceptance:
        - Metrics are scraped by Prometheus and show non-zero values after processing; alerts trigger when
          failure_rate > configured threshold.

- STORY-OPS-002 — Runbook for DB bootstrap and ETL incident (P1)
    - Description: Create runbooks with steps for manual intervention: how to re-run migrations safely, how to
      re-enqueue snapshots, how to roll back.
    - Acceptance:
        - On-call can follow runbook to safely re-run ETL or bootstrap with minimal assistance.

---

### 4.3 Detailed use cases

Use cases describe step-by-step flows, actors, preconditions, main flows, alternative flows and postconditions. These
are more detailed than user stories and map to acceptance tests.

#### UC-100 — Fetch profile by NameCode

- ID: UC-100
- Actors: Player (Alex), Ingestion API (or local CLI that posts), Backend, DB (hero_snapshots), ETL Worker, Bot/UI
- Preconditions:
    - Player provides a valid NameCode.
    - System has network access to upstream get_hero_profile endpoint or the player runs CLI to fetch and POST the
      result.
- Main flow:
    1. Player uses CLI or UI to request profile by NameCode.
    2. System (client) calls upstream get_hero_profile and receives JSON body and response headers.
    3. System computes content_hash (SHA256) and size_bytes.
    4. If a snapshot with same content_hash exists within dedupe window, mark as duplicate and link; else insert into
       hero_snapshots with metadata: source="fetch_by_namecode", created_at, server_time.
    5. System enqueues snapshot id into processing queue.
    6. Worker claims snapshot (atomic update processing=true).
    7. Worker parses snapshot:
        - Upsert users table (user row keyed by NameCode/Id).
        - Upsert user_troops (amount, level, rarity, fusion_cards, traits_owned, extra).
        - Upsert user_pets, user_artifacts.
        - Upsert user_teams (array of troop ids), guilds and guild_members if present.
        - Update user_profile_summary with denormalized fields (level, top 5 troops, equipped pet, PvP tier, guild
          name).
    8. Worker sets processed_at and clears processing flag; emits metrics.
    9. Bot/UI queries /profile/summary and returns the summary to the player.
- Alternative flows:
    - Upstream failure (network or rate limit): client retries with backoff; no snapshot inserted until successful or
      cached error logged.
    - Snapshot malformed: worker records error metadata, does not set processed_at; admin alerted if repeated failures.
    - Duplicate snapshot detected: system increments duplicate counter and optionally returns existing snapshot id to
      client.
- Postconditions:
    - hero_snapshots contains an inserted or linked snapshot record.
    - Normalized tables reflect the snapshot if ETL succeeded.
    - Metrics recorded for ingestion latency and ETL time.

#### UC-101 — Login-based profile fetch (large payload)

- ID: UC-101
- Actors: Player (Alex), CLI script, Upstream login endpoint, Ingestion API/Backend, DB, ETL worker
- Preconditions:
    - Player runs get_hero_profile.sh --login locally and supplies credentials in interactive prompt.
    - CLI prompts must not persist passwords anywhere on disk or in repo.
- Main flow:
    1. CLI posts login_user payload to upstream and receives a login response containing session info and possibly
       NameCode.
    2. CLI saves the login response locally (file) for debugging; it should not POST credentials to ingestion service.
    3. If NameCode present or if CLI requests final profile, CLI triggers get_hero_profile call to retrieve large
       profile JSON (~2–3MB).
    4. Follow UC-100 main flow to insert snapshot and process.
- Alternative flows:
    - jq missing locally: CLI instructs the user to install jq or to extract NameCode manually and aborts.
    - Upstream returns token: CLI redacts token when saving to file and does not persist tokens in ingestion system
      unless explicitly authorized and encrypted.
- Postconditions:
    - Snapshot stored and queued; no passwords persisted.
    - Large snapshot processed by ETL in streaming/chunked manner.

#### UC-102 — Developer local bootstrap and sample processing

- ID: UC-102
- Actors: Developer, Local Postgres, Scripts (bootstrap-db.sh, ingest-sample.sh), ETL worker
- Preconditions:
    - Developer has Node, pnpm, local Postgres or remote dev DB, and .env configured with DATABASE_URL.
- Main flow:
    1. Developer runs bootstrap script.
    2. Script validates env vars, installs dependencies, runs migrations and idempotent seeds.
    3. Developer runs ingest-sample.sh which inserts an example JSON into hero_snapshots.
    4. Developer starts local worker; worker processes snapshot and populates normalized tables.
    5. Developer validates by running SQL queries against user_profile_summary and user_troops.
- Alternative flows:
    - Missing pg extension permission: script prints instructions and suggests a manual step or alternative UUID
      generation.
    - Seed fails: script aborts with an error and rollbacks partial seeds.
- Postconditions:
    - Local DB schema and seeds applied; sample snapshot processed.

#### UC-103 — Admin reprocess snapshot

- ID: UC-103
- Actors: Admin, Admin API, Queue, Worker
- Preconditions:
    - Admin has auth to call admin endpoints.
    - Snapshot id exists in hero_snapshots.
- Main flow:
    1. Admin calls POST /admin/snapshots/:id/reprocess.
    2. API validates admin rights and snapshot existence.
    3. API clears snapshot error flags, resets processed_at if needed, and enqueues snapshot id.
    4. Worker picks up job and processes idempotently.
    5. System returns job status and logs.
- Alternative flows:
    - Snapshot in-progress: API returns 409 and informs admin.
    - Snapshot not found: API returns 404.
- Postconditions:
    - Snapshot reprocessed and normalized tables updated.

#### UC-104 — Retention & archival of old snapshots

- ID: UC-104
- Actors: Cron retention job, DB, S3 (archive store)
- Preconditions:
    - Retention policy configured (days or keep last N snapshots per user).
- Main flow:
    1. Retention job selects hero_snapshots older than retention threshold and not flagged as permanent.
    2. For each snapshot: compress and upload raw JSON to S3, store archival metadata (s3_path, archived_at) and then
       delete or mark archived in DB.
    3. Job logs success and raises alert on failures.
- Alternative flows:
    - S3 temporarily unavailable: job retries with exponential backoff and logs failures; if persistent, escalate.
- Postconditions:
    - Old snapshots are archived and DB storage reduced, with audit entries retained.

#### UC-105 — Materialized view refresh & analytics export

- ID: UC-105
- Actors: Analyst, Export Job, Materialized Views
- Preconditions:
    - Normalized data exists in user_troops and related tables.
- Main flow:
    1. Analyst triggers materialized view refresh or scheduled job refreshes it.
    2. Analyst runs a query against materialized view for aggregated insights (e.g., troop ownership counts).
    3. For large export, analyst requests export job which writes data to S3.
- Alternative flows:
    - View refresh collides with heavy DB load: refresh is scheduled during off-peak or uses CONCURRENTLY option where
      supported.
- Postconditions:
    - Materialized view is up-to-date and exports are available on S3.

#### UC-106 — Migration permission failure handling

- ID: UC-106
- Actors: Maintainer, GitHub Actions, Database provider
- Preconditions:
    - Migrations contain extension creation (CREATE EXTENSION IF NOT EXISTS pgcrypto).
- Main flow:
    1. Workflow runs and attempts to create extension.
    2. DB provider denies permission; migration fails.
    3. Workflow captures error, aborts and notifies approver with remediation steps (enable extension or run alternate
       migration).
- Alternative flows:
    - Maintainer has privilege to enable extension: run remedial step then re-run migration.
- Postconditions:
    - Workflow fails with clear remediation instructions and DB left in consistent state.

---

## Mapping to Acceptance Tests & Tickets

For each user story above create a ticket that contains:

- Story description and priority.
- Acceptance criteria (Given/When/Then) copied verbatim.
- Test plan (unit tests, integration tests, local end‑to‑end).
- Example payload(s) from examples/ for test fixtures.
- Any migration steps or environment requirements.

---

## Backlog & Iteration recommendations

1. Sprint 1 (foundation):
    - STORY-DB-001, STORY-DB-002, STORY-SNAP-001, STORY-DEV-001, STORY-DEV-002 (migrate, bootstrap, snapshot persist,
      sample payloads, docs).

2. Sprint 2 (ETL core + API):
    - STORY-ETL-001, STORY-API-001, STORY-API-002, STORY-ETL-003 (idempotent ETL, summary endpoint, bot command,
      preserve unmapped fields).

3. Sprint 3 (resilience & ops):
    - STORY-ETL-002, STORY-SNAP-002, STORY-OPS-001, STORY-SEC-002 (streaming ETL, dedupe, metrics, retention).

4. Sprint 4 (analytics & polish):
    - EPIC-ANALYTICS stories and remaining P2 items.

---

## 5. Functional Requirements

This section describes the functional scope for the Player Profile & DB Foundation project. It lists features at a high
level, provides detailed functional specifications for each major feature, defines data requirements (entities,
retention and archival rules), outlines integration requirements with external systems, and lists third‑party services
and dependencies (quotas, rate limits and SLAs).

---

### 5.1 Feature list (high level)

The following feature list groups work into logically cohesive capabilities that will be delivered across sprints.

- Feature: Database Foundation & Migrations
    - Versioned migrations (node-pg-migrate), bootstrap script, protected GitHub Actions workflow for manual production
      bootstrap.
- Feature: Snapshot Ingestion Endpoint & CLI Integration
    - Persist raw get_hero_profile JSON snapshots with metadata (size, SHA256 hash, source) to hero_snapshots.
    - Deduplication within configurable window.
- Feature: Background ETL Worker
    - Queue + worker that claims snapshots, parses them, and upserts normalized tables (users, user_troops, user_pets,
      user_artifacts, user_teams, guilds, guild_members, user_profile_summary).
    - Idempotent processing, per-entity transactions, streaming/chunked parsing for large payloads.
- Feature: Profile Summary API & Bot Commands
    - Low‑latency read endpoints using profile_summary; slash command integration for Discord bot.
    - Friendly fallbacks when summary is pending.
- Feature: Admin & Operational Endpoints
    - Reprocess snapshot API, health and metrics endpoints, retention/archival job control.
- Feature: Analytics & Exports
    - Materialized views and export jobs to S3 (CSV/Parquet) for BI pipelines.
- Feature: Security & Compliance Controls
    - Redaction of tokens in logs, never persist passwords, snapshot retention policies and GDPR-related deletion flows.
- Feature: Observability & Runbooks
    - Metrics (Prometheus), logs (structured), alerts and on-call runbooks for ETL and DB bootstrap operations.
- Feature: Developer Experience
    - Sample payloads, local bootstrap scripts, documentation (DB_MIGRATIONS.md, ETL_AND_WORKER.md) and automated tests
      for ETL idempotency.

---

### 5.2 Detailed functional specification (per feature)

Below are detailed specifications for the highest-priority features. Each feature includes overview, inputs/outputs,
UI/UX behavior (when applicable), API contract examples, business rules & validations, and error handling.

Feature A — Snapshot Ingestion (API + CLI integration)

- Overview
    - Receive and persist raw player profile snapshots returned by get_hero_profile (NameCode fetch or login flow).
      Capture metadata to detect duplicates and feed ETL pipeline.
- Inputs / outputs
    - Inputs:
        - JSON body (raw get_hero_profile payload)
        - HTTP headers (optional: upstream server_time)
        - Query params / metadata: source (string), client_name (string), content_hash optional
    - Outputs:
        - DB insert into hero_snapshots: id (UUID), user_id (nullable), namecode (optional), source, raw JSONB,
          size_bytes, content_hash (SHA256), server_time, created_at
        - HTTP response with snapshot id and status
- UI/UX behavior
    - CLI: get_hero_profile.sh saves raw JSON locally and can POST to ingestion endpoint if configured; CLI prints
      snapshot id and next steps (e.g., "snapshot queued for processing — check /profile/summary in ~30s").
    - Web/UI: Button or action to “Fetch profile by NameCode” returns immediate acknowledgement (202) and GUID.
- API contract (example)
    - Endpoint: POST /api/internal/snapshots
    - Method: POST
    - Auth: Bearer token (service), or limited API key for CLI; endpoint restricted to internal clients
    - Request JSON:
      {
      "source": "fetch_by_namecode" | "login",
      "namecode": "COCORIDER_JQGB",
      "payload": { ... full get_hero_profile JSON ... }
      }
    - Response:
        - 201 Created
          {
          "snapshot_id": "uuid",
          "status": "queued",
          "created_at": "2025-11-28T12:34:56Z"
          }
        - 409 Duplicate (optional)
          {
          "snapshot_id": "existing-uuid",
          "status": "duplicate"
          }
- Business rules & validations
    - Validate that payload is JSON and non-empty.
    - Compute SHA256(content) as content_hash. If a snapshot with same content_hash exists within dedupe_window (
      configurable, default 60s), return duplicate response (do not insert duplicate raw row) but record an attempt (
      duplicate_count) or an audit event.
    - size_bytes recorded as byte length of payload.
    - If namecode present in payload, attempt to map to existing users record (user_id) if a match exists.
    - Enqueue snapshot id to ETL queue after successful insert.
- Error handling & messages
    - 400 Bad Request if payload missing or invalid JSON.
    - 401 Unauthorized if auth fails.
    - 413 Payload Too Large if size exceeds configured maximum (reject or return 413 and instruct to use CLI with
      chunking).
    - 500 Internal Server Error on DB/queue problems; response includes safe error id for support tracing (no sensitive
      data).

Feature B — Background ETL Worker (core normalization)

- Overview
    - Asynchronous worker that consumes snapshot ids, parses raw JSON, and upserts normalized relational records.
      Designed to be idempotent, stream-friendly and observable.
- Inputs / outputs
    - Inputs:
        - snapshot id (UUID)
        - hero_snapshots.raw JSONB
    - Outputs:
        - Upserts to normalized tables (users, user_troops, user_pets, user_artifacts, user_teams, guilds,
          guild_members, user_profile_summary, user_progress)
        - Snapshot processed metadata: processed_at, processing flag cleared, error metadata if failure
        - Metrics emitted (duration_ms, items_processed, failure_count)
- UI/UX behavior
    - Not user-facing directly. Admin UI may show snapshot processing status and allow reprocess action.
- Processing steps (core)
    1. Claim snapshot: atomically set processing=true where processing=false to avoid duplicate claims (SQL WHERE
       processing=false RETURNING id).
    2. Parse JSON safely, using streaming / chunked processing for large arrays (troops, inventories).
    3. Begin per-entity upsert transaction:
        - Upsert users by unique keys (namecode, discord_user_id). Use ON CONFLICT for idempotency.
        - Upsert user_troops: for each troop record create or update unique (user_id, troop_id).
        - Upsert pets, artifacts, teams similarly.
        - Upsert guilds and guild_members if present.
        - Create/update user_profile_summary (denormalized for quick reads).
        - Save any unmapped fields into `extra` JSONB on each row or into a special unmapped_fields table for audit.
    4. Commit and set processed_at timestamp; if partially failed, capture entity-level errors and write to etl_errors
       table.
- API contract (admin)
    - Endpoint: POST /api/admin/snapshots/:id/reprocess
    - Method: POST
    - Auth: Admin-level JWT or API key
    - Response:
        - 202 Accepted { "job_id": "uuid", "status": "enqueued" }
        - 404 Not Found if snapshot id unknown
        - 409 Conflict if snapshot currently processing
- Business rules & validations
    - Worker must be idempotent: repeated processing of same snapshot id must not create duplicates nor corrupt state.
    - For large snapshots, break work into smaller DB transactions per-entity to reduce lock contention; do not hold one
      monolithic transaction for whole snapshot.
    - Unknown fields must not cause failure; store them under `extra` and emit a telemetry event for later mapping.
    - If upsert fails due to referential integrity (missing catalog row), optionally create a placeholder catalog row or
      write the failure to etl_errors for manual resolution (configurable behavior).
    - Processing attempts limited by retry policy (exponential backoff). After N failed attempts, mark snapshot as
      failed and alert.
- Error handling & messages
    - If parsing error: set snapshot.processing=false, processed_at=NULL, write detailed error into etl_errors (include
      snapshot_id, exception, stack, truncated raw snippet for debugging), and notify via alerting channel.
    - If DB deadlock or transient error: retry automatically per policy.
    - If permanent error (schema mismatch / unknown severe condition): mark snapshot failed, do not retry, and create a
      manual work item for engineers.

Feature C — Profile Summary API & Bot

- Overview
    - Expose low-latency read APIs and a Discord bot command that returns denormalized profile summaries built by the
      ETL.
- Inputs / outputs
    - Inputs:
        - namecode or user_id param
    - Outputs:
        - JSON summary with fields: namecode, username, level, top_troops [ {troop_id, amount, level} ], equipped_pet,
          pvp_tier, guild {id, name}, last_seen, summary_generated_at
- UI/UX behavior
    - Bot: Slash command `/profile <namecode>` returns a compact embed: player name, level, top 3 troops, main pet,
      guild, last seen. If summary pending, bot replies with friendly ETA.
    - Web UI: profile page loads summary quickly and displays a link "View raw snapshot" for advanced users (requires
      permission).
- API contract (example)
    - Endpoint: GET /api/profile/summary/:namecode
    - Method: GET
    - Auth: public read or authenticated as needed (rate limited)
    - Response:
        - 200 OK { "namecode": "...", "level": 52, "top_troops": [...], "equipped_pet": {...}, "guild": {...}, "
          last_seen": "...", "cached_at": "..." }
        - 202 Accepted { "message": "Profile processing in progress", "estimated_ready_in": "30s" }
        - 404 Not Found { "message": "No profile found" }
- Business rules & validations
    - If profile_summary exists return it immediately.
    - If profile_summary missing but a processed hero_snapshot exists, build an ad-hoc summary from the latest processed
      snapshot and return with freshness metadata.
    - Apply per-client rate limits to avoid abuse; enforce caching headers (Cache-Control) as appropriate.
- Error handling & messages
    - 404 if neither summary nor processed snapshot exists.
    - 429 Too Many Requests when client exceeds rate limits.
    - 500 for backend issues with an error id for support.

Feature D — Retention & Archival Job

- Overview
    - Retention job to prune or archive hero_snapshots older than configured retention; supports archiving to
      S3/compatible storage with audit trail.
- Inputs / outputs
    - Inputs:
        - Retention configuration (days to retain or N snapshots per user)
    - Outputs:
        - Archived files on S3 (optionally compressed), DB archival metadata rows, deleted or marked archived snapshots
          from DB.
- Business rules & validations
    - Default retention: 90 days (configurable per environment).
    - Optionally: keep last N snapshots per user (e.g., keep last 30 per user).
    - Archive must include minimal audit metadata: snapshot_id, original_size_bytes, archived_at, s3_path, checksum.
    - Retention job should be idempotent and resumable.
- Error handling & messages
    - When S3 upload fails: retry with exponential backoff and escalate if exceeding thresholds.
    - If unable to archive a snapshot, do not delete DB row; log and create a ticket.

Feature E — Developer Experience & Migrations

- Overview
    - Tools and docs for dev onboarding, local bootstrap, sample ingestion and migration execution.
- Inputs / outputs
    - Inputs: developer environment, .env with DATABASE_URL, sample JSON files
    - Outputs: running local DB with schema applied, seeded data and example snapshots processed
- Business rules & validations
    - Bootstrap script must be idempotent and provide clear error messages for missing permissions (e.g., CREATE
      EXTENSION).
    - Migrations must be reversible or documented with rollback steps.
- Error handling & messages
    - If migration fails, scripts must print human-friendly remediation (missing extension, permission denied) and not
      leak secrets.

---

### 5.3 Data requirements

This subsection documents the data entities required, retention and archival rules, and points to the canonical data
schema docs.

- Data entities required (primary)
    - users
        - id (UUID), namecode, username, discord_user_id, created_at, updated_at
    - hero_snapshots
        - id (UUID), user_id (nullable), namecode, source, raw JSONB, size_bytes, content_hash (SHA256), server_time,
          processing (bool), processed_at, created_at, error metadata
    - user_troops
        - id (UUID), user_id, troop_id (int), amount, level, rarity, extra JSONB, last_seen
    - user_pets
        - id (UUID), user_id, pet_id, amount, level, xp, extra JSONB
    - user_artifacts
        - id (UUID), user_id, artifact_id, level, xp, extra JSONB
    - user_teams
        - id (UUID), user_id, name, banner, troops (int array), updated_at
    - guilds
        - id (UUID), discord_guild_id, name, settings JSONB, feature_flags
    - guild_members
        - id (UUID), guild_id, user_id, discord_user_id, joined_at
    - user_profile_summary
        - user_id (PK), denormalized fields for fast reads (level, top_troops array, equipped_pet, pvp_tier, last_seen,
          cached_at)
    - etl_errors / etl_audit
        - id, snapshot_id, error_type, message, details, created_at
    - catalog tables (optional)
        - troop_catalog, pet_catalog, artifact_catalog (static metadata, seeded)
- Retention and archival rules
    - Default snapshot retention: 90 days (configurable).
    - Optionally keep last N snapshots per user (e.g., 30). Policy expressed as: keep newest N OR keep snapshots younger
      than D days, whichever keeps more recent data.
    - Archival: snapshots older than retention are compressed and uploaded to S3 (or other object store) with checksum,
      and either deleted from DB or marked archived (policy driven).
    - Audit: archival actions must write audit rows (archived_by_job, archived_at, s3_path, checksum).
    - PII retention: any PII detected must be handled according to DATA_PRIVACY.md — if user requests deletion, both DB
      rows and archived files must be purged according to legal process.
- Data schema references
    - Canonical DB model and ERD: docs/DB_MODEL.md (link). All normalized tables, indexes and constraints are defined in
      DB_MODEL.md and migrations generated from that model.
    - Migrations and seed files live under database/migrations/ and database/seeds/.

---

### 5.4 Integration requirements

List of external systems to integrate with, required interfaces and authentication mechanisms.

- Discord (Bot integration)
    - Purpose: present profiles to players via slash commands; optionally link NameCode to Discord accounts.
    - Integration:
        - OAuth2 / Bot token stored in GitHub Secrets (DISCORD_TOKEN).
        - Use Discord Gateway intents as required (presence if needed).
        - Rate limit handling: respect Discord API limits; implement backoff and retries.
    - Permissions:
        - Bot must request only required scopes and have clear privacy policy for data usage.

- Supabase / Postgres (Primary DB)
    - Purpose: host hero_snapshots and normalized tables.
    - Integration:
        - Use DATABASE_URL from GitHub Secrets or environment variables.
        - Migrations run via node-pg-migrate; use pgcrypto extension (or documented alternative).
        - Use separate DB roles for app writes and read-only analytics.
    - Constraints:
        - CREATE EXTENSION permissions may be restricted on managed providers; bootstrap scripts must handle permission
          errors gracefully.

- Redis / Queue (BullMQ or equivalent)
    - Purpose: queue snapshot processing jobs and manage worker orchestration.
    - Integration:
        - Connection via REDIS_URL (secret). Jobs enqueued upon snapshot insert.
        - Worker concurrency configured via environment variable.
    - Notes:
        - If using hosted Redis (e.g., Upstash), account for connection limits and latency.

- S3 / Object Storage (AWS S3 / S3-compatible)
    - Purpose: archive snapshots and store exports for analytics.
    - Integration:
        - Use service account credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) stored as secrets.
        - Upload archived snapshots to dedicated bucket with lifecycle rules.
    - Security:
        - Enforce server-side encryption (SSE) and proper IAM policies.

- Google Cloud (optional)
    - Purpose: CI secrets, service accounts for GCP-based resources if used.
    - Integration:
        - GOOGLE_SA_JSON stored as GitHub secret for actions that need it.

- GitHub Actions (CI/CD)
    - Purpose: run migrations (manual), run tests, build & publish container images to GHCR.
    - Integration:
        - Use repository secrets for DB connections; protect workflows that run on production via GitHub
          Environments/approvals.

- Monitoring & Logging (Prometheus, Grafana, Sentry or alternatives)
    - Purpose: collect metrics and errors, manage alerts.
    - Integration:
        - Worker exposes /metrics; scrape by Prometheus or push to managed provider.
        - Sentry DSN for error tracking; configure sampling to avoid PII leakage.

- Upstream game API (get_hero_profile endpoints)
    - Purpose: source of raw profile snapshots.
    - Integration:
        - Scripts or proxy clients call this endpoint. Respect upstream rate limits and terms of service.
        - Any credentials used by players for login flows must be handled locally (never committed) and not stored by
          ingestion service.
    - Rate limiting:
        - Track upstream rate limits and surface to users when exceeded.

- CI Container Registry (GHCR)
    - Purpose: publish worker images or other containers.
    - Integration:
        - Use GHCR_TOKEN or GitHub Actions authentication; include retention and cleanup policy for images.

---

### 5.5 Third‑party services & dependencies

An inventory of external services and dependencies with operational constraints, quotas, and suggested SLA/targets.

- Postgres (Supabase/managed Postgres)
    - Typical SLA: provider dependent (e.g., 99.95%).
    - Limits: connection limits, extensions permissions may be restricted.
    - Recommendations: use a dedicated DB role for ETL operations; monitor connection count and long-running queries.

- Redis / Managed queue service (e.g., Upstash, RedisLabs)
    - SLA: provider dependent.
    - Limits: concurrent connections, max memory, max message throughput.
    - Recommendations: size instance for peak ETL throughput, set eviction policies.

- S3 / Object Storage (AWS S3, DigitalOcean Spaces, MinIO)
    - SLA: typically high durability (11 9s), provider dependent for availability.
    - Limits: request rates per prefix — follow provider guidelines for parallel uploads.
    - Recommendations: configure lifecycle, enable server-side encryption, versioning optional.

- GitHub Actions & GHCR
    - Quotas: actions minutes and storage quotas per plan; GitHub rate limits for API calls.
    - Recommendations: Use protected environments for production operations; rotate tokens periodically.

- Monitoring & Error Tracking (Prometheus/Grafana, Sentry)
    - Quotas: retention and event quotas (Sentry); scrape frequency for Prometheus.
    - Recommendations: configure alerting thresholds (ETL failure spikes, high queue latency), control sampling to avoid
      sending PII.

- Upstream game API
    - Constraints: unknown rate limits; must be treated as a throttled resource.
    - Recommendations: implement client-side backoff, expose user-facing messages when upstream limits are hit.

- Node.js / pnpm / npm ecosystem
    - Constraints: dependency vulnerabilities and transitive license issues.
    - Recommendations: dependabot or similar for dependency updates; audits in CI.

- Libraries & DB extensions
    - pgcrypto (preferred), jsonb tooling, node-pg-migrate
    - Notes: Ensure provider supports chosen extensions or provide fallback code paths.

Service-level expectations (internal targets)

- ETL worker availability: target 99.9% in production during business hours.
- Snapshot ingestion latency: < 1s for API ack when snapshot accepted (processing asynchronous).
- ETL processing SLA for interactive flows: configurable default (e.g., 30s), longer allowed for backfills.
- Alerting: trigger when ETL failure rate > 1% over 5 minutes or queue latency > threshold.

---

References

- Link canonical schema: docs/DB_MODEL.md
- Link ETL design and worker contract: docs/ETL_AND_WORKER.md
- Link migration conventions: docs/MIGRATIONS.md

## 6. Non-Functional Requirements (NFR)

This section lists measurable non-functional requirements and operational constraints for the Player Profile & DB
Foundation project. Where concrete numbers are proposed, they are recommendations to start with and should be validated
against real traffic and baseline measurement.

---

### 6.1 Performance

- Latency targets
    - Snapshot ingestion (API ack): p95 < 1s, p99 < 3s (acknowledgement that snapshot was received and queued).
    - Profile summary read endpoint (normal path served from user_profile_summary): p95 < 200ms, p99 < 500ms under
      typical staging/production read load.
    - Profile summary fallback (build ad-hoc from latest processed snapshot): p95 < 500ms, p99 < 1s.
    - ETL processing for interactive requests (small/average snapshots): median < 10s, p95 < 30s. Large payloads (login
      flow, 2–3MB) may be treated as asynchronous with SLA target p95 < 5 minutes for background processing in initial
      release.
    - Admin operations (bootstrap/migrations): no strict latency SLA but must complete within workflow timeouts (GitHub
      Actions default) and provide progress logs.

- Throughput / concurrency targets
    - Target initial throughput: 1,000 snapshot ingest requests/day (configurable).
    - Target ETL capacity: process 100 snapshots/hour with a single worker instance. Design for horizontal scaling to
      handle spikes (workers ×N).
    - Concurrent read queries: support 500 concurrent summary reads (scale via read replicas / caching).
    - These numbers are starting points; measure real traffic and increase capacity targets accordingly.

- Load profile and expected traffic
    - Typical load: bursts when community events occur (fetch scripts executed by many users); anticipate spikes (
      10–100× baseline) during coordinated runs.
    - Peak-case planning: system should be able to scale to handle spike multiplier for short periods (auto-scale worker
      pool and API replicas).
    - Backfill scenarios: bulk backfills will be scheduled during off-peak windows and run with controlled concurrency
      to avoid impacting production reads.

---

### 6.2 Scalability

- Horizontal / vertical scaling expectations
    - Stateless components (API, worker processes) must scale horizontally behind a load balancer or process supervisor.
    - Postgres: scale vertically for CPU/memory; scale horizontally for reads with read replicas. Use partitioning and
      connection pooling to scale writes and large snapshot storage.
    - Redis/Queue: scale vertically to increase throughput; consider sharding if needed.
    - Object storage (S3): scale automatically for archival/export operations.

- Bottleneck considerations
    - Postgres connections and long-running transactions are primary write bottlenecks — avoid monolithic transactions
      for entire snapshots.
    - Network bandwidth when transferring large snapshots or performing S3 uploads.
    - Memory consumption during ETL parsing for large payloads: use streaming/chunked parsing.
    - Rate limits of upstream API and Discord (throttle & queue at client side).

- Recommendations
    - Use connection pooling (pgbouncer) and limit DB connections per worker.
    - Partition hero_snapshots by time (monthly) or by hash of user_id for very large datasets.
    - Employ read replicas for heavy analytical queries and for bot read traffic if necessary.
    - Implement autoscaling policies for workers based on queue depth and processing latency.

---

### 6.3 Reliability / Availability

- Target uptime / SLA
    - Internal target: 99.9% availability for public read API and worker infrastructure during business hours (SLA can
      be refined with stakeholders).
    - Snapshot ingests and ETL are best-effort asynchronous services; availability target 99.5% for ingestion API.

- RTO / RPO objectives
    - RTO (Recovery Time Objective): 1 hour for critical failures affecting primary reads; 24 hours for full recovery
      after catastrophic failure.
    - RPO (Recovery Point Objective): database backups taken at least daily with WAL archiving; target RPO = 1 hour (
      WAL-enabled continuous archiving) for production-critical data where supported by provider.

- Redundancy strategy
    - DB: managed provider with automated backups and optional read-replicas; cross-region replicas if required for
      higher availability.
    - API & workers: run at least two instances across availability zones; use managed orchestration for automatic
      restart.
    - Queue: run with managed Redis or HA configuration; ensure persistence where required (or use jobs persisted in DB
      as fallback).
    - Storage: use durable object store with versioning and lifecycle policies (S3 or S3-compatible).

- Backup & restore
    - Regular automated backups (daily snapshots + continuous WAL where supported).
    - Periodic restore drills documented in BACKUP_RESTORE.md; at minimum yearly full restore test and quarterly partial
      restore validation.
    - Retain backups per policy balancing compliance and cost (e.g., 90 days online, archive longer-term).

---

### 6.4 Security

- Authentication & authorization model
    - Public read endpoints: allow anonymous reads or light authentication depending on product choice; enforce per-IP
      and per-token rate limiting.
    - Internal ingestion/admin endpoints: require service-to-service authentication (short-lived signed tokens or mTLS)
      or bearer tokens stored in GitHub Secrets; admin endpoints require RBAC (role-based access control) and be limited
      to designated maintainer accounts.
    - Use least privilege: separate credentials for migrations, worker writes, analytics reads.

- Data encryption (at rest / in transit)
    - In transit: TLS 1.2+ for all external and internal communications (API, DB connections with SSL).
    - At rest: rely on provider encryption (Postgres managed service encryption, S3 SSE). For highly sensitive fields
      consider application-level encryption for specific columns.
    - Secrets in GitHub Actions: use GitHub Secrets and protected Environments; avoid printing secrets to logs.

- Secret management
    - Store secrets in GitHub Secrets for CI and in a secrets manager for runtime (e.g., AWS Secrets Manager, GCP Secret
      Manager, or provider equivalent).
    - Enforce rotation policy (e.g., rotate DB credentials and service tokens every 90 days or on compromise).
    - Audit access to secrets and require multi-person approval for high-privilege environment changes.

- Threat model highlights
    - Threats:
        - Credential leakage (accidental commit, logs).
        - Data exfiltration (malicious actor or misconfigured S3 permissions).
        - Injection (SQL injection via poorly-validated fields).
        - Supply chain (malicious NPM packages).
        - DDoS / abusive traffic (rate-limiting bypass).
    - Mitigations:
        - Pre-commit scanning and CI checks to prevent secrets in code.
        - IAM least privilege and S3 bucket policies; object-level encryption.
        - Parameterized queries and ORM / query builder usage; strict validation of incoming JSON.
        - Dependency scanning (dependabot), pinned dependencies and reproducible builds.
        - WAF or rate limiting, API quotas, and abuse monitoring.

- OWASP considerations
    - Address OWASP Top 10 (A1–A10) as applicable:
        - A1 Injection: use parameterized queries; validate inputs.
        - A2 Broken Authentication: enforce secure tokens and session handling.
        - A3 Sensitive Data Exposure: redact sensitive fields in logs and encrypt at rest.
        - A5 Security Misconfiguration: restrict permissions on DB and storage; avoid unnecessary extensions.
        - A9 Components with Known Vulnerabilities: dependency scanning and patching.
    - Include security tests in CI (SAST/DSA) and periodic dependency audits.

---

### 6.5 Privacy & Compliance

- PII handling
    - Define a clear data classification: what fields in snapshots are PII (emails, real names, device identifiers,
      tokens) and handle accordingly.
    - Minimize PII storage: only store fields required for functionality; store raw snapshots only when necessary and
      redact sensitive fields before archival if required.
    - Logs: never log user credentials or raw tokens; redact PII in application logs.

- GDPR / CCPA / other regulatory constraints
    - Implement user data subject request (DSR) workflows: right to access, right to erasure ("right to be forgotten"),
      portability.
    - Maintain audit trail for deletion and retention actions.
    - Ensure Data Processing Agreement (DPA) with cloud providers when handling EU user data.
    - Document lawful basis for processing user data in DATA_PRIVACY.md.

- Data residency requirements
    - Support configuration of data residency per environment (e.g., EU-only storage). If required, deploy DB and S3
      buckets in specific regions and configure backups accordingly.
    - Ensure cross-region backups/processing comply with legal constraints.

- Consent & user-facing notices
    - If public-facing service, include privacy policy and explicit consent flows for login-based ingestion (explain
      what is captured and retained).
    - Provide user-facing controls for deleting stored profiles (or requesting archival/deletion) and document expected
      SLAs for deletion.

---

### 6.6 Maintainability & Operability

- Observability requirements (metrics, logs, traces)
    - Metrics:
        - ETL: processed_count, success_count, failure_count, average_latency, p95_latency, queue_depth.
        - API: request rates, error rates, latency percentiles.
        - Infrastructure: DB connection usage, replication lag, worker memory/CPU.
    - Logging:
        - Structured logs (JSON) with standardized fields (timestamp, service, level, job_id/snapshot_id,
          correlation_id).
        - Redact sensitive fields; log sampling for high-volume flows.
    - Tracing:
        - Distributed tracing for request → ingestion → worker pipeline (trace IDs propagated in headers).
    - Dashboards & alerts:
        - Dashboard for ETL health, queue length, failure rate, and ingestion latency.
        - Alerts when failure_rate > threshold, queue depth high, or ETL latency SLA breached.

- Error tracking & alerting expectations
    - Use Sentry or equivalent for uncaught exceptions and application errors (with PII redaction).
    - Alerts:
        - P0: ETL failure rate > 1% sustained for 5 minutes → page on-call.
        - P0: Queue depth > threshold (configurable) for > 5 minutes → notify.
        - P1: Migration workflow failure in production → notify maintainers.
    - On-call rotation and SLAs for acknowledgements should be defined in OP_RUNBOOKS/ONCALL.md.

- Operational runbooks required
    - Runbooks to include:
        - How to re-enqueue snapshots and reprocess (admin endpoint and manual DB steps).
        - How to run migrations and rollback safely (with pre-check list).
        - How to restore DB from backup and perform a sanity check.
        - Incident response for ETL storm/failure, and for secrets compromise.
        - How to perform retention/archival jobs manually.

- Testing & CI
    - CI must run unit tests, integration tests against a test Postgres instance, linting, and lightweight security
      scans.
    - Include end-to-end test that exercises ingest → ETL → profile_summary for sample payloads.

---

### 6.7 Accessibility

- A11y requirements & compliance level (WCAG)
    - Public-facing UI (if present) should aim for WCAG 2.1 AA compliance as a target.
    - Bot messages: ensure text conveys necessary information without relying on color alone; provide alt text for
      images or icons in embeds where relevant.
    - Documentation: make sure developer docs are navigable and readable (headings, code blocks, keyboard accessibility
      for any web UI).

---

### 6.8 Internationalization / Localization

- Languages supported
    - Initial supported language: English (en).
    - Target second language: French (fr) for project maintainers/community (optional for user-facing UI).
    - Use i18n frameworks for any user-facing strings; avoid hard-coded text in bot replies and web UI.

- Formatting & timezones
    - Store all timestamps in UTC in the DB (ISO 8601). Convert to local timezone only at presentation layer.
    - Number/date formatting follows locale conventions on presentation layer (client or UI).

- Character encoding
    - Use UTF-8 for all stored text and interfaces.

---

### 6.9 Constraints and limitations

- Platform or infrastructure constraints
    - Managed Postgres providers may restrict CREATE EXTENSION or certain superuser operations (documented fallback
      required).
    - GitHub Actions limitations: runner execution timeouts and secret exposure risk — production bootstrap must be
      manual and protected.
    - Provider quotas for Redis, S3, GHCR and Actions minutes should be tracked to avoid hitting limits.

- Regulatory or legal constraints
    - If processing EU resident data, comply with GDPR (DPA with provider, data residency if required).
    - If storing payment or highly sensitive data, use certified provider services and restricted handling (PCI DSS out
      of scope unless payments added).

- Cost constraints
    - Archiving snapshots and running high-frequency ETL can grow storage and compute costs quickly. Use retention
      policy, lifecycle rules and careful autoscaling.
    - Monitor monthly spend and provide cost alerts.

- Operational constraints
    - Migration changes that require downtime must be communicated and scheduled; prefer online migrations where
      possible.
    - Avoid large, blocking schema changes in a single migration — prefer migration patterns that add columns with null
      defaults, backfill asynchronously, then make columns NOT NULL in a later migration.

---

References and cross-links

- docs/DB_MODEL.md (data model)
- docs/ETL_AND_WORKER.md (worker design, retries, idempotency)
- docs/DATA_PRIVACY.md (privacy & GDPR procedures)
- docs/OBSERVABILITY.md and docs/OP_RUNBOOKS/* (monitoring and runbooks)

--- 

## 7. Data Model & Schema (overview)

This section provides a high-level overview of the canonical data model we will use to support snapshot ingestion, ETL
normalization and fast reads. It contains an embedded ERD-like diagram (textual), detailed key entities and attributes (
types, constraints and relationships), indexing and common query patterns, and the migration/versioning strategy
reference.

For the full, canonical schema (DDL, constraints, index definitions and ER diagrams) see: docs/DB_MODEL.md

---

### 7.1 High-level ERD (link or embedded)

Below is a compact textual ERD showing main tables and relationships. It is intended as an overview; the full ERD image
and complete table definitions live in docs/DB_MODEL.md.

Users (1) ⟷ (N) HeroSnapshots
Users (1) ⟷ (N) UserTroops
Users (1) ⟷ (N) UserPets
Users (1) ⟷ (N) UserArtifacts
Users (1) ⟷ (N) UserTeams
Guilds (1) ⟷ (N) GuildMembers
Users (1) ⟷ (N) GuildMembers
HeroSnapshots (1) ⟷ (N) ETLErrors / ETLAudit

Textual relationships:

- users.id (UUID, PK)
    - hero_snapshots.user_id → users.id (nullable) — raw snapshot may be inserted before user mapping exists
    - user_troops.user_id → users.id (NOT NULL)
    - user_teams.user_id → users.id (NOT NULL)
- guild_members.guild_id → guilds.id
- guild_members.user_id → users.id

(For a graphical ERD, see docs/DB_MODEL.md which contains an SVG/PNG ERD and table-by-table DDL.)

---

### 7.2 Key entities and attributes

Below are the primary tables required for the initial product vertical slice, with recommended column names, types,
constraints and brief notes on purpose.

Note: these are the canonical attributes used by the ETL and APIs. Implementation DDL lives under database/migrations/
and docs/DB_MODEL.md.

1) users

- Purpose: canonical user account mapping (NameCode, Discord id, human name)
- Columns:
    - id UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - namecode VARCHAR(64) UNIQUE NULLABLE — NameCode / Invite code (ex: COCORIDER_JQGB)
    - discord_user_id VARCHAR(64) NULLABLE
    - username VARCHAR(255) NULLABLE
    - email VARCHAR(255) NULLABLE
    - created_at TIMESTAMPTZ DEFAULT now()
    - updated_at TIMESTAMPTZ DEFAULT now()
- Notes:
    - Keep PII minimal; optionally separate PII into a protected table if compliance requires.
    - Indexes: UNIQUE on namecode; index on discord_user_id

2) hero_snapshots

- Purpose: store raw JSONB payloads from get_hero_profile / login flow for audit & replay
- Columns:
    - id UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - user_id UUID REFERENCES users(id) ON DELETE SET NULL
    - namecode VARCHAR(64) NULLABLE
    - source VARCHAR(64) NOT NULL (e.g., "fetch_by_namecode", "login", "cli_upload")
    - raw JSONB NOT NULL
    - size_bytes INTEGER NOT NULL
    - content_hash VARCHAR(128) NOT NULL -- SHA256 hex
    - server_time BIGINT NULLABLE (if provided by upstream)
    - processing BOOLEAN DEFAULT FALSE
    - processed_at TIMESTAMPTZ NULLABLE
    - created_at TIMESTAMPTZ DEFAULT now()
    - error_count INTEGER DEFAULT 0
    - last_error JSONB NULLABLE
- Constraints & indexes:
    - UNIQUE(content_hash, source) OPTIONAL depending on dedupe policy
    - INDEX on (user_id, created_at DESC)
    - GIN index on raw using jsonb_path_ops or default jsonb_ops for search:
        - CREATE INDEX ON hero_snapshots USING GIN (raw jsonb_path_ops);
    - Expression index on ( (raw ->> 'PlayerId') ) if upstream exposes stable top-level ID

3) user_troops

- Purpose: normalized inventory of troops per user (fast lookup by troop_id)
- Columns:
    - id UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
    - troop_id INTEGER NOT NULL -- references troop_catalog.id when available
    - amount INTEGER DEFAULT 0 NOT NULL
    - level INTEGER DEFAULT 1
    - rarity INTEGER DEFAULT 0
    - fusion_cards INTEGER DEFAULT 0
    - traits_owned INTEGER DEFAULT 0
    - extra JSONB DEFAULT '{}'::jsonb -- store unknown fields
    - last_seen TIMESTAMPTZ DEFAULT now()
    - updated_at TIMESTAMPTZ DEFAULT now()
- Constraints & indexes:
    - UNIQUE(user_id, troop_id)
    - INDEX on (troop_id, amount) for analytics
    - INDEX on (user_id, troop_id) for fast upsert/deletes

4) guilds

- Purpose: guild metadata and feature flags
- Columns:
    - id UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - discord_guild_id VARCHAR(64) UNIQUE NULLABLE
    - name VARCHAR(255)
    - settings JSONB DEFAULT '{}'::jsonb
    - feature_flags JSONB DEFAULT '{}'::jsonb
    - created_at TIMESTAMPTZ DEFAULT now()
    - updated_at TIMESTAMPTZ DEFAULT now()

5) guild_members

- Purpose: mapping between guilds and users
- Columns:
    - id UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - guild_id UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE
    - user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
    - discord_user_id VARCHAR(64) NULLABLE
    - joined_at TIMESTAMPTZ NULLABLE
- Constraints & indexes:
    - UNIQUE(guild_id, user_id)
    - INDEX on guild_id for guild-wide queries

6) feature_flags

- Purpose: store product feature toggles and rollout metadata (global flags)
- Columns:
    - id UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - name VARCHAR(128) UNIQUE NOT NULL
    - enabled BOOLEAN DEFAULT false
    - rollout_percentage INTEGER DEFAULT 0
    - data JSONB DEFAULT '{}'::jsonb
    - created_at TIMESTAMPTZ DEFAULT now()
    - updated_at TIMESTAMPTZ DEFAULT now()

7) user_profile_summary

- Purpose: denormalized, read-optimized summary for fast profile reads (the primary read for the bot/UI)
- Columns:
    - user_id UUID PRIMARY KEY REFERENCES users(id)
    - namecode VARCHAR(64)
    - username VARCHAR(255)
    - level INTEGER
    - top_troops JSONB DEFAULT '[]' -- e.g. [ {troop_id, amount, level}, ... ]
    - equipped_troop_ids INTEGER[] DEFAULT '{}'
    - equipped_pet JSONB NULLABLE
    - pvp_tier INTEGER NULLABLE
    - guild_id UUID NULLABLE
    - last_seen TIMESTAMPTZ NULLABLE
    - cached_at TIMESTAMPTZ DEFAULT now() -- when summary was generated
    - extra JSONB DEFAULT '{}'::jsonb
- Indexes:
    - PRIMARY KEY user_id
    - INDEX on namecode for quick lookup (if public reads use namecode)

8) etl_errors (or etl_audit)

- Purpose: capture per-snapshot or per-entity errors for debugging and reprocess prioritization
- Columns:
    - id UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - snapshot_id UUID REFERENCES hero_snapshots(id)
    - error_type VARCHAR(128)
    - message TEXT
    - details JSONB
    - created_at TIMESTAMPTZ DEFAULT now()

9) optional catalogs

- troop_catalog (id INT PRIMARY KEY, name TEXT, rarity INT, meta JSONB)
- pet_catalog, artifact_catalog

---

### 7.3 Indexing and query patterns

This section describes recommended indexes and the most common query patterns the system must serve quickly. Index
choices balance write cost of ETL upserts against read performance.

Recommended indexes (examples)

- hero_snapshots
    - GIN index: CREATE INDEX idx_hero_snapshots_raw_gin ON hero_snapshots USING GIN (raw jsonb_path_ops);
    - Recent snapshots per user: CREATE INDEX idx_hero_snapshots_user_created_at ON hero_snapshots (user_id, created_at
      DESC);
    - Optional uniqueness: CREATE UNIQUE INDEX IF NOT EXISTS ux_hero_snapshots_contenthash_source ON hero_snapshots (
      content_hash, source) WHERE (content_hash IS NOT NULL);

- users
    - CREATE UNIQUE INDEX idx_users_namecode ON users(namecode);
    - CREATE INDEX idx_users_discord_user_id ON users(discord_user_id);

- user_troops
    - CREATE UNIQUE INDEX ux_user_troops_user_troop ON user_troops (user_id, troop_id);
    - CREATE INDEX idx_user_troops_troop ON user_troops (troop_id);
    - CREATE INDEX idx_user_troops_user ON user_troops (user_id);

- user_profile_summary
    - CREATE INDEX idx_profile_summary_namecode ON user_profile_summary (namecode);

- guild_members
    - CREATE INDEX idx_guild_members_guild ON guild_members (guild_id);

- etl_errors
    - INDEX on snapshot_id and created_at for fast debugging.

Query patterns and example SQL

- Get latest processed snapshot for a user:
    - SELECT * FROM hero_snapshots WHERE user_id = $1 AND processed_at IS NOT NULL ORDER BY created_at DESC LIMIT 1;

- Get profile summary by namecode:
    - SELECT * FROM user_profile_summary WHERE namecode = $1;

- Who owns troop 6024 (list users with >0 amount):
    - SELECT u.id, u.namecode, ut.amount, ut.level FROM user_troops ut JOIN users u ON ut.user_id = u.id WHERE
      ut.troop_id = 6024 AND ut.amount > 0 ORDER BY ut.amount DESC LIMIT 100;

- Top troops for a user:
    - SELECT jsonb_array_elements(user_profile_summary.top_troops) FROM user_profile_summary WHERE user_id = $1;

- Leaderboard by troop total:
    - SELECT u.namecode, ut.amount FROM user_troops ut JOIN users u ON ut.user_id = u.id WHERE ut.troop_id = $troop_id
      ORDER BY ut.amount DESC LIMIT 100;

- Search raw snapshot for condition (example using JSON path)
    - SELECT id FROM hero_snapshots WHERE raw @? '$.ProfileData.Troops.* ? (@.TroopId == 6024 && @.Amount > 0)';

Indexing considerations & patterns

- GIN indexes on jsonb speed ad-hoc queries but carry write cost. Use them judiciously on hero_snapshots; most
  production queries should use normalized tables.
- Expression indexes: create indexes on frequently accessed extracted JSON keys (e.g., ( (raw ->> 'namecode') )) if you
  must query raw snapshots frequently.
- Partial indexes: for large tables, use partial indexes for hot subsets (e.g., processed snapshots only).
- Materialized views: create materialized views for heavy aggregations (troop ownership totals) and refresh them on
  schedule or via incremental jobs.
- Partitioning: hero_snapshots can be partitioned by created_at (e.g., monthly) or by hash(user_id) if snapshot volume
  grows into tens of millions of rows. Partitioning reduces vacuum and index bloat and improves archival deletion
  performance.

ETL upsert patterns (best practices)

- Use ON CONFLICT (user_id, troop_id) DO UPDATE ... for user_troops upserts.
- Combine small batches into single multi-row upserts where possible to reduce roundtrips.
- Limit transaction scope: commit per entity group (users, troops, pets) to reduce lock hold time.
- Use advisory locks only where required to avoid concurrency issues with parallel worker instances.

Read optimizations

- Serve interactive reads from user_profile_summary (denormalized).
- Cache summaries in Redis or an in-process LRU cache if read volume demands it.
- Use read replicas for heavy analytics or dashboard queries to avoid impacting primary.

---

### 7.4 Migration strategy & versioning (link to MIGRATIONS.md)

Migration tooling and conventions

- Tool: node-pg-migrate (JavaScript migrations)
    - Store migrations under database/migrations/ with timestamped filenames, e.g.
      20251128T1530_create_hero_snapshots.js
    - Migrations should be small, reversible where practical, and tested locally and in staging before production.

Naming & semantics

- Use a consistent filename pattern: YYYYMMDDHHMMSS_description.[js|sql]
- Each migration should contain:
    - up: statements to apply change
    - down: statements to revert change when safe
- Avoid destructive operations in one step (e.g., dropping columns) — prefer a 3-step safe migration:
    1. Add new nullable column
    2. Backfill/update data (asynchronously via worker)
    3. Make column NOT NULL and drop old column in a later migration

Migration best practices

- Use transactional migrations where possible. For long-running operations that cannot be executed inside a
  transaction (e.g., CREATE INDEX CONCURRENTLY), document them in migration and include pre/post sanity checks.
- Keep extension creation separate in its own migration with clear notes and guard behavior (CREATE EXTENSION IF NOT
  EXISTS pgcrypto). Document provider permissions fallback in MIGRATIONS.md.
- Test migrations:
    - Run migrations up/down in CI on a fresh DB instance (to ensure they apply cleanly).
    - Smoke tests: after migrations, run a suite that validates expected tables, indexes and a minimal ETL run against
      sample payloads.
- Staging → Production promotion:
    - Migrations are applied first in staging; after smoke-test pass, apply to production via the manual GitHub Actions
      workflow (db-bootstrap.yml) requiring environment approvers.
- Versioning & release policies:
    - Keep schema changes tied to feature branches; migrate with feature gates or feature flags if schema changes are
      not backwards compatible.
    - Maintain a migration changelog and map migration ids to PRs for traceability.

Rollback & emergency patches

- Plan for rollbacks:
    - For reversible migrations use the down script.
    - For destructive changes, keep backups and a pre-approved rollback plan in MIGRATIONS.md.
- Backups:
    - Before applying production migrations, take a DB snapshot or backup and validate that restore is possible.
- Emergency hotfix flow:
    - If a migration causes issues, the runbook in docs/OP_RUNBOOKS/MIGRATION_ROLLBACK.md provides the step-by-step
      mitigation: stop workers, pause ingest, restore from backup or apply compensating migration, then resume.

Automation & CI integration

- CI gates: require successful migration in a CI job against a sandbox DB before merging migration-related PRs.
- Migration pre-checks: add preflight scripts that:
    - verify required DB extensions and privileges
    - estimate the cost of index creation and warn if creating large indexes
    - check for long-running queries and locks

---

References

- Complete migration conventions and examples: docs/MIGRATIONS.md
- Full DDL, column types, constraints and ERD diagrams: docs/DB_MODEL.md
- ETL idempotency patterns and per-entity upsert examples: docs/ETL_AND_WORKER.md

---

## 8. API Specification (contract)

This section defines the API surface, design principles, authentication & authorization rules, concrete endpoints (
request/response schemas and error codes), rate limiting policy and versioning/deprecation rules. The goal is a clear,
predictable, secure and stable contract for clients (CLI, bot, UI, internal services) and operators.

---

### 8.1 API design principles (REST / GraphQL / versioning)

- Style
    - Primary design: RESTful JSON APIs. Keep resource-oriented endpoints and use standard HTTP verbs (GET, POST,
      PUT/PATCH, DELETE) and status codes.
    - Consider GraphQL in a future phase for complex client-driven queries (analytics / dashboard), but do not introduce
      it in v1 to keep the surface simple.
- Content format
    - All endpoints produce and consume JSON (application/json). Use UTF-8 encoding and ISO-8601 timestamps (UTC).
- Versioning
    - Use versioned path segments: /api/v1/...
    - Version in the Accept or custom header is optional but path-based versioning is mandatory for the initial release.
- Idempotency and safe semantics
    - POST endpoints that create jobs/resources should support an Idempotency-Key header for safe retries (
      Idempotency-Key: <uuid-or-client-generated>).
    - GET endpoints must be safe and cacheable (when appropriate). Use Cache-Control headers.
- Pagination & filtering
    - For list endpoints, use limit/offset or cursor-based pagination depending on expected volume. Default limit=50,
      max limit=1000.
    - Support filtering by common fields (e.g., namecode, user_id, troop_id) and sorting.
- Error model
    - Use a consistent error response structure (see section 8.3).
- Documentation & schema
    - Publish OpenAPI 3.0+ specification at /openapi.yaml and human-readable docs at /docs/api.
    - Include examples for common flows (snapshot ingest, fetch summary, reprocess).
- Backwards compatibility
    - Additive changes only within a major version (v1): adding new optional response fields is allowed; removing or
      renaming fields requires a new major version (v2).
- Security first
    - Enforce TLS for all traffic, require authentication for internal and admin endpoints, and apply rate limiting &
      quotas.
- Observability
    - Include correlation IDs (X-Request-Id / X-Correlation-Id) for tracing requests end-to-end (ingest → queue →
      worker).

---

### 8.2 Authentication & Authorization

- Auth types supported
    - Service-to-service bearer tokens (signed JWTs) for internal services and GitHub Actions. Validate signature via
      JWKS or shared secret.
    - API keys (opaque tokens) for CLI clients when needed (ingest uploads). API keys scoped and revocable.
    - Admin tokens (OIDC or short-lived JWT) for admin endpoints; RBAC enforced server-side.
    - OAuth2 for optional user-based flows (Discord linking) — only where user consent is explicitly required.
- Least privilege & scopes
    - Tokens must be scoped. Example scopes:
        - ingest:snapshots — allow POST /api/v1/internal/snapshots
        - read:profiles — allow GET /api/v1/profile/summary/*
        - admin:snapshots — allow reprocess and admin actions
        - migrate:apply — allow running migrations (CI workflow only)
    - Do not use a single global token with full access in production; prefer environment-scoped tokens and short-lived
      tokens for human-triggered workflows.
- Admin RBAC
    - Admin endpoints require authentication AND role check. Roles: admin, maintainer, operator, analyst. Only
      admin/maintainer roles may trigger production migrations or archive operations.
- Key lifecycle & rotation
    - Enforce rotation for long-lived keys (e.g., API keys rotated every 90 days).
    - Provide an API to list and revoke API keys for service accounts.
- Credential storage
    - Secrets stored in a secrets manager (provider-specific) in runtime; GitHub Actions use repository secrets and
      protected environments.
- Auditing
    - Log admin actions (who triggered, when, on which snapshot/migration). Audit logs must not contain raw secrets or
      full snapshots (store only references/hashes).
- Client guidance
    - Require clients to set User-Agent with app name and version (User-Agent: StarForgeCLI/0.1) to aid support and rate
      limiting.

---

### 8.3 Endpoints (list)

All endpoints are under /api/v1. Below are primary endpoints for the initial vertical slice. Each entry shows method,
request/response examples and error cases.

Common error response format (JSON)

- HTTP status >= 400:
  {
  "error": {
  "code": "ERROR_CODE",
  "message": "Human-readable message",
  "details": { /* optional additional data */ },
  "request_id": "uuid"
  }
  }
- Example error codes:
    - INVALID_PAYLOAD, UNAUTHORIZED, FORBIDDEN, NOT_FOUND, CONFLICT, RATE_LIMIT_EXCEEDED, SERVER_ERROR,
      PAYLOAD_TOO_LARGE, DUPLICATE_SNAPSHOT

1) POST /api/v1/internal/snapshots

- Purpose: Accept a raw get_hero_profile JSON payload and create a hero_snapshots row (internal ingestion).
- Auth: Bearer token with scope ingest:snapshots or valid API key.
- Idempotency: Support Idempotency-Key header (recommended).
- Request (application/json)
  {
  "source": "fetch_by_namecode" | "login" | "cli_upload",
  "namecode": "COCORIDER_JQGB", // optional but recommended
  "payload": { /* full get_hero_profile JSON */ }
  }
    - Headers:
        - Authorization: Bearer <token>
        - Idempotency-Key: <uuid> (optional)
        - X-Request-Id: <uuid> (optional)
- Responses:
    - 201 Created
      {
      "snapshot_id": "uuid",
      "status": "queued",
      "created_at": "2025-11-28T12:34:56Z"
      }
    - 202 Accepted (when accepted but queued)
      {
      "snapshot_id": "uuid",
      "status": "queued",
      "estimated_processing_seconds": 10
      }
    - 409 Conflict (duplicate within dedupe window)
      {
      "snapshot_id": "existing-uuid",
      "status": "duplicate",
      "message": "Identical snapshot detected within dedupe window"
      }
    - 400 Bad Request (invalid JSON / missing payload)
    - 413 Payload Too Large (size limit exceeded) with guidance
    - 401 Unauthorized / 403 Forbidden
    - 429 Rate limit exceeded
    - 500 Server error (includes request_id)
- Notes:
    - Server calculates content_hash (SHA256) and size_bytes. If namecode can be extracted server-side, it attempts to
      map to users.id.

2) GET /api/v1/profile/summary/:namecode

- Purpose: Return denormalized profile_summary for a given namecode; fallback behavior documented.
- Auth: Public read allowed (no auth) or read:profiles scope if private deployment.
- Request
    - Path param: namecode (string)
    - Query params (optional):
        - source=cache|latest — prefer cached summary or compute ad-hoc from latest processed snapshot
- Success Response (200 OK)
  {
  "namecode": "COCORIDER_JQGB",
  "user_id": "uuid",
  "username": "Coco",
  "level": 52,
  "top_troops": [
  { "troop_id": 6024, "amount": 15, "level": 3 },
  { "troop_id": 6010, "amount": 8, "level": 2 }
  ],
  "equipped_pet": { "pet_id": 101, "level": 2 },
  "pvp_tier": 4,
  "guild": { "id": "uuid", "name": "GuildName" },
  "last_seen": "2025-11-28T12:00:00Z",
  "cached_at": "2025-11-28T12:01:00Z"
  }
- Alternate responses:
    - 202 Accepted
      {
      "message": "Profile processing in progress",
      "estimated_ready_in_seconds": 30
      }
    - 404 Not Found { "message": "No profile found" }
    - 429 Rate limit exceeded
    - 500 Server error

3) GET /api/v1/profile/raw/:namecode

- Purpose: Return latest processed hero_snapshot.raw for a namecode (restricted).
- Auth: read:profiles scope or admin access for raw snapshot access.
- Response:
    - 200 OK { "snapshot_id": "uuid", "payload": { ... full raw JSON ... }, "created_at": "..." }
    - 403 Forbidden if client lacks permission
    - 404 Not Found
- Notes:
    - Raw snapshot may contain sensitive fields (tokens); only expose to trusted clients and redaction may occur based
      on policy.

4) POST /api/v1/admin/snapshots/:id/reprocess

- Purpose: Enqueue an existing snapshot for reprocessing by the ETL worker.
- Auth: Admin scope admin:snapshots; requires RBAC.
- Request: no body required.
- Responses:
    - 202 Accepted { "job_id": "uuid", "status": "enqueued" }
    - 404 Not Found
    - 409 Conflict (snapshot currently processing)
    - 401/403 Unauthorized / Forbidden
- Audit:
    - Log requester ID, snapshot_id, timestamp and reason (optional).

5) GET /api/v1/admin/snapshots/:id/status

- Purpose: Return processing status and errors for a given snapshot id.
- Auth: admin:snapshots
- Response:
  {
  "snapshot_id": "uuid",
  "processing": false,
  "processed_at": "2025-11-28T12:10:00Z",
  "error_count": 0,
  "last_error": null
  }

6) GET /api/v1/health

- Purpose: Readiness/liveness check for orchestration. Minimal response for health probes.
- Auth: none (or token if cluster requires)
- Response:
    - 200 OK { "status": "ok", "timestamp": "..." }
    - 503 Service Unavailable when dependent systems unhealthy
- Implementation:
    - Health check should validate DB connectivity (light query), queue connectivity (PING), and optionally S3
      reachable.

7) GET /metrics

- Purpose: Prometheus metrics endpoint for the service and worker.
- Auth: IP-restricted or bearer token (prometheus scrape jobs).
- Response: text/plain; version=0.0.4 with metrics lines.

8) POST /api/v1/admin/migrations/apply (optional / restricted)

- Purpose: Trigger a migration run in CI context (rare; normally performed via GitHub Action). Very restricted.
- Auth: migrate:apply and require environment approval / multi-person auth.
- Response:
    - 202 Accepted { "job_id": "uuid", "status": "started" }
    - 403 Forbidden if not allowed
- Notes:
    - Prefer the GitHub Actions workflow for production migrations. This endpoint is optional and must be heavily
      guarded.

9) GET /api/v1/admin/exports?entity=user_troops&from=...&to=...

- Purpose: Trigger or query export jobs that write CSV/Parquet to S3 for analytics.
- Auth: admin or analyst scope
- Response: job listing with status and s3_path once complete.

---

### 8.4 Rate limiting and throttling policy

- Objectives
    - Protect upstream systems (our API, the DB and third-party APIs), provide fair usage and avoid abuse.
- Policy overview
    - Public read endpoints (GET /profile/summary):
        - Default per-IP: 60 requests/minute
        - Burst: 120 requests in short window allowed, then throttled
        - Authenticated clients (with API key) may get higher quotas (e.g., 600 req/min) subject to plan.
    - Ingestion endpoints (POST /internal/snapshots):
        - Per-api-key limit: 30 requests/min by default for CLI clients (configurable); service clients allowed higher
          quotas.
        - Enforce per-client concurrency limits to avoid fan-out storms to ETL workers.
    - Admin endpoints:
        - Strict low-rate limits and additional checks (e.g., require two-person approval for migration triggers).
    - Bot endpoints:
        - Commands are rate limited per guild/user according to Discord best practices; enforce additional server-side
          rate limits to avoid abuse.
- Enforcement & headers
    - Use token-based rate limiting where possible (rate limits keyed by API key or bearer token).
    - Return standard rate-limit headers:
        - X-RateLimit-Limit: <limit>
        - X-RateLimit-Remaining: <remaining>
        - X-RateLimit-Reset: <unix-timestamp>
    - On limit exceeded return 429 Too Many Requests with:
      {
      "error": { "code": "RATE_LIMIT_EXCEEDED", "message": "Rate limit exceeded", "retry_after": 30 }
      }
- Throttling & backpressure
    - For queue saturation (queue depth high) return 202 Accepted with "queued" response and estimated ETA rather than
      accepting more work that will overload workers.
    - Provide graceful degradation: if write path is saturated, serve read-only cached summaries with explanation to
      clients.
- Abuse detection
    - Monitor for abnormal patterns and apply temporary IP blacklisting, challenge flows or manual review.
- Client recommendations
    - Clients should respect Retry-After header and implement exponential backoff with jitter for retries.
    - Use pagination to limit result sizes.

---

### 8.5 API versioning & deprecation policy

- Versioning strategy
    - Major version in path: /api/v1/... . When breaking changes are required, introduce /api/v2/ and deprecate /api/v1
      per policy below.
    - Semantic versioning for SDKs and API clients; server-side follows path-major-versioning.
- Deprecation policy
    - Non-breaking (additive) changes: no deprecation required; clients should handle extra optional fields.
    - Breaking changes:
        - Announce deprecation at least 90 calendar days prior to removal (for public endpoints).
        - Provide migration guide and example mapping, and a compatibility layer where feasible.
        - Emit Deprecation headers on responses for deprecated endpoints:
            - Deprecation: true
            - Sunset: <RFC 1123 date>
            - Link: <URL to migration guide>
        - Examples:
            - Response header: Deprecation: true
            - Response header: Sunset: Tue, 27 Feb 2025 00:00:00 GMT
            - Response header: Link: <https://docs.example.com/migration-guide>; rel="sunset"
- Version negotiation
    - Support clients that include Accept header versioning temporarily, but path-based versioning is authoritative.
- Grace period & support
    - Maintain backward compatibility shims where reasonable.
    - During deprecation window offer a compatibility testing sandbox and provide sample code/libraries to ease
      migration.
- Breaking-change approval & communication
    - Any breaking change must be approved by Product and Engineering leads.
    - Announce via release notes, mailing list, GitHub release and docs.
- Emergency patches
    - For security critical changes requiring immediate breaking change, apply emergency channel and communicate impact,
      provide a temporary mitigation path.
- OpenAPI & docs per version
    - Publish /openapi-v1.yaml, /openapi-v2.yaml when multiple versions exist. Keep docs for older versions available
      until sunset.

---

References & artifacts

- OpenAPI definition: /openapi.yaml (generate from code or maintain manually).
- API docs: /docs/api (user-friendly).
- Admin & migration runbooks: docs/OP_RUNBOOKS/*.
- Client SDKs and examples: /clients (optional — add TypeScript/Node example for snapshot ingestion and profile read).

## 9. UI / UX

This section defines design goals, constraints, wireframe links, detailed interaction behavior per screen, accessibility
requirements and responsive behavior for the Profile & DB Foundation features. The intent is to provide clear guidance
to designers and frontend engineers so UX decisions are consistent with operational, security and performance needs.

---

### 9.1 Design goals & constraints

Design goals

- Clarity & speed: present the most important player information (summary) quickly and clearly. The primary read path
  must be lightweight and highly cacheable.
- Progressive disclosure: show a compact summary by default and allow drilling into details (inventory, teams, raw
  snapshot) on demand.
- Predictability: indicate freshness of data and processing status (queued / processing / processed) with consistent
  affordances.
- Operational safety: provide clear admin UI states for ETL jobs, reprocess actions and migration triggers; require
  confirmations for destructive operations.
- Privacy-aware: clearly label any view that exposes raw snapshots and require elevated permissions to see sensitive
  fields.
- Developer-friendly: include sample data, debug mode and links to underlying snapshot id for troubleshooting.

Design constraints

- Performance: primary summary must load from a denormalized cache (user_profile_summary) and be served under latency
  targets (p95 < 200ms). Avoid heavy client-side parsing of raw JSON.
- Security: raw snapshot view restricted to authenticated and authorized users; UI must not display secrets (tokens)
  even for privileged users — redact or mask them.
- Consistency: align visual language with existing branding and the Discord embed style for bot responses.
- Minimal scope: initially provide a compact set of screens (Summary, Raw Snapshot viewer, Admin/ETL dashboard). Expand
  only after validating usage patterns.

Design tokens & components (suggested)

- Color tokens: primary, secondary, success, warning, danger, neutral; ensure WCAG contrast.
- Typography tokens: scale for headings, body, monospace for raw JSON.
- Components: Card, Badge (status), Table, Collapsible panel, Modal (confirm), SearchBar, Pagination,
  AsyncActionButton (shows spinner / progress), CodeBlock (syntax-highlighted JSON), EmptyState, Toasts/Notifications.

---

### 9.2 Wireframes / mockups (links to design files)

Design files location (placeholders to update with real URLs)

- Figma (recommended): https://www.figma.com/file/XXXX/StarForge-Designs (replace with actual team Figma URL)
- Repository design folder: /design (store exported PNG/SVG wireframes and final assets)
- Example image files:
    - docs/design/wireframes/profile_summary_desktop.png
    - docs/design/wireframes/profile_summary_mobile.png
    - docs/design/wireframes/admin_etl_dashboard.png
    - docs/design/wireframes/raw_snapshot_viewer.png

What to include in the design repository

- Low-fidelity wireframes for desktop and mobile for each screen listed below.
- High-fidelity mockups / component-library tokens.
- Interaction prototypes for critical flows: fetch snapshot, ETL job lifecycle, reprocess snapshot, migration workflow
  approval.
- Exported assets for Discord embeds (icons, small thumbnails).

Notes for designers

- Provide a compact “bot embed” mock that mirrors the Discord message card: title, small icon, level & top troops as
  inline fields, CTA link to full profile.
- Annotate mockups with accessibility notes (contrast ratios, keyboard order, ARIA roles).
- Include states: loading, empty, error, stale data (cached_at older than threshold).

---

### 9.3 Interaction details per screen

This subsection documents screen-by-screen interactions (user inputs, expected responses, validation, and error
handling). Screens prioritized for first release are marked P0.

Screen: Profile Summary (P0)

- Purpose: Show denormalized, quick-read information about a player.
- Primary elements:
    - Header: Player name, NameCode, level, small avatar / thumbnail
    - Status badge: processed / processing / pending
    - Key stats: level, PvP tier, guild, last_seen
    - Top Troops: list of top 3–5 troops with icons, amount, and small stat badges
    - Equipped pet: icon + level
    - Actions: Refresh (trigger a new fetch), View Raw Snapshot, Report Issue
    - Footer: cached_at timestamp and "last updated" tooltip
- Inputs & interactions:
    - Click Refresh: POST to /api/v1/internal/snapshots with source=ui_fetch (requires auth) or trigger client-side
      instruction to run CLI; show toast "Snapshot requested" and estimated ETA.
    - View Raw Snapshot: opens Raw Snapshot viewer in modal or new page (auth gated).
    - If status == processing: show progress spinner and disable actions that would trigger further duplicate fetches;
      provide ETA if available.
- Validation & error handling:
    - If API returns 202 (pending): show non-blocking banner "Processing, expected in ~30s".
    - If profile not found: show call-to-action "Fetch profile by NameCode" with input field and button, validate
      namecode format client-side.
    - On network/API error: show inline error toast with request id and "Retry" option.

Screen: Raw Snapshot Viewer (P1)

- Purpose: Allow privileged users to view the stored JSONB and metadata for debugging and audit.
- Primary elements:
    - Metadata header: snapshot_id, created_at, size_bytes, content_hash, processed_at, error_count
    - JSON viewer: pretty-printed JSON with collapsible nodes, line numbers, search within JSON
    - Controls: Download JSON, Copy link, Redact/Mask sensitive fields toggle (always mask tokens by default), Reprocess
      button (admin)
    - Audit panel: ETL errors for this snapshot and processing history
- Inputs & interactions:
    - Search box filters JSON keys and values, highlights matches.
    - Download triggers GET /api/v1/profile/raw/:namecode or snapshot export (auth).
    - Reprocess: shows modal confirm (require typing "REPROCESS" or similar), then POST admin reprocess endpoint; show
      enqueue toast and job id.
- Validation & security:
    - Redact tokens and known sensitive keys automatically on client (and server side).
    - Require admin auth for reprocess and raw download.
    - Confirm destructive actions and record audit entries.

Screen: Admin / ETL Dashboard (P0)

- Purpose: Monitor queue, worker health, recent failures, top error reasons and process snapshots manually.
- Primary elements:
    - Summary tiles: queue depth, processing rate (per minute), success rate, failure rate.
    - Recent snapshots list: snapshot_id, namecode, size, status, created_at, processed_at, error_count, quick actions (
      view, reprocess)
    - Failure trends chart (time series)
    - Worker pool status: instance list, memory/CPU, last heartbeat, current job id
    - Retention controls: run retention job, configure retention thresholds
- Inputs & interactions:
    - Click snapshot row to open Raw Snapshot Viewer.
    - Bulk reprocess: select snapshots and enqueue reprocess (confirm modal).
    - Pause queue / Pause worker: confirmed action with reason required.
    - Export errors: download CSV of latest etl_errors.
- Validation & error handling:
    - Action confirmations required for bulk or destructive operations.
    - All admin actions generate audit logs visible on the panel.
    - Show warn banner if queue depth > threshold or worker heartbeats missing.

Screen: Migrations & Bootstrap UI (P1)

- Purpose: Provide a controlled UI for reviewing migration plans and triggering the protected GitHub Action for
  production bootstrap (optional — primarily run via Actions).
- Primary elements:
    - List of pending migrations with descriptions, author and migration id
    - Preflight checks panel that shows required extensions, estimated index size and pre-check results
    - Trigger button: "Run Bootstrap (Requires Approval)" — links to GitHub Actions run or triggers action via API (if
      implemented)
    - Audit trail of past bootstrap runs with logs
- Inputs & interactions:
    - Preflight must pass before allowing run; if fails, show remediation steps.
    - On trigger, require approver identity (GitHub environment approval or multi-person confirmation).
- Safety:
    - UI should not expose DATABASE_URL or secrets. Only provide links to logs and artifacts.

Screen: Exports & Analytics (P2)

- Purpose: Allow analysts to request exports of materialized/relevant views to S3.
- Interactions:
    - Select entity (user_troops), date-range picker, choose format (CSV/Parquet), submit export job.
    - Show job status and S3 link when complete.
    - Validate ranges to avoid huge exports; if too large, suggest incremental export.
- Permissions:
    - Analyst/admin scope only.

Screen: Onboarding / Developer Docs (P0)

- Purpose: Offer one-click links and quick instructions to set up local dev environment.
- Contents:
    - Quick start steps, sample payloads, button to insert sample snapshot (local only), link to migration docs.
    - Troubleshooting tips for extension permission errors and common failures.

Cross-cutting interaction patterns

- Confirmations: destructive or high-impact actions require typed confirmation and display expected consequences.
- Idempotency: UI must set and present Idempotency-Key when making snapshot ingest requests so retries are safe.
- Feedback: every async action returns immediate UI feedback (toast + job id) and updates dashboard when job completes
  via websocket or polling.
- Visibility: show timestamps (UTC) and relative times (e.g., "5 minutes ago") with tooltip showing exact ISO timestamp.

---

### 9.4 Accessibility considerations (keyboard nav, screen readers)

Accessibility goals

- Follow WCAG 2.1 AA where reasonable for public-facing screens; aim for compliance on documentation and admin consoles.
- Ensure keyboard-only users and screen reader users can perform core tasks (view summary, trigger fetch, view errors).

Specific requirements & implementation notes

- Semantic HTML: use proper headings (h1..h6), lists, tables, forms and landmarks (role="main", role="navigation",
  role="complementary").
- ARIA attributes: provide ARIA labels for interactive controls (modals, confirm dialogs, buttons without textual
  labels).
- Focus management:
    - On modal open: move focus to the first interactive element; on close return focus to invoking control.
    - Provide visible focus indicators for all focusable elements.
- Keyboard navigation:
    - All controls accessible via Tab / Shift+Tab.
    - Provide keyboard shortcuts for frequent admin actions (e.g., reprocess selected snapshots) but make them
      discoverable and optional.
- Screen reader support:
    - Provide descriptive alt text for images and icons.
    - Announce dynamic updates (toasts, job status changes) via aria-live regions.
    - For the JSON viewer provide a "Toggle collapsed/expanded" control and text-mode view optimized for screen
      readers (collapsible structure with headings).
- Contrast & typography:
    - Maintain contrast ratio >= 4.5:1 for body text and 3:1 for large text per WCAG guidance.
    - Avoid relying on color alone to communicate status; use icons and text labels.
- Motion & reduced-motion:
    - Respect prefers-reduced-motion; provide reduced animations if user prefers.
- Forms & error messages:
    - Associate labels with inputs; provide inline error messages with aria-describedby linking to the error text.
- Testing & validation:
    - Include automated accessibility checks in CI (axe-core, pa11y).
    - Conduct manual testing with a screen reader (NVDA/VoiceOver) on key screens.

---

### 9.5 Responsive behavior (mobile / tablet / desktop)

Responsive design principles

- Progressive enhancement: keep the core experience (summary read, refresh request) usable on low-bandwidth / low-CPU
  devices.
- Breakpoints (suggested):
    - Small (mobile): up to 600px
    - Medium (tablet): 600px–1024px
    - Large (desktop): 1024px+
- Layout adjustments
    - Profile Summary:
        - Mobile: single column card; header with avatar and name, followed by vertical list of stats; action buttons
          stacked.
        - Tablet: two-column layout — header + key stats left, top troops and actions right.
        - Desktop: multi-column with expanded top troops, quick actions, and last_seen + cached_at in header.
    - Raw Snapshot Viewer:
        - Mobile: show truncated JSON with "Open Full" link to download or open in a separate view; provide search but
          limit initial expansion to avoid extremely long DOM.
        - Desktop: full collapsible JSON tree with side-by-side metadata panel.
    - Admin Dashboard:
        - Mobile: present only the most critical tiles (queue depth, recent failures) and allow navigation to full
          desktop UI for advanced operations.
        - Desktop: full dashboard with charts, tables and controls.
- Touch targets & spacing
    - Ensure tap targets are >= 44x44 px for mobile.
    - Use adequate spacing to avoid accidental taps.
- Performance considerations for mobile
    - Lazy-load heavy components (charts, JSON tree) and prefer server-side rendered summaries for initial paint.
    - Use compressed images and optimized icons (SVG).
- Offline & poor connectivity
    - Provide graceful messages when offline or when API is unreachable, and allow queuing of non-sensitive actions
      locally if relevant (e.g., store a requested snapshot request to retry).
- Discord bot experience
    - Discord embeds are single-card content: keep messages short and provide a link to the web UI for details. Design
      embed messages to display well on mobile Discord clients.
- Testing
    - Validate on a matrix of devices (Android/iOS) and browsers (Chrome, Firefox, Safari) and ensure performance meets
      p95 targets.

---

Appendix: UI copy & microcopy guidance

- Use concise, action-oriented labels: "Fetch profile", "Reprocess snapshot", "Download JSON".
- Status language:
    - "Processed" — snapshot fully processed and summary available.
    - "Processing" — ETL in progress; provide ETA where possible.
    - "Queued" — snapshot enqueued for ETL.
    - "Failed" — show a short reason and link to error details.
- Confirm dialogs should explicitly state consequences, e.g., "Reprocessing will re-run ETL for this snapshot and may
  overwrite current normalized records. Type REPROCESS to confirm."

---

## 10. Integrations & External Systems

This section lists each external system we integrate with, the expected contract, security considerations, operational
needs and best practices. Use it as an integration checklist for implementation, CI, runbooks and security review.

---

### 10.1 Discord bot integration (scopes, intents, webhooks)

Overview

- Purpose: provide player-facing commands (e.g., /profile), notifications, and optional guild admin features via a
  Discord bot.
- Clients: Bot runs as a service (Node.js/TypeScript) connecting to Discord Gateway and calling our backend APIs.

Bot token & secrets

- Store the bot token in secrets (GitHub Secret: DISCORD_TOKEN; runtime: secrets manager). Never commit tokens.
- Use short-lived OAuth flows for any user-level consent (if linking accounts), avoid storing user tokens long-term.

Required Bot Scopes

- Bot OAuth scopes:
    - bot — add the bot to guilds
    - applications.commands — register slash commands
    - identify (if linking to users)
    - email (only if explicitly required and consented)
- Recommended optional scopes:
    - guilds.members.read — only if bot needs member discovery and compliant with Discord policies (review privacy
      implications)

Recommended Gateway Intents

- Privileged intents require enabling in the developer portal and may require justification:
    - GUILD_MEMBERS (privileged) — only if you need member join events or mapping users to guilds. Avoid unless strictly
      necessary.
    - GUILD_PRESENCES (privileged) — usually unnecessary; avoid for privacy and rate reasons.
- Non-privileged:
    - GUILDS — required
    - GUILD_MESSAGES — if bot reacts to messages
    - DIRECT_MESSAGES — only if bot supports DMs

Slash Commands & Webhook Patterns

- Use slash commands for profile lookup: /profile <namecode>
    - Command handler calls GET /api/v1/profile/summary/:namecode
    - If profile not ready, reply ephemeral "Profile processing — try again in ~30s"
- Use interaction responses and followups properly (within interaction timeout) and include links to full profile in web
  UI.
- Use webhooks for asynchronous notifications only if necessary (e.g., bulk ETL completion notifications to a given
  channel) and restrict webhook URLs to server-side config.

Rate limits & retry logic

- Respect Discord's rate limits. Use Discord library's built-in rate limiting.
- Add retry with exponential backoff for 429 responses and log incidents (Sentry).
- Avoid heavy operations inside interaction handlers; delegate to background jobs.

Security & privacy

- Mask or never display tokens, private identifiers or PII in bot messages.
- If linking Discord user to a NameCode or internal user_id, require explicit user command/consent and store mapping in
  DB with clear audit log.
- Use separate ephemeral tokens for webhooks if you must expose them.

Operational considerations

- Auto-sharding or multiple bot instances: use recommended sharding or a gateway manager when scaling.
- Monitor bot health: register heartbeats and expose metrics (command_count, error_count, avg_latency).
- Provide a "maintenance" mode command to disable features during migrations.

Testing

- Use a sandbox Discord application and test guilds.
- Provide sample tokens in a secure test secrets store for CI e2e tests (rotate regularly).

---

### 10.2 Supabase / Postgres (connection, roles, backups)

Overview

- Primary data store: managed Postgres (Supabase or equivalent).
- Use Postgres for hero_snapshots (JSONB), normalized tables and small catalogs.

Connection & configuration

- Use DATABASE_URL from runtime secrets (format: postgres://user:pass@host:port/dbname?sslmode=require).
- Enforce SSL (PGSSLMODE=require) in production.
- Use connection pooling (pgbouncer) or the provider's connection pool to avoid hitting connection limits from many
  workers/clients.
- Set statement timeouts and connection timeouts (application-side) to prevent long-running queries from blocking.

Roles & least privilege

- Define separate DB roles/users:
    - migrations_role: used by migration jobs, limited to DDL operations in non-production or specifically granted on
      production with approvals.
    - app_write_role: used by API & workers for DML and ETL upserts.
    - app_read_role: read-only used by analytics and dashboards.
    - admin_role: only for emergency & DBA tasks (not used in app runtime).
- Use separate credentials for CI (migrations) with limited scope and require environment approvals to run production
  migrations.

Extensions & provider constraints

- Preferred extension: pgcrypto (gen_random_uuid()). If provider disallows extension creation, document fallback (
  generate UUIDs client-side or use alternative).
- Avoid extensions that require superuser privileges unless provider allows them.

Backups & retention

- Use provider-managed automated backups (daily snapshots) and enable continuous WAL archiving when available.
- Backup retention policy: at least 90 days for quick restore; archive older snapshots per organization policy.
- Periodically test restores (quarterly or as defined in BACKUP_RESTORE.md) and record the exercises.

Monitoring & maintenance

- Monitor:
    - connection count
    - long-running queries
    - replication lag (if using replicas)
    - index bloat and vacuum stats
- Set alerts for high connection counts or replication lag.
- Use partitioning for hero_snapshots if volume grows (monthly partitions).

Migrations & schema changes

- Use node-pg-migrate for migrations; run migrations first in staging.
- Use migration preflight checks (check CREATE EXTENSION permissions, estimate index build time).
- Apply production migrations only via manual GitHub Actions workflow with environment protection.

Security

- Restrict public DB access via network rules (VPC, allowlist).
- Rotate DB credentials regularly and after incidents.
- Use encryption at rest and in transit.

Secrets & connectivity for CI

- Store DATABASE_URL in GitHub Secrets for GitHub Actions.
- Avoid echoing secrets in logs. Use run steps that mask secrets and use environment protection.

Operational procedures

- Scale read replicas for analytics and high read throughput.
- For heavy backfills, use isolated worker instances and throttled concurrency to limit write pressure.

---

### 10.3 Google APIs (service account usage)

Overview

- Use Google service accounts for any CI or infrastructure tasks requiring Google Cloud (optional).
    - Common uses: uploading artifacts to GCS, running Cloud tasks, secret access for GCP-hosted resources.

Service account & key handling

- Use a dedicated service account per purpose (CI, backup, monitoring).
- Prefer Workload Identity or OIDC (GitHub Actions -> GCP) over long-lived JSON keys when possible.
- If JSON keys are required, store them encrypted as GitHub Secrets (GOOGLE_SA_JSON) and restrict access to protected
  workflows/environments.

Scopes & permissions

- Principle of the least privilege:
    - Give service accounts only the minimal IAM roles required (e.g., storage.objectAdmin for uploads, but prefer
      granular roles).
    - Avoid broad roles like Owner.

Example usage patterns

- GitHub Actions authenticates to GCP to upload artifacts to GCS or run export jobs.
- Scheduled backups may push export files to a GCS bucket (or S3) using the service account.

Security & rotation

- Rotate service account keys periodically if used.
- Audit IAM bindings and service account usage logs.

Alternative & recommended patterns

- Prefer cloud provider-native authentication methods:
    - For GCP: use Workload Identity Federation from GitHub Actions to eliminate JSON keys.
    - For AWS: use OIDC or short-lived STS tokens.

---

### 10.4 CI/CD & Container Registry (GH Actions, GHCR)

Overview

- CI/CD via GitHub Actions.
- Container images and artifacts published to GitHub Container Registry (GHCR) or other registries as required.

Workflows & environments

- Key workflows:
    - ci.yml — run tests, lint, build artifacts
    - build-and-publish.yml — build containers and publish to GHCR with tags (pr-<pr-number>, sha-<sha>, latest on main)
    - db-bootstrap.yml — manual workflow_dispatch for running migrations/bootstraps (protected environment, approver
      required)
    - deploy.yml — deploy to staging/prod (manual approvals for prod)
- Use GitHub Environments to protect production secrets and require approvals for production bootstrap/deploy jobs.

Secrets & artifacts

- Store secrets in GitHub repository or organization secrets, restrict to environments.
- Examples: DATABASE_URL, DISCORD_TOKEN, REDIS_URL, GHCR_PAT (or use built-in GITHUB_TOKEN with package permissions).
- Mask secrets in logs and avoid printing them.
- Configure artifact retention in Actions settings (short retention for logs unless required).

Image tagging & retention

- Tag images:
    - owner/repo:pr-<pr>, sha-<short-sha>, v<semver>, latest (only for main)
- Use immutable tags for released versions (vX.Y.Z).
- Configure GHCR retention and cleanup policy for old images (avoid unbounded storage).

Security in CI

- Use Dependabot for dependency updates and run dependency scanning in CI.
- Use SAST and license checks in CI (optional).
- Use OIDC federated credentials where supported to avoid storing long-lived cloud keys.

Deployment & rollout

- Canary / blue-green deployments recommended for stateful services.
- Use feature flags in code to control rollout of new behaviors.

Access control & auditing

- Limit who can approve workflows for protected environments.
- Audit GitHub Actions runs and who triggered them.

Testing & promotion

- Require all migration PRs to run a migration sanity job in CI against a disposable DB container.
- Promote changes to staging only after CI passes; production deployment requires manual approval.

---

### 10.5 Monitoring & Logging providers (e.g., Prometheus, Grafana, Sentry)

Overview

- Observability stack to monitor ETL worker, API services, queue health, DB metrics and alert on anomalies.

Metrics & monitoring

- Metrics exported by services:
    - ETL worker: processed_count, success_count, failure_count, processing_time_histogram, queue_depth_gauge
    - API: http_requests_total, http_request_duration_seconds, error_rate
    - DB: connections, active queries, replication lag, slow queries
    - Infrastructure: CPU, memory, disk, network
- Prometheus:
    - Scrape instrumented metrics endpoints (/metrics).
    - Retention: per org policy; use long-term storage for analytics if needed.
- Grafana:
    - Dashboards:
        - ETL overview (throughput, latency, queue depth)
        - Snapshot ingestion & failures
        - DB health & query performance
        - Worker instance metrics and resource usage
    - Alerts: create alert rules for thresholds described in NFRs (ETL failure spikes, queue depth, high latency)

Error tracking & logs

- Sentry:
    - Capture exceptions and errors in worker and API.
    - Sanitize events to remove PII and tokens.
    - Use environment tags (staging/prod) and sampling to control volume.
- Structured logging:
    - JSON logs with fields: timestamp, service, level, snapshot_id/job_id, request_id, message, details.
    - Centralized aggregation (ELK stack, Logflare, Datadog logs).
    - Index common fields (snapshot_id, user_id, error_type) to make searching easier.

Tracing

- Distributed tracing (optional but helpful): instrument with OpenTelemetry and forward to a tracing backend (Jaeger,
  Tempo).
- Include correlation ids in logs and traces (X-Request-Id or traceparent).

Alerting & incident management

- Medium: Alerts via Slack, PagerDuty, or email for critical issues.
- Define alert severity and on-call rotation in runbooks.
- Example alert thresholds:
    - ETL failure rate > 1% sustained for 5 min → P0 alert
    - Queue depth > threshold for 10 minutes → P1 alert
    - DB connection count > 80% of limit → P1 alert

Retention & privacy

- Log retention policy: store logs for N days (configurable); anonymize or redact sensitive fields before long-term
  storage.
- Sentry retention and sampling to avoid storing sensitive data.

Testing & validation

- Include observability tests in CI: ensure metrics endpoint is reachable and basic counters increment when running test
  flows.

---

### 10.6 Other third-party services

This subsection covers additional services we likely use or consider integrating. Each entry includes purpose, key
constraints and operational guidance.

Redis / Queue (BullMQ, RQ, Sidekiq, etc.)

- Purpose: durable job queue for ETL tasks and background jobs.
- Choices: Redis-backed (BullMQ) or a hosted queue (AWS SQS, Google Pub/Sub) for durability.
- Notes:
    - Redis must be sized for concurrency and not used as primary persistence.
    - Ensure persistence if required and monitor memory usage.
    - Consider durable queue options (SQS) if Redis availability is a concern.

Object Storage (S3 / Spaces / MinIO)

- Purpose: archive old snapshots, store exports (CSV/Parquet), store artifacts.
- Security:
    - Use dedicated buckets, enforce IAM policies and encryption (SSE).
    - Use lifecycle rules to move archived data to colder tiers and remove older backups per retention.
- Performance:
    - When uploading many files in parallel, follow provider guidelines for prefixes and parallel requests.

Email / Notifications (SES, SendGrid)

- Purpose: notify admins about ETL failures, migration results, or user-facing notifications.
- Notes:
    - Use verified domains, monitor quotas and bounce rates.
    - Keep email templates for incident notifications.

Dependency Scanning & Security Tools

- Dependabot (GitHub), Snyk, WhiteSource
- Purpose: detect vulnerable dependencies and license issues.
- Integrate scans into CI and require fixes for critical vulnerabilities.

Secrets Manager

- Purpose: store runtime secrets securely (AWS Secrets Manager, GCP Secret Manager, Vault).
- Integration:
    - Fetch secrets at runtime with minimal latency and caching.
    - Audit access and rotate secrets regularly.

CI Artifacts & Storage (GitHub Packages, GHCR)

- Purpose: store built container images and artifacts.
- Policies:
    - Retention and cleanup policy for storage.
    - Access control and package permissions.

Analytics / BI (Snowflake, BigQuery, Redshift, or ETL to CSV)

- Purpose: heavy analytics and reporting (materialized views or periodic exports).
- Considerations:
    - Use scheduled exports to avoid hitting transactional DB during work hours.
    - Sanitize PII before exporting.

Payment Providers (if future monetization)

- Purpose: handle in-app purchases or subscriptions.
- Considerations:
    - PCI compliance out of scope until payments added. Plan carefully before adding.

CDN (Cloudflare, Fastly)

- Purpose: accelerate static assets and protect APIs (WAF).
- Use for: hosting web UI assets, protecting API endpoints with rate-limiting and WAF rules.

License & Third-party dependency inventory

- Maintain a list of third-party services, versions and licenses in docs/THIRD_PARTY.md and enforce policies for
  acceptable licenses.

---

Integration checklist (practical)

- [ ] Define credentials & secrets for each service and store them in secrets manager / GitHub Secrets.
- [ ] Document per-service IAM roles and scopes.
- [ ] Add health checks for each external dependency (DB, Redis, S3, Discord).
- [ ] Add monitoring (metrics & alerts) for third-party interactions: S3 failures, Redis memory, Discord rate-limit
  events.
- [ ] Add tests & CI steps that validate integrations in sandbox environments.

References

- Discord developer docs: https://discord.com/developers/docs/intro
- Supabase docs: https://supabase.com/docs
- GitHub Actions docs & Environments: https://docs.github.com/en/actions
- Prometheus/Grafana best practices and sample dashboards in docs/OBSERVABILITY.md

---

## 11. Architecture & Technical Design

This section describes the system architecture and technical design decisions for the Player Profile & DB Foundation
project. It covers a high-level architecture overview, component diagrams and data flow (described), service boundaries,
storage and caching strategy, queueing and background jobs, deployment topology for staging/production, CI/CD pipeline
summary pointers, and failover & disaster recovery approach.

---

### 11.1 System architecture overview

Goal

- Provide a scalable, observable and secure platform to ingest large player profile JSON snapshots, persist raw
  snapshots for audit, normalize important fields into relational tables, serve low‑latency profile reads (bot/UI) and
  support analytics/backfill operations.
- Keep components modular so we can scale each independently: API, ETL workers, Discord bot, admin UI, and
  analytics/export jobs.

Primary components

- API service (stateless): receives snapshot ingestion requests, profile read endpoints, admin endpoints.
- ETL worker(s) (stateless compute): background consumers that claim hero_snapshots and upsert normalized tables.
- Queue broker: Redis (BullMQ) by default; optionally replaceable with durable queue (AWS SQS / GCP Pub/Sub) for higher
  durability.
- Postgres primary DB: stores hero_snapshots (JSONB), normalized tables and metadata. Managed provider (Supabase or
  equivalent) recommended.
- Redis cache / connection pool: used for job queue, ephemeral caches and rate limiting.
- Object storage: S3 or S3-compatible for snapshot archival and exports.
- Discord bot: separate process connecting to Discord Gateway and calling the API.
- Admin UI: read-only/operational UI for ETL dashboard, raw snapshot viewer and migration runbook links.
- CI/CD: GitHub Actions building images and running migrations (manual bootstrap for prod).
- Observability: Prometheus metrics, Grafana dashboards, Sentry for error tracking, centralized structured logging.

High-level flow (summary)

1. Client (CLI / bot / UI) posts snapshot to API or uploads snapshot file.
2. API validates, computes content hash, stores raw payload into hero_snapshots JSONB, and enqueues a job with snapshot
   id.
3. ETL worker dequeues job, atomically claims the snapshot, streams/parses payload, upserts normalized rows, writes
   profile_summary, and marks snapshot processed or records errors.
4. Bot/UI queries profile_summary for fast reads; falls back to latest processed hero_snapshot when summary missing.
5. Retention job archives snapshots to S3 and removes them from DB per policy.

---

### 11.2 Component diagrams & data flow

This section describes the component interactions and the core data flow as sequences and call graphs (textual). Keep a
copy of the diagram in docs/ERD.svg or docs/architecture/diagram.svg (recommended).

Component interaction (textual diagram)

- Client (CLI / Web / Bot)
  -> API Service (Ingress)
  -> Postgres (hero_snapshots)
  -> Redis (enqueue snapshot id)
  -> Response to Client (snapshot queued)
- Worker pool (n instances)
  -> Redis (dequeue)
  -> Postgres (upsert normalized tables)
  -> Prometheus / Metrics
  -> Sentry / Logs
  -> Postgres (update hero_snapshot.processed_at)
- API Service
  -> Postgres (read user_profile_summary)
  -> Redis (cache profile_summary)
  -> S3 (download archived snapshot when requested)
- Admin UI
  -> API Service (admin endpoints)
  -> GitHub Actions (link to migration runs and bootstrap)

Sequence for snapshot ingestion & processing

1. POST /api/v1/internal/snapshots -> API validates payload, computes SHA256(content).
2. API inserts hero_snapshots row with content_hash, size_bytes, raw JSONB and returns snapshot_id.
3. API enqueues snapshot_id into Redis/BullMQ queue (job payload minimal: snapshot_id).
4. Worker picks job:
    - atomic SQL claim: UPDATE hero_snapshots SET processing=true WHERE id=$1 AND processing=false RETURNING id
    - read raw JSONB from hero_snapshots by id (streaming/parsing)
    - upsert users (ON CONFLICT), user_troops (ON CONFLICT DO UPDATE), etc.
    - write user_profile_summary (INSERT ... ON CONFLICT DO UPDATE)
    - update hero_snapshots (processed_at=now(), processing=false) and write alerts/metrics
5. API reads user_profile_summary for client requests; if missing, optionally compute best-effort response using latest
   processed hero_snapshot.

Data flow security & telemetry

- All messages and DB writes include correlation id (X-Request-Id) to link API request -> queue job -> worker logs ->
  final write.
- Telemetry produced: job_duration_ms, processed_rows_count, failure_count, queue_wait_time.

---

### 11.3 Service boundaries (microservices / monolith)

Recommended decomposition

- api-service (stateless)
    - Responsibilities: authentication & authorization, snapshot ingestion endpoint, read endpoints (profile summary),
      admin endpoints, health & metrics.
    - Tech: Node.js/TypeScript (existing repo), express/fastify, pg client, BullMQ client.
- etl-worker (stateless)
    - Responsibilities: consume jobs, parse JSON, perform domain upserts, emit metrics, handle retries and error
      recording.
    - Tech: Node.js/TypeScript (same codebase or separate package), worker framework using BullMQ or alternative.
- discord-bot (separate process)
    - Responsibilities: register slash commands, respond to users, call API for summary reads.
    - Tech: discord.js or equivalent.
- admin-ui (optional separate frontend)
    - Responsibilities: operational dashboard, raw snapshot viewer, migration links, reprocess UI.
    - Tech: React / Next.js (deployed as static + API calls).
- analytics/export workers (batch)
    - Responsibilities: materialized view refresh, export scheduled jobs to S3 (CSV/Parquet).
- orchestration/runtime
    - Responsibilities: deploy & scale instances, scheduling, secrets, and monitoring.

Why separate services

- Scaling flexibility: ETL workers have different scaling needs (CPU/memory) compared to API service.
- Operational isolation: crashes or heavy ETL workloads should not impact API latency.
- Security: admin UI & migration operations isolated and access-restricted.

Monorepo / single-repo approach

- Keep services in the same repository (monorepo) for shared types and utilities, but package them as separate
  containers. Share CI pipelines and consistent linting/tests.

Boundaries & contracts

- API <-> Worker: queue messages contain minimal payload (snapshot_id + correlation metadata). Workers rely only on
  hero_snapshots table schema and documented upsert contracts.
- API <-> Bot: public read API with rate limiting; bot must not rely on slow snapshot ingestion synchronously.
- Admin UI <-> API: admin endpoints protected by RBAC and audit logging.

---

### 11.4 Storage & caching strategy (Postgres, Redis, S3)

Postgres (primary datastore)

- Use managed Postgres (Supabase or equivalent) for transactional data and JSONB snapshots.
- Store raw snapshots in hero_snapshots JSONB (TOAST compression).
- Normalize frequently queried entities (user_troops, user_profile_summary) for performant queries.
- Index strategy:
    - GIN index on hero_snapshots.raw for ad-hoc search (used sparingly).
    - B-tree and partial indexes for normalized tables as documented in Section 7.
- Partition hero_snapshots by created_at (monthly) when dataset grows (recommended after threshold).

Redis (cache and queue)

- Primary usage: job broker (BullMQ) and ephemeral caching (profile_summary cache, rate-limits).
- Configure persistence and sizing appropriate for job retention; if Redis is not durable enough, consider SQS/Cloud
  PubSub for critical jobs.
- Use Redis for a short-term summary cache (TTL e.g., 30–60s) to reduce DB reads during bursts (cache invalidation when
  ETL updates summary).
- Use Redis for distributed locks if needed (but prefer DB atomic claims for snapshot processing to keep single source
  of truth).

Object storage (S3 or compatible)

- Store archived snapshots and analytic exports in S3 bucket with lifecycle rules and encryption (SSE).
- Keep metadata (s3_path, checksum, archived_at) in Postgres audit tables.
- For large backfills / exports, write Parquet files to S3 for BI ingestion.

Other caches

- Optional application-level caches (in-memory) for extremely hot reads (but prefer Redis or read replicas for scale).
- Read replicas for Postgres to scale heavy reads without impacting writes.

Backup & retention storage

- Rely on provider-managed backups for Postgres. Additionally archive snapshots to S3 to control DB size.
- Set retention policy and lifecycle to reduce cost (e.g., archive to Glacier/cold tier after N days).

---

### 11.5 Queueing & background jobs (worker design)

Queue selection

- Primary choice: Redis + BullMQ for job queueing (popular Node.js ecosystem).
- Alternative: AWS SQS or Google Pub/Sub for durability and managed scaling (easy to swap the queue adapter).

Job design and payloads

- Job payload minimal: { snapshot_id: UUID, correlation_id: UUID, attempt: n }
- Keep job small to avoid large payload serialization overhead.
- Use Idempotency-Key pattern for any jobs that may be retried or retriggered.

Worker lifecycle & claim semantics

- Claiming snapshot:
    - Use atomic DB claim to avoid race conditions: UPDATE hero_snapshots SET processing=true,
      processing_started_at=now() WHERE id=$1 AND (processing IS NULL OR processing=false) RETURNING id
    - If claim succeeded, proceed; otherwise, skip job (another worker claimed it).
- Processing model:
    - Stream/parse JSON payload (avoid loading entire 3MB object into memory if possible).
    - For large arrays (troops): process in batches; build multi-row upserts for efficiency.
    - Upsert per entity:
        - users: upsert by unique key (namecode or discord_user_id)
        - user_troops: ON CONFLICT (user_id, troop_id) DO UPDATE set amount/level/extra
    - Commit by entity group (user, troops, pets) to keep transactions small and reduce lock contention.
- Error handling & retry policy:
    - Transient DB/network errors: exponential backoff with jitter; use BullMQ retry features.
    - Parsing/validation errors: write to etl_errors with details and mark snapshot as failed if not recoverable.
    - After N retried attempts, mark snapshot as failed and escalate (alert).
- Idempotency:
    - Design database upserts to be idempotent. Use snapshot_id for audit and include last_processed_snapshot_id on
      summary rows if desired.
- Scalability & parallelism:
    - Worker pool scales horizontally; use queue length to drive autoscaling.
    - Limit concurrency per worker to avoid too many DB connections (respect pgbouncer limits).
- Observability:
    - Expose /metrics for Prometheus: processed_count, success_count, failure_count, processing_time_histogram.
    - Emit structured logs with snapshot_id and correlation_id for tracing.

Admin & auxiliary jobs

- Reprocess jobs: same job processing path but require admin-auth enqueues.
- Retention/archival job: scheduled job that selects snapshot partitions to archive to S3 and updates DB.
- Export jobs: scheduled or on-demand jobs that materialize queries and write to S3.

---

### 11.6 Deployment topology (staging, production)

Environments

- local: developer machine via docker-compose (Postgres, Redis, local S3 emulator) with scripts/bootstrap-db.sh for
  migrations.
- ci: GitHub Actions ephemeral environment for tests and migration preflight checks (use ephemeral DB).
- staging: production-like environment for integration testing, smoke tests and validation; runs same containers as prod
  but smaller resources.
- production: high-availability deployment across availability zones/regions as required.

Deployment model options

- Container orchestration (recommended):
    - Kubernetes (managed): EKS/GKE/AKS or Fly/Koyeb for small teams — gives autoscaling, health checks and service
      discovery.
    - Alternative: ECS/Fargate for simpler serverless container runtime.
- Simpler options:
    - Single-container managed platforms (Fly.io, Render, Heroku) for smaller teams, acceptable if traffic low.

Service placement & redundancy

- API service: multiple replicas behind load balancer, autoscaled by CPU/RPS.
- ETL workers: autoscaled group sized by queue depth and desired ETL throughput.
- Discord bot: one or several instances (gateway sharding when required).
- Admin UI: static frontend served via CDN, backend admin APIs protected.
- Database: managed Postgres with read-replicas; multi-AZ recommended.
- Redis: managed (cluster or HA) with persistence enabled if needed.

Traffic flow & ingress

- Use API gateway / load balancer (managed) to terminate TLS and route to API services.
- Enforce WAF rules and rate limiting at edge if necessary.

Deployment & release practices

- Build container images in CI and push to GHCR.
- Use immutable tags (sha-<commit>) and promote images between environments.
- Use staged deployment:
    - CI build -> staging deploy -> smoke tests -> manual approval -> production deploy
- Rollout strategies:
    - Canary or blue/green deploys for API and worker updates where possible.
    - For DB schema changes, follow migration best practices: add columns, backfill, convert and cut over in separate
      steps.

Secrets and configuration

- Runtime secrets loaded from a secrets manager (or provider-specific secret store) and not stored in containers as
  plain text.
- Use environment-specific configuration (12-factor app) and avoid baked-in credentials.

---

### 11.7 CI/CD pipeline summary (link to CI_CD.md)

Summary of CI/CD responsibilities (details in docs/CI_CD.md)

- Tests: run unit tests, linting, typechecks and integration tests against ephemeral DB in CI.
- Build: build container artifacts and run container image scanning.
- Publish: push images to GHCR with immutability patterns.
- Migrations: run migration preflight in CI; production migrations performed by manual GitHub Actions workflow (
  db-bootstrap.yml) requiring environment approval.
- Releases: create GitHub release notes and tag images; deploy to staging automatically on main, production on manual
  approval.
- Rollbacks: use prior immutable image tag to roll back services; run DB rollback only if reversible or follow
  restore-from-backup runbook.

Link: docs/CI_CD.md (see that document for full workflow definitions, GitHub Actions config examples and required
secrets).

---

### 11.8 Failover & disaster recovery approach

Objectives

- Meet RTO and RPO targets (RTO target: 1 hour for critical reads; RPO: ~1 hour as defined in NFR).
- Ensure data durability and ability to restore service in degraded mode.

Backup strategy

- Managed DB automated daily full snapshots + continuous WAL archiving (where available).
- Regular snapshot backups validated by automated restore tests (quarterly full restore, monthly partial restore
  testing).
- Archive raw snapshots to S3 with checksum and metadata as an additional data source for recovery.

Failover & redundancy

- Postgres:
    - Use managed provider multi-AZ deployments with automated failover (enable read-replica promotion if provider
      supports).
    - Maintain standby read-replicas across AZs (optionally cross-region for higher DR).
- API & Workers:
    - Multi-AZ replicas behind LB; implement health probes and automatic restart.
    - Autoscaling groups should be configured with minimum replica count (ideally >1).
- Redis:
    - Use HA/cluster deployment with failover, or use managed queue service (SQS) as fallback.
- Object storage:
    - Use high durability provider (S3) and enable versioning if needed.

DR runbooks & steps

- Emergency flow examples:
    1. Detection: monitoring alerts (DB down, massive ETL failures).
    2. Triage: follow on-call runbook (docs/OP_RUNBOOKS/INCIDENT_RESPONSE.md).
    3. Mitigation:
        - Stop workers to prevent further writes if DB in inconsistent state.
        - Switch API traffic to read-only or to a fallback read-replica if primary degraded.
        - If primary DB irrecoverable, promote a read-replica or restore to new instance from backup.
        - If snapshot backfill required, use archived snapshots from S3 to re-ingest in controlled backfill job.
    4. Recovery: bring up services against restored DB, run smoke tests, resume processing.
    5. Postmortem: produce incident report, RCA and preventions.
- Pre-approved emergency steps:
    - Restore from latest good snapshot -> run schema migrations replay (if needed).
    - Use point-in-time restore to RPO target.

Testing & drills

- Schedule periodic DR drills to verify restore procedures and runbook clarity.
- Include simulated failover tests for read-replica promotion and application failover.
- Keep runbooks current and versioned in docs/OP_RUNBOOKS/.

Data integrity & consistency

- Design ETL with idempotent operations and audit logs so that reprocessing archived snapshots yields a consistent
  state.
- Record which snapshot versions were used to build profile_summary so rebuilds are traceable.

Cost vs availability tradeoffs

- Evaluate cross-region replication and multi-region deployments against cost and required SLA. Use a tiered approach:
    - Starter: single-region multi-AZ with backups and manual restore.
    - Higher availability: cross-region read-replicas and automated failover.

---

References & artifacts to maintain

- docs/DB_MODEL.md (schema & DDL)
- docs/ETL_AND_WORKER.md (worker internals)
- docs/MIGRATIONS.md and docs/OP_RUNBOOKS/MIGRATION_ROLLBACK.md
- docs/CI_CD.md (CI/CD pipeline)
- docs/OBSERVABILITY.md (monitoring & alerting)
- diagrams/architecture.svg (visual architecture diagram)

---

## 12. Operational & Runbook Items

This section documents day‑to‑day operational responsibilities, on‑call and escalation paths, the short list of required
runbooks with actionable steps for common incidents, maintenance/upgrade procedure guidance and cost/budget monitoring
practices. The runbook content here is intended to be concise and actionable — each runbook below should be copied into
its own dedicated file under docs/OP_RUNBOOKS/ for expansion and sign‑off.

---

### 12.1 Day-to-day operations (who does what)

Role matrix (high level)

- Product Owner (PO)
    - Prioritize operational work and approve maintenance windows.
    - Communicate incidents and planned downtime to community/stakeholders.
- Technical Lead / Engineering Lead
    - Technical decisions and approvals for schema changes and major deploys.
    - Triage complex incidents and coordinate engineering response.
- Backend Engineers / Devs
    - Implement features, fixes and ETL improvements.
    - Respond to issues assigned from monitoring (level 2).
    - Maintain CI pipelines, ensure migrations and seeds are correct.
- DevOps / SRE
    - Maintain infrastructure (DB, Redis, queues, S3) and CI/CD workflows.
    - Responsible for runbooks maintenance, backups, and recovery drills.
    - Implement and tune autoscaling, alerts and service accounts.
- On‑call Engineer (rotating)
    - First responder for P0/P1 alerts per on‑call schedule.
    - Execute runbooks for common incidents, escalate as needed.
- QA Engineer
    - Validate fixes in staging, run deployment smoke tests, verify rollback succeed.
- Data Analyst
    - Maintain analytics jobs, maintain materialized views and exports; assist on data integrity incidents.
- Community Manager / Bot Operator
    - Communicate outages, respond to community reports and coordinate with PO for user messaging.
- Security Officer / Privacy Officer
    - Advise on incidents with potential leakage, coordinate disclosure and legal steps.

Daily operational tasks

- Morning check: review dashboard for overnight anomalies (ETL failure rate, queue depth, DB replication lag).
- Alerts triage: acknowledge and assign alerts within defined SLA.
- Backups check: verify daily backup job success and retention logs.
- Queue health: inspect queue depth, worker heartbeats and recently failed jobs.
- Deployments: apply small, tested changes during working hours to non-prod; schedule production migrations.
- Documentation: update runbooks after any incident or change.

Operational dashboards to monitor daily

- ETL health: processed_count, failure_rate, queue_depth, avg_processing_time.
- Snapshot ingestion: ingestion rate, size distribution, duplicate rate.
- DB health: connections, slow queries, replication lag, bloat.
- Cost dashboards: monthly spend trends and top cost centers.

---

### 12.2 On-call & escalation paths

On-call model and contact flows

- On-call schedule
    - Maintain a weekly rotating on‑call roster (e.g., 1 week per engineer). Store roster in docs/OP_RUNBOOKS/ONCALL.md
      and publicly available to maintainers.
- Alerting channels
    - Primary alerts: PagerDuty (or equivalent) for P0 incidents (pages).
    - Secondary notifications: Slack channel #ops-alerts (read‑only for automated alerts).
    - Email for lower‑severity notifications and billing alerts.
- Severity definitions
    - P0 — Critical: production outage affecting many or all users (API down, DB inaccessible, ETL completely halted).
      Immediate page to on‑call, 15 min response expectation.
    - P1 — High: significant degradation (high ETL failure rate, degraded performance, large queue backlog). Page or
      high-priority Slack ping, 30 min response expectation.
    - P2 — Medium: partial loss of functionality or non-urgent failures (single feature affected). Slack notify, action
      within business day.
    - P3 — Low: informational issues, minor UX bugs, scheduled maintenance notifications.
- Escalation path
    1. On‑call engineer (first responder). Acknowledge within 15 minutes for P0.
    2. If unresolved in 30 minutes or severity increases, escalate to Engineering Lead / Technical Lead.
    3. If unresolved in 60 minutes or incident impacts SLA/customers, escalate to Product Owner and DevOps lead.
    4. For security incidents or suspected data breaches, notify Security Officer immediately (do not postpone).
- Communication flow
    - Use incident channel #incident-<id> to coordinate response (create via standard template).
    - Provide regular status updates (every 15–30 minutes) until mitigation.
    - Once stabilized, perform a postmortem and publish RCA within agreed SLA (e.g., 3 business days).

Escalation contact details (placeholder)

- On‑call rotation / PagerDuty schedule: docs/OP_RUNBOOKS/ONCALL.md
- Slack channel: #ops-alerts, #incident-management
- Emergency escalation: Engineering Lead (name/email), PO (name/email), Security Officer (name/email)
  (Replace placeholders with actual names/emails in production doc)

---

### 12.3 Runbooks (short list of required runbooks)

Each runbook below must exist as a dedicated document in docs/OP_RUNBOOKS/ with step‑by‑step commands, required
credentials (location reference), verification queries and "when to escalate" rules. The abbreviated runbook summaries
below provide the core actions and checks.

Runbook: Incident Response (critical production incident)

- Purpose: triage and mitigate production incidents quickly and safely.
- Preconditions:
    - Alert triggered (P0/P1). On‑call engineer available.
- Quick checklist:
    1. Acknowledge the alert in PagerDuty and create an incident channel (#incident-YYYYMMDD-XYZ).
    2. Capture initial facts: time, alert name, affected services, scope (percent users), first observed.
    3. Establish incident commander (IC) and roles: scribe (notes), comms (external comms), tech leads.
    4. Triage: run health checks (GET /api/v1/health, DB connectivity check, queue depth, worker heartbeats).
    5. Contain:
        - If API overloaded: enable read‑only mode or scale API replicas.
        - If DB is failing: stop ETL workers to avoid further load; switch reads to replica if available.
        - If queue backlog: scale workers cautiously or pause enqueueing non-critical jobs.
    6. Mitigate: apply hotfix or rollback to previous stable image; if schema related, stop and coordinate with
       migrations owner.
    7. Communication: post periodic updates to stakeholders and public status page if applicable.
    8. Post-incident: collect logs, assign RCA owner, schedule postmortem publication (with timeline, root cause,
       fixes).
- Verification:
    - Confirm service health (API 200 on /health), ETL failure rates dropped, queue depth stabilized.
- Escalation:
    - If suspected data loss or leak, notify Security Officer immediately. If SLA breach likely, notify PO and
      stakeholders.

Runbook: DB Restore (postgres recovery)

- Purpose: restore Postgres to a known good state from backups (partial or full).
- Preconditions:
    - Confirm backup availability and most recent successful backup (check backup logs).
    - Ensure sufficient permissions to perform restore (DB admin). Coordinate maintenance window and approvals.
- Quick checklist:
    1. Stop ETL workers and pause incoming snapshot ingestion (set API to return 503 for new writes if necessary).
    2. Note current DB state and take diagnostic dumps (if possible).
    3. Choose restore point:
        - Full snapshot restore: use most recent full backup.
        - Point-in-time restore: compute desired target_time (RPO).
    4. Restore into a new DB instance (do not overwrite primary until validated).
        - Provider-managed: use provider console (Supabase/GCP/AWS) to restore snapshot or perform PITR restore.
        - Manual: pg_restore / psql restore from dump; apply WAL segments as required.
    5. Run smoke tests on restored DB:
        - Schema validity: SELECT count(*) FROM users; sample user_profile_summary.
        - Application smoke tests: run minimal end-to-end ingestion flow against restored DB in staging.
    6. If validation passes, promote restored DB to primary (follow provider-specific steps) or swap connection string
       with minimal downtime.
    7. Restart workers and ingestion; monitor metrics closely.
- Verification:
    - Successful sample queries, ETL run for small sample snapshot, alerting cleared.
- Rollback:
    - If restored DB is invalid, revert to previous step and consult backups or escalate to DB admin.
- Postmortem:
    - Document root cause, time to restore, data lost (if any), and process improvements.

Runbook: Scaling Up (ETL workers / DB / Redis)

- Purpose: increase capacity for worker throughput, API replicas, DB resources, or Redis.
- Preconditions:
    - Observed sustained queue depth > threshold or high CPU/memory on workers/API or DB metrics triggers.
- Quick checklist:
    1. Assess current capacity and bottleneck (CPU, memory, DB connections, queue depth).
    2. For workers:
        - Increase worker replicas (k8s HPA or start additional instances) or increase worker process concurrency env
          var.
        - Monitor DB connections and set per‑worker max connections to avoid exhausting DB.
        - If needed, scale DB vertically or add read replicas for read traffic.
    3. For API:
        - Scale API replicas using CI/CD or HPA based on CPU/RPS.
        - Ensure load balancer health checks ok.
    4. For Postgres:
        - Vertical scaling: increase instance class (CPU/RAM) via provider console. Plan for brief failover if provider
          has maintenance windows.
        - Read scale: add or promote read replica for analytics.
        - Partition hero_snapshots if write volume extremely high.
    5. For Redis:
        - Increase memory/instance class or add cluster nodes. Validate persistence settings.
    6. Verify:
        - Monitor queue depth, processing rate, latency, DB connections and worker error rates.
    7. De‑scale when load returns to normal to control cost.
- Safety:
    - Avoid scaling DB schema changes at same time as scale-up events; separate concerns.
- Post action:
    - Update capacity planning docs and autoscaling thresholds.

Other required runbooks (short titles & purpose)

- Runbook: Reprocess Snapshot (admin flow) — step-by-step to re-enqueue and monitor.
- Runbook: Apply Migrations (preflight → apply → validate) — checklist for manual GitHub Action bootstrap approval.
- Runbook: Backup Verification & Restore Drill — schedule and how to run a restore drill.
- Runbook: Secrets Compromise / Rotation — how to rotate and revoke secrets quickly.
- Runbook: Cost Spike Investigation — identify services causing cost increase and emergency mitigation.

---

### 12.4 Maintenance windows & upgrade procedures

Maintenance windows

- Policy:
    - Routine maintenance window: weekly window for non-disruptive updates (e.g., Tuesdays 02:00–04:00 UTC) for
      non-production environments and low-traffic production tasks.
    - High-risk changes (schema-altering, large index builds): schedule during pre-approved maintenance windows with 48h
      notice to stakeholders and community (if user-facing).
    - Emergency maintenance: allowed outside windows for severe incidents, but must be communicated as soon as possible.
- Communication:
    - Announce planned downtime/maintenance at least 48 hours in advance via Slack, status page and community channels.
    - Publish expected impact, start/end time, contact point and rollback plan.

Upgrade / release procedure (high level)

1. Prepare
    - Create migration PR and run migration preflight in CI against a disposable DB.
    - Prepare rollback plan and ensure backups taken immediately before production migration.
    - Prepare runbook and designate approvers.
2. Approve
    - Get Product & Engineering Lead approval and schedule maintenance window if required.
3. Execute (during maintenance window)
    - Run preflight checks (extensions availability, estimated index time).
    - Trigger db-bootstrap GitHub Action (requires environment approval).
    - Run schema migrations in staging and smoke tests; then apply to production with approvals.
    - Apply application deployment (canary/blue-green).
4. Validate
    - Run smoke tests (API /health, sample ingest & ETL processing).
    - Monitor metrics and logs for regressions for at least agreed post-deploy window (e.g., 1–2 hours).
5. Rollback (if needed)
    - If critical failure occurs, follow rollback runbook: stop workers, restore DB from backup if migration
      irreversible, or deploy previous image and run compensating migration if safe.
6. Post-upgrade
    - Publish post-deploy report summarizing changes and any observed issues.
    - Update runbooks if new steps were required.

Guidelines for DB migrations

- Always take a fresh backup before applying production migrations.
- Avoid long-running exclusive locks; use phased migration strategy (add columns → backfill → enforce constraints).
- For large index creation use CREATE INDEX CONCURRENTLY and monitor the index build progress; schedule during
  low-traffic windows.

---

### 12.5 Cost monitoring & budget alerts

Cost visibility & ownership

- Assign cost owner per environment (staging, production) and per major service (DB, Redis, S3).
- Tag cloud resources (where possible) with project and environment tags to allow cost breakdowns.

Monitoring and budgets

- Set up billing alerts in cloud provider (monthly spend thresholds) and a billing dashboard with expected monthly run
  rate.
- Configure budget alerts at multiple thresholds (e.g., 50%, 75%, 90%, 100% of monthly budget).
- Create a Slack channel #billing-alerts to forward budget notifications.

Automated cost control measures

- Autoscaling policies tuned to limit max replicas to reasonable levels and avoid runaway scaling.
- Implement lifecycle rules for S3 to move old archives to colder tiers and delete older-than-N-days.
- Scheduled job to prune or archive large volumes (hero_snapshots) per retention policy to control DB storage costs.
- Enforce image retention policy on GHCR (clean up old images).

Action plan on cost spike

1. Immediate triage: identify resource causing spike via cost dashboard (DB egress, large S3 writes, over-provisioned
   instances).
2. Short-term mitigation:
    - Scale down non-critical services, stop bulk backfill jobs, pause expensive scheduled exports.
    - Apply aggressive retention / archival to remove hot storage.
3. Long-term:
    - Rightsize instances, implement caching read paths, optimize ETL to reduce DB write churn, schedule heavy jobs
      off-peak.
4. Post incident:
    - Produce a cost RCA and update capacity plans.

Billing & forecast review cadence

- Weekly cost snapshot in the ops meeting.
- Monthly finance review and adjustment of budgets for upcoming events (community backfills, marketing events).
- Quarterly cost optimization audit.

---

References & next actions

- Create individual runbook files under docs/OP_RUNBOOKS/:
    - ONCALL.md
    - INCIDENT_RESPONSE.md
    - DB_RESTORE.md
    - SCALING_UP.md
    - APPLY_MIGRATIONS.md
    - BACKUP_DRILL.md
    - COST_SPIKE.md
- Link runbooks from the main operations dashboard and ensure each runbook lists required permissions/secrets location,
  contact list and verification queries.

---

## 13. Testing & QA Strategy

This section documents the testing strategy for the Player Profile & DB Foundation project: test levels, environments,
test data management, mapping of acceptance criteria to user stories, CI gating, and the QA sign‑off process. The goal
is to ensure high confidence when shipping changes that affect ingestion, ETL, schemas and read surfaces.

---

### 13.1 Testing pyramid / levels

We follow the standard testing pyramid and expand it with performance and reliability tests. Each level has
responsibilities, example tools and target coverage.

1. Unit tests (fast, many)
    - Purpose: verify individual functions, parsing logic, small utilities and business rules (e.g., content_hash
      calculation, JSON mapping helpers, validation).
    - Scope:
        - JSON parsers / transformers for get_hero_profile.
        - Upsert SQL generation helpers.
        - Small utilities used by CLI and API.
    - Tools: Jest / Vitest (Node/TypeScript), sinon/mock for time, quick DB mocks where needed.
    - Targets:
        - Fast (<< 1s per test).
        - Coverage target: team-defined minimum (e.g., 70–80% overall; critical modules 90%+).

2. Integration tests (medium, moderate speed)
    - Purpose: verify interactions between components (API ↔ Postgres, worker ↔ DB, queue integration).
    - Scope:
        - API endpoints exercising DB (ephemeral test DB).
        - Worker logic processing sample snapshots and persisting normalized rows.
        - Migration preflight tests applying migrations to a fresh DB.
    - Tools: Jest + Supertest for HTTP endpoints, testcontainers or Docker Compose for ephemeral Postgres/Redis,
      node-pg-migrate test harness.
    - Targets:
        - Run in CI per PR; reasonably fast (~30–120s depending on setup).
        - Exercise key happy-paths and common error paths.

3. End-to-end (E2E) tests (slower, representative)
    - Purpose: validate full vertical flows in an environment similar to staging (ingest → queue → worker → summary
      read).
    - Scope:
        - Ingest a representative get_hero_profile sample file, ensure hero_snapshots inserted, worker processes it, and
          profile_summary is readable via API and bot behaviour simulated.
        - Admin flows: reprocess snapshot, run retention job (simulation).
    - Tools: Playwright / Cypress for UI interactions (if Admin UI exists), or scripts using HTTP clients;
      testcontainers/staging for infrastructure.
    - Targets:
        - Run in CI on merge-to-main or nightly; gating for release on staging success.

4. Load / performance tests (wide, scheduled)
    - Purpose: ensure system meets NFRs and scales under expected and spike loads.
    - Scope:
        - API ingestion throughput (concurrent snapshot POSTs).
        - Worker throughput & memory profiling with large snapshots (2–3MB).
        - Read latency for profile_summary under concurrent reads.
        - Backfill / bulk ingestion scenarios to validate throttling and scaling behavior.
    - Tools: k6, Gatling, Locust for HTTP load; custom scripts to simulate queue and worker scaling.
    - Targets:
        - Run on demand and scheduled (weekly or before major releases).
        - Define baselines (e.g., 100 snapshots/hour per worker instance) and SLAs (p95 read <200ms).
    - Observability:
        - Collect metrics (CPU/memory, DB locks, queue depth) and use these for sizing and autoscaling policy tuning.

Cross-cutting tests

- Security tests: static analysis (SAST), dependency scanning (npm audit / Snyk), secret scanning. Run in CI.
- Contract tests: ensure API and worker contracts remain stable (OpenAPI contract tests, schema validation).
- Chaos / resilience tests (optional): simulate worker crashes or DB failover in staging to validate failover runbooks.

---

### 13.2 Test data & environment

Environment types

- local-dev: developer machine with docker-compose (Postgres, Redis, optional S3 emulator) for fast iteration.
- ci: ephemeral environment spun up in GitHub Actions (testcontainers or ephemeral cloud DB) for PR checks.
- staging: production-like environment (managed Postgres, Redis, S3) used for smoke tests and QA sign-off.
- production: live environment with guarded deployments and manual approval for migrations.

Test data management

- Representative sample payloads:
    - Keep canonical test files in repository: /examples/get_hero_profile_COCORIDER_JQGB.json and other variants (small,
      medium, large, malformed).
    - Use anonymized or synthetic payloads for tests to avoid PII in repo.
- Fixtures & seeds:
    - database/seeds/ contains idempotent seeds for catalogs (troop_catalog, pet_catalog) and a few test users.
    - In tests, use seeds to create required catalog rows before running ETL flows.
- Data isolation
    - Each CI/integration test run should use a fresh DB schema or a disposable DB instance to avoid cross-test
      contamination.
    - Use randomized namecode values or test-specific UUIDs in fixtures.
- Sensitive data handling
    - Never include real user credentials or PII in test repositories.
    - If using production sample data for deeper tests, anonymize and audit the dataset, and restrict access (see
      TEST_DATA_POLICY.md).
- Snapshot fixtures and golden files
    - Maintain "golden" expected outputs for transformations (small JSON or SQL query results) to assert mapping
      correctness.
    - Keep versioned fixtures aligned with migration versions (if schema evolves, update fixtures).

Environment provisioning & teardown

- Use Docker Compose for local developer flows (fast start scripts).
- Use testcontainers or ephemeral cloud instances in CI to run integration and migration tests.
- CI must clean up resources after test run to avoid cost leaks.

Test data lifecycle & retention

- Keep test artifacts (failing test snapshots, logs) as CI artifacts for troubleshooting, but limit retention (e.g.,
  7–30 days).
- CI should prune old test databases and S3 test artifacts per budget/policy.

---

### 13.3 Acceptance criteria & test cases mapping (link to USER_STORIES)

Traceability and mapping

- All user stories in docs/USER_STORIES.md (or Section 4 user stories) must map to one or more test cases.
- Maintain a traceability matrix (simple CSV or doc) that links:
    - Story ID → Acceptance Criteria → Test case IDs → Test type (unit/integration/e2e) → Automated? (yes/no) →
      Location (test file path or test case management tool)

Example mapping (samples)

- STORY-DB-001 (migrations)
    - Acceptance: running pnpm migrate:up creates expected tables
    - Test cases: integration/migrations.test.ts (CI), manual smoke-check script for staging
- STORY-ETL-001 (worker idempotency)
    - Acceptance: worker sets processed_at and normalized tables reflect snapshot; reprocessing is idempotent
    - Test cases: integration/worker/idempotency.test.ts (inserts a snapshot, runs worker, asserts tables, re-runs
      worker)
- STORY-API-001 (profile summary endpoint)
    - Acceptance: GET /profile/summary/:namecode returns summary in <200ms p95 (staging)
    - Test cases: e2e/profile_summary.test.ts; performance test scenario in k6

Acceptance test design

- Format each acceptance case with Given/When/Then and an automated test that can be executed in CI or during staging
  validation.
- Include negative tests (bad payloads, malformed JSON, duplicate payloads) to assert expected error responses and safe
  behavior.

Test case repository & management

- Keep automated tests alongside code (monorepo) under /tests/ with clear naming:
    - tests/unit/**
    - tests/integration/**
    - tests/e2e/**
    - scripts/perf/** for load tests
- Consider a lightweight test management spreadsheet or a GitHub Project board to track manual test cases and QA
  progress.

---

### 13.4 CI test automation (gating, required checks)

CI gating policy

- All pull requests must pass required CI checks before merge into main. Required checks include:
    - Linting (ESLint, Prettier)
    - Type checking (TypeScript tsc)
    - Unit tests (fast)
    - Integration tests against ephemeral DB (target lightweight subset for PRs)
    - Migration preflight (apply migrations to ephemeral DB and rollback if possible)
    - Security scans: dependency audit (npm audit / Snyk) and secret scanning
    - Code quality checks (optional): coverage guard, static analysis
- Merge block: protect main branch with required checks enforced by GitHub branch protection rules.

Pipeline stages & examples

- PR / Push pipeline:
    1. Install deps (pnpm install --frozen-lockfile)
    2. Lint, typecheck
    3. Unit tests
    4. Quick integration tests (single worker + test DB)
    5. Report coverage and test results
- Merge-to-main pipeline:
    1. Full integration suite (longer)
    2. E2E smoke tests against staging (or ephemeral staging)
    3. Build and publish container images to GHCR (with tags)
    4. Run migration preflight job (simulate or run migrations in disposable DB)
- Pre-release pipeline:
    - Run performance tests (k6) against a staging deployment and generate performance report
    - Run dependency scans and SCA checks
- Production deployment:
    - Manual approval required for DB migrations and production deploy (GitHub Environment approval)
    - Post-deploy smoke tests run automatically

Gating specifics for migrations

- Migrations must include up and down where reasonable.
- CI must run migration preflight (apply to fresh DB) and run a small smoke ETL to verify compatibility.
- Production migrations require manual approval and a pre-deploy backup step.

Test flakiness management

- Detect flaky tests via CI (re-run once automatically if intermittent, but flag and require fix).
- Maintain a flakiness dashboard and tag flaky tests for prioritization.

Test artifacts & reporting

- Upload test logs, failing request payloads, and sample DB dumps as CI artifacts on failures.
- Report summary: pass/fail, coverage percentage, test durations, and a link to failing logs.

---

### 13.5 QA sign-off process

Purpose

- Define minimum criteria and process for QA/PO sign-off before a feature is considered releasable to production.

Sign-off prerequisites

- All required CI checks passed (lint, unit, integration, migration preflight).
- E2E smoke tests in staging passed.
- Performance tests for critical paths executed with results meeting NFRs in staging (or a documented known limitation
  with mitigation).
- Security & SCA scans no critical vulnerabilities (or documented exception with mitigation).
- Documentation updated: README, docs/DB_MIGRATIONS.md, docs/ETL_AND_WORKER.md and user-facing docs if relevant.
- Runbooks/operational docs updated for any operational impacts (migration, retention policy changes, large-scale
  backfills).
- Migration & backup validated: a pre-migration backup exists (or provider snapshot), and rollback plan documented.

Sign-off actors & responsibilities

- QA Lead:
    - Executes and verifies acceptance tests in staging.
    - Confirms regression checklist and documents any open non-blocking issues.
- Technical Lead / Engineering Lead:
    - Reviews code changes and signs off on architecture and migration implications.
- Product Owner:
    - Confirms feature behavior meets product requirements and acceptance criteria.
- Security Officer (for releases that touch sensitive flows):
    - Reviews security findings and approves release if no critical risk exists.
- DevOps / SRE:
    - Confirms required infrastructure and backup readiness and approves migration window.

Sign-off checklist (example)

- [ ] All required CI checks passed
- [ ] Migration preflight executed and backup taken
- [ ] E2E smoke tests passed in staging
- [ ] Performance targets validated or exception documented
- [ ] Documentation & runbooks updated
- [ ] Release notes drafted
- [ ] PO, TL, QA and SRE approvals recorded (names + timestamp)

Recording sign-off

- Use PR approvals (GitHub) plus a release checklist issue that includes approvals and links to test results and logs.
- For production migrations, require GitHub Environment approval and record approver(s) in the workflow run.

Release / roll-out steps after sign-off

- Promote image to production with manual approval.
- Apply production migrations via protected workflow (db-bootstrap.yml).
- Run post-deploy smoke tests and monitor dashboards for at least defined post-deploy window (e.g., 60–120 minutes).
- If issues, follow rollback plan and file an incident.

Post-release validation & retrospective

- After release, QA runs a small regression suite and monitors for 24–72 hours depending on impact.
- Hold a short retrospective to capture lessons learned and update tests/runbooks accordingly.

---

## 14. Rollout & Release Plan

This section defines the staged release process for features and schema changes, the controlled rollout strategy using
feature flags, rollback rules and criteria, communication plans for internal and external stakeholders, and the
post‑release monitoring checklist. The goal is a safe, observable, and auditable path from development to general
availability.

---

### 14.1 Release phases (alpha → beta → canary → general)

Define clear phases with entry/exit criteria so teams know when to progress a change. For DB schema changes the process
is stricter (preflight, backup, manual approval).

Phase: Alpha (internal)

- Audience: core developers, internal testers, trusted community contributors.
- Scope: early engineering validation of feature and schema changes; may contain telemetry instrumentation and debug
  logs.
- Duration: short (days).
- Criteria to enter:
    - Implemented feature with unit tests and integration tests passing locally.
    - Migration preflight ran successfully on disposable DB.
- Exit criteria:
    - No critical functional bugs in alpha test cases.
    - Basic ETL smoke test passes (ingest → ETL → summary).
    - Observability metrics created and collected (APM, metrics, logs).
- Controls:
    - Feature flag default = off for all users except whitelisted test accounts.
    - Enable debug logging for alpha actors only.

Phase: Beta (broader, opt-in)

- Audience: larger QA group, select community beta testers.
- Scope: more real-world validation, UX polish, performance profiling.
- Duration: 1–2+ weeks depending on risk.
- Criteria to enter:
    - All unit & integration tests pass in CI.
    - E2E smoke tests on staging pass.
    - Performance test baseline executed and acceptable.
- Exit criteria:
    - No P0/P1 regressions for a defined observation window (e.g., 48–72 hours).
    - Telemetry shows stable error and latency rates.
- Controls:
    - Feature flag rollout to a controlled audience (list of namecodes or Discord guilds).
    - Beta telemetry and user feedback channels enabled.

Phase: Canary (small percentage of production traffic)

- Audience: a small fraction of production traffic/users.
- Scope: production validation under realistic load, confirm migration effects and scaling.
- Duration: staged, multiple steps (see canary steps below).
- Criteria to enter:
    - Production preflight: manual approval, backup taken, migrations validated in staging.
    - Deployment artifacts built and promoted to a canary tag.
- Canary steps (recommended):
    1. Deploy to 1% of traffic (or 1–5 users/entities depending on user cardinality) for 1–2 hours; monitor.
    2. If stable, increase to 5% for 2–4 hours; monitor.
    3. If stable, increase to 25% for 6–12 hours; monitor.
    4. If stable, increase to 100% (general rollout).
- Exit criteria:
    - No critical errors or unacceptable metric regressions during each step (see thresholds in monitoring checklist).
- Controls:
    - Use feature flags and routing (load balancer / gateway) to limit traffic.
    - Have kill-switch procedure and runbook ready.

Phase: General Availability (GA)

- Audience: all users.
- Scope: fully enabled feature and final cleanup (remove temporary flags, adjust logging).
- Criteria to enter:
    - Canary completed successfully and product owner + engineering lead sign-off.
    - Migration and data changes validated in production; backup retention confirmed.
- Post-GA:
    - Monitor for at least 24–72 hours with heightened observability.
    - Plan cleanup: remove old feature flags, debug logging, and alpha-only instrumentation.

Special handling: Database Migrations

- DB migrations require an additional safety path:
    - Migration preflight in CI & staging.
    - Full backup/snapshot taken immediately before applying to production.
    - Production migrations run via manual GitHub Action with environment approval.
    - Prefer phased migrations: add columns nullable → backfill asynchronously → set NOT NULL later.
- If migration is destructive (drop/rename), require extended Canary and fallback plan including point-in-time restore
  readiness.

---

### 14.2 Feature flags & controlled rollout strategy

Use feature flags to decouple deploy from launch and enable safe incremental rollouts.

Flag types

- Boolean flags: simple on/off for a feature.
- Percentage rollout flags: allow rolling out to X% of users.
- Targeted flags: enable for specific users, guilds, or environments (whitelists).
- Ops flags: control operational behavior (worker concurrency, ETL throttling).

Storage & implementation

- Store flags in feature_flags table (see DB model) with fields: name, enabled, rollout_percentage, data JSONB.
- Provide a lightweight SDK or helper in the backend to evaluate flags (deterministic hashing by user_id/namecode).
- Cache flags in Redis for fast evaluation with a short TTL; invalidate on change.

Rollout patterns

- Canary via flags: enable for a deterministic subset of users (hash-based) to ensure reproducibility.
- Guild-based pilot: enable for specific Discord guild IDs for community pilots.
- Manual whitelists: use for alpha/beta testers identified by namecode or user_id.
- Progressive percent rollout:
    - Start at 0% → 1% → 5% → 25% → 100%, monitor between steps.
    - Use automated gates: promote to next step only if monitoring checks pass.

Kill-switch and emergency rollback

- Always include a kill-switch flag that immediately disables the new feature or routes behavior to safe default.
- Flags should be actionable from admin UI and also via infra (direct DB update + cache invalidation) for emergency use.
- Document the exact steps to flip flags and confirm effect (e.g., clear local caches, restart nodes if needed).

Telemetry & validation

- Emit feature flag evaluation metrics (evaluations, enabled_count, latency) and track adoption.
- Attach correlation IDs to events produced while the flag is enabled for traceability.

Governance

- Require PRs that add feature flags to include a short plan: rollout steps, metrics to watch, rollback criteria, and
  owner (engineer + PO).

---

### 14.3 Rollback strategy and criteria

Define clear, fast, and safe rules for rolling back both code and data changes.

Rollback triggers (criteria)

- Functional trigger: a P0 user-facing outage or feature-caused data corruption detected.
- Performance trigger: ETL failure rate or API error rate exceeds pre-defined thresholds (e.g., ETL failure rate > 1%
  sustained for 5 min, p95 API latency > 2× baseline).
- Data integrity trigger: evidence of incorrect writes, FK violations or lost records traceable to a new change.
- Security trigger: any suspected data leak or credential exposure.

Rollback types & steps

A. Code-only rollback (safe, quick)

- When to use:
    - New service container causes errors but DB schema is unchanged.
- Steps:
    1. Flip feature flag to disable the feature (kill-switch). If that resolves issue, continue rollback verification.
    2. If kill-switch insufficient: deploy prior stable image (immutable tag) to replace the new release (canary or
       full).
    3. Monitor health and metrics.
    4. Postmortem and root cause analysis.

B. App + small reversible migration rollback

- When to use:
    - Migration added a non-destructive column or index and is reversible via down migration.
- Steps:
    1. Stop workers if writes could be inconsistent.
    2. Deploy previous application version.
    3. Run migration down if reversible and safe.
    4. Validate data integrity and resume workers.
    5. If migration down is risky, restore from backup instead (see C).

C. Destructive migration / data rollback (complex)

- When to use:
    - Migration dropped or transformed data, or produced corruption; down migration not feasible.
- Steps:
    1. Stop ingestion and workers immediately to prevent further writes.
    2. Restore DB from pre‑migration backup or use point‑in‑time recovery (PITR) to restore to a time before the change.
    3. Apply tested migration path or compensating scripts against restored DB in an isolated environment first.
    4. Promote restored DB to production after validation or perform carefully orchestrated in-place corrective
       migration.
    5. Re-run ETL/batch jobs if needed to repopulate derived tables.
    6. Communicate incident and data impact per communication plan.
- Notes:
    - Always take a fresh backup prior to running any production migration; record the backup id and retention.

Operational considerations

- Always prefer feature-flag-based disablement before full rollback where possible (least impact).
- Maintain a changelog mapping release → migration id(s) → backup snapshot id used before migration.
- For rollback requiring DB restore, allocate a maintenance window and coordinate stakeholders.

Verification after rollback

- Run smoke tests: GET /api/v1/health, sample ingest & ETL flow, validate critical queries.
- Compare key metrics (error rate, latency) to baseline and ensure stability before resuming normal operations.

---

### 14.4 Communication plan (users, stakeholders)

Clear, timely communication is crucial for releases and incidents. Use templates and channels below.

Stakeholders & channels

- Internal stakeholders:
    - Engineering team (Slack #engineering)
    - SRE/DevOps (Slack #ops-alerts)
    - Product (email/Slack)
    - QA (Slack #qa)
- External stakeholders:
    - Maintainers / beta testers (Discord private channel)
    - Public users (Status page, Discord announcements)
- Incident escalation:
    - PagerDuty for P0 pages
    - #incident-<id> Slack channel for coordination

Pre-release communication

- For releases that may impact users (schema changes, potential downtime):
    - Announce at least 48 hours in advance to stakeholders and community (Discord + status page).
    - Provide release notes including expected impact, maintenance window, rollback plan, and contact info.
    - Share required action items for community (e.g., "do not run bulk fetches between 02:00–04:00 UTC").

Release-day communication

- Before deployment:
    - Post a short "deploy starting" message to #ops-alerts and status page.
- During deployment:
    - Post progress updates if long (>10–15 minutes) or if human approvals required.
- After deployment:
    - Post completion message with summary and link to release notes and monitoring dashboard.

Post-release & incident communication

- For incidents:
    - Initial message: short description, scope, ETA for next update.
    - Updates: every 15–30 minutes until mitigated.
    - Resolution message: summary of cause, actions taken, and next steps.
    - Postmortem: publish within agreed SLA (e.g., 3 business days) with RCA and remediation.
- External user messages:
    - Use status page for system-wide issues, and Discord for community-specific messages.
    - Keep external communications factual and avoid technical jargon; include mitigation steps and timelines.

Templates (examples)

- Release announcement (short)
    - Title: "Release: Player Profile & DB Foundation — vX.Y — Scheduled <date/time>"
    - Body: summary, affected features, maintenance window, expected impact, contact
- Incident update
    - Title: "Incident <id>: <short description> — Update #n"
    - Body: summary of observed issue, impact, actions taken, ETA, requester contact

Documentation & release notes

- Publish release notes per release in GitHub Releases and link to docs/CHANGELOG.md.
- Update docs/DB_MIGRATIONS.md and docs/ETL_AND_WORKER.md when relevant.

---

### 14.5 Post-release monitoring checklist

A concise, actionable checklist to run immediately after a release/canary promotion. Each item should be validated
within the post-deploy observation window (first 1–2 hours, and periodically during first 24–72 hours).

Immediate smoke checks (0–15 minutes)

- [ ] /health returns 200 from each service replica.
- [ ] DB connectivity check: run a light query (SELECT 1) and confirm response.
- [ ] Verify latest migrations applied and migration id recorded in schema_migrations table.
- [ ] Check worker heartbeats and ensure workers are processing queue items.
- [ ] Run a manual sample end-to-end test: ingest a sample snapshot and verify profile_summary populated.

Metrics & alerts (0–60 minutes)

- [ ] ETL failure rate: confirm < configured threshold (e.g., <1%); investigate spikes.
- [ ] Queue depth: confirm within expected range and draining rate healthy.
- [ ] API latencies: p95 and p99 within expected targets; errors per minute near baseline.
- [ ] DB metrics: connections < threshold, replication lag (if any) acceptable, no long-running locks.
- [ ] Error tracking: Sentry error count not spiking; new error types triaged.

Logs & traces (0–60 minutes)

- [ ] Inspect logs for repeated error patterns related to new code/migration.
- [ ] Search for any warnings about schema mismatches or unhandled JSON shapes.
- [ ] Verify correlation ids in traces for a sample request flow.

Data integrity & validation (0–24 hours)

- [ ] Sample data verification: compare key fields between raw snapshot and normalized tables for a set of sample users.
- [ ] Confirm no duplicate snapshots inserted unexpectedly (validate content_hash duplicates).
- [ ] Validate expected counts in materialized views or aggregates (if backfill executed).

Operational & governance checks (0–24 hours)

- [ ] Backups recorded: confirm successful backup/snapshot taken just prior to production migration.
- [ ] Feature flags: verify they’re in expected state; confirm ability to flip flags quickly if needed.
- [ ] Approvers on standby: confirm contact persons available in case rollback required.

User-facing verification (0–72 hours)

- [ ] Monitor support channels (Discord) for user reports and triage quickly.
- [ ] Validate a handful of reported user flows (bot commands) succeed.

Post-release follow-up (within 72 hours)

- [ ] Compile release metrics summary and circulate to stakeholders.
- [ ] Open tickets for any improvements, follow-ups or cleanup tasks (remove temporary flags, reduce debug logging).
- [ ] Schedule a short retrospective to capture lessons learned and action items.

Automation & dashboards

- Provide a release dashboard that aggregates the key monitoring signals (ETL, queue depth, API errors, DB metrics) for
  easy at-a-glance verification.
- Configure automated gating: promote canary to next step only if all gate checks pass (automated checks + manual
  approval).

---

## 15. Migration & Backfill Plan

This section describes the planned approach to apply schema migrations and to backfill historical/profile data into the
new normalized schema. It covers the migration/backfill strategy, risk & impact assessment, detailed migration steps
with rollback guidance, and dry‑run and validation checks to prove correctness before and after production runs.

---

### 15.1 Data migration approach (backfill strategy)

Goal

- Safely evolve the database schema and populate normalized tables (users, user_troops, user_pets, user_artifacts,
  user_teams, user_profile_summary, etc.) from existing raw snapshots, minimizing downtime and risk while preserving
  full auditability.

Principles

- Non‑destructive first: prefer additive, reversible schema changes. Avoid blocking ALTERs that acquire long exclusive
  locks.
- Idempotence: backfill and ETL upserts are idempotent — reprocessing the same source should not create duplicates.
- Small transactions: perform backfill in small batches per user or per snapshot to limit contention and expedite
  recovery.
- Auditability: record backfill progress, source snapshot ids, and checksums so every transformed row can be traced back
  to the original snapshot.
- Observable: emit metrics for backfill progress, throughput, errors and slowest operations.
- Throttled & controlled: support concurrency limits and backpressure to protect primary DB and upstream providers.

Backfill sources

- Primary source: existing hero_snapshots table containing raw JSONB (preferred). Backfill reads hero_snapshots rows (
  either latest per user, or historical per retention strategy).
- Secondary source (if hero_snapshots incomplete): ingest additional JSON files from archives (S3) or re-run fetch
  scripts where upstream access available.
- Catalog seeds: ensure troop_catalog, pet_catalog, artifact_catalog seeded before backfill so FK-based upserts
  succeed (or use placeholder catalogs with deferred resolution).

Backfill modes

- Incremental / live backfill (recommended for large datasets):
    - Process newest snapshots first (most likely to be accessed), then older.
    - Use per-user incremental approach: upsert current entity rows and mark snapshot as backfilled.
    - Keep the ingestion and worker pipeline running; new snapshots continue to be processed normally.
- Bulk backfill (for initial fill or one-off full rebuild):
    - Run in controlled window on a dedicated worker fleet with concurrency limits.
    - Use read-replicas or a maintenance replica if provider supports it (avoid impacting primary).
    - Consider restoring a backup into a dedicated backfill cluster and performing transformation there, then import
      results into primary DB if low-impact rollout required.
- Hybrid:
    - Perform initial bulk backfill over history in an offline prepared environment, then merge incremental changes done
      in production via reprocessing of recent snapshots.

Batching & parallelism

- Batch granularity: process per user or per snapshot in batches of configurable size (e.g., 100–1000 user snapshosts
  per job depending on complexity).
- Parallelism: use a worker pool sized to DB capacity; autoscale based on queue depth and target DB connection limits.
- Rate control: pause or reduce concurrency when DB metrics (CPU, connections, locks) exceed thresholds.

Data transformation approach

- Use ETL worker logic already designed for snapshot processing to perform backfill; reuse the same mapping rules to
  guarantee parity between real-time ETL and backfill.
- For each snapshot:
    - Parse raw JSON and extract user-level facts (namecode, user metadata).
    - Upsert user row (ON CONFLICT by namecode or unique external id).
    - Upsert user_troops, user_pets, user_artifacts with ON CONFLICT DO UPDATE.
    - Update or create user_profile_summary with denormalized quick-read fields.
    - Record mapping: write a backfill_audit (or etl_audit) row with snapshot_id, processed_by (backfill_job_id),
      processed_at, status.
- Preserve unknown fields in extra JSONB columns to avoid data loss.

Progress tracking & resume

- Use a backfill_jobs table:
    - id, started_at, completed_at, job_state, total_snapshots, processed_count, error_count, config (batch_size,
      concurrency), owner
- For each processed snapshot record job_id and processed_at in hero_snapshots (or backfill_audit table) to allow
  restart from last processed id.
- Support resumable jobs: if a job stops, it can resume from the last processed snapshot id for that job or process only
  snapshots with processed_at IS NULL.

Cost & time estimation

- Estimate per-snapshot average processing time from sample: use that to forecast total backfill time = avg_time *
  number_of_snapshots / concurrency.
- Include overhead for down-time windows and provider constraints. Provide budget estimate for compute, DB IOPS and S3
  egress if reading from archived storage.

---

### 15.2 Risk & impact assessment

Summary of key risks and mitigations

1. Risk: Long-running migrations locking tables and blocking production traffic
    - Impact: degraded API response or downtime.
    - Mitigations:
        - Avoid exclusive locks; use non-blocking patterns (add columns NULLable, backfill, convert).
        - Use CREATE INDEX CONCURRENTLY for large indexes.
        - Schedule high-impact changes in maintenance windows.
        - Run migration preflight in staging and estimate index build times.

2. Risk: ETL/backfill job overload causing DB connection exhaustion or lock contention
    - Impact: production slowdowns or failures.
    - Mitigations:
        - Throttle worker concurrency and use connection pooling (pgbouncer).
        - Use small batches and per-entity transactions.
        - Monitor DB metrics and pause backfill if thresholds exceeded.

3. Risk: Data corruption or incorrect mapping during backfill
    - Impact: incorrect normalized state and downstream errors.
    - Mitigations:
        - Run dry-run and checksum comparisons in staging.
        - Use golden-record tests on sample datasets and compare normalized outputs to expected values.
        - Preserve raw snapshots and unmapped fields; write backfill_audit entries for traceability.
        - Backfill into separate schema or branch before merge if high risk (validate then merge).

4. Risk: Duplicates or inconsistent upserts due to non-idempotent logic
    - Impact: duplicate rows or inconsistent aggregates.
    - Mitigations:
        - Use robust unique constraints and ON CONFLICT upserts keyed by (user_id, troop_id).
        - Ensure worker is idempotent and uses snapshot_id-based audit tags.

5. Risk: Storage & cost spike (DB size, S3, IO)
    - Impact: billing surprises and throttling.
    - Mitigations:
        - Estimate storage needs; apply retention & archival policies to older snapshots.
        - Use economical instance sizing and scale out/in during backfill.
        - Monitor billing and set budget alerts.

6. Risk: Extension/privilege limitations (CREATE EXTENSION denied)
    - Impact: migrations failing in the provider environment.
    - Mitigations:
        - Have fallback code paths (generate UUIDs app-side).
        - Document required provider permissions and request elevated privileges via ops ticket prior to migration.

7. Risk: Upstream format changes mid-backfill
    - Impact: mapping logic break or partial failures.
    - Mitigations:
        - Preserve raw JSON; mark failures and quarantine snapshots for manual review.
        - Implement schema versioning field in hero_snapshots.raw (if upstream provides no version).

Stakeholder impact matrix

- Players (end users): minimal for read-only backfill; potential transient slowdowns — communicate maintenance windows.
- Bot operators: may see delays in summary availability during heavy backfill — provide ETA & status messages.
- Analytics team: will gain access to normalized data after backfill; may need a schedule for exports.
- Dev/DevOps: responsible for monitoring and rolling back if needed.

Acceptance criteria for backfill run

- All processed snapshots have backfill_audit entries and processed_at timestamps.
- Normalized counts for a sampled subset match expected derived values from raw snapshots.
- ETL failure rate under acceptable threshold (e.g., <1% with actionable failures recorded).
- No significant production latency regressions observed while backfill runs.

---

### 15.3 Migration steps & rollback plan

Pre-migration checklist (must be completed before any production migration/backfill)

- Review & approve migration plan with Product and Engineering lead.
- Ensure database backups / snapshots are available and verify restore test result id.
- Determine maintenance window if required and notify stakeholders at least 48 hours prior.
- Ensure all required secrets and environment approvals present in GitHub Actions environment.
- Run migration preflight on a staging environment and validate migration up/down if feasible.
- Seed catalog tables (troop_catalog, pet_catalog, artifact_catalog) and verify referential integrity.
- Ensure runbooks and on-call staff are available during migration window.

Production migration & backfill steps (example safe procedure)

1. Preflight & Backup
    - Take a full DB snapshot/backup and record backup id.
    - Run migration preflight checks in CI/staging to ensure no immediate issues.
    - Validate required extensions and privileges.

2. Apply Additive Migrations (DDL)
    - Apply non-blocking migrations via node-pg-migrate using the manual GitHub Action (db-bootstrap.yml) with
      environment approval.
    - Examples:
        - CREATE EXTENSION IF NOT EXISTS pgcrypto; (separate migration)
        - CREATE TABLE hero_snapshots (...);
        - CREATE TABLE user_troops (...) (add indexes with CONCURRENTLY if large)
        - Add user_profile_summary table
    - Run post-migration sanity checks (expected tables exist, sample queries succeed).

3. Seed catalogs
    - Insert required catalog rows using idempotent seeds.

4. Small-scale smoke backfill (canary)
    - Run backfill on a small subset (e.g., 100 recent snapshots or selected test accounts).
    - Validate mapping, idempotency and impact on DB metrics. If problems found, abort and fix.

5. Progressive full backfill
    - Start incremental backfill jobs with conservative concurrency.
    - Monitor metrics and adjust concurrency.
    - Use job-level checkpoints and backfill_audit table to resume if stopped.

6. Post-backfill cleanup & verification
    - Verify sample data and aggregates against expected values (see validation queries below).
    - Remove temporary columns/flags in subsequent migrations only after verification.
    - Update monitoring & dashboards to use normalized tables for production reads where applicable.

Rollback plan

A. If non-critical issue discovered (data mapping bug or isolated failures)

- Pause backfill jobs.
- Fix ETL mapping or seed catalog and re-run backfill for affected snapshot id(s) via admin reprocess endpoint.
- No DB restore required if issue limited and fix is idempotent.

B. If production performance degraded (DB connection exhaustion / high locks)

- Pause backfill workers immediately (disable worker autoscaling or set concurrency to 0).
- If performance not restored:
    - Revert application code to previous container image (code rollback).
    - If migration caused the issue (e.g., index creation), consider reverting the migration if reversible or restoring
      DB from backup if destructive.
- Resume normal operations and re-run backfill at reduced concurrency.

C. If data corruption / destructive migration failure

- Immediately stop ingestion and workers.
- Restore DB from the pre-migration backup / point-in-time restore to the last known good state.
- Re-evaluate migration plan, apply safe migration sequence (e.g., add columns, backfill then drop).
- Re-run backfill on restored DB as needed.

Post-rollback actions

- Conduct incident review and root cause analysis.
- Update mapping/tests to prevent recurrence.
- Communicate impact and remediation to stakeholders.

Permissions & approvals

- Require at least two approvers for production migrations: Engineering Lead + Product (or SRE).
- Ensure someone with DB admin permissions is on-call during migration windows.

---

### 15.4 Dry-run and validation checks

Dry-run goals

- Prove the backfill process and mapping logic on a safe dataset and environment.
- Measure performance characteristics (per-snapshot processing time, DB impact).
- Validate idempotency and correctness of transforms.

Dry-run environments

- Use a staging environment running the same migration code and a representative subset of production snapshot data (
  anonymized).
- Optionally restore a recent production backup into an isolated environment for a full-scale dry-run if resources
  permit.

Dry-run steps

1. Select representative dataset
    - Choose small sets: (a) 100 recent snapshots, (b) 100 large login snapshots (2–3MB), (c) a few malformed/edge
      snapshots.
    - Optionally include a small random historical sample for regressions.

2. Run backfill in staging using the exact code & worker config planned for production.
    - Use same migration versions and config (batch_size, concurrency).
    - Enable verbose logging and extra metrics during dry-run.

3. Validate correctness & idempotency
    - For each processed snapshot in the sample, run validation queries (see below).
    - Re-run backfill for the same snapshots and assert no duplicate rows / same resulting normalized state.

4. Performance & resource profiling
    - Monitor DB CPU, memory, connection counts, locks and I/O; measure per-snapshot average time and memory usage.
    - Tune batch_size and concurrency accordingly.

Validation checks (automated)

- Schema & migration checks
    - Confirm all expected tables and indexes exist.
    - Validate migration version recorded in migrations table.

- Row-level validation (examples)
    - Snapshot count processed:
        - SELECT count(*) FROM hero_snapshots WHERE processed_at IS NOT NULL AND backfill_job_id = '<job_id>';
    - User mapping verification:
        - For a sample snapshot id: compare namecode from raw JSON to users.namecode
            - SELECT raw ->> 'NameCode' as namecode_raw FROM hero_snapshots WHERE id = '<snapshot_id>';
            - SELECT namecode FROM users WHERE id = (SELECT user_id FROM hero_snapshots WHERE id = '<snapshot_id>');
    - Troop counts parity:
        - Parse raw snapshot troops and compare aggregated sums with user_troops for that user (example pseudocode):
            - FROM raw: sum Amount for TroopId = X
            - FROM normalized: SELECT amount FROM user_troops WHERE user_id = ... AND troop_id = X
    - Check uniqueness constraints:
        - SELECT user_id, troop_id, count(*) FROM user_troops GROUP BY user_id, troop_id HAVING count(*) > 1;
            - Expect zero rows.
    - Validate profile_summary correctness:
        - For sampled users, compute top troops from user_troops and compare to user_profile_summary.top_troops JSON.
    - Check etl_errors:
        - SELECT * FROM etl_errors WHERE snapshot_id IN (<sample>) — ensure no unexpected errors remain.

- Idempotency test
    - Reprocess the same sample snapshots and assert:
        - processed_at updated (or processed_at unchanged if logic preserves timestamp), but normalized rows identical (
          check checksums).
        - No rows duplicated.
        - etl_errors count unchanged or only increased for new failures.

- Consistency checks
    - Referential integrity: no user_troops with user_id NULL.
        - SELECT count(*) FROM user_troops WHERE user_id IS NULL; EXPECT 0
    - Catalog foreign key checks (if FK present):
        - SELECT ut.* FROM user_troops ut LEFT JOIN troop_catalog tc ON ut.troop_id = tc.id WHERE tc.id IS NULL LIMIT
          10;

- Performance acceptance
    - Per-snapshot avg processing time and P95 within planned target for staging and adjusted for prod.
    - DB connection usage and CPU consumption below alert thresholds during backfill.

Automated regression comparison

- Keep golden output for sample snapshots and compare output JSON or joined SQL results using a diff tool or automated
  test script.
- Store validation reports for each dry-run as CI artifacts.

Pre-production checklist (pass required to run production backfill)

- All dry-run validation checks pass for representative dataset.
- Backups verified and restore tested.
- Capacity checks completed and concurrency limits configured.
- Observability dashboards and alerts in place.
- Approvals recorded (Engineering Lead and PO or SRE).

Post-backfill validation (production)

- Run a reduced set of validation queries (sampling) immediately after backfill completes.
- Monitor metrics for 24–72 hours to detect delayed regressions.
- Keep backfill job logs as artifacts and ensure etl_errors are triaged.

---

## 16. Security & Compliance Details

This section summarizes the security posture, controls and operational policies for the Player Profile & DB Foundation
project. It focuses on threat modelling, sensitive data handling, required testing and audits, evidence and logs
retention policies, and a secrets rotation policy. These items should be used as inputs to the security review and to
the operational runbooks.

---

### 16.1 Threat model summary

Scope

- Assets in scope:
    - Raw player profile snapshots (hero_snapshots JSONB) that may contain PII or tokens.
    - Normalized user data (users, user_troops, user_profile_summary).
    - Infrastructure credentials (DATABASE_URL, REDIS_URL, cloud keys).
    - CI/CD pipelines, GitHub Actions secrets and container images in GHCR.
    - Discord bot tokens and any linked OAuth tokens.
    - Backups and archived snapshots stored in S3.

Key threats

1. Credential leakage
    - Cause: accidental commits, misconfigured CI logs, compromised GitHub secrets, or leaked service account keys.
    - Impact: unauthorized DB or cloud access, data exfiltration, impersonation of bot.

2. Data exfiltration / unauthorized access
    - Cause: compromised application server, weak RBAC, exposed DB ports, misconfigured S3 buckets.
    - Impact: PII or sensitive tokens exposed to external parties.

3. Injection / data-driven attacks
    - Cause: unvalidated input, direct JSON injection into SQL or unsafe query building.
    - Impact: data corruption, privilege escalation, SQL injection.

4. Supply-chain / dependency compromise
    - Cause: malicious NPM package or exploitable transitive dependency.
    - Impact: remote code execution, exfiltrate secrets from CI or runtime.

5. Abuse & DoS
    - Cause: high-frequency snapshot ingest from many clients or upstream spike, or malicious bot commands.
    - Impact: DB overload, worker OOM, elevated infra costs.

6. Privilege misuse & insider risk
    - Cause: overly-broad credentials, locally stored secrets, or un-audited admin actions.
    - Impact: unauthorized changes, accidental data deletion or migration misapplication.

7. Data leakage via logs/telemetry
    - Cause: logging raw snapshots or tokens to Sentry / structured logs.
    - Impact: PII or tokens visible in logs retained widely.

Mitigations / Controls (high level)

- Least privilege: separate roles for migrations, app writes, reads, analytics.
- Secrets management: do not keep long-lived keys in code; use secrets manager / GitHub Secrets; avoid printing secrets
  to logs.
- Network restrictions: restrict DB access to trusted hosts / VPCs and limit S3 access via IAM policies.
- Input validation & safe DB access: parameterized queries / prepared statements for all DB writes.
- ETL safeguards: parse JSON defensively, preserve raw snapshot for auditing, store unknown fields in extra JSONB, and
  keep idempotent upserts.
- Rate limiting & quotas: throttle ingestion and bot commands; reject abusive traffic.
- Observability & alerting: monitor for abnormal activity (spikes in ingestion rate, high failure/etl error rates).
- Dependency management: enable Dependabot, run SCA and SAST checks in CI.
- Incident response: defined runbooks, PagerDuty escalation, and forensic playbooks for compromise scenarios.

Threat modelling outputs to maintain

- Asset inventory (what is stored and where)
- Data classification table (PII, Sensitive, Internal, Public)
- Attack surface map (APIs, bot gateway, CI, DB, S3)
- Risk register with probability/impact and mitigation owners

---

### 16.2 Sensitive data handling checklist

Use this checklist when designing features, accepting snapshots, or adding a new data store. Items marked "MUST" are
mandatory controls; "SHOULD" are strongly recommended.

Data classification

- [MUST] Define which fields in snapshots are PII or sensitive (emails, real names, device ids, auth tokens). Document
  mapping in docs/DATA_PRIVACY.md.
- [MUST] Classify all tables and archived stores with data sensitivity labels.

Ingest & storage controls

- [MUST] Do not persist user plaintext passwords; login flows must keep credentials only in local client or ephemeral
  memory.
- [MUST] Redact or remove auth tokens from hero_snapshots if not required; if stored, encrypt and mark as secrets in
  metadata.
- [SHOULD] Normalize and store minimum PII required; avoid duplicating PII across tables.
- [MUST] Use JSONB storage for raw snapshots but mask sensitive fields on disk copies exported as artifacts.

Access control

- [MUST] Enforce RBAC for admin endpoints (reprocess, raw snapshot access, migrations).
- [MUST] Use dedicated DB roles for migrations, app writes and analytics reads.
- [SHOULD] Enforce context-aware access (e.g., only certain GitHub environments can run production migrations).

Logs & telemetry

- [MUST] Redact tokens, passwords, and PII from logs and Sentry events. Apply automated scrubbers where feasible.
- [SHOULD] Flag logs that may include identifiable fields and restrict access to operations staff.

Backups & archives

- [MUST] Encrypt backups and S3 objects (SSE).
- [MUST] Keep an audit trail for backups and restores (who triggered, when, and restoration id).
- [SHOULD] Apply access controls for archived snapshots; require elevated roles to retrieve raw archived data.

Data subject rights & deletion

- [MUST] Implement processes to locate and delete personal data on request (right-to-be-forgotten). This includes
  deletion from DB and from S3 archives (or mark for purge and follow up).
- [SHOULD] Provide an API/admin path to request user data removal; document expected SLAs for erasure.

Transport & storage encryption

- [MUST] TLS for all network communications (HTTPS, SSL for DB).
- [MUST] Rely on provider encryption for data at rest and, for extra-sensitive fields, apply application-level
  encryption.

Developer & CI hygiene

- [MUST] Scan commits for accidental secrets (git-secrets, pre-commit hooks) and block commits with secrets.
- [MUST] Use ephemeral credentials in CI where possible (OIDC federation). Avoid storing long-lived JSON service keys in
  repo.
- [SHOULD] Enforce protected branches, code review and signed commits for infrastructure/config changes.

Incident handling

- [MUST] On suspected exposure of sensitive data or secrets, follow SECRET_COMPROMISE runbook: rotate secrets, revoke
  tokens, notify security lead, and perform forensic log capture.
- [MUST] Keep an incident log for any PII exposure with timeline and actions taken.

Compliance & audit

- [SHOULD] Maintain a mapping of sensitive fields to legal obligations (GDPR, CCPA).
- [MUST] Retain logs/audit trails long enough for investigations and compliance obligations (see next section).

---

### 16.3 Penetration testing / audits required

Scope & cadence

- Initial security assessment:
    - [REQUIRED] External penetration test (black-box) before major production release (GA).
    - Scope: public APIs (/api/v1/*), admin endpoints, Discord bot public surface, OAuth flows, authentication & session
      handling.
- Ongoing testing:
    - [RECOMMENDED] Annual external pentest (or after major infra changes).
    - [RECOMMENDED] Quarterly internal security review (dependency checks, SAST scans, config review).
- Triggered tests:
    - [REQUIRED] Re-run pentest or focused retest after any significant infrastructure change that affects the public
      attack surface (new public endpoint, major migration that exposes data in new ways).
    - [REQUIRED] If a high-severity vulnerability is discovered in a dependency (critical CVE), perform a targeted
      security audit.

Penetration test scope items

- External network perimeter: API ingress, rate limiting, WAF rules.
- Authentication & authorization: token issuance, scope checks, RBAC, API key lifecycle.
- Input validation and injection vectors: JSON handling, SQL injection, stored XSS in data consumed by admin UI.
- Data exposure: attempts to access raw hero_snapshots, backups or S3 artifacts without authorization.
- Business logic flaws: unauthorized reprocessing, duplication, or data overwrite.
- CI/CD & supply chain: checks on GitHub Actions secrets, packaging, GHCR permission configuration, and dependency
  provenance.
- Social engineering / ops procedures: review of runbooks and approval gating to ensure no weak human-process vectors.

Deliverables & remediation

- Pen test report with findings categorized by severity (Critical, High, Medium, Low).
- Fix timelines:
    - Critical: fix or mitigation within 24–72 hours (depending on exploitability).
    - High: fix within 7 calendar days.
    - Medium/Low: tracked and scheduled per roadmap.
- Post-remediation verification: targeted retest for critical & high issues.

Audit log & compliance review

- [RECOMMENDED] SOC2 readiness assessment if project intends to serve enterprise customers.
- [RECOMMENDED] Data Protection Impact Assessment (DPIA) if processing sensitive PII or large-scale profiling.
- Keep copies of pentest and audit reports in a secure internal docs area with controlled access.

---

### 16.4 Compliance evidence & logs retention

Retention policy (recommended baseline)

- Application logs (error/transactional):
    - Retain detailed logs for 30 days in primary logging store for debugging and triage.
    - Retain aggregated/rollup metrics for 365 days for trends and capacity planning.
- Audit & security logs (admin actions, migration runs, audit trail for data deletion):
    - Retain for minimum 1 year (or longer if regulatory requirements demand); ideally 3–7 years depending on legal
      context.
- ETL & processing metadata (etl_errors, backfill_audit, backfill_jobs):
    - Retain for 365 days by default. Archive older entries to cold storage if needed.
- Backups & archived snapshots (S3):
    - Keep production backups for at least 90 days online. Move older backups to cold storage tiers per retention
      policy.
    - For legal holds or compliance requests, preserve required data longer as directed by legal.
- Security & compliance artifacts (pentest reports, DPIA, SOC2 evidence):
    - Keep indefinitely in a secured, access-controlled repository for audit purposes.

Access & integrity

- [MUST] Audit access to logs and backups: log who accessed, when, and reason.
- [MUST] Protect log storage with ACLs and encryption.
- [SHOULD] Implement tamper-evident storage or immutability where required for forensic chain-of-custody (e.g.,
  retention vaults).

Evidence for audits

- Maintain the following evidence for compliance or audit requests:
    - Migration runbooks and execution logs (who ran migrations, when, and output).
    - Backup and restore logs with backup ids and successful restore proof.
    - Pentest & remediation reports with timelines and verification.
    - RBAC and secrets inventory (who has access to which secrets).
    - Data deletion logs for user DSR requests (what was deleted, when, and by whom).

Privacy & DSR logging

- Log DSR requests (Right to access, right to be forgotten) and the action taken; keep proof of deletion/archival and
  any correspondence with the user.
- Section docs/DATA_PRIVACY.md should specify SLA for responding to DSRs (e.g., 30 days as per GDPR).

Legal hold & e-discovery

- Provide a means to suspend deletion and retention policies for data subject to legal hold; document the procedure,
  authorization steps and access control.

---

### 16.5 Secrets rotation policy

Purpose & goals

- Minimize risk from leaked or compromised secrets by enforcing regular rotation, limiting secret lifetime and enabling
  rapid revocation and re-issuance.

Secret types & owners

- CI/CD secrets (GitHub Secrets, GHCR tokens): owner = SRE/DevOps
- Runtime secrets (DATABASE_URL, REDIS_URL): owner = SRE/DevOps, application config
- Service accounts & cloud keys (AWS/GCP): owner = Infrastructure/Cloud team
- Bot tokens (Discord): owner = Bot operator
- API keys for external partners: owner = Integrations lead

Rotation frequency & rules

- Short-lived tokens (recommended where supported, e.g., OIDC / ephemeral credentials):
    - Rotate automatically based on provider; prefer ephemeral credentials.
- Long-lived secrets (where unavoidable):
    - Database credentials: rotate at least every 90 days.
    - Service account keys (JSON): rotate at least every 90 days or migrate to OIDC federation to avoid keys.
    - Bot tokens: rotate every 90 days or immediately on suspected compromise.
    - API keys for third parties: follow vendor guidance; rotate at least every 180 days.
- Access keys with high privilege (migrations, admin): rotation and multi-person approval for re-issuance.

Automated rotation practices

- Use a secrets manager (AWS Secrets Manager, GCP Secret Manager, HashiCorp Vault) that supports programmatic rotation
  and versioning.
- Where possible, use cloud provider OIDC federation (GitHub Actions -> cloud) to avoid storing static credentials.
- Integrate secret rotation into CI/CD pipelines: deploy rotated secret, run smoke tests, then retire previous secret.

Revocation & incident steps

- On suspected or confirmed compromise:
    1. Immediately revoke the secret (disable token or change password).
    2. Issue a new secret and update runtime config via secrets manager + CI deployment.
    3. Re-deploy or restart services that consume the secret in a controlled manner.
    4. Run the SECRET_COMPROMISE runbook (rotate, audit logs, notify stakeholders, escalate to security).
    5. Record incident, root cause, and mitigation steps.

Operational considerations

- Maintain an inventory of all secrets, owners and last-rotation timestamps (securely).
- Use automation to detect secrets that are past rotation windows and create tickets/alerts.
- Limit the blast radius by scoping secrets narrowly (least privilege) and using different secrets per environment (
  dev/staging/prod).
- Avoid secret sprawl: prefer a small number of managed secrets references (e.g., one DATABASE_URL per environment)
  rather than multiple copies.

Audit & verification

- Periodically run automated scans for secret usage in code, history, and CI logs.
- Track rotation events and provide proof of rotation for audits (timestamped events from secrets manager).
- Include secret rotation checks in regular compliance evidence package.

---

References & next steps

- Add a dedicated docs/SECURITY_REVIEW.md containing the threat model diagram, asset inventory and signed-off
  mitigations.
- Add /docs/OP_RUNBOOKS/SECRET_COMPROMISE.md with step-by-step rotation & incident handling procedures.
- Implement automatic log redaction and Sentry scrubbing for PII and tokens.
- Schedule an external pentest prior to GA and add remediation timelines into the project plan.

---

## 17. Risks, Assumptions & Mitigations

This section collects the project’s core assumptions, a prioritized risk register with mitigation plans, and the open
questions or decisions that still need resolution. Use this section to drive risk reviews, prioritize spikes, and record
stakeholder decisions.

---

### 17.1 Key assumptions

These assumptions underlie the designs, timelines and choices in this PRD. Treat them as validated premises or items
requiring early verification.

- The upstream get_hero_profile JSON shape is reasonably stable for core fields (namecode, troops, pets, teams);
  occasional new fields may appear but not frequent breaking shape changes.
- Raw snapshots are available to be stored as JSONB in Postgres and storing them (TOAST) is acceptable cost-wise for the
  short term.
- The project will use a managed Postgres provider (e.g., Supabase) that allows pgcrypto or provides an acceptable
  fallback for UUID generation.
- Node.js + pnpm is the primary runtime and packaging tool for API and worker services.
- Team can enforce manual approval for production migrations via GitHub Environments (no automatic apply-on-merge).
- Worker compute (memory/CPU) can be autoscaled and Redis (or alternative queue) is available and permitted by ops
  budget.
- Backups and point-in-time restore (PITR) are available through the DB provider and can be executed in case of
  migration issues.
- Community users will run CLI-based login flows locally for large payloads; credentials will not be persisted by the
  backend.
- Performance targets (p95 read < 200ms, ETL interactive p95 < 30s) are achievable after normalization and indexing.
- The team has or will obtain authority to enable required DB extensions or accept documented fallback solutions if
  provider restricts extensions.
- Security & compliance requirements (GDPR/DSR) are implementable within the project scope and timeline.

---

### 17.2 Risk register (ID, description, probability, impact, mitigation)

Entries are ordered roughly by priority (high to low). Probability and impact use High / Medium / Low.

- RISK-001 — Migration causes production outage
    - Probability: Medium
    - Impact: High
    - Description: A migration (DDL or index build) acquires locks or triggers a long-running operation that blocks
      production reads/writes.
    - Mitigation:
        - Preflight migrations against staging; estimate index build times.
        - Use phased migrations (add columns nullable → backfill → enforce constraints).
        - Create backups immediately before production migration.
        - Run production migrations only with manual workflow and approver present.
        - Have rollback runbook and on-call DB admin available.
    - Owner: Engineering Lead

- RISK-002 — ETL backfill overloads DB (connection/IO exhaustion)
    - Probability: Medium
    - Impact: High
    - Description: Large-scale backfill or poorly throttled workers overwhelm DB causing degraded production
      performance.
    - Mitigation:
        - Throttle backfill concurrency; process in small batches.
        - Use connection pooling (pgbouncer) and limit per-worker DB connections.
        - Monitor DB metrics and implement automatic pause if thresholds exceeded.
        - Consider using replica/isolated backfill cluster if volume is very large.
    - Owner: SRE / DevOps

- RISK-003 — Worker OOM or excessive memory use when parsing large snapshots
    - Probability: Medium
    - Impact: High
    - Description: 2–3MB snapshots parsed naively can cause worker OOM and instability.
    - Mitigation:
        - Implement stream-aware or chunked parsers; process large arrays in batches.
        - Enforce maximum snapshot size limit and handle larger payloads asynchronously.
        - Add memory monitoring and autoscale worker pods based on memory/queue metrics.
    - Owner: Backend Engineer (ETL)

- RISK-004 — Provider denies required DB extension
    - Probability: Medium
    - Impact: Medium
    - Description: Managed Postgres provider refuses CREATE EXTENSION pgcrypto or other needed extensions.
    - Mitigation:
        - Prefer pgcrypto but implement fallback (generate UUIDs in app).
        - Isolate extensions into a single migration and detect permission errors early in preflight.
        - Document provider requirements and request operations team/provider to enable extension where possible.
    - Owner: DevOps

- RISK-005 — Sensitive data (tokens/PII) leaked in logs or artifacts
    - Probability: Low
    - Impact: High
    - Description: Raw snapshots or tokens are accidentally logged or included in CI artifacts leading to exposure.
    - Mitigation:
        - Enforce automatic log scrubbing and Sentry scrubbing rules.
        - Pre-commit hooks and CI secret scanning (git-secrets, GitHub secret scanning).
        - Do not include raw snapshots in public artifacts; redact in stored artifacts.
        - Maintain SECRET_COMPROMISE runbook and rotate secrets promptly.
    - Owner: Security Officer

- RISK-006 — Upstream API rate limits or changes disrupt ingestion
    - Probability: Medium
    - Impact: Medium
    - Description: Upstream service rate-limits or modifies API causing fetch failures or inconsistent payloads.
    - Mitigation:
        - Implement exponential backoff and retry logic in clients.
        - Record upstream rate-limit responses and surface friendly messages to users.
        - Preserve raw snapshots and build ETL tolerant to missing/extra fields; employ quarantining for malformed
          snapshots.
    - Owner: Backend Engineer / Integrations lead

- RISK-007 — Duplicate snapshots flooding DB
    - Probability: Medium
    - Impact: Low/Medium (storage growth)
    - Description: Clients may submit identical snapshots repeatedly causing storage growth and repeated ETL work.
    - Mitigation:
        - Compute and check content_hash (SHA256) on insert; dedupe within a configurable window.
        - Record duplicate attempts without full duplicate insertion.
        - Monitor duplicate rate and surface alerts when threshold exceeded.
    - Owner: Backend Engineer

- RISK-008 — Dependency vulnerability or supply-chain attack
    - Probability: Medium
    - Impact: High
    - Description: Malicious or vulnerable NPM package compromises CI/runtime.
    - Mitigation:
        - Enable Dependabot and SCA tools; run SAST in CI.
        - Pin critical dependencies and use reproducible builds.
        - Limit GitHub Actions permissions and use OIDC for cloud credentials.
    - Owner: Engineering Lead / Security

- RISK-009 — Unauthorized access to raw snapshots or admin endpoints
    - Probability: Low
    - Impact: High
    - Description: Misconfigured RBAC or leaked admin keys give external access to sensitive admin APIs or snapshots.
    - Mitigation:
        - Enforce RBAC and scoped tokens for admin endpoints.
        - Require multi-person approval for migration workflows and limit environment access.
        - Audit admin actions and keep audit logs with retention.
    - Owner: Security / DevOps

- RISK-010 — Cost overrun due to high storage or backfill compute
    - Probability: Medium
    - Impact: Medium
    - Description: Storing many raw snapshots and running heavy backfills increase monthly infra costs unexpectedly.
    - Mitigation:
        - Implement and enforce retention/archival policies.
        - Estimate costs before backfill and run within budget alerts.
        - Use cold storage (S3 infrequent/Glacier) for older archives.
        - Add budget alerts and automated throttles for heavy jobs.
    - Owner: Finance / DevOps

- RISK-011 — Data integrity mismatch between raw snapshot and normalized tables
    - Probability: Low/Medium
    - Impact: Medium
    - Description: Mapping bugs or schema mismatches cause normalized records to diverge from raw content.
    - Mitigation:
        - Provide extensive unit/integration tests against sample snapshots.
        - Perform dry-runs with validation queries and golden outputs.
        - Preserve raw JSON and unmapped fields to enable replay and corrections.
        - Add backfill_audit and etl_errors for traceability.
    - Owner: Data Engineer / Backend

---

### 17.3 Open questions / decisions pending

List of unresolved items that require explicit decisions; include an owner and suggested resolution approach.

- Q-001: Exact ETL queue technology choice
    - Status: Pending
    - Options: Redis + BullMQ (current preference) vs AWS SQS / PubSub (managed)
    - Impact: operational complexity, persistence guarantees, cost
    - Owner: Engineering Lead
    - Suggested resolution: Evaluate Redis vs SQS using short spike comparing durability, ease of retries and cost; pick
      SQS if long-term durability and operational simplicity are prioritized.

- Q-002: Default retention policy for snapshots (days and per-user N)
    - Status: Pending
    - Options: 30 / 90 / 180 days and keep last N snapshots per user
    - Owner: Product Owner + Legal
    - Suggested resolution: Default to 90 days + keep last 30 snapshots per user; confirm with Legal for GDPR.

- Q-003: Whether profile_summary endpoint will be public (no auth) or require authentication
    - Status: Pending
    - Impact: Rate limiting, privacy, caching, user discoverability
    - Owner: Product Owner
    - Suggested resolution: Make read endpoint public but rate-limited; sensitive raw snapshot access remains
      restricted.

- Q-004: DB provider selection and extension availability
    - Status: Pending
    - Impact: UUID strategy, migration scripts
    - Owner: DevOps
    - Suggested resolution: Confirm Supabase/managed Postgres capability and whether pgcrypto is allowed; if not, adopt
      app-side UUIDs.

- Q-005: Backup & restore SLAs (RTO/RPO) to target for production
    - Status: Pending
    - Owner: SRE / Product
    - Suggested resolution: Define RTO = 1 hour and RPO = 1 hour as initial targets; confirm provider can support and
      budget accordingly.

- Q-006: Feature flag system to use (in-house DB flags vs third-party)
    - Status: Pending
    - Impact: rollout control, SDK complexity, cost
    - Owner: Engineering Lead + Product
    - Suggested resolution: Start with in-house feature_flags table + simple SDK; revisit third-party if flags and
      experimentation needs grow.

- Q-007: Decision on using read-replicas for scaling reads vs caching (Redis) for profile_summary
    - Status: Pending
    - Impact: consistency, cost, operational complexity
    - Owner: SRE
    - Suggested resolution: Implement short-term Redis caching for summaries; plan read-replica architecture as load
      grows.

- Q-008: Level of sensitivity for fields in snapshots (what is considered PII)
    - Status: Pending
    - Owner: Legal / Security
    - Suggested resolution: Produce a field-level mapping from sample snapshots and have Legal classify fields; then
      implement redaction rules.

- Q-009: Policy for storing tokens that appear in snapshots (if upstream includes session tokens)
    - Status: Pending
    - Owner: Security Officer
    - Suggested resolution: Default policy is "do not store"; if storing is required, encrypt and restrict access,
      document retention and rotation.

- Q-010: Canary rollout thresholds and automated gating criteria
    - Status: Pending
    - Owner: Engineering Lead + SRE + PO
    - Suggested resolution: Define concrete gates (ETL failure rate < 0.5%, API p95 within +20% of baseline, queue
      depth < threshold) to allow automated promotion; add manual approval step for production migration.

---

Action items

- Validate assumptions Q-002, Q-004, Q-005 and Q-008 as highest priority before large-scale backfill or production
  migration.
- Assign owners to outstanding questions and schedule decision checkpoints during the next planning meeting.
- Add high-priority mitigation tasks for RISK-001 through RISK-004 into the immediate backlog (spikes & tests).

---

## 18. Dependencies & Stakeholders

This section lists internal and external dependencies required to deliver the Player Profile & DB Foundation work and a
RACI (Responsible / Accountable / Consulted / Informed) matrix describing stakeholder responsibilities for the major
activities. Use this section to coordinate cross-team work, request permissions, and track who to contact for approvals.

---

### 18.1 Internal dependencies (teams, services)

Teams

- Product
    - Prioritizes features, defines acceptance criteria and approves releases.
- Backend / Platform Engineering
    - Implements API, ETL worker, migrations, and data model.
- DevOps / SRE
    - Manages CI/CD, production infrastructure, backups, scaling, secrets and runbooks.
- Data Engineering / Analytics
    - Seeds catalogs, builds materialized views, validates backfill and exports.
- QA / Test Engineering
    - Creates test plans, runs integration/E2E tests and validates staging.
- Security & Privacy
    - Reviews threat model, approves retention/PII handling, coordinates pentest.
- Community / Bot Operator
    - Runs and monitors the Discord bot, coordinates community betas and feedback.
- Legal / Compliance
    - Advises on GDPR/CCPA and data residency/DSR obligations.
- Documentation / Developer Experience
    - Maintains docs: DB_MIGRATIONS.md, ETL_AND_WORKER.md, OP_RUNBOOKS, onboarding.

Internal services & components

- GitHub (Repositories, Actions, Environments)
    - Workflows, protected environments, secrets stored, manual approvals.
- CI runners (GitHub Actions)
    - Build, test, migration preflight, publish artifacts.
- Container Registry (GHCR)
    - Stores built images for API, worker, bot and jobs.
- Observability stack (Prometheus, Grafana, Sentry, logging pipeline)
    - Metrics, dashboards, alerting and error aggregation.
- Internal secret manager (if in use) or GitHub Secrets
    - Storage for DATABASE_URL, DISCORD_TOKEN, REDIS_URL, GOOGLE_SA_JSON, GHCR_PAT.
- Internal artifact/storage (S3/GCS)
    - Archive snapshots, export files and backup artifacts.

Cross-team coordination points

- DB extension & provider constraints — coordinate DevOps and Backend to confirm provider capabilities.
- Migration schedule — Product, Engineering and SRE must agree to windows and approvers.
- Backfill windows & capacity — Data Engineering + SRE to plan concurrency and cost.
- Security review & pentest scheduling — Security, Product and Engineering to approve scope and remediation timelines.

---

### 18.2 External dependencies (third-party services)

Primary external services

- Managed Postgres (Supabase or equivalent)
    - Stores hero_snapshots JSONB and normalized tables. Dependencies: extension support (pgcrypto), backups, connection
      limits and pricing.
- Redis / Queue provider (self-hosted Redis or managed provider such as Upstash/RedisLabs)
    - Job queue backend (BullMQ) or small cache for flags and rate limiting.
- Object storage (AWS S3, DigitalOcean Spaces, GCS or S3-compatible)
    - Archive raw snapshots, exports and large artifacts.
- Discord (API & Gateway)
    - Bot integration, slash commands, webhooks and guild interactions.
- Upstream game API (get_hero_profile)
    - Source of the raw profile snapshots; rate limits and format stability are external constraints.
- GitHub (Actions, Environments, GHCR)
    - CI/CD, protected workflows, secret storage and image registry.
- Monitoring / error tracking providers (Prometheus + Grafana, Sentry or hosted alternatives)
    - Metrics aggregation, dashboards and exception tracking.
- Cloud provider APIs (AWS/GCP) or platform services
    - If used for storage, backups, or additional compute; may require service accounts and billing.
- Third-party feature-flag or experimentation providers (optional)
    - If adopted later for rollout control (e.g., LaunchDarkly).
- Dependency/security scanners (Dependabot, Snyk)
    - Supply-chain monitoring and vuln alerts.

Operational constraints & SLAs to confirm

- Rate limits and quotas for Discord and upstream game API.
- Connection limits and available extensions for chosen Postgres provider.
- Cost/usage quotas for GitHub Actions, GHCR and cloud services.
- Data residency constraints for object storage (region availability).

Third-party contact & support expectations

- Identify account owners and support tiers for each provider (e.g., Supabase contact, S3 support plan).
- Plan for support escalation for production incidents affecting third-party services.

---

### 18.3 Stakeholder RACI / responsibility matrix

This RACI matrix maps key activities to stakeholders. Use it to determine who executes work, who signs off, who should
be consulted, and who must be informed.

Key: R = Responsible (do the work), A = Accountable (final sign-off), C = Consulted (advised/inputs), I = Informed (kept
up-to-date)

Activities / Stakeholders

- PO = Product Owner
- TL = Technical Lead / Engineering Lead
- BE = Backend Engineers
- DE = Data Engineering / Analytics
- SRE = DevOps / SRE
- QA = Quality Assurance
- SEC = Security & Privacy
- BOT = Bot Operator / Community Manager
- LEG = Legal / Compliance
- DOC = Documentation / DevEx

1) Schema migrations & DB bootstrap

- Responsible: BE, SRE (BE writes migrations, SRE runs/provisions)
- Accountable: TL
- Consulted: PO, QA, SEC, LEG
- Informed: DOC, BOT

2) Snapshot ingestion endpoint & CLI integration

- Responsible: BE
- Accountable: TL
- Consulted: BOT, SRE, QA
- Informed: PO, DOC

3) ETL worker implementation & backfill

- Responsible: BE, DE
- Accountable: TL
- Consulted: SRE, QA, SEC
- Informed: PO, DOC

4) Backfill execution & operational run

- Responsible: DE, SRE
- Accountable: TL
- Consulted: PO, BE, QA
- Informed: BOT, DOC, LEG

5) Profile summary API & bot commands

- Responsible: BE, BOT
- Accountable: TL
- Consulted: PO, QA
- Informed: SRE, DOC

6) Admin UI & reprocess endpoints

- Responsible: BE, DOC (API + UI)
- Accountable: TL
- Consulted: SRE, QA, SEC
- Informed: PO, BOT

7) Retention & archival jobs

- Responsible: SRE, BE
- Accountable: TL
- Consulted: DE, LEG, SEC
- Informed: PO, DOC

8) Observability, metrics & alerts

- Responsible: SRE
- Accountable: SRE Lead (or TL if SRE embedded)
- Consulted: BE, DE, QA
- Informed: PO, BOT, SEC

9) Security review & pentest

- Responsible: SEC
- Accountable: SEC Lead
- Consulted: BE, SRE, TL
- Informed: PO, LEG

10) CI/CD & production deployments (including db-bootstrap workflow)

- Responsible: SRE, BE (CI config)
- Accountable: SRE Lead
- Consulted: TL, PO, QA
- Informed: DOC, BOT

11) Incident response & runbook execution

- Responsible: On-call Engineer (SRE/BE)
- Accountable: SRE Lead / TL
- Consulted: PO, SEC, LEG
- Informed: All stakeholders via incident channel

12) Legal / Compliance sign-off (retention, DSR)

- Responsible: LEG
- Accountable: LEG lead
- Consulted: PO, SEC, SRE
- Informed: TL, DOC

13) Developer docs & onboarding

- Responsible: DOC, BE
- Accountable: TL
- Consulted: QA, SRE
- Informed: PO

Example RACI table (condensed)

- Activity: Migrations & bootstrap -> R: BE/SRE | A: TL | C: PO/QA/SEC/LEG | I: DOC
- Activity: ETL Worker -> R: BE/DE | A: TL | C: SRE/QA/SEC | I: PO
- Activity: Backfill -> R: DE/SRE | A: TL | C: BE/QA/PO | I: LEG/BOT
- Activity: Profile API -> R: BE | A: TL | C: BOT/QA | I: SRE/PO
- Activity: Observability -> R: SRE | A: SRE Lead | C: BE/DE | I: PO

Notes & recommendations

- Assign named owners for each role as the project matures (replace generic roles with specific people).
- For critical actions (production migration, data deletion/DSR), require explicit multi-person approvals (Accountable +
  one approver).
- Keep the RACI matrix in docs/OWNERS.md and update when responsibilities change.
- Ensure all teams have a clear escalation contact and a primary + secondary on-call rotation.

---

## 19. Acceptance Criteria & Definition of Done

This section defines the concrete acceptance criteria that must be met before features, epics or the project can be
considered done. It covers functional story-level criteria, non‑functional requirements (SLAs, performance, security),
compliance items required to mark work complete, and the final sign‑off process (who must approve).

---

### 19.1 Functional acceptance criteria (per epic / story)

Below are the core epics and their minimal functional acceptance criteria. Each story derived from these epics must map
to one or more of the criteria below or have its own Given/When/Then acceptance steps recorded in the backlog.

EPIC-DB-FOUNDATION

- node-pg-migrate integrated and initial migrations are present in database/migrations/.
- Running migrations locally:
    - Given a fresh Postgres instance and DATABASE_URL, when `pnpm run migrate:up` is executed, then tables listed in
      DB_MODEL.md are created without error.
- Bootstrap workflow:
    - Given repository secrets present, when the manual db-bootstrap GitHub Action is triggered, then migrations and
      seeds complete and a sanity query returns expected tables.
- Seeds are idempotent:
    - Re-running seeds should not create duplicate seed rows.

EPIC-SNAPSHOT-INGESTION

- Raw snapshot persist:
    - Given a valid get_hero_profile payload, when POST /api/v1/internal/snapshots is called, then hero_snapshots
      contains a JSONB row with size_bytes and content_hash.
- Duplicate detection:
    - When the same payload is posted within dedupe_window, system returns a duplicate response and does not insert a
      duplicate raw row (duplicate attempt recorded).
- CLI integration:
    - The CLI can save payloads locally and optionally POST to ingestion endpoint; successful run prints snapshot id.

EPIC-ETL-WORKER

- Worker idempotency:
    - Given a hero_snapshot row, when the worker processes it, then processed_at is set and normalized tables (users,
      user_troops, user_pets, user_profile_summary) reflect expected data.
    - Reprocessing the same snapshot does not create duplicate rows and leaves normalized state consistent.
- Large payload handling:
    - Given a ~3MB snapshot and constrained memory environment, when the worker runs, then it completes without OOM and
      updates processed_at (or marks for retry if transient failure).
- Error handling:
    - Malformed snapshots are recorded in etl_errors and do not crash the worker; admins can reprocess after fix.

EPIC-API-BACKEND & BOT

- Profile summary endpoint:
    - Given a processed profile, when GET /api/v1/profile/summary/:namecode is called, then it returns the denormalized
      user_profile_summary.
- Fallback behavior:
    - If summary missing but a processed snapshot exists, the endpoint returns best-effort data or 202 with an ETA
      message.
- Bot command:
    - Slash command `/profile <namecode>` returns the summary or a friendly "processing" message; respects Discord
      timeouts.

EPIC-ANALYTICS

- Materialized view:
    - Given user_troops populated, when materialized view is refreshed, then a query for troop ownership runs within
      acceptable time for the staging dataset.

EPIC-DEVEX & DOCS

- Documentation:
    - docs/DB_MIGRATIONS.md, docs/ETL_AND_WORKER.md and .env.example exist and show step-by-step local bootstrap.
- Sample payload:
    - examples/get_hero_profile_*.json present and ingest-sample.sh populates normalized tables in local environment.

EPIC-SECURITY & PRIVACY

- No plaintext passwords stored:
    - When a login-based payload is processed, no user passwords are persisted in DB or logs.
- Tokens redaction:
    - Logs and Sentry events do not contain unredacted tokens or credentials.

Operational acceptance

- Admin reprocess endpoint:
    - Given a snapshot id and admin auth, POST /admin/snapshots/:id/reprocess enqueues a job and returns 202 with job
      id.

---

### 19.2 Non-functional acceptance criteria (SLA, perf, security)

These measurable NFRs must be met before marking release done for production.

Performance & availability

- Profile summary read latency:
    - p95 < 200ms, p99 < 500ms for the typical staging dataset when servicing user_profile_summary.
- Ingestion ack latency:
    - POST /internal/snapshots ack p95 < 1s, p99 < 3s.
- ETL processing SLA (interactive):
    - Median processing time < 10s, p95 < 30s for small/average snapshots. For large login payloads (2–3MB) treat as
      asynchronous; aim for p95 < 5 minutes initially.
- Throughput baseline:
    - System can sustain at least 100 snapshots/hour per worker pool configuration; autoscaling must allow scaling
      beyond baseline for spikes.

Reliability & resilience

- Uptime / SLA:
    - Target 99.9% availability for read API during business hours.
- Error rates:
    - ETL job failure rate < 1% (transient errors retried automatically).
- Backups:
    - Automated backups configured; verified restore procedure documented and a successful restore drill performed
      before GA.

Security & compliance

- Authentication & RBAC:
    - Admin endpoints require scoped tokens and role checks; unauthenticated access to raw snapshots is disallowed.
- Secrets handling:
    - No secrets present in repo; GitHub Actions secrets used and not printed to logs.
- Pentest:
    - External pentest scheduled and medium/high issues resolved or have documented mitigations before GA.

Observability

- Metrics:
    - ETL processed_count, failure_count, processing_latency, and queue_depth are exported and visible on dashboards.
- Alerts:
    - Alerts for ETL failure spikes, high queue depth, and DB connection saturation are configured with on-call
      recipients.

Scalability & capacity

- Connection limits:
    - Worker concurrency settings must respect DB connection limits (no more than configured max connections).
- Partitioning / indexing:
    - Indexes required for primary query patterns are present and validated by explain plans for critical queries.

Privacy & data retention

- Retention policy:
    - Snapshot retention configuration implemented (default 90 days or as approved), archival to S3 validated.
- DSR handling:
    - Data deletion flow for user erasure requests tested end-to-end and logged.

---

### 19.3 Compliance checklist to mark "Done"

Before marking an Epic/Release "Done" for production, the following compliance items must be completed and evidence
attached (logs, links or runbook entries):

General compliance

- [ ] Data classification documented and approved (docs/DATA_PRIVACY.md).
- [ ] Retention policy defined and implemented (docs/DATA_RETENTION.md).
- [ ] Encryption at rest and in transit confirmed for DB and S3.

Security & auditing

- [ ] RBAC policies applied for admin endpoints; list of privileged accounts recorded.
- [ ] Secrets stored in secrets manager / GitHub Secrets; rotation policy documented.
- [ ] Logging redaction implemented (tokens/PII not present in logs/Sentry).
- [ ] Pentest scheduled or completed; critical/high findings resolved or have mitigation timeline.

Operational & backups

- [ ] Daily backup configured; last successful backup ID documented.
- [ ] Restore drill performed successfully in staging (date and outcome recorded).
- [ ] Runbooks created and reviewed for: INCIDENT_RESPONSE.md, DB_RESTORE.md, APPLY_MIGRATIONS.md.

Privacy compliance

- [ ] DSR (data subject request) flow implemented and tested (deletion and verification sample).
- [ ] Data processing agreements (DPA) in place with cloud providers if EU data is involved.

Legal & policy

- [ ] Legal sign-off obtained for retention and data residency constraints (if applicable).
- [ ] Documentation for any third‑party contracts (Discord, provider SLAs) linked.

Testing & documentation

- [ ] All required automated tests pass in CI (unit, integration, migration preflight).
- [ ] E2E smoke tests passed in staging with screenshots/logs attached.
- [ ] Documentation updated (README, migration docs, ETL mapping) and links included in release notes.

Evidence & artifacts

- [ ] Attach links to: migration run logs, backup id, CI job runs, pentest report (or ticket), dashboards used for
  monitoring.

Only after all the checked items above have corresponding evidence linked to the release ticket should the release be
considered compliant and ready for GA.

---

### 19.4 Sign-off: Product, Engineering, Security, QA

Final approval requires explicit sign-off from the following roles. Record approver name, date, and any notes in the
release checklist.

Sign-off table

- Product Owner (PO)
    - Responsibility: Accept functional behavior and user-impacting decisions.
    - Sign-off required: Yes
    - Example signature line: PO: __________________  Date: ______  Notes: __________________

- Engineering Lead / Technical Lead (TL)
    - Responsibility: Confirm architecture, migration safety and rollout readiness.
    - Sign-off required: Yes
    - Example signature line: TL: __________________  Date: ______  Notes: __________________

- Security & Privacy Officer (SEC)
    - Responsibility: Verify security controls, secret management, pentest remediation and data protection measures.
    - Sign-off required: Yes (or documented exceptions)
    - Example signature line: SEC: __________________  Date: ______  Notes: __________________

- QA Lead
    - Responsibility: Confirm tests passed, E2E smoke tests in staging and regression checklist.
    - Sign-off required: Yes
    - Example signature line: QA: __________________  Date: ______  Notes: __________________

- SRE / DevOps Lead (optional but recommended)
    - Responsibility: Confirm backups, restore capability, monitoring & alerts and deployment readiness.
    - Sign-off required: Recommended
    - Example signature line: SRE: __________________  Date: ______  Notes: __________________

Sign-off process

1. Populate release checklist with links to CI runs, test artifacts, migration logs, backup ids and monitoring
   dashboards.
2. Each approver reviews checklist items and evidence.
3. Approver signs (digital approval in ticketing system or a GitHub Environment approval) and adds comments if any
   conditions apply.
4. If any approver refuses sign-off, the release is blocked until conditions are met or an explicit escalation/exception
   is recorded and approved by senior leadership.

Definition of Done (DoD) summary

- All functional acceptance criteria satisfied and tests pass.
- Non-functional SLAs and monitoring configured and validated.
- Compliance checklist items completed with evidence.
- Required sign-offs obtained (PO, TL, SEC, QA).
- Release notes and runbooks updated and accessible.

Once all items are complete and sign-offs recorded, the feature/release may be promoted to production following the
rollout plan in Section 14.

---

## 20. Metrics, Observability & Analytics

This section specifies what to measure, how to expose it, alerting rules, logging/tracing conventions, telemetry event
schemas and retention policies. Use these guidelines to instrument code, build Grafana dashboards, and satisfy
operational & compliance needs.

---

### 20.1 Business metrics to monitor (dashboards)

Purpose: track product health, adoption and business outcomes. Dashboards should be organized by audience (Product /
Ops / Data).

Suggested dashboards and widgets

1) Snapshot ingestion & freshness (Product / Ops)

- Ingest rate: snapshots received per minute / hour
- Enqueued vs processed ratio (per minute)
- Average / median snapshot size (bytes)
- Content-hash duplicate rate (%) over window
- Profile freshness: percentage of active users with profile_summary cached within last 5/30/90 minutes
- SLA compliance: percent of snapshot ACKs under 1s

2) Bot & user engagement (Product)

- Bot command usage: /profile commands per minute, per guild
- Bot success rate: percentage of commands that return summary vs "processing" errors
- Active unique namecodes per day / week
- Top N guilds by command volume

3) ETL throughput & business outcomes (Data)

- Snapshots processed per hour (by worker pool)
- Number of user records created/updated per hour
- Troop ownership changes: top changed troop_ids (useful for product analytics)
- Materialized view refresh status and last refresh timestamp

4) Storage & cost monitoring (Finance/OPS)

- DB storage growth (MB/day) for hero_snapshots table
- S3 archival bytes written per day
- Estimate monthly cost for storage/compute (if available from cloud provider)

5) Backfill & migration progress (Ops/Data)

- Backfill job progress: total snapshots, processed, failed
- Backfill throughput (snapshots/hour)
- Migration run status and applied migration id

Visualization tips

- Use heatmaps or time-series with p50/p95/p99 shading.
- Add annotations for deployments, migration runs and manual bootstrap events to correlate with metric spikes.
- Provide a succinct "At-a-glance" status tile showing overall system health: OK / Degraded / Critical derived from key
  alerts.

---

### 20.2 Technical metrics & alerts

Instrument the system with metrics exposed for Prometheus (or equivalent). Provide clear alerting rules with playbooks.

Core metric types (per service)

- Counters:
    - snapshots_received_total
    - snapshots_enqueued_total
    - snapshots_processed_total
    - snapshots_failed_total
    - etl_entity_upserts_total (tagged by entity: users, user_troops, user_pets, etc.)
    - bot_commands_total (tag: guild, command)
- Gauges:
    - queue_depth (per queue)
    - worker_pool_instances
    - worker_memory_bytes / worker_cpu_seconds
    - db_connections_current
    - db_replication_lag_seconds
    - hero_snapshots_table_size_bytes
- Histograms / Summaries:
    - api_request_duration_seconds (labels: endpoint, method, status)
    - etl_processing_duration_seconds (labels: success/failure)
    - snapshot_size_bytes distribution
    - etl_entity_upsert_latency_seconds

Recommended alert rules (with suggested thresholds and urgency)

- P0: ETL failure rate spike
    - Condition: rate(snapshots_failed_total[5m]) / rate(snapshots_processed_total[5m]) > 0.01 (i.e., >1%)
    - Action: page on-call, runbook INCIDENT_RESPONSE
- P0: Queue depth high (backlog)
    - Condition: queue_depth > X (configurable; e.g., >500) for >10 minutes OR queue depth growth > 3x baseline
    - Action: page on-call, investigate worker health and scale
- P0: DB connection exhaustion
    - Condition: db_connections_current > 0.9 * db_connections_max
    - Action: page on-call, reduce worker concurrency, scale DB if necessary
- P0: DB replication lag critical
    - Condition: db_replication_lag_seconds > 30s (tunable)
    - Action: page; investigate replica health
- P1: API error rate increase
    - Condition: rate(http_requests_total{status=~"5.."}[5m]) > baseline * 5 or error rate > 1% of requests
    - Action: notify Slack & on-call
- P1: API latency regression
    - Condition: api_request_duration_seconds{endpoint="/api/v1/profile/summary"} p95 > 2× baseline for 10m
    - Action: notify SRE; consider temporary throttling
- P1: Worker OOM or repeated process restarts
    - Condition: rate(worker_restarts_total[10m]) > 3
    - Action: page & investigate memory usage
- P1: Snapshot ACK latency high
    - Condition: api snapshot ack p95 > 3s
    - Action: notify and investigate upstream or DB latency
- P2: Duplicate snapshot rate increase
    - Condition: rate(duplicate_snapshots_total[1h]) / rate(snapshots_received_total[1h]) > 0.2
    - Action: notify product and review client behavior

Alert content should include: summary, affected service, recent metric snippets, runbook link, and suggested remediation
steps. Tie alerts to runbooks in docs/OP_RUNBOOKS/*.

Noise reduction & escalation

- Use multi-window evaluation (5m & 1h) to avoid transient noise.
- Require consecutive alerts or burst detection before paging for non-critical metrics.
- Automatically escalate to TL if alert unresolved for defined time windows (e.g., 30/60 minutes).

---

### 20.3 Logging & tracing guidelines

Goal: consistent, actionable logs and traces to speed triage and preserve privacy.

Logging guidelines

- Structured logs (JSON) only. Each log record should include standardized fields:
    - timestamp (ISO 8601)
    - service (api | worker | bot | admin-ui)
    - env (staging | production)
    - level (DEBUG | INFO | WARN | ERROR)
    - message (short human-readable)
    - request_id (X-Request-Id) — correlate API request
    - trace_id / span_id — if tracing available
    - snapshot_id (where applicable)
    - user_id, namecode (only if not PII; prefer namecode as identifier)
    - job_id (background jobs)
    - module/component
    - error_code (if error)
    - details (JSON) — any non-sensitive structured context
- Do NOT log:
    - Plaintext passwords, raw tokens, secrets or full PII fields (email, real name) unless redacted.
    - Full raw snapshot payloads in standard logs; use a debug-only path that is disabled in production. If raw
      snapshots are required for troubleshooting, log a reference (snapshot_id and s3_path) only.
- Log levels:
    - DEBUG: verbose dev info (local & staging only or gated by feature flag)
    - INFO: normal operational events (snapshot_enqueued, job_started)
    - WARN: recoverable issues (transient upstream error)
    - ERROR: failures requiring investigation (etl failure, DB errors)
- Sampling:
    - For high-volume endpoints or repetitive errors, sample logs (e.g., 1%) and always log the first N occurrences.
- Centralization:
    - Ship logs to a centralized store (ELK, Datadog logs, Logflare). Protect access to logs and ensure redact/scrub
      pipelines before long-term storage.

Tracing guidelines

- Use OpenTelemetry-compatible tracing libraries.
- Propagate trace_id across:
    - API request -> queue enqueue (include request_id and trace_id in job payload) -> worker processing -> DB writes ->
      subsequent API calls.
- Typical spans:
    - http.server (API ingress)
    - queue.enqueue
    - queue.dequeue / worker.process
    - etl.parse
    - db.upsert.users, db.upsert.user_troops, db.index.create
    - external.call (call to upstream get_hero_profile)
- Trace retention: keep high-resolution traces for 7 days; store sampling traces (1-5%) for 30 days if allowed.
- Link traces to logs with trace_id to provide full context during incident triage.

Sentry / error tracking

- Capture exceptions with structured context (service, request_id, snapshot_id).
- Configure scrubbing rules to remove any PII or tokens from event data before sending.
- Set error alerting for new error types (regression), increasing frequency, or critical severity.

Operational notes

- Inject correlation ids early (API middleware) and return X-Request-Id to clients.
- Make request_id visible in user-facing error messages (support code) so users can report issues with trace context.
- Ensure job retries include the original trace metadata where useful (but avoid spamming traces for retry loops).

---

### 20.4 Telemetry events (schema + examples)

Ship meaningful business and operational events to analytics and event pipelines (e.g., Kafka, Segment, BigQuery). Keep
event schemas versioned.

Event design principles

- Events are immutable facts (e.g., snapshot_received). Keep schema small and stable.
- Use snake_case for event names and fields.
- Include common header fields in every event:
    - event_name
    - event_version (semver or integer)
    - event_timestamp (ISO 8601 UTC)
    - env (staging|production)
    - service
    - request_id
    - trace_id (optional)
    - user_id (nullable)
    - namecode (nullable)
    - snapshot_id (nullable)
    - source (cli|bot|ui|upstream)

Core event schemas (examples)

1) snapshot_received (v1)

- Purpose: recorded when API receives a snapshot payload
- Schema:
  {
  "event_name": "snapshot_received",
  "event_version": 1,
  "event_timestamp": "2025-11-28T12:34:56Z",
  "env": "production",
  "service": "api",
  "request_id": "uuid",
  "trace_id": "trace-uuid",
  "user_id": "uuid|null",
  "namecode": "COCORIDER_JQGB|null",
  "snapshot_id": "uuid",
  "source": "fetch_by_namecode|login|cli_upload",
  "size_bytes": 234567,
  "content_hash": "sha256-hex",
  "ingest_latency_ms": 123
  }

2) snapshot_enqueued (v1)

- Purpose: a lightweight event after enqueue to queue
- Schema:
  {
  "event_name": "snapshot_enqueued",
  "event_version": 1,
  "event_timestamp": "...",
  "service": "api",
  "snapshot_id": "uuid",
  "queue_name": "etl_default",
  "queue_depth_at_enqueue": 42
  }

3) snapshot_processed (v1)

- Purpose: emitted when worker finishes processing a snapshot (success)
- Schema:
  {
  "event_name": "snapshot_processed",
  "event_version": 1,
  "event_timestamp": "...",
  "service": "worker",
  "snapshot_id": "uuid",
  "user_id": "uuid|null",
  "namecode": "COCORIDER_JQGB|null",
  "processing_time_ms": 5432,
  "troops_count": 120,
  "pets_count": 3,
  "entities_upserted": { "users": 1, "user_troops": 120, "user_pets": 3 },
  "worker_instance": "worker-1",
  "success": true
  }

4) snapshot_failed (v1)

- Purpose: processing failure with limited context
- Schema:
  {
  "event_name": "snapshot_failed",
  "event_version": 1,
  "event_timestamp": "...",
  "service": "worker",
  "snapshot_id": "uuid",
  "error_code": "PARSE_ERROR|DB_ERROR|FK_VIOLATION|OOM",
  "error_message": "short message (sanitized)",
  "retry_count": 2
  }

5) etl_entity_upserted (v1)

- Purpose: emitted per entity upsert aggregation (useful for analytics)
- Schema:
  {
  "event_name": "etl_entity_upserted",
  "event_version": 1,
  "event_timestamp": "...",
  "service": "worker",
  "snapshot_id":"uuid",
  "entity": "user_troops",
  "rows_upserted": 120,
  "rows_updated": 10
  }

6) api_request (v1)

- Purpose: generic API access logging for analytics and rate-limiting metrics
- Schema:
  {
  "event_name": "api_request",
  "event_version": 1,
  "event_timestamp": "...",
  "service": "api",
  "endpoint": "/api/v1/profile/summary/:namecode",
  "method": "GET",
  "status_code": 200,
  "latency_ms": 120,
  "client": "bot|cli|web",
  "user_id": "uuid|null",
  "namecode": "COCORIDER_JQGB|null"
  }

7) bot_command_executed (v1)

- Purpose: track bot command usage
- Schema:
  {
  "event_name": "bot_command_executed",
  "event_version": 1,
  "event_timestamp": "...",
  "service": "bot",
  "guild_id": "1234567890",
  "channel_id": "9876543210",
  "command_name": "/profile",
  "user_discord_id": "discord-id",
  "namecode": "COCORIDER_JQGB|null",
  "response_type": "summary|processing|error",
  "latency_ms": 500
  }

Schema versioning & evolution

- Start event_version = 1 and increment if breaking changes occur.
- Always make new fields optional; maintain backward compatibility in consumers.
- Store event schemas in docs/events/ or a schema registry so downstream consumers can validate.

Transport & storage

- Export events to a streaming system (Kafka / Kinesis / PubSub) or directly to an analytics store (Segment, Snowplow).
- Ensure event pipeline scrubs PII fields per DATA_PRIVACY policy before writing to long-term analytics stores.

Examples: small sequence

- User triggers CLI upload → snapshot_received → snapshot_enqueued → snapshot_processed → etl_entity_upserted events
  emitted. Downstream dashboards aggregate these into KPIs.

---

### 20.5 Data retention for metrics/logs

Retention policy goals: balance operational usefulness, storage cost, and compliance.

Recommended baseline retention (tunable per org policy)

Metrics (Prometheus / TSDB)

- High-resolution metrics (raw samples):
    - Retention: 30 days at full resolution (default)
- Medium-resolution rollups:
    - Retain 1m/5m aggregates for 365 days for capacity planning and trending
- Long-term aggregates:
    - Retain monthly rollups for > 3 years if required for audits

Traces

- Full traces:
    - Retain for 7 days at full fidelity
- Sampled traces:
    - Retain a sampled set (1–5%) for 30 days for longer-term debugging of regressions

Logs

- Application logs (structured):
    - Hot store (searchable): 30 days
    - Warm/Cold archive (compressed): 365 days (or longer per compliance)
- Security & audit logs (admin actions, migration runs, DSR events):
    - Retain for a minimum of 1 year; consider 3–7 years for legal/contractual needs
- Error tracking (Sentry):
    - Retain raw events per Sentry plan; keep organization-level issues and resolution history for at least 365 days

Event / telemetry data (analytics)

- Raw event stream:
    - Keep raw events in data lake for 90–180 days depending on cost and analytics needs
- Processed/aggregated analytics tables:
    - Retain 365 days to support reporting, longer if storage and compliance allow

Archival & deletion strategy

- Use lifecycle policies (S3) to move logs and events to cheaper tiers (Infrequent Access, Glacier) after N days.
- Provide an archival index in the DB linking artifact ids to archived S3 paths to retrieve data for audits when needed.
- Implement deletion workflows tied to retention rules and DSR requests; log every deletion action for audit.

Privacy & compliance notes

- Before storing telemetry or logs that include user-identifiable information, ensure it is either necessary,
  pseudonymized, or covered by explicit consent.
- For DSR requests requiring deletion, purge or mark related telemetry per policy and propagate deletions to archived
  stores where feasible (or flag for legal hold if deletion not possible due to regulatory reasons).

---

Next steps / implementation checklist

- Instrument API & worker code to emit the metrics and events listed above.
- Create Grafana dashboard templates and alerting rules (Prometheus alertmanager) based on thresholds here.
- Implement structured logging and OpenTelemetry tracing in API and worker, and ensure correlation ids are propagated
  into job payloads.
- Define concrete retention settings in monitoring stack and S3 lifecycle rules in infra-as-code.

---

## 21. Documentation & Training

This section lists required developer documentation, onboarding checklists, runbooks and operations documentation,
user‑facing help articles, and a training plan for support teams. The goal is to ensure engineers, SREs, QA and
community support have the information and playbooks they need to operate, troubleshoot and explain the system.

---

### 21.1 Developer docs & onboarding checklist

Purpose: get a new developer productive quickly and reduce cognitive load when making changes that touch ingestion, ETL,
migrations or the profile APIs.

Minimum docs to include (location suggestions)

- docs/README.md — project overview, architecture summary, where to start
- docs/DEVELOPER_ONBOARDING.md — step-by-step local setup
- docs/DB_MIGRATIONS.md — migration conventions, node-pg-migrate usage, preflight checks
- docs/ETL_AND_WORKER.md — ETL design, idempotency rules, upsert patterns, error handling
- docs/DB_MODEL.md — canonical schema, ERD, table definitions and DDL snippets
- docs/CI_CD.md — CI jobs, GitHub Actions workflows, protected environments
- docs/OBSERVABILITY.md — metrics, dashboards and alert guide
- docs/DATA_PRIVACY.md — PII classification and handling rules
- docs/EXAMPLES.md — example requests, sample payloads and sample CLI usage
- docs/CHANGELOG.md — release notes and migration mapping

Onboarding checklist (developer)

1. Access & accounts
    - Request GitHub access and membership to required repos/teams.
    - Request access to required secrets manager entries (read-only where appropriate) and test credentials for staging.
2. Local environment
    - Install Node.js (supported LTS), pnpm, Docker.
    - Clone repo and run pnpm install.
    - Copy .env.example -> .env.local and populate required values for local Postgres/Redis emulators.
3. Bootstrap DB locally
    - Run ./scripts/bootstrap-db.sh (or pnpm run db:bootstrap) and verify migrations applied.
    - Run database seeds and validate sample data present.
4. Run worker & API locally
    - Start API server in dev mode and start a local worker; run ingest-sample.sh to process a sample snapshot.
    - Verify user_profile_summary exists and API GET /api/v1/profile/summary/:namecode returns expected output.
5. Tests & CI
    - Run unit and integration tests locally (pnpm test); ensure familiarity with testcontainers usage.
6. Observability & debugging
    - Learn to read logs, use X-Request-Id to correlate flows and run basic Prometheus queries against local dev
      metrics (if available).
7. PR workflow
    - Follow GitHub branching, PR, code review and CI requirements; ensure migrations include up/down where feasible.

Developer docs helpful additions

- Quick troubleshooting FAQ (common errors and resolutions).
- Common SQL snippets for debugging (e.g., find latest snapshot, reprocess a snapshot).
- Packaging & release notes template for PRs that include migration changes.

---

### 21.2 Runbooks & operations docs required

Runbooks should be short, actionable and kept in docs/OP_RUNBOOKS/*. Each must list prerequisites, exact commands,
expected outputs and "when to escalate".

Priority runbooks (minimum)

- INCIDENT_RESPONSE.md — triage steps, create incident channel, initial checks, containment and mitigation.
- DB_RESTORE.md — step-by-step restore from provider snapshot or pg_restore with verification queries.
- APPLY_MIGRATIONS.md — preflight checklist, how to trigger the protected db-bootstrap GitHub Action, required approvals
  and post-checks.
- SCALING_UP.md — how to scale workers/API, safe concurrency increments, DB connection considerations.
- REPROCESS_SNAPSHOT.md — how to re-enqueue a snapshot (API & manual DB option) and verify results.
- SECRET_COMPROMISE.md — immediate revocation/rotation steps, who to notify, short-term containment.
- BACKUP_DRILL.md — how to run and verify a restore drill; checklist for sign-off.
- COST_SPIKE.md — identify cost drivers, throttle jobs and communicate with Finance.
- MAINTENANCE_WINDOW.md — how to schedule, communicate and run maintenance with rollback plan.

Formatting & maintenance

- Each runbook: Purpose, Preconditions, Step-by-step commands (copyable), Verification queries, Post-action steps,
  Contacts (owners & backup), Audit logging requirements.
- Store runbooks in Markdown with code examples and links to related docs.
- Review cadence: runbooks reviewed quarterly and after each major incident.

Runbook automation

- Include scripts or helper CLI commands where safe (e.g., enqueue-reprocess.sh) and ensure they respect RBAC and
  require approver confirmation for production operations.

---

### 21.3 User-facing documentation / help articles

Audience: end users (players), community managers and bot operators. Docs should be accessible, concise and linked from
Discord bot messages and project site.

Essential articles (docs/USER_DOCS/*)

- Quick Start: How to fetch your profile
    - Steps for NameCode fetch using CLI, web UI or bot command.
    - Explanation of interactive (--login) vs NameCode fetch; privacy notes.
- Understanding Profile Summary
    - What the summary shows (level, top troops, pet), freshness and how to request a refresh.
- How to use the Discord bot
    - List of slash commands and examples (/profile <namecode>), permissions and rate limits.
- Privacy & Data Handling for players
    - What is stored, retention windows, how to request deletion (DSR flow) and contact.
- Troubleshooting & FAQ
    - Common errors: "Profile pending", "No profile found", rate-limited upstream, what to do.
- Developer-facing: CLI usage
    - Detailed docs for get_hero_profile.sh, ingest options, Idempotency-Key usage, extracting NameCode with jq.
- Community admin guide
    - How guild leaders can view guild-level reports, request bulk fetches, and best practices for coordinating
      community snapshot runs.
- Change log & release notes (user friendly)
    - Short, clear notes about feature additions and any user-impacting maintenance.

Delivery & discoverability

- Host docs on a docs site (GitHub Pages or a small static site) and link them from bot embeds and repository README.
- Embed short help text in bot replies (with link to fuller docs).
- Keep a short status/known-issues / planned-maintenance page for community.

Guidelines for user docs

- Use plain language and examples.
- Make privacy implications explicit for login flows.
- Provide expected ETA guidance for processing and tips to reduce failure (e.g., run CLI from stable connection).

---

### 21.4 Training plan for support teams

Audience: Community moderators, Bot operators, Support reps and first-line troubleshooters.

Goals

- Enable support staff to triage common user questions, interpret basic metrics, perform safe non-destructive recovery
  steps, and escalate incidents properly.

Training components

1. Training materials
    - Slide deck: "StarForge Profiles: Architecture & Troubleshooting" covering end-to-end flow, common failure points,
      and tools.
    - Short video walkthroughs (5–10 min) for:
        - How to fetch profile (user perspective)
        - How to read the Admin ETL Dashboard
        - How to reprocess a snapshot (admin flow)
        - How to interpret status messages and error codes
    - One‑page cheat sheets:
        - Quick triage steps (first 5 checks)
        - Error codes & recommended actions
        - Contact & escalation list (PagerDuty/Slack/Email)

2. Hands-on sessions
    - Run a live 60–90 minute training for initial cohort: demo ingestion, show raw snapshot view, reprocess flow and
      run a simulated incident drill.
    - Provide a sandbox environment where support reps can practice reprocessing and viewing snapshots safely.

3. Knowledge base & playbooks
    - Support playbook: step-by-step for common cases (profile pending, snapshot malformed, user asks to delete data).
    - FAQ maintained in docs/USER_DOCS/FAQ.md with contributor access for community managers.

4. Certification & sign-off
    - A lightweight quiz or checklist to verify competency (e.g., 10-question quiz + practical task: reprocess snapshot
      in staging).
    - Maintain a list of trained and certified support reps.

5. Ongoing refresh
    - Monthly 30-min brown-bag updates for new features, major incidents and process changes.
    - Immediate ad-hoc training for significant process changes (migrations that affect admin workflows).

Support escalation & SLA

- Define support Tier 1 responsibilities: user communication, initial triage, run known non-invasive fixes (request
  snapshot fetch, retry).
- Tier 2: Engineers handle reprocessing issues, data anomalies and runbook execution.
- Ensure support team knows how to open an incident channel and whom to page for P0 incidents.

Onboarding timeline (example)

- Week 0: Documentation provided; basic self-study.
- Week 1: Live hands-on training + sandbox practice.
- Week 2: Shadowing: support rep observes two real incidents with engineer present.
- Week 3: Practical sign-off: support rep reprocesses a snapshot and verifies result in staging.

Measurement & feedback

- Track support KPIs: time-to-first-response, time-to-resolution for common issues, number of escalations to
  engineering.
- Collect support feedback and update docs/runbooks quarterly based on real incidents and recurring support questions.

---

## 22. Legal, Licensing & Third‑party Notices

This section summarizes the legal and licensing considerations relevant to the Player Profile & DB Foundation project:
license choices for the project, impacts on Terms of Service and Privacy Policy, and obligations that arise from
third‑party dependencies. Use this as guidance for engineering, product, and legal teams to ensure compliance before
public releases.

---

### 22.1 License considerations

Purpose

- Provide clear guidance on what license the project will be published under, how contributors and consumers are
  affected, and how to handle mixed‑license third‑party components.

Key questions to decide

- What primary license will the project use? (e.g., MIT, Apache 2.0, BSD-3, GPLv3)
- Will contributors sign a Contributor License Agreement (CLA) or Developer Certificate of Origin (DCO)?
- Are there any components we cannot ship under the chosen license due to dependency compatibility?

License selection guidance

- Permissive (recommended for tools, SDKs, and developer utilities):
    - MIT or BSD-3: minimal obligations, broad adoption, simple attribution requirements.
    - Apache 2.0: permissive + explicit patent grant; recommended if patent concerns exist.
- Copyleft (use with care):
    - GPLv2/GPLv3: enforces distribution of derivative source; avoid if you want to allow proprietary downstream use.
    - LGPL: weaker copyleft for libraries; still has obligations.
- Commercial / dual-licensing:
    - Consider only if organization plans to enforce paid licensing.

Recommended default

- For this project, choose Apache 2.0 or MIT:
    - Apache 2.0 if you want explicit patent protections and stronger contributor grant language.
    - MIT if you prefer the simplest permissive terms.
- Record the license in a top-level LICENSE file and include SPDX identifier (e.g., "Apache-2.0", "MIT").

Contributor policy

- Use a DCO or lightweight CLA to ensure contribution ownership and grant of rights:
    - DCO is simpler (contributors sign-off on commits).
    - CLA provides stronger legal certainty for corporate contributors.
- Document contribution process in CONTRIBUTING.md, requiring sign-off and specifying license acceptance.

Third‑party license compatibility

- Audit all direct and transitive dependencies for license compatibility with the chosen project license.
- Watch for viral/copy-left licenses (GPL family) that may impose distribution obligations.
- If a dependency is GPL and used in a way that triggers distribution (e.g., linked into a distributed binary), consult
  legal before including.

Attribution & NOTICE file

- For Apache 2.0 projects, maintain a NOTICE file with required attributions for included third‑party components.
- For any license that requires attribution, include the attribution block in docs or README and ensure it is packaged
  with releases.

Binary / Release packaging

- When shipping compiled artifacts or containers, include:
    - LICENSE (project license)
    - Third‑party licenses (LICENSES-THIRD-PARTY.txt)
    - NOTICE (if required)
    - Source link (if required by license) or instructions on how to obtain source

License scanning & automation

- Integrate license scanning in CI:
    - Tools: FOSSA, licensee, scancode-toolkit, OSS Review Toolkit, or GitHub's dependency graph/license detection.
- CI should fail or require manual review on detection of disallowed licenses.
- Record license approvals and exceptions in a dependency inventory (docs/THIRD_PARTY.md).

Export controls & cryptography

- If using cryptography (e.g., pgcrypto, client-side encryption), verify export control obligations in your
  jurisdictions.
- Include notice if the project contains cryptographic code that may be subject to export/import restrictions.

Practical checklist

- [ ] Choose project license and add LICENSE file (with SPDX identifier).
- [ ] Add CONTRIBUTING.md with sign-off policy (DCO/CLA).
- [ ] Add third‑party license aggregation file (LICENSES-THIRD-PARTY.txt).
- [ ] Enable license scanning in CI and define a policy for disallowed licenses.
- [ ] Ensure NOTICE file present if using Apache 2.0 and third‑party components require it.

---

### 22.2 Terms of Service / Privacy policy impacts

Purpose

- Capture the product‑level legal impacts that arise from accepting, storing and processing user snapshots and from
  public access to profile data; prepare language for Terms of Service (ToS) and Privacy Policy.

Privacy & data processing considerations

- Data processed:
    - Raw snapshots potentially include personal data (emails, real names, device identifiers, tokens). Audit sample
      payloads to enumerate PII fields.
- Lawful basis:
    - Document lawful basis for processing (consent, legitimate interest) depending on product design and jurisdiction.
    - For data captured during login flows, explicit user consent is recommended and should be included in UI/CLI flow.
- Retention:
    - Implement retention policy in ToS/Privacy Policy (e.g., snapshots retained 90 days by default; last N snapshots
      kept per user).
    - Communicate retention periods and archival behavior to users.
- Data subject rights:
    - Describe procedures for access, correction, portability, and deletion (DSR). Indicate expected SLAs (e.g., 30
      days).
    - Provide an easy way for users to request deletion — record requests and audit actions.
- Third‑party disclosures:
    - If you send data to analytics, monitoring or backup providers, list those categories of processors and link to
      DPAs where applicable.
- Children’s data:
    - If product may be used by minors, comply with COPPA and local laws; consider blocking or giving special treatment.

Terms of Service (ToS) impacts

- Usage rules:
    - Define acceptable use (no abuse/rate‑limit circumvention, no scraping of other users).
    - State that users must not submit others' credentials or private data without consent.
- Liability & disclaimers:
    - Disclaim accuracy of third‑party data and limit liability for damages arising from using aggregated profile data.
- Intellectual property:
    - Clarify ownership of snapshots uploaded by users (user retains rights but grants the service limited rights to
      store/process/display).
    - Include a license grant from user to the service to process snapshots for the features described.
- Termination & account handling:
    - Describe consequences of ToS violations (removal of profiles, account suspensions), and data retention after
      termination.

Consent flows & UX

- For login-based ingestion (where credentials or tokens are used locally), ensure:
    - Users explicitly consent before uploading snapshots to the service.
    - Provide clear on-screen/local CLI notices explaining what will be uploaded and retention.
    - CLI must never persist credentials unless explicitly requested and encrypted — document best practices.

Cross-border / data residency

- If serving EU users or requiring EU hosting:
    - State data transfer practices in Privacy Policy.
    - Consider limiting storage/processing to EU regions for EU users or provide opt‑in/out options.
    - Execute DPAs with cloud providers where required.

Security responsibilities

- Communicate security measures in high-level terms (encryption in transit and at rest, access controls) in Privacy
  Policy.
- Avoid including implementation details that could aid attackers (e.g., exact rotation schedules).

Incident disclosure & breach notification

- Define breach notification timelines (e.g., notify affected users and supervisory authorities within statutory
  deadlines — GDPR: 72 hours where applicable).
- Document how users will be informed (email, status page, direct contact) and who to contact for questions.

Practical checklist for ToS/Privacy updates

- [ ] Map PII fields and decide what is stored vs redacted.
- [ ] Draft Privacy Policy section covering snapshots, retention, DSR process and data transfers.
- [ ] Add ToS clauses for user uploads, acceptable use, IP grants and liability limits.
- [ ] Ensure CLI and UI show concise consent notices for uploading snapshots.
- [ ] Prepare template DSR response and deletion verification logs.
- [ ] Obtain Legal sign-off and publish policies with version and date.

---

### 22.3 Third-party dependency licenses and obligations

Purpose

- Outline obligations arising from third‑party libraries, services and tools used in the project and how to comply with
  their license terms and contractual obligations.

Types of third‑party items

- Open-source libraries (NPM packages, build tooling)
- System libraries and DB extensions (pgcrypto, extensions)
- Hosted services (Supabase, Redis provider, S3, Sentry, Grafana Cloud)
- Vendor SDKs (Google Cloud, AWS SDKs)
- Fonts, images, and UI assets (may have separate license obligations)

Common license obligations and practical steps

- MIT / BSD / Apache 2.0:
    - Typically require inclusion of copyright and license text; Apache 2.0 requires NOTICE attribution for some
      components.
    - Action: include the dependency’s license block in LICENSES-THIRD-PARTY.txt and record their package and version.
- LGPL:
    - If used in a library form, ensure you meet requirements for relinking or providing source for the LGPLed library
      if distributing compiled binaries.
    - Action: avoid linking proprietary code in ways that would trigger LGPL obligations without legal review.
- GPL family:
    - Viral licenses: can require distribution of derivative source code under GPL if a GPL component is combined/linked
      into distributed binaries.
    - Action: avoid GPL libraries for server-side components unless you accept the obligations; consult legal for any
      transitive GPL.
- Commercial SDKs / APIs:
    - Adhere to terms of service: usage limits, attribution, branding constraints and paid plan obligations.
    - Action: store and review the TOS for each vendor and ensure quotas/monitoring are in place.

Obligations for hosted services

- Data processing agreements (DPA):
    - For processors handling personal data, ensure a DPA exists (Supabase, S3, Sentry) and is accessible in contract
      records.
- Security & compliance:
    - Some providers require specific configurations to maintain compliance (e.g., encryption settings, region
      settings).
    - Action: record provider hardening checklist and evidence.

Attribution and bundling

- When distributing binaries/containers or publishing the project:
    - Include all required license texts and attributions in the distribution.
    - Provide a clear third‑party license notice file in the repository and release artifacts.

Practical steps for dependency compliance

- Maintain a dependency inventory:
    - Tool-driven: `npm ls --json`, `yarn licenses`, scancode-toolkit, or a dedicated SBOM tool.
    - Record: package name, version, license, license URL, author, and any special obligations.
- Automate detection:
    - CI integration: fail builds on unknown or disallowed license types, or flag for human review.
- Handle exceptions:
    - If a dependency is required but license is incompatible, evaluate:
        - Replace with an alternative library.
        - Isolate use so distribution obligations are not triggered.
        - Seek legal approval and document an exception.
- Keep up to date:
    - Track security advisories and licensing changes for dependencies; update dependencies and re-scan regularly.

Templates and artifacts to maintain

- LICENSE (project license)
- LICENSES-THIRD-PARTY.txt (aggregate of all bundled licenses)
- THIRD_PARTY_NOTICES.md (short list showing critical dependencies and required attributions)
- DEPENDENCY_INVENTORY.csv or SBOM (software bill of materials)
- DPA and vendor contract references in a secure legal drive

Audit readiness & periodic review

- Schedule periodic audits:
    - Quarterly: dependency license scan + security vuln scan.
    - Before GA: full license audit and a list of third‑party obligations to satisfy packaging/release requirements.
- Keep audit logs and approvals for any license exceptions.

---

### Final checklist (legal readiness)

- [ ] Project license chosen and LICENSE file added.
- [ ] Contributor policy (DCO/CLA) chosen and CONTRIBUTING.md updated.
- [ ] Third‑party license inventory created and included with releases.
- [ ] NOTICE file (if required) assembled and included.
- [ ] Privacy Policy and Terms of Service updated to reflect snapshot processing, retention and DSR flows.
- [ ] DPAs signed with cloud vendors processing personal data, if applicable.
- [ ] License scanning configured in CI and exceptions tracked.
- [ ] Legal sign-off obtained prior to public GA release.

---

## 23. Appendices

This appendix collects supporting material, definitions, diagrams and references useful when implementing, operating and
auditing the Player Profile & DB Foundation project. Link targets point to files and folders in the repository; if any
are missing, create the referenced file or update the links.

---

### 23.1 Glossary & abbreviations

- API — Application Programming Interface.
- ETL — Extract, Transform, Load. The background processing that turns raw snapshots into normalized rows.
- P0/P1/P2 — Priority/Severity levels used for incidents (P0 = critical).
- DSR — Data Subject Request (requests under GDPR/CCPA to access or delete personal data).
- DPA — Data Processing Agreement.
- DB — Database (Postgres in this project).
- JSONB — PostgreSQL JSON binary column type.
- GIN — Generalized Inverted Index (Postgres index type used for jsonb).
- TTL — Time To Live.
- SLA — Service Level Agreement.
- SLO — Service Level Objective.
- RTO — Recovery Time Objective.
- RPO — Recovery Point Objective.
- PITR — Point-In-Time Recovery.
- RBAC — Role-Based Access Control.
- CI / CD — Continuous Integration / Continuous Delivery.
- GHCR — GitHub Container Registry.
- DCO / CLA — Developer Certificate of Origin / Contributor License Agreement.
- TTL — Time To Live (cache lifetime).
- p95 / p99 — 95th / 99th percentile latency.
- S3 — Object storage API (AWS S3 or S3-compatible service).
- OIDC — OpenID Connect.
- PCI / SOC2 — Compliance standards (Payment Card Industry / Service Organization Controls).
- PID — Process Identifier (used for workers) or Product ID depending on context — clarify in context.
- Idempotency-Key — header used to make POST operations idempotent.
- NameCode — user-identifying code used in upstream game (example: COCORIDER_JQGB).

---

### 23.2 Reference documents / links

Core repository documents:

- DB model & ERD: docs/DB_MODEL.md — canonical DDL, ER diagrams and table descriptions.
- ETL design & worker contract: docs/ETL_AND_WORKER.md
- Migrations conventions: docs/MIGRATIONS.md
- Observability & alerts: docs/OBSERVABILITY.md
- Data privacy & DSR: docs/DATA_PRIVACY.md
- CI/CD and deployment: docs/CI_CD.md
- Runbooks (operations): docs/OP_RUNBOOKS/ (directory with INCIDENT_RESPONSE.md, DB_RESTORE.md, etc.)
- Change log: docs/CHANGELOG.md

External reference links:

- Discord Developer Docs: https://discord.com/developers/docs/intro
- Postgres Documentation (jsonb, GIN, partitioning): https://www.postgresql.org/docs/
- OpenTelemetry: https://opentelemetry.io/
- Prometheus: https://prometheus.io/
- Grafana: https://grafana.com/
- OWASP Top 10: https://owasp.org/www-project-top-ten/

Repository pointers (replace with actual repo links if needed):

- Project repo root: https://github.com/CorentynDevPro/StarForge
- Examples folder: https://github.com/CorentynDevPro/StarForge/tree/main/docs/examples
- PRD main file: docs/PRD.md — this document (project requirements)

---

### 23.3 Example payloads (e.g., hero profile JSON) — link to examples folder

Canonical example payloads and sample test fixtures live in the examples folder. Use these as fixtures for unit,
integration and E2E tests, and for dry-runs of backfill.

Repository examples folder:

- docs/examples/
    - get_hero_profile_sample_small.json
    - get_hero_profile_sample_large.json
    - get_hero_profile_malformed_example.json
    - ingest-sample.sh (helper script)
      Link: https://github.com/CorentynDevPro/StarForge/tree/main/docs/examples

Notes:

- All example payloads must be synthetic or scrubbed of real PII. Do not commit real user credentials or tokens.
- Keep a short README in the examples folder describing each fixture, expected test outcomes and any special parsing
  caveats.

---

### 23.4 ER diagrams / sequence diagrams

Canonical diagrams for architecture, data model and core flows are stored under docs/diagrams/ (or docs/ as noted
below). Use these for onboarding, design reviews and runbooks.

Suggested diagram files (placeholders):

- docs/ERD.svg — high-level Entity Relationship Diagram (visual).
- docs/architecture/ingest_sequence.svg — sequence diagram: client -> API -> hero_snapshots -> enqueue -> worker ->
  normalized tables.
- docs/architecture/system_component_diagram.svg — components and dataflow (API, Worker, Redis/Queue, Postgres, S3,
  Discord).
- docs/diagrams/admin_workflow.svg — admin reprocess / retention / migration workflow.

Repository pointers:

- ERD & diagrams folder: https://github.com/CorentynDevPro/StarForge/tree/main/docs/diagrams
- If diagrams are not yet present, export SVG/PNG from your design tools (Figma / draw.io / diagrams.net) and add them
  to docs/diagrams/ then reference the files above.

Best practices:

- Keep source files (draw.io / Figma links) in addition to exported images for easy edits.
- Add short captions to each diagram explaining the intended audience and version (diagram versioning helps track schema
  changes).

---

### 23.5 Relevant meeting notes / decisions

Keep a curated record of architecture decisions, meeting notes and important decisions in a single place for
traceability. Suggested locations:

- docs/DECISIONS.md — Architecture Decision Records (ADRs) listing decisions, rationale, consequences and date/owner.
- docs/MEETINGS/ — directory with meeting notes (YYYY-MM-DD_<topic>.md). Example files:
    - docs/MEETINGS/2025-10-01_architecture_kickoff.md
    - docs/MEETINGS/2025-10-15_migration_plan_review.md
    - docs/MEETINGS/2025-11-01_security_review.md

Meeting notes template (example)

- Date: YYYY-MM-DD
- Attendees: list
- Purpose / agenda:
- Decisions made:
- Action items (owner, due date)
- Links to related PRs / tickets / docs

Why this matters:

- ADRs and meeting notes provide context for future engineers, help legal/compliance audits, and document trade-offs (
  e.g., choice of queue, retention defaults, extension fallbacks).

---

### 23.6 Change log (pointer to docs/CHANGELOG.md)

Record release notes, migration mappings and notable changes in a CHANGELOG to help operations and users understand what
changed and why.

Location:

- docs/CHANGELOG.md — canonical changelog for releases and major infra/migration events
  Link: https://github.com/CorentynDevPro/StarForge/blob/main/docs/CHANGELOG.md

Changelog guidance:

- Follow "Keep a Changelog" format: date-stamped entries, Unreleased section, and per-release notes (Added, Changed,
  Deprecated, Removed, Fixed, Security).
- For migration-related releases include:
    - Migration ids applied
    - Backup snapshot id used before migration
    - Any runbook links for rollback or verification
- Record who approved the release and link to the release ticket/PR for traceability.

---

## 24. Approvals

- Product Owner: **_Star Tiflette_**
- Engineering Lead: name / date
- Security Review: name / date
- QA: name / date
- Operations: name / date

---
