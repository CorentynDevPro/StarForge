-- Comprehensive Supabase/Postgres schema for StarForge
-- File: database/supabase_schema.sql
-- Purpose: store canonical game data (troops, kingdoms, classes, weapons, pets, spells, aspects, medals, events)
-- and player data (heroes, hero_troops, pets, artifacts, teams, progress, PvP, guilds, roles, permissions, raw dumps, job logs).
-- Designed for Supabase Cloud (Postgres). This script is idempotent-friendly: it uses IF NOT EXISTS where appropriate
-- and DO blocks to safely create triggers (Postgres doesn't have CREATE TRIGGER IF NOT EXISTS).
--
-- Usage:
-- 1) Open Supabase SQL editor and paste the entire file.
-- 2) Run it. If some objects already exist the script will skip or replace as needed.
-- 3) After running, refresh your database schema in Supabase UI.

-- ------------------------
-- Extensions
-- ------------------------
CREATE
EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE
EXTENSION IF NOT EXISTS pgcrypto; -- for gen_random_uuid()

-- ------------------------
-- Utility: updated_at trigger function
-- ------------------------
CREATE
OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at
= now();
RETURN NEW;
END;
$$;

-- ------------------------
-- Core admin / auth tables
-- ------------------------

CREATE TABLE IF NOT EXISTS app_users
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    email text UNIQUE,
    username text,
    display_name text,
    avatar_url text,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS roles
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    name text UNIQUE NOT NULL,
    description text,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS permissions
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    code text UNIQUE NOT NULL,
    description text,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS role_permissions
(
    role_id
    uuid
    REFERENCES
    roles
(
    id
) ON DELETE CASCADE,
    permission_id uuid REFERENCES permissions
(
    id
)
  ON DELETE CASCADE,
    PRIMARY KEY
(
    role_id,
    permission_id
)
    );

CREATE TABLE IF NOT EXISTS guilds
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    external_id text UNIQUE,
    name text,
    description text,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    settings jsonb DEFAULT '{}'::jsonb
    );

CREATE TABLE IF NOT EXISTS guild_members
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    guild_id uuid REFERENCES guilds
(
    id
) ON DELETE CASCADE,
    user_id uuid REFERENCES app_users
(
    id
)
  ON DELETE CASCADE,
    game_player_id text,
    joined_at timestamptz,
    is_owner boolean DEFAULT false,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    UNIQUE
(
    guild_id,
    user_id
)
    );

CREATE TABLE IF NOT EXISTS guild_roles
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    guild_id uuid REFERENCES guilds
(
    id
) ON DELETE CASCADE,
    role_id uuid REFERENCES roles
(
    id
)
  ON DELETE CASCADE,
    name text,
    permission_overrides jsonb DEFAULT '{}'::jsonb
    );

CREATE TABLE IF NOT EXISTS guild_member_roles
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    guild_member_id uuid REFERENCES guild_members
(
    id
) ON DELETE CASCADE,
    guild_role_id uuid REFERENCES guild_roles
(
    id
)
  ON DELETE CASCADE,
    created_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS audit_logs
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    action text NOT NULL,
    user_id uuid REFERENCES app_users
(
    id
),
    guild_id uuid REFERENCES guilds
(
    id
),
    metadata jsonb,
    ip_address text,
    user_agent text,
    created_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS feature_flags
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    name text UNIQUE NOT NULL,
    enabled boolean DEFAULT false,
    rollout_percentage int,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS guild_feature_flags
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    guild_id uuid REFERENCES guilds
(
    id
) ON DELETE CASCADE,
    feature_flag_id uuid REFERENCES feature_flags
(
    id
)
  ON DELETE CASCADE,
    enabled boolean DEFAULT false
    );

-- ------------------------
-- Canonical game data
-- ------------------------

