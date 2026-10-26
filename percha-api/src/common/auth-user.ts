import { createParamDecorator, ExecutionContext, ForbiddenException } from '@nestjs/common';
import type { Role } from './authz/permissions';

/** Identidad del request, extraída del JWT por AuthGuard. */
export interface AuthUser {
  userId: string;
  tenantId: string;
  membershipId: string;
  role: Role;
  /** null = acceso a todas las sucursales. */
  branchId: string | null;
}

export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthUser => {
  return ctx.switchToHttp().getRequest().user;
});

/** Un miembro asignado a una sucursal no puede operar en otra. */
export function assertBranchAccess(user: AuthUser, branchId: string) {
  if (user.branchId && user.branchId !== branchId) {
    throw new ForbiddenException('No tienes acceso a esta sucursal');
  }
}
