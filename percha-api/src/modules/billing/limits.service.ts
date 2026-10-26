import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { and, eq, gt, isNull, sql } from 'drizzle-orm';
import type { Tx } from '../../database/database.service';
import { branches, invitations, memberships, plans, products, subscriptions } from '../../database/schema';
import type { PlanLimits } from '../../database/schema';

export type LimitedResource = keyof PlanLimits;

const LABELS: Record<LimitedResource, string> = { branches: 'sucursales', members: 'usuarios', products: 'productos' };

/**
 * Límites del plan. Se verifican DENTRO de la transacción que crea el recurso, así dos altas
 * simultáneas no pueden pasarse del límite por una condición de carrera... casi: el conteo no
 * bloquea filas, así que en el peor caso se excede por uno. Para límites comerciales es
 * aceptable; si hiciera falta exactitud, se bloquearía la fila de la suscripción (FOR UPDATE).
 *
 * Responde 402 (Payment Required) con code PLAN_LIMIT: la app ofrece mejorar el plan.
 */
@Injectable()
export class LimitsService {
  async usage(tx: Tx, tenantId: string): Promise<Record<LimitedResource, number>> {
    const count = async (q: Promise<{ c: number }[]>) => (await q)[0].c;
    const c = sql<number>`count(*)::int`;
    return {
      branches: await count(tx.select({ c }).from(branches).where(eq(branches.tenantId, tenantId))),
      // Usuarios activos + invitaciones pendientes vigentes (una invitación "reserva" un cupo).
      members:
        (await count(tx.select({ c }).from(memberships).where(and(eq(memberships.tenantId, tenantId), eq(memberships.status, 'active'))))) +
        (await count(
          tx
            .select({ c })
            .from(invitations)
            .where(and(eq(invitations.tenantId, tenantId), isNull(invitations.acceptedAt), gt(invitations.expiresAt, new Date()))),
        )),
      products: await count(tx.select({ c }).from(products).where(eq(products.tenantId, tenantId))),
    };
  }

  async limits(tx: Tx, tenantId: string): Promise<PlanLimits | null> {
    const [row] = await tx
      .select({ limits: plans.limits })
      .from(subscriptions)
      .innerJoin(plans, eq(plans.id, subscriptions.planId))
      .where(eq(subscriptions.tenantId, tenantId));
    return row?.limits ?? null;
  }

  async assertCanAdd(tx: Tx, tenantId: string, resource: LimitedResource, adding = 1) {
    const limits = await this.limits(tx, tenantId);
    const limit = limits?.[resource];
    if (limit === null || limit === undefined) return; // ilimitado o tienda sin suscripción (datos previos)
    const current = (await this.usage(tx, tenantId))[resource];
    if (current + adding > limit) {
      throw new HttpException(
        {
          message: `Tu plan permite hasta ${limit} ${LABELS[resource]}. Mejora tu plan para agregar más.`,
          code: 'PLAN_LIMIT',
          resource,
          limit,
          current,
        },
        HttpStatus.PAYMENT_REQUIRED,
      );
    }
  }
}
