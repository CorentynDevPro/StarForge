/**
 * Initial Database Schema Migration
 *
 * Creates all base tables, indexes, triggers, and functions for StarForge.
 * Uses pgcrypto extension for UUID generation (gen_random_uuid()) for better
 * compatibility with Supabase cloud and managed databases.
 *
 * This migration is idempotent - it can be run multiple times safely.
 */

/**
 * Apply migration - create schema
 * @param {import('node-pg-migrate').MigrationBuilder} pgm
 */
exports.up = async (pgm) => {
  // Enable pgcrypto extension for UUID generation
  pgm.sql('CREATE EXTENSION IF NOT EXISTS pgcrypto;');

  // Create users table
  pgm.createTable('users', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    email: {
      type: 'varchar(255)',
      notNull: true,
      unique: true,
    },
    username: {
      type: 'varchar(100)',
      notNull: true,
      unique: true,
    },
    created_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
    updated_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
  });

  // Create roles table
  pgm.createTable('roles', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    name: {
      type: 'varchar(50)',
      notNull: true,
      unique: true,
    },
    description: {
      type: 'text',
    },
  });

  // Create guilds table (multi-tenant)
  pgm.createTable('guilds', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    discord_guild_id: {
      type: 'varchar(100)',
      notNull: true,
      unique: true,
    },
    name: {
      type: 'varchar(255)',
      notNull: true,
    },
    settings: {
      type: 'jsonb',
      default: "'{}'",
    },
    feature_flags: {
      type: 'jsonb',
      default: "'{}'",
    },
    created_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
    updated_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
  });

  // Create user_roles junction table
  pgm.createTable('user_roles', {
    user_id: {
      type: 'uuid',
      notNull: true,
      references: 'users',
      onDelete: 'CASCADE',
    },
    role_id: {
      type: 'uuid',
      notNull: true,
      references: 'roles',
      onDelete: 'CASCADE',
    },
    guild_id: {
      type: 'uuid',
    },
  });

  // Add composite primary key to user_roles
  pgm.addConstraint('user_roles', 'user_roles_pkey', {
    primaryKey: [
      'user_id',
      'role_id',
      pgm.func("COALESCE(guild_id, '00000000-0000-0000-0000-000000000000'::UUID)"),
    ],
  });

  // Create guild_members table
  pgm.createTable('guild_members', {
    guild_id: {
      type: 'uuid',
      notNull: true,
      references: 'guilds',
      onDelete: 'CASCADE',
    },
    user_id: {
      type: 'uuid',
      notNull: true,
      references: 'users',
      onDelete: 'CASCADE',
    },
    discord_user_id: {
      type: 'varchar(100)',
      notNull: true,
    },
    joined_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
  });

  pgm.addConstraint('guild_members', 'guild_members_pkey', {
    primaryKey: ['guild_id', 'user_id'],
  });

  // Create feature_flags table
  pgm.createTable('feature_flags', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    name: {
      type: 'varchar(100)',
      notNull: true,
      unique: true,
    },
    enabled: {
      type: 'boolean',
      default: false,
    },
    rollout_percentage: {
      type: 'integer',
      default: 0,
      check: 'rollout_percentage >= 0 AND rollout_percentage <= 100',
    },
    guild_ids: {
      type: 'jsonb',
      default: "'[]'",
    },
    created_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
    updated_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
  });

  // Create audit_logs table
  pgm.createTable('audit_logs', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    action: {
      type: 'varchar(255)',
      notNull: true,
    },
    user_id: {
      type: 'uuid',
      references: 'users',
      onDelete: 'SET NULL',
    },
    guild_id: {
      type: 'uuid',
      references: 'guilds',
      onDelete: 'SET NULL',
    },
    metadata: {
      type: 'jsonb',
      default: "'{}'",
    },
    ip_address: {
      type: 'inet',
    },
    user_agent: {
      type: 'text',
    },
    created_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
  });

  // Create analytics_events table
  pgm.createTable('analytics_events', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    event_type: {
      type: 'varchar(100)',
      notNull: true,
    },
    user_id: {
      type: 'uuid',
      references: 'users',
      onDelete: 'SET NULL',
    },
    guild_id: {
      type: 'uuid',
      references: 'guilds',
      onDelete: 'SET NULL',
    },
    metadata: {
      type: 'jsonb',
      default: "'{}'",
    },
    created_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
  });

  // Create scheduled_jobs table
  pgm.createTable('scheduled_jobs', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    name: {
      type: 'varchar(255)',
      notNull: true,
    },
    schedule: {
      type: 'varchar(100)',
      notNull: true,
    },
    payload: {
      type: 'jsonb',
      default: "'{}'",
    },
    last_run: {
      type: 'timestamp with time zone',
    },
    next_run: {
      type: 'timestamp with time zone',
      notNull: true,
    },
    enabled: {
      type: 'boolean',
      default: true,
    },
    created_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
    updated_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
  });

  // Create queue_jobs table
  pgm.createTable('queue_jobs', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    type: {
      type: 'varchar(100)',
      notNull: true,
    },
    payload: {
      type: 'jsonb',
      default: "'{}'",
    },
    priority: {
      type: 'integer',
      default: 0,
    },
    attempts: {
      type: 'integer',
      default: 0,
    },
    max_attempts: {
      type: 'integer',
      default: 3,
    },
    status: {
      type: 'varchar(20)',
      default: "'pending'",
      check: "status IN ('pending', 'processing', 'completed', 'failed')",
    },
    created_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
    processed_at: {
      type: 'timestamp with time zone',
    },
  });

  // Create troops table (Gems of War data)
  pgm.createTable('troops', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    name: {
      type: 'varchar(255)',
      notNull: true,
    },
    rarity: {
      type: 'varchar(50)',
      notNull: true,
    },
    mana_colors: {
      type: 'jsonb',
      default: "'[]'",
    },
    attack: {
      type: 'integer',
      default: 0,
    },
    armor: {
      type: 'integer',
      default: 0,
    },
    life: {
      type: 'integer',
      default: 0,
    },
    magic: {
      type: 'integer',
      default: 0,
    },
    traits: {
      type: 'jsonb',
      default: "'[]'",
    },
    spell_description: {
      type: 'text',
    },
  });

  // Create battle_simulations table
  pgm.createTable('battle_simulations', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    user_id: {
      type: 'uuid',
      references: 'users',
      onDelete: 'SET NULL',
    },
    team1: {
      type: 'jsonb',
      notNull: true,
    },
    team2: {
      type: 'jsonb',
      notNull: true,
    },
    result: {
      type: 'jsonb',
      notNull: true,
    },
    created_at: {
      type: 'timestamp with time zone',
      notNull: true,
      default: pgm.func('NOW()'),
    },
  });

  // Create indexes
  pgm.createIndex('users', 'email', { name: 'idx_users_email' });
  pgm.createIndex('guilds', 'discord_guild_id', { name: 'idx_guilds_discord_id' });
  pgm.createIndex('audit_logs', 'user_id', { name: 'idx_audit_logs_user_id' });
  pgm.createIndex('audit_logs', 'guild_id', { name: 'idx_audit_logs_guild_id' });
  pgm.createIndex('audit_logs', 'created_at', { name: 'idx_audit_logs_created_at' });
  pgm.createIndex('analytics_events', 'guild_id', { name: 'idx_analytics_events_guild_id' });
  pgm.createIndex('analytics_events', 'created_at', { name: 'idx_analytics_events_created_at' });
  pgm.createIndex('queue_jobs', 'status', { name: 'idx_queue_jobs_status' });
  pgm.createIndex('scheduled_jobs', 'next_run', {
    name: 'idx_scheduled_jobs_next_run',
    where: 'enabled = true',
  });

  // Create function to update updated_at timestamp
  pgm.createFunction(
    'update_updated_at_column',
    [],
    {
      returns: 'TRIGGER',
      language: 'plpgsql',
      replace: true,
    },
    `
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
    `,
  );

  // Create triggers for updated_at
  pgm.createTrigger('users', 'update_users_updated_at', {
    when: 'BEFORE',
    operation: 'UPDATE',
    function: 'update_updated_at_column',
    level: 'ROW',
  });

  pgm.createTrigger('guilds', 'update_guilds_updated_at', {
    when: 'BEFORE',
    operation: 'UPDATE',
    function: 'update_updated_at_column',
    level: 'ROW',
  });

  pgm.createTrigger('feature_flags', 'update_feature_flags_updated_at', {
    when: 'BEFORE',
    operation: 'UPDATE',
    function: 'update_updated_at_column',
    level: 'ROW',
  });

  pgm.createTrigger('scheduled_jobs', 'update_scheduled_jobs_updated_at', {
    when: 'BEFORE',
    operation: 'UPDATE',
    function: 'update_updated_at_column',
    level: 'ROW',
  });

  // Insert default roles (idempotent - will be skipped if already exist)
  pgm.sql(`
    INSERT INTO roles (name, description) VALUES
      ('admin', 'Full system access'),
      ('guild_master', 'Guild management access'),
      ('moderator', 'Moderation tools access'),
      ('member', 'Basic member access')
    ON CONFLICT (name) DO NOTHING;
  `);
};

