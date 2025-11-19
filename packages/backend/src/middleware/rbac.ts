import { FastifyRequest, FastifyReply } from 'fastify';

export interface User {
  id: string;
  roles: string[];
  guildId?: string;
}

export const rbacMiddleware = (requiredRole: string) => {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const user = request.user as User;

    if (!user) {
      return reply.status(401).send({ error: 'Unauthorized' });
    }

    // Check if user has the required role
    if (!user.roles.includes(requiredRole) && !user.roles.includes('admin')) {
      return reply.status(403).send({ error: 'Forbidden: Insufficient permissions' });
    }
  };
};
