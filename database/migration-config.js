/**
 * Node-pg-migrate Configuration
 *
 * Configuration for database migrations using node-pg-migrate.
 * Reads DATABASE_URL and PGSSLMODE from environment variables.
 *
 * @see https://salsita.github.io/node-pg-migrate/
 */

const { URL } = require('url');

// Read environment variables
const databaseUrl = process.env.DATABASE_URL;
const pgsslmode = process.env.PGSSLMODE || 'require';

if (!databaseUrl) {
  throw new Error(
    'DATABASE_URL environment variable is required for migrations.\n' +
      'Example: export DATABASE_URL="postgresql://user:password@host:port/database"',
  );
}

// Parse database URL for connection config
let connectionConfig;
try {
  const url = new URL(databaseUrl);
  connectionConfig = {
    host: url.hostname,
    port: url.port || 5432,
    database: url.pathname.slice(1),
    user: url.username,
    password: url.password,
  };

  // Add SSL configuration if needed
  if (pgsslmode === 'require' || pgsslmode === 'verify-ca' || pgsslmode === 'verify-full') {
    connectionConfig.ssl = { rejectUnauthorized: false };
  }
} catch (error) {
  throw new Error(`Invalid DATABASE_URL format: ${error.message}`);
}

module.exports = {
  // Database connection config
  ...connectionConfig,

  // Migration settings
  dir: 'database/migrations',
  migrationsTable: 'pgmigrations',
  schema: 'public',
  createSchema: false,
  createMigrationsSchema: false,

  // Transaction management
  singleTransaction: true,

  // Logging
  verbose: true,
  log: console.log,

  // Migration file settings
  direction: 'up',
  count: Infinity,
  ignorePattern: '\\..*',

  // Timestamp format for new migrations
  timestamp: true,
};
