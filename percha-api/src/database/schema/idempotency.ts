import { index, pgTable, primaryKey, text, uuid } from 'drizzle-orm/pg-core';
import { createdAt } from './_helpers';
import { tenants } from './identity';

/**
 * Claves de idempotencia: una operación que mueve stock o dinero se aplica UNA sola vez
 * aunque el cliente la reintente (red inestable, POS sin conexión que sincroniza, doble toque).
 * La clave se registra DENTRO de la transacción de la operación: o quedan ambas, o ninguna.
 */
export const idempotencyKeys = pgTable(
  'idempotency_keys',
  {
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    key: uuid('key').notNull(),
    scope: text('scope').notNull(),
    requestHash: text('request_hash').notNull(),
    /** Recurso creado (venta, devolución…), para responder igual al reintento. */
    resourceId: uuid('resource_id'),
    createdAt: createdAt(),
  },
  (t) => [primaryKey({ columns: [t.tenantId, t.key] }), index('idempotency_keys_created_idx').on(t.createdAt)],
);

