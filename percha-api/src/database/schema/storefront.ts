import { boolean, index, integer, pgEnum, pgTable, text, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk, updatedAt } from './_helpers';
import { variants } from './catalog';
import { customers } from './customers';
import { tenants } from './identity';

export const catalogOrderStatus = pgEnum('catalog_order_status', ['new', 'contacted', 'completed', 'cancelled']);

/**
 * Catálogo público de la tienda (enlace para WhatsApp / Instagram). El `slug` es la parte
 * pública de la URL; nunca se expone el id interno de la tienda.
 */
export const catalogSettings = pgTable('catalog_settings', {
  tenantId: uuid('tenant_id').primaryKey().references(() => tenants.id),
  enabled: boolean('enabled').notNull().default(false),
  slug: text('slug').notNull().unique(),
  /** Número de WhatsApp para pedidos (código de país + dígitos). */
  whatsapp: text('whatsapp'),
  /** Sucursal cuyo stock se muestra (null = suma de todas). */
  branchId: uuid('branch_id'),
  description: text('description'),
  updatedAt: updatedAt(),
});

/**
 * Pedido desde el catálogo: una INTENCIÓN de compra, no una venta. No reserva stock; la
 * tienda contacta al cliente y lo convierte en apartado o venta.
 */
export const catalogOrders = pgTable(
  'catalog_orders',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    number: integer('number').notNull(),
    status: catalogOrderStatus('status').notNull().default('new'),
    customerName: text('customer_name').notNull(),
    customerPhone: text('customer_phone').notNull(),
    note: text('note'),
    totalCents: integer('total_cents').notNull(),
    customerId: uuid('customer_id'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    unique('catalog_orders_tenant_id_uq').on(t.tenantId, t.id),
    unique('catalog_orders_tenant_number_uq').on(t.tenantId, t.number),
    tenantFk('catalog_orders_customer_fk', [t.tenantId, t.customerId], [customers.tenantId, customers.id]),
    index('catalog_orders_status_idx').on(t.tenantId, t.status, t.createdAt),
  ],
);

export const catalogOrderItems = pgTable(
  'catalog_order_items',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    orderId: uuid('order_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    quantity: integer('quantity').notNull(),
    /** Precio mostrado al pedir (referencial: el precio real se fija al vender). */
    unitPriceCents: integer('unit_price_cents').notNull(),
  },
  (t) => [
    tenantFk('catalog_order_items_order_fk', [t.tenantId, t.orderId], [catalogOrders.tenantId, catalogOrders.id]),
    tenantFk('catalog_order_items_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
  ],
);

