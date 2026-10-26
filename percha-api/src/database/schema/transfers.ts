import { index, integer, jsonb, pgTable, primaryKey, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk } from './_helpers';
import { variants } from './catalog';
import { transferStatus } from './enums';
import { branches, memberships, tenants } from './identity';

/**
 * Transferencia entre sucursales. Al ENVIAR sale el stock del origen y queda en tránsito;
 * al RECIBIR entra en el destino lo que realmente llegó. La diferencia queda registrada.
 */
export const transfers = pgTable(
  'transfers',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    number: integer('number').notNull(),
    fromBranchId: uuid('from_branch_id').notNull(),
    toBranchId: uuid('to_branch_id').notNull(),
    status: transferStatus('status').notNull().default('in_transit'),
    notes: text('notes'),
    sentBy: uuid('sent_by').notNull(),
    sentAt: createdAt(),
    receivedBy: uuid('received_by'),
    receivedAt: timestamp('received_at', { withTimezone: true }),
    receiveNotes: text('receive_notes'),
  },
  (t) => [
    unique('transfers_tenant_id_uq').on(t.tenantId, t.id),
    unique('transfers_tenant_number_uq').on(t.tenantId, t.number),
    tenantFk('transfers_from_fk', [t.tenantId, t.fromBranchId], [branches.tenantId, branches.id]),
    tenantFk('transfers_to_fk', [t.tenantId, t.toBranchId], [branches.tenantId, branches.id]),
    tenantFk('transfers_sender_fk', [t.tenantId, t.sentBy], [memberships.tenantId, memberships.id]),
    index('transfers_status_idx').on(t.tenantId, t.status),
  ],
);

export const transferItems = pgTable(
  'transfer_items',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    transferId: uuid('transfer_id').notNull(),
    variantId: uuid('variant_id').notNull(),
    quantitySent: integer('quantity_sent').notNull(),
    quantityReceived: integer('quantity_received'),
    unitCostCents: integer('unit_cost_cents').notNull(),
  },
  (t) => [
    unique('transfer_items_transfer_variant_uq').on(t.transferId, t.variantId),
    tenantFk('transfer_items_transfer_fk', [t.tenantId, t.transferId], [transfers.tenantId, transfers.id]),
    tenantFk('transfer_items_variant_fk', [t.tenantId, t.variantId], [variants.tenantId, variants.id]),
  ],
);

/**
 * Caché GLOBAL de consultas RUC/DNI (plataforma, no por tienda): cada consulta externa cuesta.
 * Solo se guarda lo necesario para el comprobante (nombre, dirección, estado), con fecha.
 */
export const identityCache = pgTable(
  'identity_cache',
  {
    docType: text('doc_type').notNull(),
    docNumber: text('doc_number').notNull(),
    data: jsonb('data').notNull(),
    fetchedAt: timestamp('fetched_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.docType, t.docNumber] })],
);

/**
 * Padrón reducido del RUC (SUNAT, gratuito, se publica a diario). Tabla de la PLATAFORMA:
 * se carga con scripts/import-padron.mjs y la consulta el pool de sistema.
 */
export const sunatPadron = pgTable('sunat_padron', {
  ruc: text('ruc').primaryKey(),
  name: text('name').notNull(),
  status: text('status'),
  condition: text('condition'),
  ubigeo: text('ubigeo'),
  address: text('address'),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});