CREATE TABLE IF NOT EXISTS troops
(
    id
    integer
    PRIMARY
    KEY,
    kid
    text,
    name
    text,
    description
    text,
    colors
    integer,
    arcanes
    text,
    image_url
    text,
    kingdom_id
    integer,
    kingdom_name
    text,
    max_attack
    integer,
    max_armor
    integer,
    max_life
    integer,
    max_magic
    integer,
    rarity
    text,
    rarity_id
    integer,
    spell_id
    integer,
    shiny_spell_id
    integer,
    spell_name
    text,
    shiny_spell_name
    text,
    spell_cost
    integer,
    release_date
    bigint,
    switch_date
    bigint,
    troop_role1
    text,
    type
    text,
    type_code1
    text,
    type_code2
    text,
    traits
    jsonb
    DEFAULT
    '[]'
    :
    :
    jsonb,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE INDEX IF NOT EXISTS idx_troops_name ON troops USING gin (to_tsvector('simple', COALESCE (name,'')));
CREATE INDEX IF NOT EXISTS idx_troops_kingdom ON troops (kingdom_id);
CREATE INDEX IF NOT EXISTS idx_troops_rarity ON troops (rarity_id);

CREATE TABLE IF NOT EXISTS kingdoms
(
    id
    integer
    PRIMARY
    KEY,
    kid
    text,
    name
    text,
    map_index
    text,
    byline
    text,
    description
    text,
    banner_name
    text,
    banner_image_url
    text,
    bg_image_url
    text,
    banner_mana
    text,
    banner_mana_bits
    integer,
    release_date
    bigint,
    switch_date
    bigint,
    tribute_glory
    integer,
    tribute_gold
    integer,
    tribute_souls
    integer,
    explore_traitstone_id
    integer,
    explore_traitstone_colors
    integer,
    explore_traitstone_color_names
    text,
    level_mana_color
    integer,
    level_stat
    text,
    quest
    text,
    map_position
    text,
    type
    text,
    troops
    jsonb
    DEFAULT
    '[]'
    :
    :
    jsonb,
    bonuses
    jsonb
    DEFAULT
    '[]'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE INDEX IF NOT EXISTS idx_kingdoms_name ON kingdoms USING gin (to_tsvector('simple', COALESCE (name,'')));

CREATE TABLE IF NOT EXISTS classes
(
    id
    integer
    PRIMARY
    KEY,
    class_code
    text,
    name
    text,
    kingdom_id
    integer,
    kingdom_name
    text,
    image_url
    text,
    page_url
    text,
    rarity
    text,
    max_armor
    integer,
    max_attack
    integer,
    max_life
    integer,
    max_magic
    integer,
    spell_id
    integer,
    weapon_id
    integer,
    weapon_name
    text,
    talent_codes
    jsonb
    DEFAULT
    '[]'
    :
    :
    jsonb,
    talent_list
    jsonb
    DEFAULT
    '[]'
    :
    :
    jsonb,
    traits
    jsonb
    DEFAULT
    '[]'
    :
    :
    jsonb,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE INDEX IF NOT EXISTS idx_classes_name ON classes USING gin (to_tsvector('simple', COALESCE (name,'')));

CREATE TABLE IF NOT EXISTS talents
(
    code
    text
    PRIMARY
    KEY,
    name
    text,
    talent1
    text,
    talent1_desc
    text,
    talent2
    text,
    talent2_desc
    text,
    talent3
    text,
    talent3_desc
    text,
    talent4
    text,
    talent4_desc
    text,
    talent5
    text,
    talent5_desc
    text,
    talent6
    text,
    talent6_desc
    text,
    talent7
    text,
    talent7_desc
    text,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS medals
(
    id
    integer
    PRIMARY
    KEY,
    name
    text,
    description
    text,
    data
    text,
    effect
    text,
    level
    integer,
    rarity
    text,
    is_event_medal
    boolean
    DEFAULT
    false,
    image_url
    text,
    evolves_into
    integer,
    group_id
    integer,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS pets
(
    id
    integer
    PRIMARY
    KEY,
    name
    text,
    kingdom_id
    integer,
    kingdom_name
    text,
    mana_color
    text,
    mana_color_num
    integer,
    image_url
    text,
    effect
    text,
    effect_data
    text,
    effect_title
    text,
    event
    text,
    release_date
    bigint,
    switch_date
    bigint,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS spells
(
    id
    integer
    PRIMARY
    KEY,
    name
    text,
    description
    text,
    cost
    integer,
    image_url
    text,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE INDEX IF NOT EXISTS idx_spells_name ON spells USING gin (to_tsvector('simple', COALESCE (name,'')));

CREATE TABLE IF NOT EXISTS aspects
(
    code
    text
    PRIMARY
    KEY,
    name
    text,
    description
    text,
    image_url
    text,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS traitstones
(
    id
    integer
    PRIMARY
    KEY,
    name
    text,
    colors
    integer,
    image_url
    text,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS weapons
(
    id
    integer
    PRIMARY
    KEY,
    name
    text,
    image_url
    text,
    kingdom_id
    integer,
    kingdom_name
    text,
    spell_id
    integer,
    spell_name
    text,
    spell_cost
    integer,
    affixes
    text,
    colors
    integer,
    mastery_requirement
    integer,
    rarity
    text,
    rarity_id
    integer,
    obtain_by
    text,
    weapon_role1
    text,
    weapon_upgrade
    text,
    release_date
    bigint,
    switch_date
    bigint,
    extras
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE INDEX IF NOT EXISTS idx_weapons_name ON weapons USING gin (to_tsvector('simple', COALESCE (name,'')));

CREATE TABLE IF NOT EXISTS game_events
(
    id
    integer
    PRIMARY
    KEY,
    event_id
    integer,
    troop_id
    integer,
    kingdom_id
    integer,
    start_date
    bigint,
    end_date
    bigint,
    metadata
    jsonb
    DEFAULT
    '{}'
    :
    :
    jsonb,
    created_at
    timestamptz
    DEFAULT
    now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

-- ------------------------
-- Player / Hero Data
-- ------------------------

CREATE TABLE IF NOT EXISTS raw_profiles
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_external_id text,
    source text,
    captured_at timestamptz DEFAULT now
(
),
    raw jsonb NOT NULL
    );

CREATE TABLE IF NOT EXISTS heroes
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    external_id text UNIQUE,
    name text,
    namecode text,
    name_lower text,
    username text,
    level integer,
    level_new integer,
    race integer,
    race_alt integer,
    gender integer,
    class text,
    portrait_id integer,
    title_id integer,
    flair_id integer,
    honor_rank integer,
    equipped_weapon_id integer,
    equipped_pet_id integer,
    guild_id uuid REFERENCES guilds
(
    id
),
    guild_external_id text,
    guild_name text,
    guild_rank integer,
    server_time timestamptz,
    last_login timestamptz,
    last_played timestamptz,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    summary jsonb DEFAULT '{}'::jsonb,
    extras jsonb DEFAULT '{}'::jsonb
    );

CREATE INDEX IF NOT EXISTS idx_heroes_namecode ON heroes (namecode);
CREATE INDEX IF NOT EXISTS idx_heroes_external_id ON heroes (external_id);

CREATE TABLE IF NOT EXISTS hero_runes
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    runes jsonb NOT NULL,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS hero_troops
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    troop_id integer NOT NULL,
    amount integer NOT NULL DEFAULT 0,
    level integer,
    current_rarity integer,
    fusion_cards integer,
    orb_fusion_cards integer,
    traits_owned integer,
    invasions integer,
    shiny_level_progress integer,
    orbs_used jsonb DEFAULT '{}'::jsonb,
    extra jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    UNIQUE
(
    hero_id,
    troop_id
)
    );

CREATE INDEX IF NOT EXISTS idx_hero_troops_hero ON hero_troops (hero_id);
CREATE INDEX IF NOT EXISTS idx_hero_troops_troop ON hero_troops (troop_id);

CREATE TABLE IF NOT EXISTS hero_pets
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    pet_id integer NOT NULL,
    amount integer NOT NULL DEFAULT 0,
    level integer,
    xp bigint,
    orb_fusion_cards integer,
    orbs_used jsonb DEFAULT '{}'::jsonb,
    ascension_level integer,
    extra jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    UNIQUE
(
    hero_id,
    pet_id
)
    );

CREATE TABLE IF NOT EXISTS hero_artifacts
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    artifact_id integer NOT NULL,
    xp bigint,
    level integer,
    extra jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    UNIQUE
(
    hero_id,
    artifact_id
)
    );

CREATE TABLE IF NOT EXISTS teams
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    name text,
    banner integer,
    team_level integer,
    class text,
    override_data jsonb,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS team_troops
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    team_id uuid REFERENCES teams
(
    id
) ON DELETE CASCADE,
    position integer NOT NULL,
    troop_id integer NOT NULL
    );

CREATE INDEX IF NOT EXISTS idx_team_troops_team ON team_troops (team_id);

CREATE TABLE IF NOT EXISTS team_saves
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    name text,
    description text,
    data jsonb NOT NULL,
    is_public boolean DEFAULT false,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE INDEX IF NOT EXISTS idx_team_saves_hero ON team_saves (hero_id);

CREATE TABLE IF NOT EXISTS team_comments
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    team_save_id uuid REFERENCES team_saves
(
    id
) ON DELETE CASCADE,
    author_user_id uuid REFERENCES app_users
(
    id
),
    guild_id uuid REFERENCES guilds
(
    id
),
    comment text NOT NULL,
    created_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS hero_kingdom_progress
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    kingdom_id integer NOT NULL,
    status integer,
    income integer,
    challenge_tier integer,
    invasions integer,
    power_rank integer,
    tasks jsonb DEFAULT '[]'::jsonb,
    explore jsonb DEFAULT '{}'::jsonb,
    trials_team jsonb DEFAULT '[]'::jsonb,
    extra jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    UNIQUE
(
    hero_id,
    kingdom_id
)
    );

CREATE INDEX IF NOT EXISTS idx_hero_kingdom_progress_hero ON hero_kingdom_progress (hero_id);

CREATE TABLE IF NOT EXISTS hero_pvp_regions
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    region_id integer NOT NULL,
    team jsonb DEFAULT '{}'::jsonb,
    stats jsonb DEFAULT '{}'::jsonb,
    most_used_troop jsonb DEFAULT '{}'::jsonb,
    extras jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    UNIQUE
(
    hero_id,
    region_id
)
    );

CREATE TABLE IF NOT EXISTS hero_pvp_stats
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    invades_won integer,
    invades_lost integer,
    defends_won integer,
    defends_lost integer,
    most_invaded_kingdom jsonb,
    most_used_troop jsonb,
    raw jsonb,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    UNIQUE
(
    hero_id
)
    );

CREATE TABLE IF NOT EXISTS hero_progress_weapons
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    weapon_data jsonb NOT NULL,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS hero_class_data
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    class_name text NOT NULL,
    data jsonb NOT NULL,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
),
    UNIQUE
(
    hero_id,
    class_name
)
    );

