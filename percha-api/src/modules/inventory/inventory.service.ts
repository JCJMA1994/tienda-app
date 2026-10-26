import { randomUUID } from 'node:crypto';
import { IdempotencyService } from '../../common/idempotency';
import { PromotionsService } from '../promotions/promotions.service';
import { BadRequestException, Inject, Injectable, UnprocessableEntityException } from '@nestjs/common';
import { and, desc, eq, inArray, lt, lte, sql } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { DatabaseService, Tx } from '../../database/database.service';
import { products, stockLevels, stockMovements, tenants, variants } from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { EventBus } from '../../common/events';

type MovementType = (typeof stockMovements.$inferInsert)['type'];

export interface MovementInput {
  variantId: string;
  /** Con signo: positivo entra, negativo sale. */
  quantity: number;
  type: MovementType;
  unitCostCents?: number | null;
  referenceType?: string;
  referenceId?: string;
  reason?: string;
}

export const AdjustmentSchema = z.object({
  branchId: z.string().uuid(),
  reason: z.string().trim().min(3).max(200),
  items: z
    .array(
      z
        .object({
          variantId: z.string().uuid(),
          /** Variación directa (+3, -1)... */
          delta: z.number().int().refine((n) => n !== 0, 'delta no puede ser 0').optional(),
          /** ...o conteo físico: el sistema calcula la diferencia. */
          counted: z.number().int().min(0).optional(),
        })
        .refine((i) => (i.delta === undefined) !== (i.counted === undefined), 'Indica delta o counted, no ambos'),
    )
    .min(1)
    .max(500),
});

export const MinStockSchema = z.object({
  branchId: z.string().uuid(),
  variantId: z.string().uuid(),
  minQuantity: z.number().int().min(0).max(100_000),
});

export const StockQuerySchema = z.object({
  branchId: z.string().uuid().optional(),
  variantId: z.string().uuid().optional(),
  lowOnly: z.enum(['true', 'false']).optional(),
});

export const MovementsQuerySchema = z.object({
  variantId: z.string().uuid().optional(),
  branchId: z.string().uuid().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  before: z.string().datetime().optional(),
});

/**
 * Corazón del inventario. Regla de oro: el stock SOLO cambia a través de `apply`,
 * que escribe el movimiento (kardex) y actualiza la proyección stock_levels en la misma
 * transacción que la venta/compra/ajuste que lo origina.
 */
