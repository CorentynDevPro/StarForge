# StarForge - Gems of War Community Platform

[![CI/CD Pipeline](https://github.com/CorentynDevPro/StarForge/actions/workflows/ci.yml/badge.svg)](https://github.com/CorentynDevPro/StarForge/actions/workflows/ci.yml)

Next-generation community platform for Gems of War Guild Masters and players. Track progress, manage guilds, analyze statistics, simulate battles, and much more.

## 🚀 Features

- **Guild Management**: Multi-tenant per-guild configuration and member tracking
- **Discord Bot**: Fully integrated Discord bot with slash commands
- **Battle Simulator**: Test team compositions and strategies
- **Recommendation Engine**: Get suggestions for optimal teams and strategies
- **Analytics Pipeline**: Comprehensive analytics and reporting
- **Admin UI**: RBAC-based admin panel with moderator tools
- **Feature Flags**: Dynamic feature toggling per guild or globally
- **Job Scheduler**: Cron and queue-based background jobs
- **Import/Export**: Google Sheets integration and CSV tools
- **Audit Logs**: Complete audit trail for all actions

## 📦 Monorepo Structure

This is a TypeScript monorepo using npm workspaces and Turbo:

```
StarForge/
├── packages/
│   ├── backend/         # Fastify REST API
│   ├── bot/             # Discord.js bot
│   ├── frontend/        # Vue 3 + Vite + Pinia + Router
│   ├── admin-ui/        # Admin panel with RBAC
│   ├── battle-sim/      # Battle simulation engine
│   ├── recommendation/  # Recommendation engine
│   ├── import-export/   # Data import/export tools
│   └── shared/          # Shared types and utilities
├── database/            # Postgres/Supabase schema
├── docker/              # Docker configurations
└── .github/workflows/   # GitHub Actions CI/CD
```

## 🛠️ Tech Stack

### Backend

- **Fastify**: High-performance REST API
- **Supabase/Postgres**: Database with Row Level Security
- **Redis**: Caching and job queue
- **JWT**: Authentication

### Frontend

- **Vue 3**: Progressive JavaScript framework
- **Vite**: Lightning-fast build tool
- **Pinia**: State management
- **Vue Router**: Client-side routing

### Bot

- **discord.js**: Discord bot framework
- **Slash Commands**: Modern Discord interactions

### DevOps

- **Docker Compose**: Local development
- **GitHub Actions**: CI/CD pipeline
- **Turbo**: Monorepo build system

## 🚦 Getting Started

### Prerequisites

- Node.js 18+
- npm 9+
- Docker and Docker Compose
- PostgreSQL 15+ (or use Docker)

### Installation

1. Clone the repository:

```bash
git clone https://github.com/CorentynDevPro/StarForge.git
cd StarForge
```

2. Install dependencies:

```bash
npm install
```

3. Copy environment variables:

```bash
cp .env.example .env
# Edit .env with your configuration
```

4. Start the database:

```bash
docker-compose up -d postgres redis
```

5. Run database migrations:

```bash
psql -h localhost -U starforge -d starforge -f database/schema.sql
psql -h localhost -U starforge -d starforge -f database/seeds.sql
```

### Development

Start all services in development mode:

```bash
npm run dev
```

Or start individual packages:

```bash
npm run dev --workspace=@starforge/backend
npm run dev --workspace=@starforge/frontend
npm run dev --workspace=@starforge/bot
npm run dev --workspace=@starforge/admin-ui
```

Services will be available at:

- Backend API: http://localhost:3000
- Frontend: http://localhost:5173
- Admin UI: http://localhost:5174

### Using Docker Compose

Start everything with Docker:

```bash
docker-compose up
```

Stop all services:

```bash
docker-compose down
```

## 🧪 Testing

Run all tests:

```bash
npm test
```

Run tests for a specific package:

```bash
npm test --workspace=@starforge/backend
```

## 🎨 Linting & Formatting

Lint all packages:

```bash
npm run lint
```

Format code:

```bash
npm run format
```

Check formatting:

```bash
npm run format:check
```

## 🏗️ Building

Build all packages:

```bash
npm run build
```

Build a specific package:

```bash
npm run build --workspace=@starforge/backend
```

## 📚 Documentation

- [Features Documentation](./docs/features_500.md) - Detailed feature list
- [API Documentation](./packages/backend/README.md) - Backend API endpoints
- [Database Schema](./database/schema.sql) - Database structure
- [Discord Bot Commands](./packages/bot/README.md) - Bot command reference

## 🔐 Environment Variables

See [.env.example](./.env.example) for all required environment variables.

Key variables:

- `DATABASE_URL`: PostgreSQL connection string
- `DISCORD_TOKEN`: Discord bot token
- `JWT_SECRET`: JWT signing secret
- `SUPABASE_URL`: Supabase project URL
- `SUPABASE_ANON_KEY`: Supabase anonymous key

## 🚢 Deployment

### Docker

Build production images:

```bash
docker build -f docker/Dockerfile.backend -t starforge-backend .
docker build -f docker/Dockerfile.bot -t starforge-bot .
docker build -f docker/Dockerfile.frontend -t starforge-frontend .
```

### Manual Deployment

1. Build all packages:

```bash
npm run build
```

2. Set production environment variables

3. Start services:

```bash
npm start --workspace=@starforge/backend
npm start --workspace=@starforge/bot
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Gems of War community
- Taran's World website (predecessor)
- All contributors and supporters

## 📞 Support

For support, join our Discord server or open an issue on GitHub.

---

Made with ❤️ for the Gems of War community
