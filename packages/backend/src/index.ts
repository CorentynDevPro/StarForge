import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import env from '@fastify/env';
import { healthRoutes } from './routes/health';
import { guildRoutes } from './routes/guilds';
import { analyticsRoutes } from './routes/analytics';
import { authMiddleware } from './middleware/auth';
import { rbacMiddleware } from './middleware/rbac';

const schema = {
  type: 'object',
  required: ['PORT', 'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'JWT_SECRET'],
  properties: {
    PORT: { type: 'string', default: '3000' },
    SUPABASE_URL: { type: 'string' },
    SUPABASE_ANON_KEY: { type: 'string' },
    JWT_SECRET: { type: 'string' },
    NODE_ENV: { type: 'string', default: 'development' },
  },
};

async function buildServer() {
  const fastify = Fastify({
    logger: {
      transport: {
        target: 'pino-pretty',
        options: {
          translateTime: 'HH:MM:ss Z',
          ignore: 'pid,hostname',
        },
      },
    },
  });

  // Register env plugin
  await fastify.register(env, {
    schema,
    dotenv: true,
  });

  // Register CORS
  await fastify.register(cors, {
    origin: true,
    credentials: true,
  });

  // Register JWT
  await fastify.register(jwt, {
    secret: fastify.config.JWT_SECRET,
  });

  // Register middleware
  fastify.decorate('authenticate', authMiddleware);
  fastify.decorate('authorize', rbacMiddleware);

  // Register routes
  await fastify.register(healthRoutes, { prefix: '/api/health' });
  await fastify.register(guildRoutes, { prefix: '/api/guilds' });
  await fastify.register(analyticsRoutes, { prefix: '/api/analytics' });

  return fastify;
}

async function start() {
  try {
    const fastify = await buildServer();
    const port = parseInt(fastify.config.PORT || '3000', 10);
    const host = '0.0.0.0';

    await fastify.listen({ port, host });
    console.log(`🚀 Backend server running on http://${host}:${port}`);
  } catch (err) {
    console.error('Error starting server:', err);
    process.exit(1);
  }
}

// Start the server
start();

export { buildServer };