CREATE TABLE IF NOT EXISTS hero_meta_json
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    hero_id uuid REFERENCES heroes
(
    id
) ON DELETE CASCADE,
    key text NOT NULL,
    value jsonb,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE INDEX IF NOT EXISTS idx_hero_meta_key ON hero_meta_json (key);

-- ------------------------
-- Google Sheets sync / job queue / caches
-- ------------------------

CREATE TABLE IF NOT EXISTS sheets_sync_logs
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    guild_id uuid REFERENCES guilds
(
    id
),
    sheet_id text,
    range text,
    rows_sent integer,
    status text,
    error jsonb,
    started_at timestamptz DEFAULT now
(
),
    finished_at timestamptz
    );

CREATE TABLE IF NOT EXISTS queue_jobs
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    type text NOT NULL,
    payload jsonb,
    priority integer DEFAULT 100,
    attempts integer DEFAULT 0,
    max_attempts integer DEFAULT 5,
    status text DEFAULT 'pending',
    run_after timestamptz DEFAULT now
(
),
    last_error text,
    created_at timestamptz DEFAULT now
(
),
    updated_at timestamptz DEFAULT now
(
)
    );

CREATE TABLE IF NOT EXISTS cache_invalidation
(
    id
    uuid
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    key text NOT NULL,
    invalidated_at timestamptz DEFAULT now
(
)
    );

