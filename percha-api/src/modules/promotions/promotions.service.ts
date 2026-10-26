import { Inject, Injectable } from '@nestjs/common';
import { and, desc, eq, gt, isNull, lte, or } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { DomainError } from '../../common/domain-error';
import { AuditService } from '../audit/audit.service';
import { DatabaseService, Tx } from '../../database/database.service';
import { promotions } from '../../database/schema';
import type { Promo } from './engine';

export const PromotionSchema = z
  .object({
    name: z.string().trim().min(2).max(60),
    kind: z.enum(['percent', 'buy_x_pay_y']),
    /** 1 % … 90 % en puntos básicos (2000 = 20 %). */
    percentBp: z.number().int().min(100).max(9000).optional(),
    buyQty: z.number().int().min(2).max(10).optional(),
    payQty: z.number().int().min(1).max(9).optional(),
    scope: z.enum(['all', 'categories', 'products']).default('all'),
    categoryIds: z.array(z.string().uuid()).max(100).default([]),
    productIds: z.array(z.string().uuid()).max(500).default([]),
    startsAt: z.string().datetime(),
    endsAt: z.string().datetime().nullable().optional(),
    active: z.boolean().default(true),
  })
  .superRefine((p, ctx) => {
    if (p.kind === 'percent' && !p.percentBp) ctx.addIssue({ code: 'custom', path: ['percentBp'], message: 'Indica el porcentaje' });
    if (p.kind === 'buy_x_pay_y' && (!p.buyQty || !p.payQty || p.payQty >= p.buyQty)) ctx.addIssue({ code: 'custom', path: ['payQty'], message: '"Paga" debe ser menor que "lleva" (p. ej. lleva 2, paga 1)' });
    if (p.scope === 'categories' && !p.categoryIds.length) ctx.addIssue({ code: 'custom', path: ['categoryIds'], message: 'Elige al menos una categoría' });
    if (p.scope === 'products' && !p.productIds.length) ctx.addIssue({ code: 'custom', path: ['productIds'], message: 'Elige al menos un producto' });
    if (p.endsAt && new Date(p.endsAt) <= new Date(p.startsAt)) ctx.addIssue({ code: 'custom', path: ['endsAt'], message: 'La fecha de fin debe ser posterior al inicio' });
  });

type Row = typeof promotions.$inferSelect;
export const toPromo = (r: Row): Promo => ({
  id: r.id,
  name: r.name,
  kind: r.kind,
  percentBp: r.percentBp,
  buyQty: r.buyQty,
  payQty: r.payQty,
  scope: r.scope,
  categoryIds: r.categoryIds,
  productIds: r.productIds,
});

@Injectable()
export class PromotionsService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AuditService) private readonly audit: AuditService,
  ) {}

  list(user: AuthUser) {
    return this.db.withTenant(user.tenantId, (tx) => tx.select().from(promotions).orderBy(desc(promotions.active), desc(promotions.startsAt)));
  }

  create(user: AuthUser, input: z.infer<typeof PromotionSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [p] = await tx.insert(promotions).values({ tenantId: user.tenantId, ...this.values(input) }).returning();
      await this.audit.log(tx, user, 'promotion.created', 'promotion', p.id, { name: p.name, kind: p.kind });
      return p;
    });
  }

  update(user: AuthUser, id: string, input: z.infer<typeof PromotionSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [p] = await tx.update(promotions).set({ ...this.values(input), updatedAt: new Date() }).where(eq(promotions.id, id)).returning();
      if (!p) throw DomainError.notFound('PROMOTION_NOT_FOUND', 'Promoción no encontrada');
      await this.audit.log(tx, user, 'promotion.updated', 'promotion', id, { active: p.active });
      return p;
    });
  }

  /** Vigentes en un momento dado (la venta sin conexión usa la hora real de la venta). */
  async activeAt(tx: Tx, at: Date): Promise<Promo[]> {
    const rows = await tx
      .select()
      .from(promotions)
      .where(and(eq(promotions.active, true), lte(promotions.startsAt, at), or(isNull(promotions.endsAt), gt(promotions.endsAt, at))));
    return rows.map(toPromo);
  }

  private values(i: z.infer<typeof PromotionSchema>) {
    return {
      name: i.name,
      kind: i.kind,
      percentBp: i.kind === 'percent' ? i.percentBp! : null,
      buyQty: i.kind === 'buy_x_pay_y' ? i.buyQty! : null,
      payQty: i.kind === 'buy_x_pay_y' ? i.payQty! : null,
      scope: i.scope,
      categoryIds: i.scope === 'categories' ? i.categoryIds : [],
      productIds: i.scope === 'products' ? i.productIds : [],
      startsAt: new Date(i.startsAt),
      endsAt: i.endsAt ? new Date(i.endsAt) : null,
      active: i.active,
    };
  }
}
