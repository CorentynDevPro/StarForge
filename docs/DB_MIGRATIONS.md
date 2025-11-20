# Database Migrations

This document explains how to manage database migrations for the StarForge project.

## Overview

StarForge uses [node-pg-migrate](https://salsita.github.io/node-pg-migrate/) for database schema migrations. This provides:

- **Version control** for database schema changes
- **Up and down migrations** for easy rollback
- **Idempotent operations** that are safe to run multiple times
- **Transaction support** for atomic changes

## Key Design Decisions

### pgcrypto vs uuid-ossp

We use the `pgcrypto` extension with `gen_random_uuid()` instead of `uuid-ossp` with `uuid_generate_v4()`. This choice was made for better compatibility with managed PostgreSQL providers like Supabase, which may have restrictions on certain extensions.

### JavaScript Migrations

Migrations are written in JavaScript (not SQL) to take advantage of:

- Built-in up/down migration support
- Better transaction control
- Programmatic schema generation
- Type safety and validation

### Idempotent Seeds

Seed data uses `INSERT ... ON CONFLICT DO NOTHING` to ensure it can be safely run multiple times without duplicating data.

## Local Development

### Prerequisites

- PostgreSQL client tools (`psql`) installed
- Node.js and pnpm installed
- `DATABASE_URL` environment variable configured

### Setup

1. **Configure your database connection:**

```bash
export DATABASE_URL="postgresql://user:password@localhost:5432/starforge"
export PGSSLMODE=require  # Optional, defaults to 'require'
```

2. **Run the bootstrap script:**

```bash
./scripts/bootstrap-db.sh
```

This will:

- Install dependencies
- Run all pending migrations
- Apply seed data
- Verify the setup

### Manual Migration Commands

**Run all pending migrations:**

```bash
pnpm run migrate:up
```

**Rollback the last migration:**

```bash
pnpm run migrate:down
```

**Create a new migration:**

```bash
pnpm run migrate create my-migration-name
```

**Check migration status:**

```bash
pnpm run migrate status --config database/migration-config.js
```

## CI/CD and Production

### GitHub Actions Workflow

We have a manual workflow (`db-bootstrap.yml`) for running migrations in production:

1. Go to **Actions** → **Database Bootstrap** in GitHub
2. Click **Run workflow**
3. Select the target environment (production/staging)
4. Click **Run workflow** button
5. **Approve the deployment** if using the production environment

### Environment Protection

The workflow requires manual approval for production deployments through GitHub Environments. This prevents accidental schema changes.

### Setting Up Environments

1. In your GitHub repository, go to **Settings** → **Environments**
2. Create a `production` environment
3. Enable **Required reviewers**
4. Add team members who should approve production migrations

### Required Secrets

Add these secrets in GitHub repository settings:

- `DATABASE_URL`: PostgreSQL connection string for your database

Example:

```
postgresql://username:password@host.supabase.co:5432/postgres
```

## Creating New Migrations

### Best Practices

1. **Keep migrations small and focused** - One logical change per migration
2. **Always include down migrations** - For easy rollback if needed
3. **Use transactions** - node-pg-migrate wraps migrations in transactions by default
4. **Test locally first** - Always test migrations on a local database before production
5. **Make migrations idempotent** - Use `IF NOT EXISTS` and similar clauses

### Example Migration

```javascript
// database/migrations/1234567890_add_user_preferences.js

exports.up = (pgm) => {
  pgm.createTable(
    'user_preferences',
    {
      id: {
        type: 'uuid',
        primaryKey: true,
        default: pgm.func('gen_random_uuid()'),
      },
      user_id: {
        type: 'uuid',
        notNull: true,
        references: 'users(id)',
        onDelete: 'CASCADE',
      },
      theme: {
        type: 'varchar(50)',
        default: "'light'",
      },
      notifications_enabled: {
        type: 'boolean',
        default: true,
      },
    },
    {
      ifNotExists: true,
    },
  );

  pgm.createIndex('user_preferences', 'user_id', { ifNotExists: true });
};

exports.down = (pgm) => {
  pgm.dropTable('user_preferences', { ifExists: true });
};
```

## Troubleshooting

### Extension Permissions

If you encounter errors about creating extensions:

1. **Enable the extension manually** in your database:

   ```sql
   CREATE EXTENSION IF NOT EXISTS pgcrypto;
   ```

2. **Check extension availability:**

   ```sql
   SELECT * FROM pg_available_extensions WHERE name = 'pgcrypto';
   ```

3. **Contact your database administrator** if you don't have permissions

### Connection Issues

If migrations fail to connect:

1. Verify your `DATABASE_URL` is correct
2. Check that `PGSSLMODE` is set appropriately (`require` for most cloud providers)
3. Verify your IP is whitelisted if using managed PostgreSQL
4. Test the connection manually:
   ```bash
   psql "$DATABASE_URL" -c "SELECT 1"
   ```

### Migration Conflicts

If migrations get out of sync:

1. **Check current migration status:**

   ```bash
   pnpm run migrate status --config database/migration-config.js
   ```

2. **Inspect the pgmigrations table:**

   ```sql
   SELECT * FROM pgmigrations ORDER BY run_on DESC;
   ```

3. **Never modify completed migrations** - Create a new migration to fix issues

## Security Best Practices

### Secrets Management

- **Never commit secrets** to version control
- Use GitHub Secrets for CI/CD
- Rotate credentials regularly
- Use different credentials for each environment

### Access Control

- Limit who can run migrations in production
- Use GitHub Environment protection rules
- Enable audit logging for database changes
- Review migration PRs carefully

### Database Backups

- Always backup before running migrations in production
- Test restoration procedures regularly
- Keep backups for regulatory compliance periods
- Consider point-in-time recovery for critical databases

## Additional Resources

- [node-pg-migrate Documentation](https://salsita.github.io/node-pg-migrate/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Supabase Database Documentation](https://supabase.com/docs/guides/database)

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review recent migration files for common patterns
3. Consult the team's database administrator
4. Open an issue in the repository with detailed error messages
