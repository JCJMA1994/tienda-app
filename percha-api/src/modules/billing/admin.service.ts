import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, eq, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { DatabaseService } from '../../database/database.service';
import { auditLogs, invoices, plans, subscriptions, tenants } from '../../database/schema';
import { BillingService } from './billing.service';

export const AdminUpdateTenantSchema = z
  .object({
    /** Bloqueo duro (fraude, abuso): nadie de la tienda puede renovar sesión. */
    status: z.enum(['active', 'suspended']).optional(),
    planCode: z.string().optional(),
    extendDays: z.number().int().min(1).max(90).optional(),
  })
  .refine((v) => Object.keys(v).length > 0, 'Nada que actualizar');

export const MarkPaidSchema = z.object({
  /** Pagos verificados a mano: Plin, transferencia, efectivo. */
  method: z.enum(['plin', 'transfer', 'cash', 'other']),
  reference: z.string().trim().min(3).max(120),
});

/**
 * Backoffice de la plataforma (superadmin). Usa el pool de sistema porque, por definición,
 * mira todas las tiendas. Cada acción queda en la bitácora de la tienda afectada.
 */
@Injectable()
export class AdminService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(BillingService) private readonly billing: BillingService,
  ) {}

  tenants() {
    return this.db.withSystem(async (tx) => {
      const rows = await tx.execute(sql`
        select t.id, t.name, t.status as tenant_status, t.created_at,
               s.status as subscription_status, s.current_period_end, s.trial_ends_at, s.autopay,
               p.code as plan_code, p.price_cents,
               (select count(*) from products x where x.tenant_id = t.id)::int as products,
               (select count(*) from memberships m where m.tenant_id = t.id and m.status = 'active')::int as members,
               (select max(created_at) from sales v where v.tenant_id = t.id) as last_sale_at,
               (select coalesce(sum(amount_cents), 0) from invoices i where i.tenant_id = t.id and i.status = 'open')::int as owed_cents
          from tenants t
          left join subscriptions s on s.tenant_id = t.id
          left join plans p on p.id = s.plan_id
         order by t.created_at desc`);
      return rows.rows;
    });
  }

  /** MRR = suma del precio de los planes de tiendas activas (al día o en gracia). */
  metrics(now = new Date()) {
    return this.db.withSystem(async (tx) => {
      const [m] = (
        await tx.execute(sql`
          select count(*)::int as tenants,
                 count(*) filter (where s.status = 'trialing')::int as trialing,
                 count(*) filter (where s.status = 'active')::int as active,
                 count(*) filter (where s.status = 'past_due')::int as past_due,
                 count(*) filter (where s.status = 'suspended')::int as suspended,
                 count(*) filter (where s.status = 'canceled')::int as canceled,
                 coalesce(sum(p.price_cents) filter (where s.status in ('active', 'past_due')), 0)::int as mrr_cents,
                 count(*) filter (where s.status = 'trialing' and s.trial_ends_at < ${now}::timestamptz + interval '7 days')::int as trials_ending_7d
            from subscriptions s join plans p on p.id = s.plan_id`)
      ).rows as Record<string, number>[];
      return m;
    });
  }

  updateTenant(admin: AuthUser, tenantId: string, input: z.infer<typeof AdminUpdateTenantSchema>) {
    return this.db.withSystem(async (tx) => {
      const [t] = await tx.select().from(tenants).where(eq(tenants.id, tenantId));
      if (!t) throw new NotFoundException('Tienda no encontrada');
      if (input.status) await tx.update(tenants).set({ status: input.status }).where(eq(tenants.id, tenantId));
      if (input.planCode) {
        const [plan] = await tx.select().from(plans).where(eq(plans.code, input.planCode));
        if (!plan) throw new BadRequestException('Plan inexistente');
        await tx.update(subscriptions).set({ planId: plan.id, updatedAt: new Date() }).where(eq(subscriptions.tenantId, tenantId));
      }
      if (input.extendDays) {
        // Cortesía: extiende el periodo actual y reactiva si estaba en gracia o suspendida.
        await tx
          .update(subscriptions)
          .set({
            currentPeriodEnd: sql`greatest(${subscriptions.currentPeriodEnd}, now()) + make_interval(days => ${input.extendDays})`,
            status: sql`case when ${subscriptions.status} in ('past_due', 'suspended') then 'active'::subscription_status else ${subscriptions.status} end`,
            updatedAt: new Date(),
          })
          .where(eq(subscriptions.tenantId, tenantId));
      }
      await tx.insert(auditLogs).values({ tenantId, action: 'admin.tenant_updated', entity: 'tenant', entityId: tenantId, data: { ...input, adminUserId: admin.userId } });
      this.billing.forget(tenantId);
      return { ok: true };
    });
  }

  invoices(tenantId: string) {
    return this.db.withSystem((tx) =>
      tx.select().from(invoices).where(eq(invoices.tenantId, tenantId)).orderBy(sql`${invoices.createdAt} desc`).limit(24),
    );
  }

  /** Registrar un pago verificado a mano (p. ej. Plin a la cuenta de la empresa). */
  markPaid(admin: AuthUser, invoiceId: string, input: z.infer<typeof MarkPaidSchema>) {
    return this.db.withSystem(async (tx) => {
      const [inv] = await tx.select().from(invoices).where(and(eq(invoices.id, invoiceId), eq(invoices.status, 'open')));
      if (!inv) throw new NotFoundException('Factura abierta no encontrada');
      await this.billing.markPaid(tx, invoiceId, { provider: 'manual', providerRef: input.reference, method: input.method });
      await tx.insert(auditLogs).values({
        tenantId: inv.tenantId,
        action: 'admin.invoice_marked_paid',
        entity: 'invoice',
        entityId: invoiceId,
        data: { ...input, adminUserId: admin.userId },
      });
      return { paid: invoiceId };
    });
  }

  run(now?: string) {
    return this.billing.run(now ? new Date(now) : new Date());
  }
}
