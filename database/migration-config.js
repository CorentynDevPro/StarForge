/**
 * node-pg-migrate configuration
 * Reads DATABASE_URL and PGSSLMODE from environment variables
 */

const databaseUrl = process.env.DATABASE_URL;
const pgsslmode = process.env.PGSSLMODE || 'require';

if (!databaseUrl) {
  throw new Error('DATABASE_URL environment variable is required');
}

module.exports = {
  databaseUrl,
  dir: 'database/migrations',
  migrationsTable: 'pgmigrations',
  direction: 'up',
  ssl: pgsslmode === 'require' || pgsslmode === 'verify-full',
  decamelize: true,
  createSchema: true,
  createMigrationsSchema: false,
  verbose: true,
};
