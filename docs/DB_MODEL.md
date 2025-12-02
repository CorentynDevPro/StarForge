# StarForge — Canonical Database Model (DB_MODEL.md)

> This document is the canonical reference for the database schema used by StarForge. It expands the summary in the PRD
> and contains:
> - high-level overview and design principles,
> - canonical table definitions (key tables used by the ETL and APIs),
> - recommended indexes, constraints and partitioning guidance,
> - upsert patterns / example DDL and SQL,
> - migration & rollout checklist specific to schema changes,
> - DBML representation (paste into https://dbdiagram.io to visualize),
> - sample queries useful for debugging and validation.

--- 

# Audience

- Backend engineers implementing migrations and `ETL workers`
- `SRE / DevOps` running bootstrap and production migrations
- Data engineers and analysts consuming normalized tables
- `QA` writing `integration/e2e tests`

---

# Status

- Draft (aligns with PRD v0.1 — see [docs/PRD.md](./PRD.md)). Update this file when migrations are committed.

---

# Table of contents

1. [Design goals](#1-design-goals--guiding-principles)
2. [Naming & conventions](#2-naming--conventions)
3. [Core tables (DDL-like descriptions)](#3-core-tables-canonical-descriptions--recommended-columns)
4. [Indexes & query patterns](#4-indexes--query-patterns)
5. [Partitioning & archival guidance](#5-partitioning-retention--archival-guidance)
6. [Upsert examples and idempotency patterns](#6-upsert-examples-and-idempotency-patterns)
7. [Migration strategy & preflight checks](#7-migration-strategy--preflight-checks)
8. [Data retention & archival model](#8-data-retention--archival-model-summary)
9. [Validation queries & health checks](#9-validation-queries--health-checks)
10. [DBML schema (paste into dbdiagram.io)](#10-dbml-schema-paste-into-dbdiagramio)
11. [Change log / references](#11-change-log--references)

---

## 1. Design goals / guiding principles

- Store `raw upstream snapshots` (JSON) for audit & replay while normalizing commonly queried fields for performance.
- Keep `ETL` idempotent: repeated processing of the same snapshot must not create duplicates or corrupt state.
- Make `migrations` safe and incremental: add nullable columns first, backfill asynchronously, then make NOT NULL.
- Minimize long-running exclusive locks; prefer CONCURRENT index creation where supported.
- Keep `PII` minimal and provide explicit redaction guidance for any sensitive fields prior to archival or external
  export.

---

## 2. Naming & conventions

- All timestamps: timestamptz (UTC). Column names: `created_at`, `updated_at`, `processed_at`, `server_time` (where
  upstream provides epoch).
- Primary key convention: `id` as UUID where appropriate (generated with `gen_random_uuid()` via `pgcrypto`), or integer
  for catalog tables.
- Foreign keys: explicit FK constraints where referential integrity is required. Use `ON DELETE SET NULL` for references
  that must not cascade deletes unexpectedly.
- JSON storage: use `jsonb` for columns storing raw snapshots or arbitrary extra fields. Use `jsonb` named `extra`,
  `extras`, or `raw` for unmapped data.
- Index names: `idx_<table>_<cols>`; unique constraints prefixed `ux_`.

---

## 3. Core tables (canonical descriptions & recommended columns)

> Note: these are canonical column lists and notes — the actual `SQL DDL` must be created via versioned migrations
> (`node-pg-migrate`).

### 3.1 users (canonical user mapping)

- _Purpose:_ canonical user row used by application and joins.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `namecode` VARCHAR(64) UNIQUE NULLABLE
    - `discord_user_id` VARCHAR(64) NULLABLE
    - `username` VARCHAR(255) NULLABLE
    - `email` VARCHAR(255) NULLABLE
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`namecode`)
    - INDEX on `discord_user_id` for quick lookup
    - Consider partial indexes for active users (e.g. WHERE `updated_at > now()` - interval '90 days')

- _Notes:_
    - Keep `PII` minimal; consider moving sensitive `PII` (email) to a protected table with stricter access controls.
    - Use `gen_random_uuid()` (`pgcrypto`) where provider allows; otherwise generate `UUIDs` app-side.

---

### 3.2 hero_snapshots (raw ingestion store)

- _Purpose:_ persist raw `get_hero_profile` payloads for audit, dedupe and replay. Single source-of-truth raw payload
  retention.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `user_id` UUID REFERENCES users(id) ON DELETE SET NULL
    - `namecode` VARCHAR(64) NULLABLE
    - `source` VARCHAR(64) NOT NULL -- e.g. "fetch_by_namecode", "login", "cli_upload"
    - `raw` JSONB NOT NULL
    - `size_bytes` INTEGER NOT NULL
    - `content_hash` VARCHAR(128) NOT NULL -- hex SHA256
    - `server_time` BIGINT NULLABLE -- if upstream provides server timestamp (epoch millis)
    - `processing` BOOLEAN DEFAULT FALSE
    - `processing_started_at` TIMESTAMPTZ NULLABLE
    - `processed_at` TIMESTAMPTZ NULLABLE
    - `error_count` INTEGER DEFAULT 0
    - `last_error` JSONB NULLABLE
    - `created_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - `GIN`: CREATE INDEX `idx_hero_snapshots_raw_gin` ON `hero_snapshots` USING GIN (raw `jsonb_path_ops`);
    - `B-tree`: CREATE INDEX `idx_hero_snapshots_user_created_at` ON `hero_snapshots` (`user_id`, `created_at` DESC);
    - Optional: UNIQUE(`content_hash`, source) (or partial unique for dedupe window) — if implemented, prefer
      application-level dedupe to allow duplicates outside window.
    - Expression index: CREATE INDEX `idx_hero_snapshots_namecode_expr` ON `hero_snapshots` ((raw ->> 'NameCode'));

- _Notes:_
    - Compute `content_hash` := encode(digest(raw::text, 'sha256'), 'hex') in DB or app on insert; store `size_bytes` :=
      `octet_length`(raw::text).
    - Keep raw `JSONB` for replay; plan retention/archival (see section retention).
    - Use small inserts with Idempotency-Key header in ingestion `API` to avoid duplicate processing.

---

### 3.3 user_troops (normalized inventory)

- _Purpose:_ normalized per-user troop counts for fast queries and analytics.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `user_id` UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
    - `troop_id` INTEGER NOT NULL -- FK to `troop_catalog` when available
    - `amount` INTEGER DEFAULT 0 NOT NULL
    - `level` INTEGER DEFAULT 1
    - `rarity` INTEGER DEFAULT 0
    - `fusion_cards` INTEGER DEFAULT 0
    - `traits_owned` INTEGER DEFAULT 0
    - `extra` JSONB DEFAULT '{}'::jsonb
    - `last_seen` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`user_id`, `troop_id`)
    - INDEX `idx_user_troops_troop` ON `user_troops` (`troop_id`)
    - INDEX `idx_user_troops_user` ON `user_troops` (`user_id`)

- _Notes:_
    - Use ON CONFLICT (`user_id`, `troop_id`) DO UPDATE ... in upserts to be idempotent.
    - Keep extra `JSONB` for unmapped fields so that `ETL` remains tolerant to upstream changes.

---

### 3.4 user_pets

- _Purpose:_ normalized per-user pet inventory.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `user_id` UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
    - `pet_id` INT NOT NULL
    - `amount` INT DEFAULT 0 NOT NULL
    - `level` INT DEFAULT 1
    - `xp` BIGINT DEFAULT 0
    - `orb_fusion_cards` INT DEFAULT 0
    - `orbs_used` JSONB DEFAULT '[]'::jsonb
    - `ascension_level` INT DEFAULT 0
    - `extra` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`user_id`, `pet_id`)
    - INDEX `idx_user_pets_pet` ON `user_pets` (`pet_id`)
    - INDEX `idx_user_pets_user` ON `user_pets` (`user_id`)

- _Notes:_
    - Keep `orbs_used` as `JSONB` array of event objects if upstream provides that detail.
    - Use atomic per-user pet upserts to avoid partial state.

---

### 3.5 user_artifacts

- _Purpose:_ per-user artifacts (progress & levels).

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `user_id` UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
    - `artifact_id` INT NOT NULL
    - `level` INT DEFAULT 0
    - `xp` BIGINT DEFAULT 0
    - `extra` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`user_id`, `artifact_id`)
    - INDEX `idx_user_artifacts_artifact` ON `user_artifacts` (`artifact_id`)

- _Notes:_
    - Upsert with ON CONFLICT(`user_id`, `artifact_id`) DO UPDATE to be idempotent.

---

### 3.6 user_teams

- _Purpose:_ store user-created teams (equipped teams / saved team configurations).

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `user_id` UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
    - `name` VARCHAR(255) NULLABLE
    - `banner` INT NULLABLE
    - `team_level` INT DEFAULT 0
    - `class` VARCHAR(128) NULLABLE
    - `troops` JSONB DEFAULT '[]'::jsonb -- ordered list of troop ids or objects
    - `override_data` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - INDEX `idx_user_teams_user` ON `user_teams` (`user_id`)
    - If teams are referenced frequently by namecode, consider index on (`user_id`, `name`) unique per user.

- _Notes:_
    - Consider a separate table for Team Saves / public sharing (see `team_saves`).
    - For fast game lookups, keep troop ids as integer arrays if simpler (INT[]), but `JSONB` allows flexible metadata.

---

### 3.7 guilds

- _Purpose:_ guild metadata and per-guild settings/feature flags.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `discord_guild_id` VARCHAR(64) UNIQUE NULLABLE
    - `name` VARCHAR(255) NOT NULL
    - `description` TEXT NULLABLE
    - `settings` JSONB DEFAULT '{}'::jsonb
    - `feature_flags` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`discord_guild_id`) -- if provided
    - INDEX `idx_guilds_name` ON `guilds` (`name`)

- _Notes:_
    - `Feature_flags` is optional per-guild override; global flags live in `feature_flags` table.
    - Keep settings small and validated at application level.

---

### 3.8 guild_members

- _Purpose:_ mapping between guilds and users.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `guild_id` UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE
    - `user_id` UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
    - `discord_user_id` VARCHAR(64) NULLABLE
    - `joined_at` TIMESTAMPTZ NULLABLE
    - `is_owner` BOOLEAN DEFAULT false
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`guild_id`, `user_id`)
    - INDEX `idx_guild_members_guild` ON `guild_members` (`guild_id`)

- _Notes:_
    - Keep membership events in `audit_logs` if join/leave is important historically.

---

### 3.9 feature_flags

- _Purpose:_ global feature toggles.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `name` VARCHAR(128) UNIQUE NOT NULL
    - `enabled` BOOLEAN DEFAULT false
    - `rollout_percentage` INT DEFAULT 0
    - `data` JSONB DEFAULT '{}'::jsonb -- additional configuration
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`name`)
    - INDEX `idx_feature_flags_enabled` ON `feature_flags` (enabled)

- _Notes:_
    - Evaluate caching flags in Redis with short `TTL` for performance.
    - Use deterministic hashing to apply `rollout_percentage` by user id or namecode.

---

### 3.10 user_profile_summary (denormalized read table)

- _Purpose:_ fast-read, denormalized summary consumed by bot/UI (one row per user).

- _Columns:_
    - `user_id` UUID PRIMARY KEY REFERENCES users(id)
    - `namecode` VARCHAR(64)
    - `username` VARCHAR(255)
    - `level` INTEGER
    - `top_troops` JSONB DEFAULT '[]'::jsonb -- e.g. [ {troop_id, amount, level} ]
    - `equipped_pet` JSONB NULLABLE
    - `pvp_tier` INTEGER NULLABLE
    - `guild_id` UUID NULLABLE
    - `last_seen` TIMESTAMPTZ NULLABLE
    - `cached_at` TIMESTAMPTZ DEFAULT now() -- when summary was generated
    - `extra` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - PRIMARY KEY(`user_id`)
    - INDEX `idx_profile_summary_namecode` ON `user_profile_summary` (`namecode`)
    - Consider partial index for active players: WHERE `cached_at > now() - interval '7 days'`

- _Notes:_
    - `ETL` writes/updates this table; reads should be served from it to meet latency `SLAs`.
    - Keep `extra` for unmapped fields so reprocessing can add new summary fields without losing data.

---

### 3.11 etl_errors

- _Purpose:_ record per-snapshot or per-entity `ETL` errors for triage.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `snapshot_id` UUID REFERENCES hero_snapshots(id) ON DELETE SET NULL
    - `error_type` VARCHAR(128) NOT NULL -- e.g. PARSE_ERROR, FK_VIOLATION
    - `message` TEXT NOT NULL -- short sanitized message
    - `details` JSONB NULLABLE -- structured diagnostic (truncated snippets, stack)
    - `created_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - INDEX `idx_etl_errors_snapshot_id_created_at` ON `etl_errors` (`snapshot_id`, `created_at` DESC)

- _Notes:_
    - Do not store full raw snapshot in details; reference `snapshot_id` for investigation.
    - Create alerts if error rates exceed threshold.

---

### 3.12 catalogs (troop_catalog, pet_catalog, artifact_catalog)

- _Purpose:_ canonical static metadata seeded from official data sources or community-maintained sources.

- _Example: `troop_catalog` columns:_
    - `id` INT PRIMARY KEY
    - `kid` VARCHAR(64) NULLABLE
    - `name` VARCHAR(255) NOT NULL
    - `description` TEXT NULLABLE
    - `rarity` INT
    - `meta` JSONB DEFAULT '{}'::jsonb -- game-specific attributes (costs, traits)
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE on external identifiers (`kid`)
    - INDEX on `name` for search

- _Notes:_
    - Seed catalogs via idempotent seed scripts; `ETL` should reference catalog ids when available.
    - If `ETL` finds unmapped ids, create placeholder rows with `meta -> { "placeholder": true }` to avoid FK failures.

---

### 3.13 queue_jobs (job persistence / fallback)

- _Purpose:_ persist background jobs (optional DB-backed queue) as a durable fallback or for job inspection.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `type` VARCHAR(128) NOT NULL -- 'process_snapshot', 'archive_snapshot', ...
    - `payload` JSONB NOT NULL -- minimal payload (snapshot_id, options)
    - `priority` INT DEFAULT 0
    - `attempts` INT DEFAULT 0
    - `max_attempts` INT DEFAULT 5
    - `status` VARCHAR(32) DEFAULT 'pending' -- pending|running|failed|done
    - `run_after` TIMESTAMPTZ DEFAULT now()
    - `last_error` TEXT NULLABLE
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - INDEX `idx_queue_jobs_status_run_after` ON `queue_jobs` (`status`, `run_after`)
    - Use a small table for visibility; production queue should remain `Redis/BullMQ` for throughput.

- _Notes:_
    - Use as a fallback for job durability and administrative requeueing.

---

### 3.14 audit_logs

- _Purpose:_ capture important admin/user actions for audit and compliance.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `action` VARCHAR(255) NOT NULL -- e.g. 'migration_run', 'snapshot_reprocessed'
    - `user_id` UUID NULLABLE
    - `guild_id` UUID NULLABLE
    - `metadata` JSONB DEFAULT '{}'::jsonb -- action details, sanitized
    - `ip_address` VARCHAR(45) NULLABLE
    - `user_agent` VARCHAR(512) NULLABLE
    - `created_at` TIMESTAMPTZ DEFAULT now()

- _Indexes:_
    - INDEX `idx_audit_logs_action_created_at` ON `audit_logs` (`action`, `created_at` DESC)

- _Notes:_
    - Do not log secrets or raw snapshots here. Keep metadata minimal and traceable.

---

### 3.15 raw_profiles (alternate simplified snapshot store)

- _Purpose:_ an optional simplified table for ingesting raw profiles before enriched processing (lighter than
  `hero_snapshots`)

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_external_id` VARCHAR(255) NULLABLE -- upstream player id if available
    - `source` VARCHAR(64) NOT NULL
    - `captured_at` TIMESTAMPTZ DEFAULT now()
    - `raw` JSONB NOT NULL

- _Indexes:_
    - INDEX `idx_raw_profiles_hero_external_id` ON `raw_profiles` (`hero_external_id`)

- _Notes:_
    - This table is optional if `hero_snapshots` is sufficient. Use if you want a short ingest path decoupled from
      `ETL`.

---

### 3.16 heroes (canonical hero mapping — expanded)

- _Purpose:_ normalized representation of a player/hero aggregated across snapshots.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `external_id` VARCHAR(255) UNIQUE NULLABLE -- stable upstream id (if any)
    - `name` VARCHAR(255) NULLABLE
    - `namecode` VARCHAR(64) UNIQUE NULLABLE
    - `name_lower` VARCHAR(255) NULLABLE -- for case-insensitive search
    - `username` VARCHAR(255) NULLABLE
    - `level` INT DEFAULT 0
    - `race` INT NULLABLE
    - `gender` INT NULLABLE
    - `class` VARCHAR(128) NULLABLE
    - `portrait_id` INT NULLABLE
    - `title_id` INT NULLABLE
    - `flair_id` INT NULLABLE
    - `honor_rank` INT NULLABLE
    - `equipped_weapon_id` INT NULLABLE
    - `equipped_pet_id` INT NULLABLE
    - `guild_id` UUID NULLABLE REFERENCES guilds(id)
    - `guild_external_id` VARCHAR(64) NULLABLE
    - `guild_name` VARCHAR(255) NULLABLE
    - `guild_rank` INT NULLABLE
    - `server_time` TIMESTAMPTZ NULLABLE
    - `last_login` TIMESTAMPTZ NULLABLE
    - `last_played` TIMESTAMPTZ NULLABLE
    - `summary` JSONB NULLABLE -- snapshot-derived denormalized blob for debugging
    - `extras` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`external_id`) if upstream provides stable id
    - INDEX `idx_heroes_namecode` ON `heroes` (`namecode`)
    - INDEX `idx_heroes_guild_id` ON `heroes` (`guild_id`)

- _Notes:_
    - `heroes` can be the canonical mapping that `ETL` updates; `user_profile_summary` is the read-optimized table
      consumed by UI/bot.
    - Keep `summary` for debugging / ad-hoc fallbacks.

---

### 3.17 hero_runes

- _Purpose:_ store runes or rune-sets for a hero.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE
    - `runes` JSONB NOT NULL
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Indexes:_
    - INDEX `idx_hero_runes_hero` ON `hero_runes` (`hero_id`)

- _Notes:_
    - Could be multiple rows per hero if the upstream uses multiple rune slots/versioning.

---

### 3.18 hero_troops

- _Purpose:_ store normalized troop inventory per hero (detailed).

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE
    - `troop_id` INT NOT NULL
    - `amount` INT DEFAULT 0
    - `level` INT DEFAULT 1
    - `current_rarity` INT DEFAULT 0
    - `fusion_cards` INT DEFAULT 0
    - `orb_fusion_cards` INT DEFAULT 0
    - `traits_owned` INT DEFAULT 0
    - `invasions` INT DEFAULT 0
    - `shiny_level_progress` INT DEFAULT 0
    - `orbs_used` JSONB DEFAULT '[]'::jsonb
    - `extra` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`hero_id`, `troop_id`)
    - INDEX `idx_hero_troops_troop` ON `hero_troops` (`troop_id`)
    - INDEX `idx_hero_troops_hero` ON `hero_troops` (`hero_id`)

- _Notes:_
    - Use batch upserts with ON CONFLICT to update amounts/levels atomically.

---

### 3.19 hero_pets

- _Purpose:_ store normalized pets per hero.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE
    - `pet_id` INT NOT NULL
    - `amount` INT DEFAULT 0
    - `level` INT DEFAULT 1
    - `xp` BIGINT DEFAULT 0
    - `orb_fusion_cards` INT DEFAULT 0
    - `orbs_used` JSONB DEFAULT '[]'::jsonb
    - `ascension_level` INT DEFAULT 0
    - `extra` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`hero_id`, `pet_id`)
    - INDEX `idx_hero_pets_pet` ON `hero_pets` (`pet_id`)

---

### 3.20 hero_artifacts

- _Purpose:_ normalized artifacts per hero.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE
    - `artifact_id` INT NOT NULL
    - `xp` BIGINT DEFAULT 0
    - `level` INT DEFAULT 0
    - `extra` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`hero_id`, `artifact_id`)

---

### 3.21 teams

- _Purpose:_ normalized teams (active configurations) for heroes.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE
    - `name` VARCHAR(255) NULLABLE
    - `banner` INT NULLABLE
    - `team_level` INT DEFAULT 0
    - `class` VARCHAR(128) NULLABLE
    - `override_data` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Indexes:_
    - INDEX `idx_teams_hero` ON `teams` (`hero_id`)

---

### 3.22 team_troops

- _Purpose:_ mapping table for troops inside a team (ordered positions).

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `team_id` UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE
    - `position` INT NOT NULL -- position index in team
    - `troop_id` INT NOT NULL

- _Indexes:_
    - INDEX `idx_team_troops_team` ON `team_troops` (`team_id`, `position`)

- _Notes:_
    - Keep position contiguous and deterministic so presentation layers can render quickly.

---

### 3.23 team_saves

- _Purpose:_ user-shared/persisted team configurations (public or private).

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE
    - `name` VARCHAR(255)
    - `description` TEXT
    - `data` JSONB NOT NULL -- full team data for replay
    - `is_public` BOOLEAN DEFAULT false
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Indexes:_
    - INDEX `idx_team_saves_hero` ON `team_saves` (`hero_id`)
    - INDEX `idx_team_saves_public` ON `team_saves` (`is_public`)

---

### 3.24 team_comments

- _Purpose:_ comments on saved teams (community interactions).

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `team_save_id` UUID NOT NULL REFERENCES team_saves(id) ON DELETE CASCADE
    - `author_user_id` UUID NOT NULL REFERENCES app_users(id) -- note: app_users used for bot operators / forum users
    - `guild_id` UUID NULLABLE REFERENCES guilds(id)
    - `comment` TEXT NOT NULL
    - `created_at` TIMESTAMPTZ DEFAULT now()

- _Indexes:_
    - INDEX `idx_team_comments_team_save` ON `team_comments` (`team_save_id`)

---

### 3.25 hero_kingdom_progress

- _Purpose:_ track hero progress in per-kingdom systems.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE
    - `kingdom_id` INT NOT NULL
    - `status` INT DEFAULT 0
    - `income` INT DEFAULT 0
    - `challenge_tier` INT DEFAULT 0
    - `invasions` INT DEFAULT 0
    - `power_rank` INT DEFAULT 0
    - `tasks` JSONB DEFAULT '[]'::jsonb
    - `explore` JSONB DEFAULT '{}'::jsonb
    - `trials_team` JSONB DEFAULT '{}'::jsonb
    - `extra` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`hero_id`, `kingdom_id`)
    - INDEX `idx_hero_kingdom_progress_hero` ON `hero_kingdom_progress` (`hero_id`)

---

### 3.26 hero_pvp_regions

- _Purpose:_ store per-hero PvP region stats and most-used teams.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE
    - `region_id` INT NOT NULL
    - `team` JSONB DEFAULT '{}'::jsonb
    - `stats` JSONB DEFAULT '{}'::jsonb
    - `most_used_troop` JSONB DEFAULT '{}'::jsonb
    - `extras` JSONB DEFAULT '{}'::jsonb
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints & Indexes:_
    - UNIQUE(`hero_id`, `region_id`)
    - INDEX `idx_hero_pvp_regions_hero` ON `hero_pvp_regions` (`hero_id`)

---

### 3.27 hero_pvp_stats

- _Purpose:_ aggregate PvP metrics per hero.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE UNIQUE
    - `invades_won` INT DEFAULT 0
    - `invades_lost` INT DEFAULT 0
    - `defends_won` INT DEFAULT 0
    - `defends_lost` INT DEFAULT 0
    - `most_invaded_kingdom` JSONB NULLABLE
    - `most_used_troop` JSONB NULLABLE
    - `raw` JSONB NULLABLE -- keep raw payload if needed for debug
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Notes:_
    - This table can be updated incrementally as `ETL` processes snapshots.

---

### 3.28 hero_progress_weapons

- _Purpose:_ weapon progression state per hero.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id)
    - `weapon_data` JSONB NOT NULL
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Indexes:_
    - INDEX `idx_hero_progress_weapons_hero` ON `hero_progress_weapons` (`hero_id`)

---

### 3.29 hero_class_data

- _Purpose:_ per-hero class-related data (per-class specialization or progress).

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id)
    - `class_name` VARCHAR(128) NOT NULL
    - `data` JSONB NOT NULL
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Constraints:_
    - UNIQUE(`hero_id`, `class_name`)

---

### 3.30 hero_meta_json

- _Purpose:_ key-value JSON storage for misc hero metadata.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `hero_id` UUID NOT NULL REFERENCES heroes(id)
    - `key` VARCHAR(255) NOT NULL
    - `value` JSONB
    - `created_at` TIMESTAMPTZ DEFAULT now()
    - `updated_at` TIMESTAMPTZ DEFAULT now()

- _Indexes:_
    - INDEX `idx_hero_meta_hero_key` ON `hero_meta_json` (`hero_id`, `key`)

---

### 3.31 sheets_sync_logs

- _Purpose:_ logs for synchronizing data to external sheets (optional feature).

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `guild_id` UUID NOT NULL REFERENCES guilds(id)
    - `sheet_id` VARCHAR(255)
    - `range` VARCHAR(128)
    - `rows_sent` INT DEFAULT 0
    - `status` VARCHAR(64) -- success|failed|pending
    - `error` JSONB NULLABLE
    - `started_at` TIMESTAMPTZ NULLABLE
    - `finished_at` TIMESTAMPTZ NULLABLE

- _Indexes:_
    - INDEX `idx_sheets_sync_logs_guild` ON `sheets_sync_logs` (`guild_id`)

---

### 3.32 cache_invalidation

- _Purpose:_ single-row records used to coordinate cache invalidation across services.

- _Columns:_
    - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
    - `key` VARCHAR(255) NOT NULL -- cache key / namespace
    - `invalidated_at` TIMESTAMPTZ DEFAULT now()

- _Notes:_
    - Simple table for cross-process invalidation if pub/sub not available.

---

### 3.33 troops_master_light (materialized view)

- _Purpose:_ lightweight read-only snapshot of troops catalogs for analytics and quick lookups (materialized view).

- _Columns (materialized):_
    - `id` INT PRIMARY KEY
    - `kid` VARCHAR
    - `name` VARCHAR
    - `kingdom_id` INT
    - `kingdom_name` VARCHAR
    - `rarity` VARCHAR
    - `rarity_id` INT
    - `max_attack` INT
    - `max_armor` INT
    - `max_life` INT
    - `max_magic` INT
    - `spell_id` INT
    - `shiny_spell_id` INT
    - `colors` INT
    - `arcanes` VARCHAR
    - `image_url` VARCHAR
    - `type` VARCHAR
    - `troop_role1` VARCHAR
    - `description` TEXT

- _Notes:_
    - Refresh schedule depends on how often catalog changes; use CONCURRENTLY where supported.

---

## Foreign key / relationship summary (excerpt)

- `role_permissions.role_id` -> `roles.id`
- `role_permissions.permission_id` -> `permissions.id`
- `guild_members.guild_id` -> `guilds.id`
- `guild_members.user_id` -> `app_users.id`
- `guild_roles.guild_id` -> `guilds.id`
- `guild_roles.role_id` -> `roles.id`
- `guild_member_roles.guild_member_id` -> `guild_members.id`
- `guild_member_roles.guild_role_id` -> `guild_roles.id`
- `guild_feature_flags.guild_id` -> `guilds.id`
- `guild_feature_flags.feature_flag_id` -> `feature_flags.id`
- `troops.kingdom_id` -> `kingdoms.id`
- `classes.kingdom_id` -> `kingdoms.id`
- `troops.spell_id` -> `spells.id`
- `game_events.troop_id` -> `troops.id`
- `raw_profiles.hero_external_id` -> `heroes.external_id`
- `heroes.guild_id` -> `guilds.id`
- `hero_* tables` (*.hero_id) -> `heroes.id`
- `teams.hero_id` -> `heroes.id`
- `team_troops.team_id` -> `teams.id`
- `team_comments.team_save_id` -> `team_saves.id`
- `team_comments.author_user_id` -> `app_users.id`
- `sheets_sync_logs.guild_id` -> `guilds.id`

(See DBML snippet for the full list and diagram rendering.)

---

## Examples DDL snippets (pattern / best-practice)

- `hero_snapshots` insert with hash (`Postgres` example using `pgcrypto`):

```sql
INSERT INTO hero_snapshots (id, user_id, namecode, source, raw, size_bytes, content_hash, created_at)
VALUES (gen_random_uuid(),
        NULL,
        ($1):: varchar,
        ($2):: varchar,
        $3::jsonb,
        octet_length($3::text),
        encode(digest($3::text, 'sha256'), 'hex'),
        now());
```

- Atomic claim to process snapshot:

```sql
UPDATE hero_snapshots
SET processing            = true,
    processing_started_at = now()
WHERE id = $1
  AND (processing = false OR processing IS NULL) RETURNING id;
```

- `GIN` index creation (CONCURRENTLY for no lock where supported):

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hero_snapshots_raw_gin
    ON hero_snapshots USING GIN (raw jsonb_path_ops);
```

- `user_troops` upsert pattern:

```sql
INSERT INTO user_troops (user_id, troop_id, amount, level, rarity, fusion_cards, traits_owned, extra, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, now()) ON CONFLICT (user_id, troop_id) DO
UPDATE
    SET amount = EXCLUDED.amount,
    level = EXCLUDED.level,
    rarity = EXCLUDED.rarity,
    fusion_cards = EXCLUDED.fusion_cards,
    traits_owned = EXCLUDED.traits_owned,
    extra = COALESCE (user_troops.extra, '{}'::jsonb) || EXCLUDED.extra,
    updated_at = now();
```

---

## Operational recommendations & next steps

1. **Migrations**
    - Implement these schemas through small, tested `node-pg-migrate` migrations.
    - Separate extension creation into its own `migration (CREATE EXTENSION IF NOT EXISTS pgcrypto`) with clear fallback
      instructions.

2. **Indexes**
    - Create `GIN` indexes for `JSONB` fields used for ad-hoc queries, but measure write overhead.
    - Use CONCURRENTLY for large indexes in production to avoid long locks.

3. **Partitioning & retention**
    - Partition `hero_snapshots` by month (range) when dataset grows, to speed deletion/archive jobs.
    - Implement archival job: compress `raw JSON` -> upload to `S3` -> insert into `snapshot_archives` -> delete
      partition rows (or mark archived).

4. **Seeds & catalogs**
    - Provide idempotent seeds for `troop_catalog` / `pet_catalog` / `spells` and keep them under database/seeds/.
    - `ETL` should create placeholders for missing catalog items and mark them for analyst review.

5. **Backfill & ETL**
    - Use the same `ETL` code for new snapshots and backfills to guarantee mapping parity.
    - Record backfill job progress in `queue_jobs` or a `backfill_audit` table for resume capability.

6. **Tests & validation**
    - Add integration tests that run migrations, insert sample snapshots (docs/examples), run `ETL` and verify
      normalized tables and `user_profile_summary`.

---

## 4. Indexes & query patterns

### 4.1 Recommended indexes (examples)

- **hero_snapshots**:
    - **GIN**: `CREATE INDEX idx_hero_snapshots_raw_gin ON hero_snapshots USING GIN (raw jsonb_path_ops);`
    - **B-tree**: `CREATE INDEX idx_hero_snapshots_user_created_at ON hero_snapshots (user_id, created_at DESC);`
    - **Optional uniqueness**:
      `CREATE UNIQUE INDEX ux_hero_snapshots_contenthash_source ON hero_snapshots (content_hash, source)` (use with
      caution; dedupe logic may be more flexible in app)
- **users**:
    - `CREATE UNIQUE INDEX ux_users_namecode ON users (namecode);`
    - `CREATE INDEX idx_users_discord_user_id ON users (discord_user_id);`
- **user_troops**:
    - `CREATE UNIQUE INDEX ux_user_troops_user_troop ON user_troops (user_id, troop_id);`
    - `CREATE INDEX idx_user_troops_troop ON user_troops (troop_id);`
- **user_profile_summary**:
    - `CREATE INDEX idx_profile_summary_namecode ON user_profile_summary (namecode);`
- **etl_errors**:
    - `CREATE INDEX idx_etl_errors_snapshot_id_created_at ON etl_errors (snapshot_id, created_at DESC);`

### 4.2 Query patterns (examples)

- Latest processed snapshot for user:

```sql
SELECT *
FROM hero_snapshots
WHERE user_id = $1
  AND processed_at IS NOT NULL
ORDER BY created_at DESC LIMIT 1;
```

- Profile summary by namecode:

```sql
SELECT *
FROM user_profile_summary
WHERE namecode = $1;
```

- Who owns troop 6024:

```sql
SELECT u.id, u.namecode, ut.amount, ut.level
FROM user_troops ut
         JOIN users u ON ut.user_id = u.id
WHERE ut.troop_id = 6024
  AND ut.amount > 0
ORDER BY ut.amount DESC LIMIT 100;
```

---

## 5. Partitioning, retention & archival guidance

### 5.1 Partition hero_snapshots when volume grows

- _Strategy:_ time-based partitions (monthly) on created_at:
    - Create parent table `hero_snapshots` and child partitions `hero_snapshots_2025_11` etc.
- _Benefits:_ faster archival/deletion, reduced vacuum overhead, improved index size on recent partitions.

### 5.2 Retention policy & archival

- Default retention example: keep 90 days in DB, archive older snapshots to `S3` (compressed) with audit metadata.
- Steps for archival:
    1. SELECT snapshots older than retention threshold and not flagged permanent.
    2. Compress raw `JSON` (gzip/zstd), upload to `S3` with server-side encryption.
    3. Insert archival metadata (`s3_path`, `checksum`, `archived_at`) into `snapshot_archives` table and then DELETE or
       mark as archived.
- Keep at least N recent snapshots per user (configurable) if required.

---

## 6. Upsert examples and idempotency patterns

### 6.1 user_troops upsert (example)

- Use single multi-row upsert for batch inserts/updates:

```sql
-- example uses tmp table or values list
INSERT INTO user_troops (user_id, troop_id, amount, level, rarity, fusion_cards, traits_owned, extra, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now()), ...
    ON CONFLICT (user_id, troop_id) DO
UPDATE
    SET amount = EXCLUDED.amount,
    level = EXCLUDED.level,
    rarity = EXCLUDED.rarity,
    fusion_cards = EXCLUDED.fusion_cards,
    traits_owned = EXCLUDED.traits_owned,
    extra = COALESCE (user_troops.extra, '{}'::jsonb) || EXCLUDED.extra,
    updated_at = now();
```

- Keep transactions per entity group (users, troops, pets) to avoid holding long transactions.

### 6.2 users upsert example

```sql
INSERT INTO users (id, namecode, username, discord_user_id, email, created_at, updated_at)
VALUES (gen_random_uuid(), $namecode, $username, $discord_id, $email, now(), now()) ON CONFLICT (namecode) DO
UPDATE
    SET username = EXCLUDED.username,
    discord_user_id = COALESCE (users.discord_user_id, EXCLUDED.discord_user_id),
    email = COALESCE (users.email, EXCLUDED.email),
    updated_at = now();
```

- If generating `UUIDs` client-side, ensure deterministic mapping or idempotency key in insertion logic.

### 6.3 Mark snapshot processed

- After successful processing:

```sql
UPDATE hero_snapshots
SET processed_at = now(),
    processing   = false,
    last_error   = NULL
WHERE id = $snapshot_id;
```

- Use atomic claim to set `processing=true`:

```sql
UPDATE hero_snapshots
SET processing            = true,
    processing_started_at = now()
WHERE id = $snapshot_id
  AND (processing = false OR processing IS NULL) RETURNING id;
```

---

## 7. Migration strategy & preflight checks

### 7.1 Tooling

- Use `node-pg-migrate` (`JS`) for migrations; store migrations under `database/migrations/` and use timestamped
  filenames.
- Keep migrations small and reversible where possible.

### 7.2 Preflight checks (CI job)

- Verify required extensions & permissions (e.g., `CREATE EXTENSION IF NOT EXISTS pgcrypto;`).
- Run migrations in a disposable ephemeral DB (testcontainers) and ensure `up` completes.
- Run a smoke `ETL`: insert a sample snapshot, run the worker code path, assert summary created.

### 7.3 Safe migration pattern

- 3-step for destructive change:
    1. Add nullable column / new table / index (no locks if possible: `CREATE INDEX CONCURRENTLY`).
    2. Backfill and verify via a background job.
    3. Make column NOT NULL and remove old column in a later migration.

### 7.4 Production bootstrap

- Production migrations and bootstrap should run via a manual `GitHub Action` (`db-bootstrap.yml`) protected by GitHub
  Environments and approvers.
- Always take a DB snapshot/backup before applying production migrations.

### 7.5 Extension fallback

- If `pgcrypto` cannot be enabled by provider, fallback to generating `UUIDs` in application code or use
  `uuid_generate_v4()` only if available.

---

## 8. Data retention & archival model (summary)

- Default retention: 90 days for `hero_snapshots` in DB (configurable).
- Keep last N snapshots per user (e.g., last 30) in addition to time window.
- Archive older snapshots to `S3` (gzip/zstd) with checksum and audit metadata in `snapshot_archives` table.
- Provide admin endpoints and runbooks for reprocessing archived snapshots (download from `S3`, reinsert, reprocess).

---

## 9. Validation queries & health checks

- Basic health:

```sql
SELECT 1;
```

- Sanity check after migrations:

```sql
SELECT count(*)
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('users', 'hero_snapshots', 'user_troops');
```

- Sample `ETL` verification (for a given namecode):

```sql
-- latest snapshot exists and processed
SELECT hs.id, hs.processed_at, ups.user_id, ups.namecode
FROM hero_snapshots hs
         LEFT JOIN users ups ON hs.user_id = ups.id
WHERE hs.namecode = $1
ORDER BY hs.created_at DESC LIMIT 1;
```

- Idempotency test:
    - Insert snapshot A, process, record counts.
    - Re-insert same snapshot (or reprocess) and assert no duplicate rows and counts unchanged.

---

## 10. DBML schema (paste into dbdiagram.io)

The `DBML` representation below is provided for visualization. Paste into https://dbdiagram.io to generate diagrams. The
code here is the cleaned `DBML` derived from the PRD; it mirrors the canonical tables and relationships described above.

```sql
// DBML representation of the StarForge schema (cleaned).
// Paste this into https://dbdiagram.io to visualize the schema.
// jsonb columns are represented as "json" for visualization purposes.

Table app_users {
  id uuid [pk]
  email varchar [unique]
  username varchar
  display_name varchar
  avatar_url varchar
  created_at timestamp
  updated_at timestamp
}

Table roles {
  id uuid [pk]
  name varchar [unique, not null]
  description text
  created_at timestamp
  updated_at timestamp
}

Table permissions {
  id uuid [pk]
  code varchar [unique, not null]
  description text
  created_at timestamp
  updated_at timestamp
}

Table role_permissions {
  role_id uuid
  permission_id uuid
  // composite PK exists in SQL
}

Table guilds {
  id uuid [pk]
  external_id varchar [unique]
  name varchar
  description text
  settings json
  created_at timestamp
  updated_at timestamp
}

Table guild_members {
  id uuid [pk]
  guild_id uuid
  user_id uuid
  game_player_id varchar
  joined_at timestamp
  is_owner boolean
  created_at timestamp
  updated_at timestamp
  // unique (guild_id, user_id)
}

Table guild_roles {
  id uuid [pk]
  guild_id uuid
  role_id uuid
  name varchar
  permission_overrides json
  created_at timestamp
  updated_at timestamp
}

Table guild_member_roles {
  id uuid [pk]
  guild_member_id uuid
  guild_role_id uuid
  created_at timestamp
}

Table audit_logs {
  id uuid [pk]
  action varchar [not null]
  user_id uuid
  guild_id uuid
  metadata json
  ip_address varchar
  user_agent varchar
  created_at timestamp
}

Table feature_flags {
  id uuid [pk]
  name varchar [unique, not null]
  enabled boolean
  rollout_percentage int
  created_at timestamp
  updated_at timestamp
}

Table guild_feature_flags {
  id uuid [pk]
  guild_id uuid
  feature_flag_id uuid
  enabled boolean
}

Table troops {
  id int [pk]
  kid varchar
  name varchar
  description text
  colors int
  arcanes varchar
  image_url varchar
  kingdom_id int
  kingdom_name varchar
  max_attack int
  max_armor int
  max_life int
  max_magic int
  rarity varchar
  rarity_id int
  spell_id int
  shiny_spell_id int
  spell_name varchar
  shiny_spell_name varchar
  spell_cost int
  release_date bigint
  switch_date bigint
  troop_role1 varchar
  type varchar
  type_code1 varchar
  type_code2 varchar
  traits json
  extras json
  created_at timestamp
  updated_at timestamp
}

Table kingdoms {
  id int [pk]
  kid varchar
  name varchar
  map_index varchar
  byline varchar
  description text
  banner_name varchar
  banner_image_url varchar
  bg_image_url varchar
  banner_mana varchar
  banner_mana_bits int
  release_date bigint
  switch_date bigint
  tribute_glory int
  tribute_gold int
  tribute_souls int
  explore_traitstone_id int
  explore_traitstone_colors int
  explore_traitstone_color_names varchar
  level_mana_color int
  level_stat varchar
  quest text
  map_position varchar
  type varchar
  troops json
  bonuses json
  created_at timestamp
  updated_at timestamp
}

Table classes {
  id int [pk]
  class_code varchar
  name varchar
  kingdom_id int
  kingdom_name varchar
  image_url varchar
  page_url varchar
  rarity varchar
  max_armor int
  max_attack int
  max_life int
  max_magic int
  spell_id int
  weapon_id int
  weapon_name varchar
  talent_codes json
  talent_list json
  traits json
  extras json
  created_at timestamp
  updated_at timestamp
}

Table talents {
  code varchar [pk]
  name varchar
  talent1 varchar
  talent1_desc text
  talent2 varchar
  talent2_desc text
  talent3 varchar
  talent3_desc text
  talent4 varchar
  talent4_desc text
  talent5 varchar
  talent5_desc text
  talent6 varchar
  talent6_desc text
  talent7 varchar
  talent7_desc text
  extras json
  created_at timestamp
  updated_at timestamp
}

Table medals {
  id int [pk]
  name varchar
  description text
  data varchar
  effect varchar
  level int
  rarity varchar
  is_event_medal boolean
  image_url varchar
  evolves_into int
  group_id int
  extras json
  created_at timestamp
  updated_at timestamp
}

Table pets {
  id int [pk]
  name varchar
  kingdom_id int
  kingdom_name varchar
  mana_color varchar
  mana_color_num int
  image_url varchar
  effect varchar
  effect_data varchar
  effect_title varchar
  event varchar
  release_date bigint
  switch_date bigint
  extras json
  created_at timestamp
  updated_at timestamp
}

Table spells {
  id int [pk]
  name varchar
  description text
  cost int
  image_url varchar
  extras json
  created_at timestamp
  updated_at timestamp
}

Table aspects {
  code varchar [pk]
  name varchar
  description text
  image_url varchar
  extras json
  created_at timestamp
  updated_at timestamp
}

Table traitstones {
  id int [pk]
  name varchar
  colors int
  image_url varchar
  extras json
  created_at timestamp
  updated_at timestamp
}

Table weapons {
  id int [pk]
  name varchar
  image_url varchar
  kingdom_id int
  kingdom_name varchar
  spell_id int
  spell_name varchar
  spell_cost int
  affixes varchar
  colors int
  mastery_requirement int
  rarity varchar
  rarity_id int
  obtain_by varchar
  weapon_role1 varchar
  weapon_upgrade varchar
  release_date bigint
  switch_date bigint
  extras json
  created_at timestamp
  updated_at timestamp
}

Table game_events {
  id int [pk]
  event_id int
  troop_id int
  kingdom_id int
  start_date bigint
  end_date bigint
  metadata json
  created_at timestamp
  updated_at timestamp
}

Table raw_profiles {
  id uuid [pk]
  hero_external_id varchar
  source varchar
  captured_at timestamp
  raw json [not null]
}

Table heroes {
  id uuid [pk]
  external_id varchar [unique]
  name varchar
  namecode varchar
  name_lower varchar
  username varchar
  level int
  level_new int
  race int
  race_alt int
  gender int
  class varchar
  portrait_id int
  title_id int
  flair_id int
  honor_rank int
  equipped_weapon_id int
  equipped_pet_id int
  guild_id uuid
  guild_external_id varchar
  guild_name varchar
  guild_rank int
  server_time timestamp
  last_login timestamp
  last_played timestamp
  created_at timestamp
  updated_at timestamp
  summary json
  extras json
}

Table hero_runes {
  id uuid [pk]
  hero_id uuid
  runes json [not null]
  created_at timestamp
  updated_at timestamp
}

Table hero_troops {
  id uuid [pk]
  hero_id uuid
  troop_id int
  amount int
  level int
  current_rarity int
  fusion_cards int
  orb_fusion_cards int
  traits_owned int
  invasions int
  shiny_level_progress int
  orbs_used json
  extra json
  created_at timestamp
  updated_at timestamp
  // unique (hero_id, troop_id)
}

Table hero_pets {
  id uuid [pk]
  hero_id uuid
  pet_id int
  amount int
  level int
  xp bigint
  orb_fusion_cards int
  orbs_used json
  ascension_level int
  extra json
  created_at timestamp
  updated_at timestamp
  // unique (hero_id, pet_id)
}

Table hero_artifacts {
  id uuid [pk]
  hero_id uuid
  artifact_id int
  xp bigint
  level int
  extra json
  created_at timestamp
  updated_at timestamp
  // unique (hero_id, artifact_id)
}

Table teams {
  id uuid [pk]
  hero_id uuid
  name varchar
  banner int
  team_level int
  class varchar
  override_data json
  created_at timestamp
  updated_at timestamp
}

Table team_troops {
  id uuid [pk]
  team_id uuid
  position int
  troop_id int
}

Table team_saves {
  id uuid [pk]
  hero_id uuid
  name varchar
  description text
  data json [not null]
  is_public boolean
  created_at timestamp
  updated_at timestamp
}

Table team_comments {
  id uuid [pk]
  team_save_id uuid
  author_user_id uuid
  guild_id uuid
  comment text
  created_at timestamp
}

Table hero_kingdom_progress {
  id uuid [pk]
  hero_id uuid
  kingdom_id int
  status int
  income int
  challenge_tier int
  invasions int
  power_rank int
  tasks json
  explore json
  trials_team json
  extra json
  created_at timestamp
  updated_at timestamp
  // unique (hero_id, kingdom_id)
}

Table hero_pvp_regions {
  id uuid [pk]
  hero_id uuid
  region_id int
  team json
  stats json
  most_used_troop json
  extras json
  created_at timestamp
  updated_at timestamp
  // unique (hero_id, region_id)
}

Table hero_pvp_stats {
  id uuid [pk]
  hero_id uuid
  invades_won int
  invades_lost int
  defends_won int
  defends_lost int
  most_invaded_kingdom json
  most_used_troop json
  raw json
  created_at timestamp
  updated_at timestamp
  // unique (hero_id)
}

Table hero_progress_weapons {
  id uuid [pk]
  hero_id uuid
  weapon_data json [not null]
  created_at timestamp
  updated_at timestamp
}

Table hero_class_data {
  id uuid [pk]
  hero_id uuid
  class_name varchar
  data json [not null]
  created_at timestamp
  updated_at timestamp
  // unique (hero_id, class_name)
}

Table hero_meta_json {
  id uuid [pk]
  hero_id uuid
  key varchar
  value json
  created_at timestamp
  updated_at timestamp
}

Table sheets_sync_logs {
  id uuid [pk]
  guild_id uuid
  sheet_id varchar
  range varchar
  rows_sent int
  status varchar
  error json
  started_at timestamp
  finished_at timestamp
}

Table queue_jobs {
  id uuid [pk]
  type varchar
  payload json
  priority int
  attempts int
  max_attempts int
  status varchar
  run_after timestamp
  last_error text
  created_at timestamp
  updated_at timestamp
}

Table cache_invalidation {
  id uuid [pk]
  key varchar
  invalidated_at timestamp
}

Table troops_master_light {
  id int [pk]
  kid varchar
  name varchar
  kingdom_id int
  kingdom_name varchar
  rarity varchar
  rarity_id int
  max_attack int
  max_armor int
  max_life int
  max_magic int
  spell_id int
  shiny_spell_id int
  colors int
  arcanes varchar
  image_url varchar
  type varchar
  troop_role1 varchar
  description text
}

// =========================
// Relationships (Refs)
— deduplicated
// =========================

Ref: role_permissions.role_id > roles.id
Ref: role_permissions.permission_id > permissions.id

Ref: guild_members.guild_id > guilds.id
Ref: guild_members.user_id > app_users.id

Ref: guild_roles.guild_id > guilds.id
Ref: guild_roles.role_id > roles.id

Ref: guild_member_roles.guild_member_id > guild_members.id
Ref: guild_member_roles.guild_role_id > guild_roles.id

Ref: guild_feature_flags.guild_id > guilds.id
Ref: guild_feature_flags.feature_flag_id > feature_flags.id

Ref: troops.kingdom_id > kingdoms.id
Ref: classes.kingdom_id > kingdoms.id
Ref: weapons.kingdom_id > kingdoms.id

Ref: troops.spell_id > spells.id
Ref: troops.shiny_spell_id > spells.id

Ref: game_events.troop_id > troops.id
Ref: game_events.kingdom_id > kingdoms.id

Ref: raw_profiles.hero_external_id > heroes.external_id

Ref: heroes.guild_id > guilds.id

Ref: hero_runes.hero_id > heroes.id
Ref: hero_troops.hero_id > heroes.id
Ref: hero_pets.hero_id > heroes.id
Ref: hero_artifacts.hero_id > heroes.id

Ref: teams.hero_id > heroes.id
Ref: team_troops.team_id > teams.id

Ref: team_saves.hero_id > heroes.id
Ref: team_comments.team_save_id > team_saves.id
Ref: team_comments.author_user_id > app_users.id
Ref: team_comments.guild_id > guilds.id

Ref: hero_kingdom_progress.hero_id > heroes.id
Ref: hero_pvp_regions.hero_id > heroes.id
Ref: hero_pvp_stats.hero_id > heroes.id
Ref: hero_progress_weapons.hero_id > heroes.id
Ref: hero_class_data.hero_id > heroes.id
Ref: hero_meta_json.hero_id > heroes.id

Ref: sheets_sync_logs.guild_id > guilds.id
```

---

## 11. Change log & references

- Change log for the DB model should reference migration IDs and PR numbers. Create `docs/CHANGELOG.md` entries when
  migrations are merged.
- See also:
    - PRD: docs/PRD.md (product-level requirements and mappings)
    - ETL & Worker design: [docs/ETL_AND_WORKER.md](./ETL_AND_WORKER.md)
    - Migration conventions: [docs/MIGRATIONS.md](./MIGRATIONS.md)
    - Observability: [docs/OBSERVABILITY.md](./OBSERVABILITY.md)

---