/**
 * Rollback migration - drop schema
 * @param {import('node-pg-migrate').MigrationBuilder} pgm
 */
exports.down = async (pgm) => {
  // Drop triggers
  pgm.dropTrigger('scheduled_jobs', 'update_scheduled_jobs_updated_at', { ifExists: true });
  pgm.dropTrigger('feature_flags', 'update_feature_flags_updated_at', { ifExists: true });
  pgm.dropTrigger('guilds', 'update_guilds_updated_at', { ifExists: true });
  pgm.dropTrigger('users', 'update_users_updated_at', { ifExists: true });

  // Drop function
  pgm.dropFunction('update_updated_at_column', [], { ifExists: true });

  // Drop indexes (automatically dropped with tables, but explicit for clarity)
  pgm.dropIndex('scheduled_jobs', 'next_run', {
    name: 'idx_scheduled_jobs_next_run',
    ifExists: true,
  });
  pgm.dropIndex('queue_jobs', 'status', { name: 'idx_queue_jobs_status', ifExists: true });
  pgm.dropIndex('analytics_events', 'created_at', {
    name: 'idx_analytics_events_created_at',
    ifExists: true,
  });
  pgm.dropIndex('analytics_events', 'guild_id', {
    name: 'idx_analytics_events_guild_id',
    ifExists: true,
  });
  pgm.dropIndex('audit_logs', 'created_at', { name: 'idx_audit_logs_created_at', ifExists: true });
  pgm.dropIndex('audit_logs', 'guild_id', { name: 'idx_audit_logs_guild_id', ifExists: true });
  pgm.dropIndex('audit_logs', 'user_id', { name: 'idx_audit_logs_user_id', ifExists: true });
  pgm.dropIndex('guilds', 'discord_guild_id', { name: 'idx_guilds_discord_id', ifExists: true });
  pgm.dropIndex('users', 'email', { name: 'idx_users_email', ifExists: true });

  // Drop tables in reverse order (respecting foreign key dependencies)
  pgm.dropTable('battle_simulations', { ifExists: true, cascade: true });
  pgm.dropTable('troops', { ifExists: true, cascade: true });
  pgm.dropTable('queue_jobs', { ifExists: true, cascade: true });
  pgm.dropTable('scheduled_jobs', { ifExists: true, cascade: true });
  pgm.dropTable('analytics_events', { ifExists: true, cascade: true });
  pgm.dropTable('audit_logs', { ifExists: true, cascade: true });
  pgm.dropTable('feature_flags', { ifExists: true, cascade: true });
  pgm.dropTable('guild_members', { ifExists: true, cascade: true });
  pgm.dropTable('user_roles', { ifExists: true, cascade: true });
  pgm.dropTable('guilds', { ifExists: true, cascade: true });
  pgm.dropTable('roles', { ifExists: true, cascade: true });
  pgm.dropTable('users', { ifExists: true, cascade: true });

  // Note: We don't drop pgcrypto extension as it may be used by other schemas
  // pgm.sql('DROP EXTENSION IF EXISTS pgcrypto;');
};
