import { AuditLog } from '../types';

export async function logAudit(log: Omit<AuditLog, 'id' | 'timestamp'>): Promise<void> {
  // TODO: Implement actual audit log storage
  console.log('[AUDIT]', {
    ...log,
    timestamp: new Date().toISOString(),
  });
}

export function createAuditLog(
  action: string,
  userId: string,
  metadata: Record<string, unknown>,
  options?: {
    guildId?: string;
    ipAddress?: string;
    userAgent?: string;
  },
): Omit<AuditLog, 'id' | 'timestamp'> {
  return {
    action,
    userId,
    metadata,
    guildId: options?.guildId,
    ipAddress: options?.ipAddress,
    userAgent: options?.userAgent,
  };
}
