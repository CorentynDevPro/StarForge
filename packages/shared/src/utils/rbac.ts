import { Role } from '../types';

export interface Permission {
  resource: string;
  action: 'create' | 'read' | 'update' | 'delete';
}

const rolePermissions: Record<Role, Permission[]> = {
  admin: [
    { resource: '*', action: 'create' },
    { resource: '*', action: 'read' },
    { resource: '*', action: 'update' },
    { resource: '*', action: 'delete' },
  ],
  guild_master: [
    { resource: 'guild', action: 'read' },
    { resource: 'guild', action: 'update' },
    { resource: 'members', action: 'read' },
    { resource: 'members', action: 'update' },
    { resource: 'analytics', action: 'read' },
  ],
  moderator: [
    { resource: 'guild', action: 'read' },
    { resource: 'members', action: 'read' },
    { resource: 'members', action: 'update' },
    { resource: 'analytics', action: 'read' },
  ],
  member: [
    { resource: 'guild', action: 'read' },
    { resource: 'analytics', action: 'read' },
  ],
};

export function hasPermission(
  userRoles: Role[],
  resource: string,
  action: 'create' | 'read' | 'update' | 'delete',
): boolean {
  for (const role of userRoles) {
    const permissions = rolePermissions[role];

    for (const permission of permissions) {
      if (
        (permission.resource === '*' || permission.resource === resource) &&
        permission.action === action
      ) {
        return true;
      }
    }
  }

  return false;
}

export function getRolePermissions(role: Role): Permission[] {
  return rolePermissions[role] || [];
}

export function getAllPermissions(roles: Role[]): Permission[] {
  const allPermissions: Permission[] = [];

  for (const role of roles) {
    allPermissions.push(...getRolePermissions(role));
  }

  return allPermissions;
}
