import { index, integer, pgEnum, pgTable, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk } from './_helpers';
import { variants } from './catalog';
import { branches, tenants } from './identity';

export const stockCountStatus = pgEnum('stock_count_status', ['open', 'applied', 'cancelled']);

/**
 * Conteo de inventario guiado: se escanea prenda por prenda y al final se aplican las
 * diferencias como ajustes. Puede hacerse con la tienda abierta: ver `stockAtFirstScan`.
 */
export const stockCounts = pgTable(
  'stock_counts',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    branchId: uuid('branch_id').notNull(),
    number: integer('number').notNull(),
    status: stockCountStatus('status').notNull().default('open'),
    note: text('note'),
    createdBy: uuid('created_by').notNull(),
    createdAt: createdAt(),
    appliedAt: timestamp('applied_at', { withTimezone: true }),
    appliedBy: uuid('applied_by'),
  },
  (t) => [
    unique('stock_counts_tenant_id_uq').on(t.tenantId, t.id),
    unique('stock_counts_tenant_number_uq').on(t.tenantId, t.number),
    tenantFk('stock_counts_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
  ],
);

export const stockCountItems = pgTable(
  'stock_count_items',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    countId: uuid('count_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    counted: integer('counted').notNull(),
    /**
     * Stock del sistema cuando se contó esa prenda por primera vez. Al aplicar, la diferencia
     * es `counted − stockAtFirstScan`: lo que se vendió DESPUÉS de contarla no se toma como
     * faltante (se puede contar sin cerrar la tienda).
     */
    stockAtFirstScan: integer('stock_at_first_scan').notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    unique('stock_count_items_count_variant_uq').on(t.countId, t.variantId),
    tenantFk('stock_count_items_count_fk', [t.tenantId, t.countId], [stockCounts.tenantId, stockCounts.id]),
    tenantFk('stock_count_items_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
    index('stock_count_items_count_idx').on(t.countId),
  ],
);
