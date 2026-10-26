import { sql } from 'drizzle-orm';
import type { Tx } from './database.service';

/**
 * Siguiente correlativo de la tienda (ventas, OC, recepciones...).
 * El UPSERT bloquea la fila hasta el fin de la transacción: dos ventas simultáneas
 * nunca obtienen el mismo número, y si la venta falla el número no se "quema".
 */
export async function nextNumber(tx: Tx, tenantId: string, name: string): Promise<number> {
  const res = await tx.execute<{ value: number }>(sql`
    insert into sequences (tenant_id, name, value) values (${tenantId}, ${name}, 1)
    on conflict (tenant_id, name) do update set value = sequences.value + 1
    returning value`);
  return Number(res.rows[0].value);
}
