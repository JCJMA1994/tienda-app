import { boolean, date, integer, pgTable, text, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk } from './_helpers';
import { variants } from './catalog';
import { purchaseOrderStatus } from './enums';
import { branches, memberships, tenants } from './identity';

export const suppliers = pgTable(
  'suppliers',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    name: text('name').notNull(),
    ruc: text('ruc'),
    contactName: text('contact_name'),
    phone: text('phone'),
    email: text('email'),
    active: boolean('active').notNull().default(true),
    createdAt: createdAt(),
  },
  (t) => [unique('suppliers_tenant_id_uq').on(t.tenantId, t.id)],
);

export const purchaseOrders = pgTable(
  'purchase_orders',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    number: integer('number').notNull(),
    supplierId: uuid('supplier_id').notNull(),
    branchId: uuid('branch_id').notNull(),
    status: purchaseOrderStatus('status').notNull().default('draft'),
    expectedAt: date('expected_at'),
    notes: text('notes'),
    totalCents: integer('total_cents').notNull().default(0),
    createdBy: uuid('created_by').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    unique('purchase_orders_tenant_id_uq').on(t.tenantId, t.id),
    unique('purchase_orders_tenant_number_uq').on(t.tenantId, t.number),
    tenantFk('po_supplier_fk', [t.tenantId, t.supplierId], [suppliers.tenantId, suppliers.id]),
    tenantFk('po_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
    tenantFk('po_creator_fk', [t.tenantId, t.createdBy], [memberships.tenantId, memberships.id]),
  ],
);

export const purchaseOrderItems = pgTable(
  'purchase_order_items',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    purchaseOrderId: uuid('purchase_order_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    quantityOrdered: integer('quantity_ordered').notNull(),
    quantityReceived: integer('quantity_received').notNull().default(0),
    unitCostCents: integer('unit_cost_cents').notNull(),
  },
  (t) => [
    unique('po_items_tenant_id_uq').on(t.tenantId, t.id),
    unique('po_items_order_variant_uq').on(t.purchaseOrderId, t.variantId),
    tenantFk('po_items_order_fk', [t.tenantId, t.purchaseOrderId], [purchaseOrders.tenantId, purchaseOrders.id]),
    tenantFk('po_items_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
  ],
);

/** Recepción (total o parcial) de una orden de compra. */
export const goodsReceipts = pgTable(
  'goods_receipts',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    number: integer('number').notNull(),
    purchaseOrderId: uuid('purchase_order_id').notNull(),
    branchId: uuid('branch_id').notNull(),
    receivedBy: uuid('received_by').notNull(),
    notes: text('notes'),
    /** Factura del proveedor que respalda la recepción, y su validación en SUNAT. */
    supplierInvoiceSerie: text('supplier_invoice_serie'),
    supplierInvoiceNumber: integer('supplier_invoice_number'),
    supplierInvoiceDate: date('supplier_invoice_date'),
    supplierInvoiceTotalCents: integer('supplier_invoice_total_cents'),
    /** valid · invalid · unverified (servicio no disponible). */
    supplierInvoiceStatus: text('supplier_invoice_status'),
    supplierInvoiceDetail: text('supplier_invoice_detail'),
    createdAt: createdAt(),
  },
  (t) => [
    unique('goods_receipts_tenant_id_uq').on(t.tenantId, t.id),
    unique('goods_receipts_tenant_number_uq').on(t.tenantId, t.number),
    tenantFk('gr_order_fk', [t.tenantId, t.purchaseOrderId], [purchaseOrders.tenantId, purchaseOrders.id]),
    tenantFk('gr_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
  ],
);

export const goodsReceiptItems = pgTable(
  'goods_receipt_items',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    receiptId: uuid('receipt_id').notNull(),
    purchaseOrderItemId: uuid('purchase_order_item_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    quantity: integer('quantity').notNull(),
    unitCostCents: integer('unit_cost_cents').notNull(),
  },
  (t) => [
    tenantFk('gr_items_receipt_fk', [t.tenantId, t.receiptId], [goodsReceipts.tenantId, goodsReceipts.id]),
    tenantFk('gr_items_po_item_fk', [t.tenantId, t.purchaseOrderItemId], [purchaseOrderItems.tenantId, purchaseOrderItems.id]),
    tenantFk('gr_items_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
  ],
);
