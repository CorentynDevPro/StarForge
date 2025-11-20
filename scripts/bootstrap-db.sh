#!/bin/bash
set -e

echo "===================================="
echo "StarForge Database Bootstrap Script"
echo "===================================="
echo ""

# Check for required tools
if ! command -v psql &> /dev/null; then
    echo "ERROR: psql is not installed. Please install PostgreSQL client tools."
    exit 1
fi

if ! command -v pnpm &> /dev/null; then
    echo "ERROR: pnpm is not installed. Please install pnpm first."
    exit 1
fi

# Check for DATABASE_URL
if [ -z "$DATABASE_URL" ]; then
    echo "ERROR: DATABASE_URL environment variable is not set."
    echo "Example: export DATABASE_URL='postgresql://user:password@host:port/database'"
    exit 1
fi

# Set PGSSLMODE to require if not already set
if [ -z "$PGSSLMODE" ]; then
    echo "Setting PGSSLMODE=require (default for cloud databases)"
    export PGSSLMODE=require
else
    echo "Using PGSSLMODE=$PGSSLMODE"
fi

echo ""
echo "Step 1: Installing dependencies..."
pnpm install --frozen-lockfile || {
    echo "WARNING: Could not install with frozen lockfile, trying without..."
    pnpm install
}

echo ""
echo "Step 2: Running database migrations..."
pnpm run migrate:up || {
    echo ""
    echo "ERROR: Migration failed."
    echo ""
    echo "Common issues:"
    echo "  - Database connection failed (check DATABASE_URL)"
    echo "  - Extension permission issues (uuid-ossp or pgcrypto)"
    echo "  - Schema already exists (migrations already applied)"
    echo ""
    echo "If the error is about CREATE EXTENSION, your database user may not have"
    echo "permission to create extensions. Please ask your database administrator to:"
    echo "  1. CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    echo "Then re-run this script."
    echo ""
    exit 1
}

echo ""
echo "Step 3: Applying seed data..."
psql "$DATABASE_URL" -f database/seeds/0001_seeds.sql || {
    echo ""
    echo "WARNING: Seed data application failed or partially applied."
    echo "This might be okay if seeds were already applied."
    echo "Continuing..."
}

echo ""
echo "Step 4: Verifying database setup..."
psql "$DATABASE_URL" -c "\dt" || {
    echo "WARNING: Could not list tables. Database might still be valid."
}

echo ""
echo "===================================="
echo "✓ Database bootstrap completed!"
echo "===================================="
echo ""
echo "You can now:"
echo "  - Run migrations manually: pnpm run migrate:up"
echo "  - Rollback migrations: pnpm run migrate:down"
echo "  - Create new migration: pnpm run migrate create <name>"
echo ""