-- ------------------------
-- Materialized view for quick exports (troops light)
-- ------------------------
DROP
MATERIALIZED VIEW IF EXISTS troops_master_light;
CREATE
MATERIALIZED VIEW troops_master_light AS
SELECT id,
       kid,
       name,
       kingdom_id,
       kingdom_name,
       rarity,
       rarity_id,
       max_attack,
       max_armor,
       max_life,
       max_magic,
       spell_id,
       shiny_spell_id,
       colors,
       arcanes,
       image_url,
       type,
       troop_role1,
       description
FROM troops;

-- To refresh the materialized view later: REFRESH MATERIALIZED VIEW troops_master_light;

-- ------------------------
-- Triggers: add updated_at triggers in an idempotent way
-- (check pg_trigger table before creating a trigger)
-- ------------------------

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'app_users_updated_at_tr') THEN
CREATE TRIGGER app_users_updated_at_tr
    BEFORE UPDATE
    ON app_users
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'roles_updated_at_tr') THEN
CREATE TRIGGER roles_updated_at_tr
    BEFORE UPDATE
    ON roles
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'permissions_updated_at_tr') THEN
CREATE TRIGGER permissions_updated_at_tr
    BEFORE UPDATE
    ON permissions
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'role_permissions_updated_at_tr') THEN
CREATE TRIGGER role_permissions_updated_at_tr
    BEFORE UPDATE
    ON role_permissions
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'guilds_updated_at_tr') THEN
CREATE TRIGGER guilds_updated_at_tr
    BEFORE UPDATE
    ON guilds
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'guild_members_updated_at_tr') THEN
CREATE TRIGGER guild_members_updated_at_tr
    BEFORE UPDATE
    ON guild_members
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'guild_roles_updated_at_tr') THEN
CREATE TRIGGER guild_roles_updated_at_tr
    BEFORE UPDATE
    ON guild_roles
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'guild_member_roles_updated_at_tr') THEN
CREATE TRIGGER guild_member_roles_updated_at_tr
    BEFORE UPDATE
    ON guild_member_roles
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'audit_logs_updated_at_tr') THEN
CREATE TRIGGER audit_logs_updated_at_tr
    BEFORE UPDATE
    ON audit_logs
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'feature_flags_updated_at_tr') THEN
CREATE TRIGGER feature_flags_updated_at_tr
    BEFORE UPDATE
    ON feature_flags
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'guild_feature_flags_updated_at_tr') THEN
CREATE TRIGGER guild_feature_flags_updated_at_tr
    BEFORE UPDATE
    ON guild_feature_flags
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

