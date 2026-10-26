import { boolean, index, pgTable, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, updatedAt } from './_helpers';
import { tenants } from './identity';

/**
 * Clientes de la tienda. Datos personales (Ley 29733): solo lo útil para atenderlos y emitir
 * comprobantes; el permiso para escribirles por WhatsApp se registra explícitamente; y se pueden
 * anonimizar a pedido (las ventas se conservan, sin datos personales).
 */
export const customers = pgTable(
  'customers',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    /** dni · ruc · ce · null (sin documento) */
    docType: text('doc_type'),
    docNumber: text('doc_number'),
    name: text('name').notNull(),
    phone: text('phone'),
    email: text('email'),
    /** Cumpleaños sin año (MM-DD): basta para saludar y no expone la edad. */
    birthday: text('birthday'),
    notes: text('notes'),
    whatsappOptIn: boolean('whatsapp_opt_in').notNull().default(false),
    whatsappOptInAt: timestamp('whatsapp_opt_in_at', { withTimezone: true }),
    anonymizedAt: timestamp('anonymized_at', { withTimezone: true }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    unique('customers_tenant_id_uq').on(t.tenantId, t.id),
    // Un documento = un cliente por tienda (NULLs no chocan entre sí).
    unique('customers_tenant_doc_uq').on(t.tenantId, t.docType, t.docNumber),
    index('customers_tenant_name_idx').on(t.tenantId, t.name),
    index('customers_tenant_phone_idx').on(t.tenantId, t.phone),
  ],
);