@Injectable()
export class InventoryService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(EventBus) private readonly events: EventBus,
    @Inject(IdempotencyService) private readonly idem: IdempotencyService,
    @Inject(PromotionsService) private readonly promotions: PromotionsService,
  ) {}

  /**
   * Concurrencia: el UPDATE condicional bloquea la fila (tenant, sucursal, variante) y
   * verifica el saldo en el mismo paso. Dos ventas simultáneas de la última unidad:
   * la segunda espera, re-evalúa la condición y falla con INSUFFICIENT_STOCK.
   * Se ordena por variante para que dos transacciones bloqueen en el mismo orden (sin deadlocks).
   */
  async apply(tx: Tx, user: AuthUser, branchId: string, movements: MovementInput[]) {
    if (!movements.length) return [];
    const [{ allowNegativeStock }] = await tx.select({ allowNegativeStock: tenants.allowNegativeStock }).from(tenants);
    const sorted = [...movements].sort((a, b) => a.variantId.localeCompare(b.variantId));
    const results: { variantId: string; balance: number }[] = [];

    for (const m of sorted) {
      if (!Number.isInteger(m.quantity) || m.quantity === 0) throw new BadRequestException('Cantidad de movimiento inválida');

      await tx
        .insert(stockLevels)
        .values({ tenantId: user.tenantId, branchId, variantId: m.variantId, quantity: 0 })
        .onConflictDoNothing();

      const canGoNegative = allowNegativeStock || m.quantity > 0;
      const [updated] = await tx
        .update(stockLevels)
        .set({ quantity: sql`${stockLevels.quantity} + ${m.quantity}`, updatedAt: new Date() })
        .where(
          and(
            eq(stockLevels.branchId, branchId),
            eq(stockLevels.variantId, m.variantId),
            canGoNegative ? undefined : sql`${stockLevels.quantity} + ${m.quantity} >= 0`,
          ),
        )
        .returning({ quantity: stockLevels.quantity });

      if (!updated) {
        const [current] = await tx
          .select({ quantity: stockLevels.quantity })
          .from(stockLevels)
          .where(and(eq(stockLevels.branchId, branchId), eq(stockLevels.variantId, m.variantId)));
        throw new UnprocessableEntityException({
          message: 'Stock insuficiente',
          code: 'INSUFFICIENT_STOCK',
          variantId: m.variantId,
          available: current?.quantity ?? 0,
          requested: -m.quantity,
        });
      }

      await tx.insert(stockMovements).values({
        tenantId: user.tenantId,
        branchId,
        variantId: m.variantId,
        type: m.type,
        quantity: m.quantity,
        unitCostCents: m.unitCostCents ?? null,
        balanceAfter: updated.quantity,
        referenceType: m.referenceType,
        referenceId: m.referenceId,
        reason: m.reason,
        actorMembershipId: user.membershipId,
      });
      results.push({ variantId: m.variantId, balance: updated.quantity });
    }
    await this.warnLowStock(tx, user, branchId, sorted, results);
    return results;
  }

  /**
   * Avisa a quien repone (inventory.adjust en esa sucursal) cuando una SALIDA hace que una
   * variante cruce su mínimo (o se agote si no tiene mínimo). Solo al cruzar: no en cada venta.
   */
  private async warnLowStock(tx: Tx, user: AuthUser, branchId: string, movements: MovementInput[], results: { variantId: string; balance: number }[]) {
    const outs = movements.filter((m) => m.quantity < 0);
    if (!outs.length) return;
    const levels = await tx
      .select({ variantId: stockLevels.variantId, min: stockLevels.minQuantity, sku: variants.sku, options: variants.options, productId: products.id, name: products.name })
      .from(stockLevels)
      .innerJoin(variants, eq(variants.id, stockLevels.variantId))
      .innerJoin(products, eq(products.id, variants.productId))
      .where(and(eq(stockLevels.branchId, branchId), inArray(stockLevels.variantId, outs.map((o) => o.variantId))));
    for (const o of outs) {
      const lvl = levels.find((l) => l.variantId === o.variantId);
      const balance = results.find((r) => r.variantId === o.variantId)?.balance;
      if (!lvl || balance === undefined) continue;
      const before = balance - o.quantity;
      if (!(balance <= lvl.min && before > lvl.min)) continue;
      const opts = Object.values(lvl.options).join(' ');
      await this.events.publish(tx, {
        type: 'stock.below_minimum',
        tenantId: user.tenantId,
        branchId,
        productId: lvl.productId,
        productName: lvl.name,
        options: opts,
        balance,
        variantId: o.variantId,
      });
    }
  }

  /**
   * Verificación de integridad: el stock de cada variante y sucursal debe ser EXACTAMENTE la
   * suma de sus movimientos en el kardex. Si no, algo cambió el stock por fuera de `apply`.
   */
  integrity(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const rows = await tx.execute<{ branch_id: string; variant_id: string; stock: number; kardex: number }>(sql`
        with k as (
          select branch_id, variant_id, sum(quantity)::int as kardex from stock_movements group by branch_id, variant_id
        )
        select coalesce(s.branch_id, k.branch_id) as branch_id, coalesce(s.variant_id, k.variant_id) as variant_id,
               coalesce(s.quantity, 0) as stock, coalesce(k.kardex, 0) as kardex
        from stock_levels s full outer join k on k.branch_id = s.branch_id and k.variant_id = s.variant_id
        where coalesce(s.quantity, 0) <> coalesce(k.kardex, 0)`);
      const [{ n }] = (await tx.execute<{ n: number }>(sql`select count(*)::int as n from stock_levels`)).rows;
      return {
        ok: rows.rows.length === 0,
        checked: n,
        discrepancies: rows.rows.map((r) => ({ branchId: r.branch_id, variantId: r.variant_id, stock: Number(r.stock), kardex: Number(r.kardex) })),
      };
    });
  }

  /**
   * Foto para el POS sin conexión: variantes activas con precio, códigos y stock de la sucursal.
   * El POS la guarda y la usa para buscar y vender si se cae el internet.
   */
  snapshot(user: AuthUser, branchId: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const rows = await tx
        .select({
          id: variants.id,
          productId: products.id,
          productName: products.name,
          categoryId: products.categoryId,
          sku: variants.sku,
          barcode: variants.barcode,
          options: variants.options,
          priceCents: sql<number>`coalesce(${variants.priceCents}, ${products.priceCents})`,
          imageUrl: products.imageUrl,
          stock: sql<number>`coalesce(${stockLevels.quantity}, 0)`,
        })
        .from(variants)
        .innerJoin(products, eq(products.id, variants.productId))
        .leftJoin(stockLevels, and(eq(stockLevels.variantId, variants.id), eq(stockLevels.branchId, branchId)))
        .where(and(eq(variants.active, true), eq(products.active, true)))
        .limit(20_000);
      return { generatedAt: new Date().toISOString(), branchId, variants: rows, promotions: await this.promotions.activeAt(tx, new Date()) };
    });
  }

  adjust(user: AuthUser, input: z.infer<typeof AdjustmentSchema>, idempotencyKey?: string) {
    assertBranchAccess(user, input.branchId);
    return this.db.withTenant(user.tenantId, async (tx) =>
      this.idem.once(tx, user.tenantId, idempotencyKey, 'inventory.adjust', input, async () => {
      const ids = input.items.map((i) => i.variantId);
      // Bloqueamos los saldos actuales para que el conteo no cambie mientras calculamos.
      const current = await tx
        .select({ variantId: stockLevels.variantId, quantity: stockLevels.quantity })
        .from(stockLevels)
        .where(and(eq(stockLevels.branchId, input.branchId), inArray(stockLevels.variantId, ids)))
        .for('update');
      const byVariant = new Map(current.map((c) => [c.variantId, c.quantity]));

      const movements: MovementInput[] = input.items
        .map((i) => ({
          variantId: i.variantId,
          quantity: i.delta ?? i.counted! - (byVariant.get(i.variantId) ?? 0),
          type: 'adjustment' as const,
          reason: input.reason,
        }))
        .filter((m) => m.quantity !== 0);

      const balances = await this.apply(tx, user, input.branchId, movements);
      await this.audit.log(tx, user, 'inventory.adjusted', 'branch', input.branchId, {
        reason: input.reason,
        items: movements.map((m) => ({ variantId: m.variantId, delta: m.quantity })),
      });
      return { adjusted: movements.length, balances };
    }, () => randomUUID(), async () => ({ adjusted: 0, balances: [], replayed: true })));
  }

  setMinStock(user: AuthUser, input: z.infer<typeof MinStockSchema>) {
    assertBranchAccess(user, input.branchId);
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx
        .insert(stockLevels)
        .values({ tenantId: user.tenantId, branchId: input.branchId, variantId: input.variantId, minQuantity: input.minQuantity })
        .onConflictDoUpdate({
          target: [stockLevels.tenantId, stockLevels.branchId, stockLevels.variantId],
          set: { minQuantity: input.minQuantity },
        })
        .returning();
      return row;
    });
  }

  stock(user: AuthUser, q: z.infer<typeof StockQuerySchema>) {
    const branchId = q.branchId ?? user.branchId ?? undefined;
    if (branchId) assertBranchAccess(user, branchId);
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select({
          branchId: stockLevels.branchId,
          variantId: stockLevels.variantId,
          sku: variants.sku,
          options: variants.options,
          productId: products.id,
          productName: products.name,
          quantity: stockLevels.quantity,
          minQuantity: stockLevels.minQuantity,
          isLow: sql<boolean>`${stockLevels.quantity} <= ${stockLevels.minQuantity}`,
        })
        .from(stockLevels)
        .innerJoin(variants, eq(variants.id, stockLevels.variantId))
        .innerJoin(products, eq(products.id, variants.productId))
        .where(
          and(
            branchId ? eq(stockLevels.branchId, branchId) : undefined,
            q.variantId ? eq(stockLevels.variantId, q.variantId) : undefined,
            q.lowOnly === 'true' ? lte(stockLevels.quantity, stockLevels.minQuantity) : undefined,
          ),
        )
        .orderBy(products.name, variants.sku),
    );
  }

  /** Kardex paginado por cursor de fecha (estable aunque entren movimientos nuevos). */
  movements(user: AuthUser, q: z.infer<typeof MovementsQuerySchema>) {
    const branchId = q.branchId ?? user.branchId ?? undefined;
    if (branchId) assertBranchAccess(user, branchId);
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select()
        .from(stockMovements)
        .where(
          and(
            q.variantId ? eq(stockMovements.variantId, q.variantId) : undefined,
            branchId ? eq(stockMovements.branchId, branchId) : undefined,
            q.before ? lt(stockMovements.createdAt, new Date(q.before)) : undefined,
          ),
        )
        .orderBy(desc(stockMovements.createdAt))
        .limit(q.limit),
    );
  }
}
