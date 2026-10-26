import { Controller, Get, Header } from '@nestjs/common';
import {
  APPROVABLE,
  ASSIGNABLE_ROLES,
  BRANCH_SCOPED,
  hasPermission,
  PERMISSION_INFO,
  PERMISSIONS,
  Role,
  ROLE_LABELS,
  ROLE_PERMISSIONS,
} from '../../common/authz/permissions';

export type AccessLevel = 'yes' | 'no' | 'approval' | 'own_branch';

const ROLES: Role[] = ['owner', 'manager', 'seller', 'stock'];

/**
 * Catálogo de roles y permisos, GENERADO desde la misma matriz que aplican los guards.
 * La app lo usa para mostrar la pantalla de roles y saber qué roles puede asignar,
 * sin duplicar reglas: si la matriz cambia aquí, la app la refleja sola.
 */
export function describeRoles() {
  const level = (role: Role, p: (typeof PERMISSIONS)[number]): AccessLevel => {
    if (hasPermission(role, p)) return BRANCH_SCOPED[role]?.includes(p) ? 'own_branch' : 'yes';
    if (APPROVABLE.includes(p) && hasPermission(role, 'sales.create')) return 'approval';
    return 'no';
  };

  return {
    permissions: PERMISSIONS.map((key) => ({ key, ...PERMISSION_INFO[key] })),
    roles: ROLES.map((key) => ({
      key,
      label: ROLE_LABELS[key],
      permissions: [...ROLE_PERMISSIONS[key]],
      access: Object.fromEntries(PERMISSIONS.map((p) => [p, level(key, p)])) as Record<string, AccessLevel>,
      assignable: ASSIGNABLE_ROLES[key],
    })),
  };
}

@Controller('roles')
export class RolesController {
  private readonly payload = describeRoles();

  /** Cualquier miembro autenticado puede verlo (no expone datos de la tienda). */
  @Get()
  @Header('Cache-Control', 'private, max-age=3600')
  list() {
    return this.payload;
  }
}
