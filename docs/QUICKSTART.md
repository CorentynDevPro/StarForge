# Quick Start Guide

This guide will help you get StarForge up and running quickly.

## Prerequisites

- Node.js 18+ (recommended: 20.x)
- npm 9+
- Git

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/CorentynDevPro/StarForge.git
   cd StarForge
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Set up environment variables:**
   ```bash
   cp .env.example .env
   # Edit .env with your actual values
   ```

## Building

Build all packages:
```bash
npm run build
```

This will compile TypeScript for all packages in the monorepo.

## Running Individual Services

### Backend API (Port 3000)

```bash
# Development mode with hot reload
npm run dev --workspace=@starforge/backend

# Production mode
npm run build --workspace=@starforge/backend
npm run start --workspace=@starforge/backend
```

Test the backend:
```bash
curl http://localhost:3000/api/health
```

### Discord Bot

```bash
# Make sure to set DISCORD_TOKEN in .env first
npm run dev --workspace=@starforge/bot
```

### Frontend (Port 5173)

```bash
npm run dev --workspace=@starforge/frontend
```

Open http://localhost:5173 in your browser.

### Admin UI (Port 5174)

```bash
npm run dev --workspace=@starforge/admin-ui
```

Open http://localhost:5174 in your browser.

## Running All Services

Use the root dev command to start multiple services:
```bash
npm run dev
```

This uses Turbo to run all dev servers in parallel.

## Using Docker Compose

The easiest way to run everything together:

```bash
# Start all services
docker-compose up

# Run in background
docker-compose up -d

# Stop all services
docker-compose down
```

Services will be available at:
- Backend: http://localhost:3000
- Frontend: http://localhost:5173
- Admin UI: http://localhost:5174
- PostgreSQL: localhost:5432
- Redis: localhost:6379

## Database Setup

### Using Docker

```bash
# Start just the database services
docker-compose up -d postgres redis

# Run migrations
npm run migrate # (TODO: Add migration script)
```

### Manual Setup

If you have PostgreSQL installed locally:

```bash
# Create database
createdb starforge

# Run schema
psql -d starforge -f database/schema.sql

# Run seeds (optional, for development)
psql -d starforge -f database/seeds.sql
```

## Testing

Run all tests:
```bash
npm test
```

Run tests for a specific package:
```bash
npm test --workspace=@starforge/backend
```

## Linting & Formatting

```bash
# Lint all code
npm run lint

# Format all code
npm run format

# Check formatting without making changes
npm run format:check

# Type checking
npm run type-check
```

## Project Structure

```
StarForge/
├── packages/
│   ├── backend/         # Fastify API (Port 3000)
│   ├── bot/             # Discord bot
│   ├── frontend/        # Vue 3 app (Port 5173)
│   ├── admin-ui/        # Admin panel (Port 5174)
│   ├── battle-sim/      # Battle simulator
│   ├── recommendation/  # Recommendation engine
│   ├── import-export/   # Data tools
│   └── shared/          # Shared types & utils
├── database/            # SQL schemas
├── docker/              # Dockerfiles
└── docs/                # Documentation
```

## Common Issues

### Port already in use

If you get "Port already in use" errors:
```bash
# Find and kill the process
lsof -ti:3000 | xargs kill -9  # Backend
lsof -ti:5173 | xargs kill -9  # Frontend
lsof -ti:5174 | xargs kill -9  # Admin
```

### Discord bot not starting

Make sure you have:
1. Created a Discord application at https://discord.com/developers/applications
2. Created a bot and copied the token to DISCORD_TOKEN in .env
3. Invited the bot to your test server

### Database connection errors

1. Make sure PostgreSQL is running:
   ```bash
   docker-compose up -d postgres
   ```

2. Check DATABASE_URL in .env matches your setup

3. Verify the database exists:
   ```bash
   psql -U starforge -l
   ```

## Next Steps

- Read the [full README](../README.md) for more details
- Check [features_500.md](./features_500.md) for the complete feature list
- Review the database schema in `database/schema.sql`
- Explore API endpoints in `packages/backend/src/routes/`
- Check Discord bot commands in `packages/bot/src/commands/`

## Development Tips

1. **Use Turbo's cache:** Turbo caches build outputs. Clear with `npm run clean`

2. **Watch mode:** All packages support `npm run dev` for hot reloading

3. **Workspace commands:** Use `--workspace=` to run commands in specific packages

4. **TypeScript errors:** Run `npm run type-check` to check all packages

5. **Format on save:** Configure your editor to run Prettier on save

## Support

For questions or issues:
- Open an issue on GitHub
- Check existing documentation in `/docs`
- Review code comments in source files

Happy coding! 🚀
