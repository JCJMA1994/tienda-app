import { Inject, Injectable } from '@nestjs/common';
import { and, asc, desc, eq, notInArray, sql } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { DomainError } from '../../common/domain-error';
import { AuditService } from '../audit/audit.service';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import { products, stockCountItems, stockCounts, stockLevels, variants } from '../../database/schema';
import { InventoryService } from './inventory.service';

export const StartCountSchema = z.object({ branchId: z.string().uuid(), note: z.string().trim().max(200).optional() });
export const ScanSchema = z.object({
  variantId: z.string().uuid(),
  /** `add`: suma (cada escaneo +1); `set`: fija la cantidad contada. */
  mode: z.enum(['add', 'set']).default('add'),
  quantity: z.number().int().min(0).max(10_000).default(1),
});
export const ApplyCountSchema = z.object({
  /**
   * Las prendas con stock que NO se contaron se ajustan a 0. Solo para un conteo completo de
   * la sucursal: si se contó solo una parte, dejarlo en false.
   */
  zeroUncounted: z.boolean().default(false),
});

/**
 * Conteo de inventario guiado (sin cerrar la tienda):
 *  - al contar una prenda por primera vez se guarda el stock del sistema EN ESE MOMENTO;
 *  - al aplicar, la diferencia es `contado − stock al contarla`: si se vendió una unidad
 *    después de contarla, no aparece como faltante;
 *  - se aplica como ajustes del kardex ligados al conteo (la base impide aplicarlo dos veces).
 */
