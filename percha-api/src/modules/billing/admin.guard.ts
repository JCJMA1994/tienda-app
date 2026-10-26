import { CanActivate, ExecutionContext, ForbiddenException, Inject, Injectable } from '@nestjs/common';
import { eq } from 'drizzle-orm';
import type { AuthUser } from '../../common/auth-user';
import { DatabaseService } from '../../database/database.service';
import { platformAdmins, users } from '../../database/schema';
import { ENV, Env } from '../../config/env';

/**
 * Superadmin de la plataforma. Se verifica contra la BD en cada request (no en el JWT):
 * quitar a alguien de platform_admins le corta el acceso al instante.
 */
@Injectable()
export class PlatformAdminGuard implements CanActivate {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const user: AuthUser | undefined = ctx.switchToHttp().getRequest().user;
    if (!user) throw new ForbiddenException();
    const [row] = await this.db.withSystem((tx) => tx.select().from(platformAdmins).where(eq(platformAdmins.userId, user.userId)));
    if (!row) throw new ForbiddenException('Solo administradores de la plataforma');
    // En producción, el backoffice exige verificación en dos pasos (ve datos de todas las tiendas).
    if (this.env.ADMIN_REQUIRE_2FA) {
      const [u] = await this.db.withSystem((tx) => tx.select({ on: users.totpEnabledAt }).from(users).where(eq(users.id, user.userId)));
      if (!u?.on) throw new ForbiddenException({ message: 'Activa la verificación en dos pasos para usar el backoffice', code: 'TWO_FACTOR_REQUIRED' });
    }
    return true;
  }
}
