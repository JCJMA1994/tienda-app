import { check, index, integer, pgEnum, pgTable, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
import { createdAt, id, tenantFk } from './_helpers';
import { variants } from './catalog';
import { customers } from './customers';
import { branches, memberships, tenants } from './identity';
import { sales } from './sales';

export const storeCreditKind = pgEnum('store_credit_kind', ['refund', 'gift', 'courtesy']);
export const layawayStatus = pgEnum('layaway_status', ['open', 'completed', 'cancelled']);

/**
 * Vale / saldo a favor. El código es un título al portador: se guarda solo su hash (y los 4
 * últimos caracteres para reconocerlo). El saldo nunca baja de 0 (CHECK + UPDATE condicional).
 */
export const storeCredits = pgTable(
  'store_credits',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    codeHash: text('code_hash').notNull(),
    codeLast4: text('code_last4').notNull(),
    kind: storeCreditKind('kind').notNull(),
    customerId: uuid('customer_id'),
    initialCents: integer('initial_cents').notNull(),
    balanceCents: integer('balance_cents').notNull(),
    expiresAt: timestamp('expires_at', { withTimezone: true }),
    note: text('note'),
    issuedBy: uuid('issued_by').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    unique('store_credits_tenant_id_uq').on(t.tenantId, t.id),
    unique('store_credits_code_uq').on(t.codeHash),
    check('store_credits_balance_ck', sql`${t.balanceCents} >= 0 and ${t.balanceCents} <= ${t.initialCents}`),
    tenantFk('store_credits_customer_fk', [t.tenantId, t.customerId], [customers.tenantId, customers.id]),
    tenantFk('store_credits_issuer_fk', [t.tenantId, t.issuedBy], [memberships.tenantId, memberships.id]),
    index('store_credits_customer_idx').on(t.tenantId, t.customerId),
  ],
);

/** Movimientos del vale (inmutables, como el kardex): emisión, uso, devolución por anulación. */
export const storeCreditMovements = pgTable(
  'store_credit_movements',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    creditId: uuid('credit_id').notNull(),
    type: text('type').notNull(),
    deltaCents: integer('delta_cents').notNull(),
    balanceAfter: integer('balance_after').notNull(),
    saleId: uuid('sale_id'),
    createdBy: uuid('created_by').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    tenantFk('store_credit_movements_credit_fk', [t.tenantId, t.creditId], [storeCredits.tenantId, storeCredits.id]),
    index('store_credit_movements_credit_idx').on(t.creditId, t.createdAt),
  ],
);

/**
 * Apartado (separado): el cliente deja un adelanto y las prendas quedan reservadas hasta una
 * fecha. Los abonos son pagos de caja (`payments.layaway_id`). Al entregar se registra la venta.
 */
export const layaways = pgTable(
  'layaways',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    number: integer('number').notNull(),
    branchId: uuid('branch_id').notNull(),
    customerId: uuid('customer_id').notNull(),
    status: layawayStatus('status').notNull().default('open'),
    totalCents: integer('total_cents').notNull(),
    paidCents: integer('paid_cents').notNull().default(0),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    notes: text('notes'),
    createdBy: uuid('created_by').notNull(),
    saleId: uuid('sale_id'),
    closedAt: timestamp('closed_at', { withTimezone: true }),
    closeReason: text('close_reason'),
    createdAt: createdAt(),
  },
  (t) => [
    unique('layaways_tenant_id_uq').on(t.tenantId, t.id),
    unique('layaways_tenant_number_uq').on(t.tenantId, t.number),
    check('layaways_paid_ck', sql`${t.paidCents} >= 0 and ${t.paidCents} <= ${t.totalCents}`),
    tenantFk('layaways_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
    tenantFk('layaways_customer_fk', [t.tenantId, t.customerId], [customers.tenantId, customers.id]),
    tenantFk('layaways_sale_fk', [t.tenantId, t.saleId], [sales.tenantId, sales.id]),
    index('layaways_status_idx').on(t.tenantId, t.status, t.expiresAt),
  ],
);

export const layawayItems = pgTable(
  'layaway_items',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    layawayId: uuid('layaway_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    quantity: integer('quantity').notNull(),
    /** Precio congelado al apartar: si luego sube, al cliente se le respeta. */
    unitPriceCents: integer('unit_price_cents').notNull(),
  },
  (t) => [
    tenantFk('layaway_items_layaway_fk', [t.tenantId, t.layawayId], [layaways.tenantId, layaways.id]),
    tenantFk('layaway_items_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
  ],
);
