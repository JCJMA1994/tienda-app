import { CanActivate, ExecutionContext, ForbiddenException, Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import type { AuthUser } from '../../common/auth-user';
import { IS_PUBLIC, REQUIRED_PERMISSIONS } from '../../common/authz/decorators';
import { hasPermission, Permission, Role } from '../../common/authz/permissions';

export interface AccessTokenPayload {
  sub: string;
  tid: string;
  mid: string;
  role: Role;
  bid: string | null;
}

/**
 * Guard global: todo endpoint requiere JWT salvo los marcados con @Public().
 * Seguro por defecto: si alguien olvida el decorador, el endpoint queda protegido.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    @Inject(JwtService) private readonly jwt: JwtService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, [ctx.getHandler(), ctx.getClass()]);
    if (isPublic) return true;

    const req = ctx.switchToHttp().getRequest();
    const header: string | undefined = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) throw new UnauthorizedException();

    try {
      const p = await this.jwt.verifyAsync<AccessTokenPayload>(header.slice(7));
      const user: AuthUser = { userId: p.sub, tenantId: p.tid, membershipId: p.mid, role: p.role, branchId: p.bid };
      req.user = user;
      return true;
    } catch {
      throw new UnauthorizedException('Sesión inválida o expirada');
    }
  }
}

@Injectable()
export class PermissionsGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<Permission[]>(REQUIRED_PERMISSIONS, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (!required?.length) return true;
    const user: AuthUser | undefined = ctx.switchToHttp().getRequest().user;
    if (!user) throw new UnauthorizedException();
    const missing = required.filter((p) => !hasPermission(user.role, p));
    if (missing.length) throw new ForbiddenException({ message: 'Permisos insuficientes', missing });
    return true;
  }
}
