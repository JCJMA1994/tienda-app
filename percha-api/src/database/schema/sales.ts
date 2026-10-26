import { sql } from 'drizzle-orm';
import {
  index,
  integer,
  pgTable,
  text,
  timestamp,
  unique,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk } from './_helpers';
import { variants } from './catalog';
import { cashSessionStatus, paymentMethod, returnDirection, returnKind, saleStatus } from './enums';
import { customers } from './customers';
import { branches, memberships, tenants } from './identity';

/** Turno de caja por sucursal. Solo puede haber uno abierto por sucursal. */
export const cashSessions = pgTable(
  'cash_sessions',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    branchId: uuid('branch_id').notNull(),
    status: cashSessionStatus('status').notNull().default('open'),
    openedBy: uuid('opened_by').notNull(),
    openedAt: createdAt(),
    openingCents: integer('opening_cents').notNull(),
    closedBy: uuid('closed_by'),
    closedAt: timestamp('closed_at', { withTimezone: true }),
    expectedCashCents: integer('expected_cash_cents'),
    countedCashCents: integer('counted_cash_cents'),
    differenceCents: integer('difference_cents'),
  },
  (t) => [
    unique('cash_sessions_tenant_id_uq').on(t.tenantId, t.id),
    tenantFk('cash_sessions_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
    tenantFk('cash_sessions_opener_fk', [t.tenantId, t.openedBy], [memberships.tenantId, memberships.id]),
    // Índice parcial: garantiza en BD una sola caja abierta por sucursal.
    uniqueIndex('cash_sessions_one_open_uq')
      .on(t.tenantId, t.branchId)
      .where(sql`status = 'open'`),
  ],
);

export const sales = pgTable(
  'sales',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    branchId: uuid('branch_id').notNull(),
    cashSessionId: uuid('cash_session_id').notNull(),
    number: integer('number').notNull(),
    sellerId: uuid('seller_id').notNull(),
    /** Cliente identificado (por documento del comprobante o elegido en el POS). */
    customerId: uuid('customer_id'),
    status: saleStatus('status').notNull().default('completed'),
    subtotalCents: integer('subtotal_cents').notNull(),
    discountCents: integer('discount_cents').notNull().default(0),
    /** Parte del descuento que vino de promociones automáticas (el resto es manual). */
    promoDiscountCents: integer('promo_discount_cents').notNull().default(0),
    totalCents: integer('total_cents').notNull(),
    taxCents: integer('tax_cents').notNull(),
    discountApprovedBy: uuid('discount_approved_by'),
    voidedAt: timestamp('voided_at', { withTimezone: true }),
    voidedBy: uuid('voided_by'),
    voidApprovedBy: uuid('void_approved_by'),
    voidReason: text('void_reason'),
    createdAt: createdAt(),
  },
  (t) => [
    unique('sales_tenant_id_uq').on(t.tenantId, t.id),
    unique('sales_tenant_number_uq').on(t.tenantId, t.number),
    tenantFk('sales_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
    tenantFk('sales_session_fk', [t.tenantId, t.cashSessionId], [cashSessions.tenantId, cashSessions.id]),
    tenantFk('sales_seller_fk', [t.tenantId, t.sellerId], [memberships.tenantId, memberships.id]),
    tenantFk('sales_customer_fk', [t.tenantId, t.customerId], [customers.tenantId, customers.id]),
    index('sales_customer_idx').on(t.tenantId, t.customerId, t.createdAt),
    index('sales_tenant_created_idx').on(t.tenantId, t.createdAt),
  ],
);

export const saleItems = pgTable(
  'sale_items',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    saleId: uuid('sale_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    quantity: integer('quantity').notNull(),
    unitPriceCents: integer('unit_price_cents').notNull(),
    /** Parte del descuento del ticket prorrateada a esta línea. */
    discountCents: integer('discount_cents').notNull().default(0),
    /** Parte por promoción y cuál fue (2x1, 20 %…). */
    promoDiscountCents: integer('promo_discount_cents').notNull().default(0),
    promotionId: uuid('promotion_id'),
    lineTotalCents: integer('line_total_cents').notNull(),
    /** Foto del costo al momento de vender: permite calcular margen histórico. */
    unitCostCents: integer('unit_cost_cents').notNull(),
    returnedQuantity: integer('returned_quantity').notNull().default(0),
  },
  (t) => [
    unique('sale_items_tenant_id_uq').on(t.tenantId, t.id),
    tenantFk('sale_items_sale_fk', [t.tenantId, t.saleId], [sales.tenantId, sales.id]),
    tenantFk('sale_items_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
  ],
);

/** Devolución o cambio sobre una venta. */
export const returns = pgTable(
  'returns',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    saleId: uuid('sale_id').notNull(),
    branchId: uuid('branch_id').notNull(),
    cashSessionId: uuid('cash_session_id').notNull(),
    number: integer('number').notNull(),
    kind: returnKind('kind').notNull(),
    returnedCents: integer('returned_cents').notNull(),
    replacementCents: integer('replacement_cents').notNull().default(0),
    /** replacement - returned. Positivo: el cliente paga. Negativo: se le devuelve dinero. */
    differenceCents: integer('difference_cents').notNull(),
    reason: text('reason'),
    createdBy: uuid('created_by').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    unique('returns_tenant_id_uq').on(t.tenantId, t.id),
    unique('returns_tenant_number_uq').on(t.tenantId, t.number),
    tenantFk('returns_sale_fk', [t.tenantId, t.saleId], [sales.tenantId, sales.id]),
    tenantFk('returns_session_fk', [t.tenantId, t.cashSessionId], [cashSessions.tenantId, cashSessions.id]),
  ],
);

export const returnItems = pgTable(
  'return_items',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    returnId: uuid('return_id').notNull(),
    direction: returnDirection('direction').notNull(),
    /** Solo en direction = 'in': la línea original de la venta. */
    saleItemId: uuid('sale_item_id'),
    variantId: uuid('variant_id').notNull(),
    quantity: integer('quantity').notNull(),
    unitPriceCents: integer('unit_price_cents').notNull(),
  },
  (t) => [
    tenantFk('return_items_return_fk', [t.tenantId, t.returnId], [returns.tenantId, returns.id]),
    tenantFk('return_items_sale_item_fk', [t.tenantId, t.saleItemId], [saleItems.tenantId, saleItems.id]),
    tenantFk('return_items_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
  ],
);

/**
 * Pagos de una venta o reembolsos de una devolución (monto negativo).
 * Siempre ligados a la caja para poder calcular el efectivo esperado al cierre.
 */
export const payments = pgTable(
  'payments',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    cashSessionId: uuid('cash_session_id').notNull(),
    saleId: uuid('sale_id'),
    returnId: uuid('return_id'),
    /** Abono de un apartado. */
    layawayId: uuid('layaway_id'),
    /** Vale usado (pago) o vendido (gift card). */
    storeCreditId: uuid('store_credit_id'),
    method: paymentMethod('method').notNull(),
    amountCents: integer('amount_cents').notNull(),
    reference: text('reference'),
    createdAt: createdAt(),
  },
  (t) => [
    tenantFk('payments_session_fk', [t.tenantId, t.cashSessionId], [cashSessions.tenantId, cashSessions.id]),
    tenantFk('payments_sale_fk', [t.tenantId, t.saleId], [sales.tenantId, sales.id]),
    tenantFk('payments_return_fk', [t.tenantId, t.returnId], [returns.tenantId, returns.id]),
    index('payments_session_idx').on(t.cashSessionId),
  ],
);
