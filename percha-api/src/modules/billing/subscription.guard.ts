import { CanActivate, ExecutionContext, HttpException, HttpStatus, Inject, Injectable } from '@nestjs/common';
import type { AuthUser } from '../../common/auth-user';
import { BillingService, READ_ONLY_STATUSES } from './billing.service';

/** Rutas que siguen funcionando aunque la suscripción esté suspendida. */
const ALWAYS_ALLOWED = [/^\/v1\/billing(\/|$)/, /^\/v1\/auth(\/|$)/, /^\/v1\/admin(\/|$)/];
const READ_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

/**
 * Bloqueo suave: con la suscripción suspendida o cancelada, la tienda puede ENTRAR, VER y
 * EXPORTAR todo, y pagar; lo que no puede es registrar operaciones nuevas (ventas, ajustes,
 * productos...). Responde 402 con code SUBSCRIPTION_SUSPENDED para que la app muestre el aviso.
 * Los datos nunca se borran por falta de pago.
 */
@Injectable()
export class SubscriptionGuard implements CanActivate {
  constructor(@Inject(BillingService) private readonly billing: BillingService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<{ method: string; path: string; user?: AuthUser }>();
    if (!req.user || READ_METHODS.has(req.method) || ALWAYS_ALLOWED.some((r) => r.test(req.path))) return true;

    const status = await this.billing.status(req.user.tenantId);
    if (status && READ_ONLY_STATUSES.has(status)) {
      throw new HttpException(
        {
          message: status === 'canceled' ? 'Tu suscripción terminó. Reactívala para seguir operando.' : 'Tu suscripción está suspendida por falta de pago. Puedes ver tus datos y pagar desde Facturación.',
          code: 'SUBSCRIPTION_SUSPENDED',
          status,
        },
        HttpStatus.PAYMENT_REQUIRED,
      );
    }
    return true;
  }
}
