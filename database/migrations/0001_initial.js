/**
 * Initial database schema migration
 * Creates all tables, indexes, triggers, and inserts default roles
 * Uses pgcrypto extension for UUID generation (gen_random_uuid)
 * Compatible with managed PostgreSQL providers like Supabase
 */

exports.up = (pgm) => {
  // Enable pgcrypto extension (instead of uuid-ossp for better compatibility)
  pgm.createExtension('pgcrypto', {
    ifNotExists: true,
  });

  // Users table
  pgm.createTable(
    'users',
    {
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
    },
    {
      ifNotExists: true,
    },
  );

  // Roles table
  pgm.createTable(
    'roles',
    {
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
    },
    {
      ifNotExists: true,
    },
  );

  // User roles junction table
  pgm.createTable(
    'user_roles',
    {
      user_id: {
        type: 'uuid',
        notNull: true,
        references: 'users(id)',
        onDelete: 'CASCADE',
      },
      role_id: {
        type: 'uuid',
        notNull: true,
        references: 'roles(id)',
        onDelete: 'CASCADE',
      },
      guild_id: {
        type: 'uuid',
      },
    },
    {
      ifNotExists: true,
    },
  );

  // Add composite primary key for user_roles
  pgm.addConstraint(
    'user_roles',
    'user_roles_pkey',
    {
      primaryKey: [
        'user_id',
        'role_id',
        { expression: "COALESCE(guild_id, '00000000-0000-0000-0000-000000000000'::UUID)" },
      ],
    },
    {
      ifNotExists: true,
    },
  );

  // Guilds table (multi-tenant)
  pgm.createTable(
    'guilds',
    {
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
    },
    {
      ifNotExists: true,
    },
  );

  // Guild members table
  pgm.createTable(
    'guild_members',
    {
      guild_id: {
        type: 'uuid',
        notNull: true,
        references: 'guilds(id)',
        onDelete: 'CASCADE',
      },
      user_id: {
        type: 'uuid',
        notNull: true,
        references: 'users(id)',
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
    },
    {
      ifNotExists: true,
    },
  );

  pgm.addConstraint(
    'guild_members',
    'guild_members_pkey',
    {
      primaryKey: ['guild_id', 'user_id'],
    },
    {
      ifNotExists: true,
    },
  );

  // Feature flags table
  pgm.createTable(
    'feature_flags',
    {
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
    },
    {
      ifNotExists: true,
    },
  );

  // Add check constraint for rollout_percentage
  pgm.addConstraint(
    'feature_flags',
    'feature_flags_rollout_percentage_check',
    {
      check: 'rollout_percentage >= 0 AND rollout_percentage <= 100',
    },
    {
      ifNotExists: true,
    },
  );

  // Audit logs table
  pgm.createTable(
    'audit_logs',
    {
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
        references: 'users(id)',
        onDelete: 'SET NULL',
      },
      guild_id: {
        type: 'uuid',
        references: 'guilds(id)',
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
    },
    {
      ifNotExists: true,
    },
  );

  // Analytics events table
  pgm.createTable(
    'analytics_events',
    {
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
        references: 'users(id)',
        onDelete: 'SET NULL',
      },
      guild_id: {
        type: 'uuid',
        references: 'guilds(id)',
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
    },
    {
      ifNotExists: true,
    },
  );

  // Scheduled jobs table
  pgm.createTable(
    'scheduled_jobs',
    {
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
    },
    {
      ifNotExists: true,
    },
  );

  // Queue jobs table
  pgm.createTable(
    'queue_jobs',
    {
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
      },
      created_at: {
        type: 'timestamp with time zone',
        notNull: true,
        default: pgm.func('NOW()'),
      },
      processed_at: {
        type: 'timestamp with time zone',
      },
    },
    {
      ifNotExists: true,
    },
  );

  // Add check constraint for queue_jobs status
  pgm.addConstraint(
    'queue_jobs',
    'queue_jobs_status_check',
    {
      check: "status IN ('pending', 'processing', 'completed', 'failed')",
    },
    {
      ifNotExists: true,
    },
  );

  // Troops table (Gems of War data)
  pgm.createTable(
    'troops',
    {
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
    },
    {
      ifNotExists: true,
    },
  );

  // Battle simulations table
  pgm.createTable(
    'battle_simulations',
    {
      id: {
        type: 'uuid',
        primaryKey: true,
        default: pgm.func('gen_random_uuid()'),
      },
      user_id: {
        type: 'uuid',
        references: 'users(id)',
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
    },
    {
      ifNotExists: true,
    },
  );

  // Create indexes
  pgm.createIndex('users', 'email', { ifNotExists: true });
  pgm.createIndex('guilds', 'discord_guild_id', { ifNotExists: true });
  pgm.createIndex('audit_logs', 'user_id', { ifNotExists: true });
  pgm.createIndex('audit_logs', 'guild_id', { ifNotExists: true });
  pgm.createIndex('audit_logs', 'created_at', { ifNotExists: true });
  pgm.createIndex('analytics_events', 'guild_id', { ifNotExists: true });
  pgm.createIndex('analytics_events', 'created_at', { ifNotExists: true });
  pgm.createIndex('queue_jobs', 'status', { ifNotExists: true });
  pgm.createIndex('scheduled_jobs', 'next_run', {
    ifNotExists: true,
    where: 'enabled = true',
  });

  // Function to update updated_at timestamp
  pgm.createFunction(
    'update_updated_at_column',
    [],
    {
      returns: 'trigger',
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

  // Triggers for updated_at
  pgm.createTrigger(
    'users',
    'update_users_updated_at',
    {
      when: 'BEFORE',
      operation: 'UPDATE',
      function: 'update_updated_at_column',
      level: 'ROW',
    },
    {
      ifNotExists: true,
    },
  );

  pgm.createTrigger(
    'guilds',
    'update_guilds_updated_at',
    {
      when: 'BEFORE',
      operation: 'UPDATE',
      function: 'update_updated_at_column',
      level: 'ROW',
    },
    {
      ifNotExists: true,
    },
  );

  pgm.createTrigger(
    'feature_flags',
    'update_feature_flags_updated_at',
    {
      when: 'BEFORE',
      operation: 'UPDATE',
      function: 'update_updated_at_column',
      level: 'ROW',
    },
    {
      ifNotExists: true,
    },
  );

  pgm.createTrigger(
    'scheduled_jobs',
    'update_scheduled_jobs_updated_at',
    {
      when: 'BEFORE',
      operation: 'UPDATE',
      function: 'update_updated_at_column',
      level: 'ROW',
    },
    {
      ifNotExists: true,
    },
  );

  // Insert default roles (idempotent - will be handled by ON CONFLICT in seeds)
  pgm.sql(`
    INSERT INTO roles (name, description) VALUES
      ('admin', 'Full system access'),
      ('guild_master', 'Guild management access'),
      ('moderator', 'Moderation tools access'),
      ('member', 'Basic member access')
    ON CONFLICT (name) DO NOTHING;
  `);
};

exports.down = (pgm) => {
  // Drop triggers
  pgm.dropTrigger('scheduled_jobs', 'update_scheduled_jobs_updated_at', { ifExists: true });
  pgm.dropTrigger('feature_flags', 'update_feature_flags_updated_at', { ifExists: true });
  pgm.dropTrigger('guilds', 'update_guilds_updated_at', { ifExists: true });
  pgm.dropTrigger('users', 'update_users_updated_at', { ifExists: true });

  // Drop function
  pgm.dropFunction('update_updated_at_column', [], { ifExists: true });

  // Drop tables (in reverse order of creation to handle dependencies)
  pgm.dropTable('battle_simulations', { ifExists: true });
  pgm.dropTable('troops', { ifExists: true });
  pgm.dropTable('queue_jobs', { ifExists: true });
  pgm.dropTable('scheduled_jobs', { ifExists: true });
  pgm.dropTable('analytics_events', { ifExists: true });
  pgm.dropTable('audit_logs', { ifExists: true });
  pgm.dropTable('feature_flags', { ifExists: true });
  pgm.dropTable('guild_members', { ifExists: true });
  pgm.dropTable('guilds', { ifExists: true });
  pgm.dropTable('user_roles', { ifExists: true });
  pgm.dropTable('roles', { ifExists: true });
  pgm.dropTable('users', { ifExists: true });

  // Drop extension
  pgm.dropExtension('pgcrypto', { ifExists: true });
};
