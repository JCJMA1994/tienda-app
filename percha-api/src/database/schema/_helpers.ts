import { foreignKey, timestamp, uuid } from 'drizzle-orm/pg-core';
import type { AnyPgColumn } from 'drizzle-orm/pg-core';

/** Clave primaria UUID generada por Postgres (gen_random_uuid, nativo desde PG13). */
export const id = () => uuid('id').primaryKey().defaultRandom();

export const createdAt = () =>
  timestamp('created_at', { withTimezone: true }).notNull().defaultNow();
export const updatedAt = () =>
  timestamp('updated_at', { withTimezone: true }).notNull().defaultNow();

/**
 * FK compuesta (tenant_id, x_id) -> padre(tenant_id, id).
 *
 * Por qué: las verificaciones de FK en Postgres NO pasan por RLS. Con una FK simple
 * (x_id -> padre.id) alguien podría insertar una fila que apunte a un registro de otra
 * tienda si conoce su UUID. Incluir tenant_id en la FK lo hace imposible a nivel de BD.
 */
export function tenantFk(
  name: string,
  columns: [AnyPgColumn, AnyPgColumn],
  parent: [AnyPgColumn, AnyPgColumn],
) {
  return foreignKey({ name, columns, foreignColumns: parent });
}
