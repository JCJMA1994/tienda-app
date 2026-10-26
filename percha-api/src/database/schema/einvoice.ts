import { boolean, index, integer, jsonb, pgEnum, pgTable, primaryKey, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk, updatedAt } from './_helpers';
import { branches, tenants } from './identity';
import { returns, sales } from './sales';

export const einvoiceKind = pgEnum('einvoice_kind', ['boleta', 'factura', 'nota_credito', 'guia_remitente']);
/** Tipos de serie: la nota de crédito usa serie F... o B... según el documento que modifica. */
export const einvoiceSeriesKind = pgEnum('einvoice_series_kind', ['boleta', 'factura', 'nc_boleta', 'nc_factura', 'guia']);
export const einvoiceStatus = pgEnum('einvoice_status', [
  'pending', // numerado y guardado; falta enviarlo al OSE
  'accepted', // aceptado por SUNAT (vía OSE)
  'rejected', // rechazado: hay que corregir y emitir otro (el número ya se usó)
  'error', // no se pudo enviar (red, OSE caído): se reintenta
]);

/** Configuración por tienda. El token del OSE se guarda CIFRADO (AES-256-GCM). */
export const einvoiceSettings = pgTable('einvoice_settings', {
  tenantId: uuid('tenant_id').primaryKey().references(() => tenants.id),
  enabled: boolean('enabled').notNull().default(false),
  provider: text('provider').notNull().default('nubefact'),
  /** Razón social y dirección fiscal tal como figuran en SUNAT (las imprime el OSE). */
  legalName: text('legal_name'),
  fiscalAddress: text('fiscal_address'),
  apiUrl: text('api_url'),
  tokenEnc: text('token_enc'),
  updatedAt: updatedAt(),
});

export const einvoiceSeries = pgTable(
  'einvoice_series',
  {
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    branchId: uuid('branch_id').notNull(),
    kind: einvoiceSeriesKind('kind').notNull(),
    serie: text('serie').notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.tenantId, t.branchId, t.kind] }),
    unique('einvoice_series_tenant_serie_uq').on(t.tenantId, t.serie),
    tenantFk('einvoice_series_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
  ],
);

export type CustomerDocType = 'none' | 'dni' | 'ruc' | 'ce';

/**
 * Comprobante electrónico. `payload` es la FOTO completa del documento al momento de
 * numerarlo (ítems, montos, cliente, referencia): reintentar envía exactamente lo mismo,
 * aunque después cambie el catálogo o la configuración.
 */
export const einvoiceDocuments = pgTable(
  'einvoice_documents',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    branchId: uuid('branch_id').notNull(),
    saleId: uuid('sale_id'),
    returnId: uuid('return_id'),
    /** Guía de remisión de una transferencia entre sucursales. */
    transferId: uuid('transfer_id'),
    /** Para notas de crédito: el comprobante que modifican. */
    referenceId: uuid('reference_id'),
    kind: einvoiceKind('kind').notNull(),
    serie: text('serie').notNull(),
    numero: integer('numero').notNull(),
    customerDocType: text('customer_doc_type').$type<CustomerDocType>().notNull(),
    customerDocNumber: text('customer_doc_number'),
    customerName: text('customer_name'),
    totalCents: integer('total_cents').notNull(),
    status: einvoiceStatus('status').notNull().default('pending'),
    provider: text('provider').notNull(),
    payload: jsonb('payload').notNull(),
    attempts: integer('attempts').notNull().default(0),
    lastError: text('last_error'),
    sunatDescription: text('sunat_description'),
    pdfUrl: text('pdf_url'),
    hash: text('hash'),
    qr: text('qr'),
    sentAt: timestamp('sent_at', { withTimezone: true }),
    createdAt: createdAt(),
  },
  (t) => [
    // SUNAT: serie + número no se repiten jamás.
    unique('einvoice_documents_serie_numero_uq').on(t.tenantId, t.serie, t.numero),
    unique('einvoice_documents_tenant_id_uq').on(t.tenantId, t.id),
    tenantFk('einvoice_documents_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
    tenantFk('einvoice_documents_sale_fk', [t.tenantId, t.saleId], [sales.tenantId, sales.id]),
    tenantFk('einvoice_documents_return_fk', [t.tenantId, t.returnId], [returns.tenantId, returns.id]),
    index('einvoice_documents_transfer_idx').on(t.transferId),
    index('einvoice_documents_status_idx').on(t.status, t.createdAt),
    index('einvoice_documents_sale_idx').on(t.saleId),
  ],
);