-- Canonical game tables triggers
DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'troops_updated_at_tr') THEN
CREATE TRIGGER troops_updated_at_tr
    BEFORE UPDATE
    ON troops
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'kingdoms_updated_at_tr') THEN
CREATE TRIGGER kingdoms_updated_at_tr
    BEFORE UPDATE
    ON kingdoms
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'classes_updated_at_tr') THEN
CREATE TRIGGER classes_updated_at_tr
    BEFORE UPDATE
    ON classes
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'talents_updated_at_tr') THEN
CREATE TRIGGER talents_updated_at_tr
    BEFORE UPDATE
    ON talents
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'medals_updated_at_tr') THEN
CREATE TRIGGER medals_updated_at_tr
    BEFORE UPDATE
    ON medals
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'pets_updated_at_tr') THEN
CREATE TRIGGER pets_updated_at_tr
    BEFORE UPDATE
    ON pets
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'spells_updated_at_tr') THEN
CREATE TRIGGER spells_updated_at_tr
    BEFORE UPDATE
    ON spells
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'aspects_updated_at_tr') THEN
CREATE TRIGGER aspects_updated_at_tr
    BEFORE UPDATE
    ON aspects
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'traitstones_updated_at_tr') THEN
CREATE TRIGGER traitstones_updated_at_tr
    BEFORE UPDATE
    ON traitstones
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'weapons_updated_at_tr') THEN
CREATE TRIGGER weapons_updated_at_tr
    BEFORE UPDATE
    ON weapons
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'game_events_updated_at_tr') THEN
CREATE TRIGGER game_events_updated_at_tr
    BEFORE UPDATE
    ON game_events
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

