# Database Migrations

This document describes how to manage database migrations for StarForge using `node-pg-migrate`.

## Overview

StarForge uses [node-pg-migrate](https://salsita.github.io/node-pg-migrate/) for database schema management. The migration system:

- Uses **pgcrypto** extension for UUID generation (`gen_random_uuid()`) for better compatibility with Supabase cloud and managed databases
- Provides **up/down migrations** for safe schema changes
- Supports **transactions** to ensure atomic migrations
- Maintains **migration history** in the `pgmigrations` table
- Ensures **idempotence** - migrations can be safely re-run

## Prerequisites

- Node.js 18+
- pnpm 8+
- PostgreSQL client tools (psql)
- Database connection with appropriate permissions

## Environment Variables

Set these environment variables before running migrations:

```bash
export DATABASE_URL="postgresql://user:password@host:port/database"
export PGSSLMODE=require  # For cloud databases (Supabase, AWS RDS, etc.)
```

For local development, copy `.env.example` to `.env` and update the values.

## Local Development

### Initial Setup

1. **Install dependencies:**

   ```bash
   pnpm install --frozen-lockfile
   ```

2. **Run bootstrap script:**

   ```bash
   ./scripts/bootstrap-db.sh
   ```

   This script will:
   - Install dependencies
   - Run all pending migrations
   - Apply seed data
   - Verify the database setup

### Manual Migration Commands

Run migrations manually when needed:

```bash
# Apply all pending migrations
pnpm run migrate:up

# Rollback the last migration
pnpm run migrate:down

# Rollback multiple migrations
pnpm run migrate:down -- --count 2

# Create a new migration
pnpm run migrate create add_new_table

# Check migration status
pnpm run migrate -- list
```

### Creating New Migrations

1. **Generate migration file:**

   ```bash
   pnpm run migrate create my_migration_name
   ```

2. **Edit the migration file** in `database/migrations/`:

   ```javascript
   exports.up = async (pgm) => {
     // Add schema changes here
     pgm.createTable('my_table', {
       id: { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') },
       name: { type: 'varchar(255)', notNull: true },
     });
   };

   exports.down = async (pgm) => {
     // Add rollback logic here
     pgm.dropTable('my_table');
   };
   ```

3. **Test the migration:**

   ```bash
   # Apply
   pnpm run migrate:up

   # Rollback (test down migration)
   pnpm run migrate:down

   # Re-apply
   pnpm run migrate:up
   ```

## CI/CD Deployment

### GitHub Actions Workflow

Migrations can be applied via GitHub Actions using the manual workflow.

1. **Navigate to GitHub Actions:**
   - Go to your repository on GitHub
   - Click on "Actions" tab
   - Select "Database Bootstrap" workflow

2. **Run the workflow:**
   - Click "Run workflow"
   - Select the target branch
   - Choose the environment (production/staging/development)
   - Click "Run workflow"

3. **Approval (for production):**
   - If the workflow is configured with environment protection, an approval may be required
   - Designated approvers will receive a notification
   - Review the changes and approve/reject

### Workflow Configuration

The workflow is located at `.github/workflows/db-bootstrap.yml` and:

- Runs on manual trigger only (`workflow_dispatch`)
- Supports environment selection
- Requires `DATABASE_URL` secret to be configured
- Automatically sets `PGSSLMODE=require`
- Installs dependencies and runs migrations
- Applies seed data
- Verifies database setup

### Setting Up Secrets

Configure the following secrets in GitHub:

1. **Repository Settings → Secrets and variables → Actions**
2. **Add secret:**
   - Name: `DATABASE_URL`
   - Value: `postgresql://user:password@host:port/database`

For environment-specific secrets:

1. **Repository Settings → Environments**
2. **Create environment** (e.g., "production")
3. **Add environment secret:** `DATABASE_URL`
4. **(Optional) Add protection rules** for manual approval

## Migration Best Practices

### Writing Migrations

1. **Always provide down migrations** for rollback capability
2. **Use transactions** (enabled by default in config)
3. **Make migrations idempotent** when possible using:
   - `IF NOT EXISTS` clauses
   - `ON CONFLICT DO NOTHING` for inserts
4. **Test migrations locally** before deploying
5. **Keep migrations small and focused** on single changes
6. **Never modify existing migrations** that have been applied to production

### Schema Changes

1. **Adding columns:**

   ```javascript
   pgm.addColumn('users', {
     new_column: { type: 'text', notNull: false },
   });
   ```

2. **Creating indexes:**

   ```javascript
   pgm.createIndex('users', 'email', {
     name: 'idx_users_email',
     unique: true,
   });
   ```

3. **Adding foreign keys:**
   ```javascript
   pgm.addConstraint('posts', 'fk_posts_user_id', {
     foreignKeys: {
       columns: 'user_id',
       references: 'users(id)',
       onDelete: 'CASCADE',
     },
   });
   ```

## Troubleshooting

### Extension Permission Errors

If you get errors about `CREATE EXTENSION`:

```
ERROR: permission denied to create extension "pgcrypto"
```

**Solution:** Ask your database administrator to run:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

Alternatively, if you have superuser access:

```bash
psql "$DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
```

### Migration Already Applied

If migrations fail because they're already applied:

```bash
# Check migration status
pnpm run migrate -- list

# Mark specific migration as run without executing
pnpm run migrate -- mark-migration-as-run <migration-name>
```

### SSL Connection Issues

For cloud databases, ensure SSL is enabled:

```bash
export PGSSLMODE=require
```

Or add `?sslmode=require` to your `DATABASE_URL`:

```
postgresql://user:pass@host:5432/db?sslmode=require
```

### Connection Timeouts

For slow networks or large migrations:

1. Increase timeout in `migration-config.js`
2. Run migrations from a location closer to the database
3. Break large migrations into smaller ones

## Rollback Strategy

### Rolling Back

```bash
# Rollback last migration
pnpm run migrate:down

# Rollback multiple migrations
pnpm run migrate:down -- --count 3

# Rollback to specific migration
pnpm run migrate:down -- --to <migration-timestamp>
```

### Recovery from Failed Migrations

1. **Check migration status:**

   ```bash
   pnpm run migrate -- list
   ```

2. **If migration partially applied:**
   - Manually fix the database state
   - Mark migration as complete: `pnpm run migrate -- mark-migration-as-run`
   - Or rollback and retry: `pnpm run migrate:down && pnpm run migrate:up`

3. **If database is in bad state:**
   - Restore from backup
   - Re-apply migrations from known good state

## Security Considerations

1. **Never commit DATABASE_URL** or credentials to the repository
2. **Use GitHub Secrets** for CI/CD workflows
3. **Require manual approval** for production migrations
4. **Use SSL connections** (`PGSSLMODE=require`) for cloud databases
5. **Review migrations** before applying to production
6. **Test rollback procedures** before deploying
7. **Maintain database backups** before major migrations

## Additional Resources

- [node-pg-migrate Documentation](https://salsita.github.io/node-pg-migrate/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Supabase Database Guide](https://supabase.com/docs/guides/database)

## Support

For questions or issues with migrations:

1. Check this documentation
2. Review migration logs in GitHub Actions
3. Check database logs for errors
4. Contact the development team