@Injectable()
export class CountsService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(InventoryService) private readonly inventory: InventoryService,
    @Inject(AuditService) private readonly audit: AuditService,
  ) {}

  start(user: AuthUser, input: z.infer<typeof StartCountSchema>) {
    assertBranchAccess(user, input.branchId);
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [open] = await tx.select({ id: stockCounts.id, number: stockCounts.number }).from(stockCounts).where(and(eq(stockCounts.branchId, input.branchId), eq(stockCounts.status, 'open')));
      if (open) throw DomainError.conflict('COUNT_OPEN', `Ya hay un conteo abierto (#${open.number}) en esta sucursal: termínalo o cancélalo`, { countId: open.id });
      const number = await nextNumber(tx, user.tenantId, 'stock_count');
      const [c] = await tx.insert(stockCounts).values({ tenantId: user.tenantId, branchId: input.branchId, number, note: input.note, createdBy: user.membershipId }).returning();
      return c;
    });
  }

  list(user: AuthUser, branchId: string) {
    assertBranchAccess(user, branchId);
    return this.db.withTenant(user.tenantId, (tx) => tx.select().from(stockCounts).where(eq(stockCounts.branchId, branchId)).orderBy(desc(stockCounts.createdAt)).limit(30));
  }

  scan(user: AuthUser, id: string, input: z.infer<typeof ScanSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const c = await this.lockOpen(tx, user, id);
      const [v] = await tx.select({ id: variants.id }).from(variants).where(eq(variants.id, input.variantId));
      if (!v) throw DomainError.notFound('VARIANT_NOT_FOUND', 'Prenda no encontrada');
      const [current] = await tx.select({ q: stockLevels.quantity }).from(stockLevels).where(and(eq(stockLevels.branchId, c.branchId), eq(stockLevels.variantId, input.variantId)));
      await tx
        .insert(stockCountItems)
        .values({ tenantId: user.tenantId, countId: id, variantId: input.variantId, counted: input.quantity, stockAtFirstScan: current?.q ?? 0 })
        .onConflictDoUpdate({
          target: [stockCountItems.countId, stockCountItems.variantId],
          // La "foto" del stock (stockAtFirstScan) NO se actualiza: es la del primer escaneo.
          set: { counted: input.mode === 'set' ? input.quantity : sql`${stockCountItems.counted} + ${input.quantity}`, updatedAt: new Date() },
        });
      return this.load(tx, c);
    });
  }

  removeItem(user: AuthUser, id: string, variantId: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const c = await this.lockOpen(tx, user, id);
      await tx.delete(stockCountItems).where(and(eq(stockCountItems.countId, id), eq(stockCountItems.variantId, variantId)));
      return this.load(tx, c);
    });
  }

  get(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [c] = await tx.select().from(stockCounts).where(eq(stockCounts.id, id));
      if (!c) throw DomainError.notFound('COUNT_NOT_FOUND', 'Conteo no encontrado');
      assertBranchAccess(user, c.branchId);
      return this.load(tx, c);
    });
  }

  apply(user: AuthUser, id: string, input: z.infer<typeof ApplyCountSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const c = await this.lockOpen(tx, user, id);
      const items = await tx.select().from(stockCountItems).where(eq(stockCountItems.countId, id));
      const reason = `Conteo de inventario #${c.number}`;
      const movements = items
        .map((i) => ({ variantId: i.variantId, quantity: i.counted - i.stockAtFirstScan }))
        .filter((m) => m.quantity !== 0)
        .map((m) => ({ ...m, type: 'adjustment' as const, referenceType: 'stock_count', referenceId: id, reason }));

      if (input.zeroUncounted) {
        const counted = items.map((i) => i.variantId);
        const rest = await tx
          .select({ variantId: stockLevels.variantId, q: stockLevels.quantity })
          .from(stockLevels)
          .where(and(eq(stockLevels.branchId, c.branchId), sql`${stockLevels.quantity} > 0`, counted.length ? notInArray(stockLevels.variantId, counted) : undefined));
        movements.push(...rest.map((r) => ({ variantId: r.variantId, quantity: -r.q, type: 'adjustment' as const, referenceType: 'stock_count', referenceId: id, reason: `${reason} (no contada)` })));
      }
      if (movements.length) await this.inventory.apply(tx, user, c.branchId, movements);
      await tx.update(stockCounts).set({ status: 'applied', appliedAt: new Date(), appliedBy: user.membershipId }).where(eq(stockCounts.id, id));
      const missing = movements.filter((m) => m.quantity < 0).reduce((a, m) => a - m.quantity, 0);
      const extra = movements.filter((m) => m.quantity > 0).reduce((a, m) => a + m.quantity, 0);
      await this.audit.log(tx, user, 'inventory.count_applied', 'stock_count', id, { adjusted: movements.length, missing, extra });
      return { ...(await this.load(tx, { ...c, status: 'applied' })), adjusted: movements.length, missingUnits: missing, extraUnits: extra };
    });
  }

  cancel(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const c = await this.lockOpen(tx, user, id);
      await tx.update(stockCounts).set({ status: 'cancelled' }).where(eq(stockCounts.id, id));
      return { ...c, status: 'cancelled' as const };
    });
  }

  private async lockOpen(tx: Tx, user: AuthUser, id: string) {
    const [c] = await tx.select().from(stockCounts).where(eq(stockCounts.id, id)).for('update');
    if (!c) throw DomainError.notFound('COUNT_NOT_FOUND', 'Conteo no encontrado');
    assertBranchAccess(user, c.branchId);
    if (c.status !== 'open') throw DomainError.conflict('COUNT_CLOSED', 'Este conteo ya se cerró');
    return c;
  }

  private async load(tx: Tx, c: typeof stockCounts.$inferSelect) {
    const items = await tx
      .select({
        variantId: stockCountItems.variantId,
        counted: stockCountItems.counted,
        stockAtFirstScan: stockCountItems.stockAtFirstScan,
        sku: variants.sku,
        options: variants.options,
        productName: products.name,
      })
      .from(stockCountItems)
      .innerJoin(variants, eq(variants.id, stockCountItems.variantId))
      .innerJoin(products, eq(products.id, variants.productId))
      .where(eq(stockCountItems.countId, c.id))
      .orderBy(asc(products.name), asc(variants.sku));
    return {
      ...c,
      items: items.map((i) => ({ ...i, difference: i.counted - i.stockAtFirstScan })),
      totals: {
        variants: items.length,
        counted: items.reduce((a, i) => a + i.counted, 0),
        missing: items.reduce((a, i) => a + Math.max(i.stockAtFirstScan - i.counted, 0), 0),
        extra: items.reduce((a, i) => a + Math.max(i.counted - i.stockAtFirstScan, 0), 0),
      },
    };
  }
}
