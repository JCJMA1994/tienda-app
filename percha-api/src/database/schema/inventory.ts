import { index, integer, pgTable, primaryKey, text, timestamp, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk } from './_helpers';
import { variants } from './catalog';
import { movementType } from './enums';
import { branches, tenants } from './identity';

/**
 * Stock actual por sucursal y variante. Es una PROYECCIÓN del kardex:
 * nunca se edita directamente, solo lo actualiza InventoryService al registrar movimientos.
 */
export const stockLevels = pgTable(
  'stock_levels',
  {
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    branchId: uuid('branch_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    quantity: integer('quantity').notNull().default(0),
    minQuantity: integer('min_quantity').notNull().default(0),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    primaryKey({ columns: [t.tenantId, t.branchId, t.variantId] }),
    tenantFk('stock_levels_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
    tenantFk('stock_levels_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
  ],
);

/** Kardex: registro inmutable (append-only) de cada entrada y salida. */
export const stockMovements = pgTable(
  'stock_movements',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    branchId: uuid('branch_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    type: movementType('type').notNull(),
    /** Con signo: positivo entra, negativo sale. */
    quantity: integer('quantity').notNull(),
    unitCostCents: integer('unit_cost_cents'),
    /** Saldo de la variante en la sucursal después del movimiento. */
    balanceAfter: integer('balance_after').notNull(),
    referenceType: text('reference_type'),
    referenceId: uuid('reference_id'),
    reason: text('reason'),
    actorMembershipId: uuid('actor_membership_id'),
    createdAt: createdAt(),
  },
  (t) => [
    tenantFk('stock_movements_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
    tenantFk('stock_movements_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
    index('stock_movements_variant_idx').on(t.tenantId, t.variantId, t.createdAt),
    index('stock_movements_ref_idx').on(t.referenceType, t.referenceId),
    // Reportes por rango de fechas (ventas netas, costo de lo vendido, rotación).
    index('stock_movements_tenant_created_idx').on(t.tenantId, t.createdAt),
  ],
);
