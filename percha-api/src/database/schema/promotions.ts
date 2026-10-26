import { boolean, integer, pgEnum, pgTable, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, updatedAt } from './_helpers';
import { tenants } from './identity';

export const promotionKind = pgEnum('promotion_kind', ['percent', 'buy_x_pay_y']);
export const promotionScope = pgEnum('promotion_scope', ['all', 'categories', 'products']);

/**
 * Promociones automáticas: se aplican solas en el POS y en el catálogo en línea.
 *  - percent: X % de descuento (p. ej. liquidación de temporada).
 *  - buy_x_pay_y: lleva X, paga Y (2x1, 3x2): las más baratas del grupo salen gratis.
 */
export const promotions = pgTable(
  'promotions',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    name: text('name').notNull(),
    kind: promotionKind('kind').notNull(),
    percentBp: integer('percent_bp'),
    buyQty: integer('buy_qty'),
    payQty: integer('pay_qty'),
    scope: promotionScope('scope').notNull().default('all'),
    categoryIds: uuid('category_ids').array().notNull().default([]),
    productIds: uuid('product_ids').array().notNull().default([]),
    startsAt: timestamp('starts_at', { withTimezone: true }).notNull(),
    endsAt: timestamp('ends_at', { withTimezone: true }),
    active: boolean('active').notNull().default(true),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [unique('promotions_tenant_id_uq').on(t.tenantId, t.id)],
);
