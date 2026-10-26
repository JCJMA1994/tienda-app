import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { eq, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { DatabaseService } from '../../database/database.service';
import { attributes, branches, memberships, products, sales, tenants } from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { LimitsService } from '../billing/limits.service';

export const UpdateStoreSchema = z
  .object({
    name: z.string().trim().min(2).max(80),
    ruc: z.string().regex(/^\d{11}$/, 'El RUC debe tener 11 dígitos').nullable(),
    currency: z.enum(['PEN', 'USD']),
    taxRateBp: z.number().int().min(0).max(5000),
    pricesIncludeTax: z.boolean(),
    discountLimitBp: z.number().int().min(0).max(10_000),
    allowNegativeStock: z.boolean(),
    timezone: z.string().refine((tz) => {
      try {
        new Intl.DateTimeFormat('es', { timeZone: tz });
        return true;
      } catch {
        return false;
      }
    }, 'Zona horaria inválida'),
  })
  .partial();

export const BranchSchema = z.object({
  name: z.string().trim().min(2).max(80),
  address: z.string().trim().max(200).nullable().optional(),
  /** Ubigeo INEI de 6 dígitos (p. ej. 150122 = Miraflores, Lima). */
  ubigeo: z.string().regex(/^\d{6}$/, 'Ubigeo de 6 dígitos').nullable().optional(),
});

@Injectable()
export class StoreService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(LimitsService) private readonly limits: LimitsService,
  ) {}

  get(user: AuthUser) {
    // RLS: la política tenant_self solo deja ver la propia tienda.
    return this.db.withTenant(user.tenantId, async (tx) => (await tx.select().from(tenants))[0]);
  }

  update(user: AuthUser, input: z.infer<typeof UpdateStoreSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx.update(tenants).set(input).where(eq(tenants.id, user.tenantId)).returning();
      await this.audit.log(tx, user, 'store.updated', 'tenant', user.tenantId, input);
      return row;
    });
  }

  /**
   * Progreso del onboarding CALCULADO a partir de los datos reales, no de banderas:
   * si el dueño importa productos por otra vía, el paso "catálogo" se marca solo.
   */
  onboarding(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [t] = await tx.select().from(tenants);
      const count = async (table: typeof attributes | typeof products | typeof memberships | typeof sales) =>
        (await tx.select({ c: sql<number>`count(*)::int` }).from(table))[0].c;

      const steps = [
        { key: 'business', label: 'Datos del negocio', done: Boolean(t.ruc) },
        { key: 'attributes', label: 'Atributos de variantes', done: (await count(attributes)) > 0 },
        { key: 'catalog', label: 'Primeros productos', done: (await count(products)) > 0 },
        { key: 'team', label: 'Invitar al equipo', done: (await count(memberships)) > 1 },
        { key: 'first_sale', label: 'Primera venta', done: (await count(sales)) > 0 },
      ];
      const completed = steps.filter((s) => s.done).length;
      return {
        steps,
        completed,
        total: steps.length,
        nextStep: steps.find((s) => !s.done)?.key ?? null,
        dismissed: t.onboardingDismissed,
      };
    });
  }

  dismissOnboarding(user: AuthUser) {
    return this.db.withTenant(user.tenantId, (tx) =>
      tx.update(tenants).set({ onboardingDismissed: true }).where(eq(tenants.id, user.tenantId)),
    );
  }

  listBranches(user: AuthUser) {
    return this.db.withTenant(user.tenantId, (tx) => tx.select().from(branches).orderBy(branches.createdAt));
  }

  createBranch(user: AuthUser, input: z.infer<typeof BranchSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      await this.limits.assertCanAdd(tx, user.tenantId, 'branches');
      const [row] = await tx.insert(branches).values({ tenantId: user.tenantId, ...input }).returning();
      await this.audit.log(tx, user, 'branch.created', 'branch', row.id, input);
      return row;
    });
  }

  updateBranch(user: AuthUser, id: string, input: Partial<z.infer<typeof BranchSchema>>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx.update(branches).set(input).where(eq(branches.id, id)).returning();
      if (!row) throw new NotFoundException('Sucursal no encontrada');
      return row;
    });
  }
}
