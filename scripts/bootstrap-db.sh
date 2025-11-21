#!/usr/bin/env bash

#
# StarForge Database Bootstrap Script
# 
# This script bootstraps the database with migrations and seeds.
# It is idempotent and safe to run multiple times.
#
# Requirements:
# - psql command-line tool (PostgreSQL client)
# - node and pnpm installed
# - DATABASE_URL environment variable set
#
# Usage:
#   export DATABASE_URL="postgresql://user:pass@host:port/dbname"
#   ./scripts/bootstrap-db.sh
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "StarForge Database Bootstrap"
echo "=========================================="
echo ""

# Check DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
  echo -e "${RED}ERROR: DATABASE_URL environment variable is not set${NC}"
  echo "Please set DATABASE_URL to your PostgreSQL connection string:"
  echo "  export DATABASE_URL='postgresql://user:password@host:port/database'"
  exit 1
fi

echo -e "${GREEN}✓${NC} DATABASE_URL is set"

# Set PGSSLMODE if not already set
if [ -z "$PGSSLMODE" ]; then
  export PGSSLMODE=require
  echo -e "${YELLOW}ℹ${NC} PGSSLMODE not set, defaulting to 'require'"
else
  echo -e "${GREEN}✓${NC} PGSSLMODE is set to '$PGSSLMODE'"
fi

# Check if psql is installed
if ! command -v psql &> /dev/null; then
  echo -e "${RED}ERROR: psql command not found${NC}"
  echo "Please install PostgreSQL client tools (psql)"
  exit 1
fi

echo -e "${GREEN}✓${NC} psql is installed"

# Check if node is installed
if ! command -v node &> /dev/null; then
  echo -e "${RED}ERROR: node command not found${NC}"
  echo "Please install Node.js"
  exit 1
fi

echo -e "${GREEN}✓${NC} node is installed"

# Check if pnpm is installed
if ! command -v pnpm &> /dev/null; then
  echo -e "${RED}ERROR: pnpm command not found${NC}"
  echo "Please install pnpm: npm install -g pnpm"
  exit 1
fi

echo -e "${GREEN}✓${NC} pnpm is installed"

echo ""
echo "Installing dependencies..."
pnpm install --frozen-lockfile

echo ""
echo "Running database migrations..."

# Run migrations
# Check if migration fails due to extension permission issues
if pnpm run migrate:up; then
  echo -e "${GREEN}✓${NC} Migrations completed successfully"
else
  EXIT_CODE=$?
  echo -e "${YELLOW}⚠${NC} Migration failed (exit code: $EXIT_CODE)"
  
  # Check if it's a permission error related to extensions
  echo ""
  echo -e "${YELLOW}This might be due to extension permission issues.${NC}"
  echo "Some managed PostgreSQL providers restrict extension creation."
  echo "The migration uses pgcrypto which is typically available."
  echo ""
  echo "If the error is about extensions, please:"
  echo "  1. Enable the pgcrypto extension in your database manually"
  echo "  2. Re-run this script"
  echo ""
  exit $EXIT_CODE
fi

echo ""
echo "Applying seed data..."

# Apply seeds if the file exists
SEEDS_FILE="database/seeds/0001_seeds.sql"
if [ -f "$SEEDS_FILE" ]; then
  if psql "$DATABASE_URL" < "$SEEDS_FILE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Seed data applied successfully"
  else
    echo -e "${YELLOW}⚠${NC} Seed data application had warnings (might be already present)"
  fi
else
  echo -e "${YELLOW}⚠${NC} No seed file found at $SEEDS_FILE"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Database bootstrap completed!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  - Start your application: pnpm run dev"
echo "  - Check database: psql \$DATABASE_URL"
echo ""