-- Player / hero triggers
DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'raw_profiles_updated_at_tr') THEN
CREATE TRIGGER raw_profiles_updated_at_tr
    BEFORE UPDATE
    ON raw_profiles
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'heroes_updated_at_tr') THEN
CREATE TRIGGER heroes_updated_at_tr
    BEFORE UPDATE
    ON heroes
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_runes_updated_at_tr') THEN
CREATE TRIGGER hero_runes_updated_at_tr
    BEFORE UPDATE
    ON hero_runes
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_troops_updated_at_tr') THEN
CREATE TRIGGER hero_troops_updated_at_tr
    BEFORE UPDATE
    ON hero_troops
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_pets_updated_at_tr') THEN
CREATE TRIGGER hero_pets_updated_at_tr
    BEFORE UPDATE
    ON hero_pets
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_artifacts_updated_at_tr') THEN
CREATE TRIGGER hero_artifacts_updated_at_tr
    BEFORE UPDATE
    ON hero_artifacts
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'teams_updated_at_tr') THEN
CREATE TRIGGER teams_updated_at_tr
    BEFORE UPDATE
    ON teams
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'team_troops_updated_at_tr') THEN
CREATE TRIGGER team_troops_updated_at_tr
    BEFORE UPDATE
    ON team_troops
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'team_saves_updated_at_tr') THEN
CREATE TRIGGER team_saves_updated_at_tr
    BEFORE UPDATE
    ON team_saves
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'team_comments_updated_at_tr') THEN
CREATE TRIGGER team_comments_updated_at_tr
    BEFORE UPDATE
    ON team_comments
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_kingdom_progress_updated_at_tr') THEN
CREATE TRIGGER hero_kingdom_progress_updated_at_tr
    BEFORE UPDATE
    ON hero_kingdom_progress
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_pvp_regions_updated_at_tr') THEN
CREATE TRIGGER hero_pvp_regions_updated_at_tr
    BEFORE UPDATE
    ON hero_pvp_regions
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_pvp_stats_updated_at_tr') THEN
CREATE TRIGGER hero_pvp_stats_updated_at_tr
    BEFORE UPDATE
    ON hero_pvp_stats
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_progress_weapons_updated_at_tr') THEN
CREATE TRIGGER hero_progress_weapons_updated_at_tr
    BEFORE UPDATE
    ON hero_progress_weapons
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_class_data_updated_at_tr') THEN
CREATE TRIGGER hero_class_data_updated_at_tr
    BEFORE UPDATE
    ON hero_class_data
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'hero_meta_json_updated_at_tr') THEN
CREATE TRIGGER hero_meta_json_updated_at_tr
    BEFORE UPDATE
    ON hero_meta_json
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

-- Jobs / sheets / cache triggers
DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'sheets_sync_logs_updated_at_tr') THEN
CREATE TRIGGER sheets_sync_logs_updated_at_tr
    BEFORE UPDATE
    ON sheets_sync_logs
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'queue_jobs_updated_at_tr') THEN
CREATE TRIGGER queue_jobs_updated_at_tr
    BEFORE UPDATE
    ON queue_jobs
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

DO
$$
BEGIN
  IF
NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'cache_invalidation_updated_at_tr') THEN
CREATE TRIGGER cache_invalidation_updated_at_tr
    BEFORE UPDATE
    ON cache_invalidation
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();
END IF;
END;
$$;

-- ------------------------
-- Helpful indexes for common queries
-- ------------------------

CREATE INDEX IF NOT EXISTS idx_troops_colors ON troops (colors);
CREATE INDEX IF NOT EXISTS idx_troops_spell_id ON troops (spell_id);
CREATE INDEX IF NOT EXISTS idx_heroes_guild ON heroes (guild_external_id);
CREATE INDEX IF NOT EXISTS idx_game_events_troop ON game_events (troop_id);
CREATE INDEX IF NOT EXISTS idx_game_events_dates ON game_events (start_date, end_date);

-- ------------------------
-- Final notes
-- ------------------------
-- - If you manage RLS (Row Level Security) in Supabase, add policies after this script as required.
-- - To populate canonical tables (troops, kingdoms, classes, spells, pets, weapons, medals, aspects, traitstones, events)
--   import your master JSON/CSV data into these tables (bulk COPY or use Supabase import tools / scripts).
-- - To ingest player profiles: store the full JSON into raw_profiles, then run ingestion/upsert job that populates heroes, hero_troops, etc.
-- - To refresh the lightweight troops view used for fast Google Sheets exports:
--     REFRESH MATERIALIZED VIEW troops_master_light;
-- - For any errors while running: check the exact line reported by Supabase and run that small portion first; the SQL editor sometimes truncates big scripts.
