import { BadRequestException, createParamDecorator, ExecutionContext, Global, Inject, Injectable, Module } from '@nestjs/common';
import { and, eq, lt } from 'drizzle-orm';
import { createHash } from 'node:crypto';
import { DatabaseService, Tx } from '../database/database.service';
import { idempotencyKeys } from '../database/schema';
import { DomainError } from './domain-error';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Lee la cabecera `Idempotency-Key` (UUID). Opcional: sin ella la operación no se deduplica. */
export const IdempotencyKey = createParamDecorator((_: unknown, ctx: ExecutionContext): string | undefined => {
  const raw = ctx.switchToHttp().getRequest<{ headers: Record<string, string | undefined> }>().headers['idempotency-key'];
  if (raw === undefined || raw === '') return undefined;
  if (!UUID.test(raw)) throw new BadRequestException({ message: 'Idempotency-Key debe ser un UUID', code: 'INVALID_IDEMPOTENCY_KEY' });
  return raw.toLowerCase();
});

/** JSON con claves ordenadas: el mismo pedido siempre da la misma huella. */
function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value as object)
      .sort()
      .filter((k) => (value as Record<string, unknown>)[k] !== undefined)
      .map((k) => `${JSON.stringify(k)}:${stable((value as Record<string, unknown>)[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

/**
 * Idempotencia DENTRO de la transacción de la operación (no en un interceptor aparte):
 *
 *   begin()    inserta la clave con ON CONFLICT DO NOTHING.
 *              · Si otra petición con la misma clave está en curso, Postgres espera a que
 *                termine: si confirmó, esta ve la clave y responde lo mismo (sin repetir);
 *                si se revirtió, esta sigue y la operación se aplica una vez.
 *   complete() guarda el id del recurso creado, en la misma transacción.
 *
 * Así no existe la ventana "se aplicó pero no se registró la clave" (o al revés).
 * Reusar la clave con OTRO contenido es un error (409), no una repetición.
 */
@Injectable()
export class IdempotencyService {
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  /**
   * Limpieza (cron diario). Se conservan 7 días: más que la antigüedad máxima de una venta sin
   * conexión (72 h), así un reintento tardío sigue reconociéndose.
   */
  async purge(days = 7) {
    const before = new Date(Date.now() - days * 86_400_000);
    const rows = await this.db.withSystem((tx) => tx.delete(idempotencyKeys).where(lt(idempotencyKeys.createdAt, before)).returning({ key: idempotencyKeys.key }));
    return { purged: rows.length };
  }

  /** Devuelve el id del recurso si es una repetición; undefined si hay que ejecutar la operación. */
  async begin(tx: Tx, tenantId: string, key: string | undefined, scope: string, payload: unknown): Promise<string | undefined> {
    if (!key) return undefined;
    const requestHash = createHash('sha256').update(stable(payload)).digest('hex');
    const inserted = await tx.insert(idempotencyKeys).values({ tenantId, key, scope, requestHash }).onConflictDoNothing().returning({ key: idempotencyKeys.key });
    if (inserted.length) return undefined;

    const [prev] = await tx.select().from(idempotencyKeys).where(and(eq(idempotencyKeys.tenantId, tenantId), eq(idempotencyKeys.key, key)));
    if (!prev || prev.scope !== scope || prev.requestHash !== requestHash) {
      throw DomainError.conflict('IDEMPOTENCY_KEY_REUSED', 'Esta clave de idempotencia ya se usó para otra operación');
    }
    if (!prev.resourceId) throw DomainError.conflict('IDEMPOTENCY_IN_PROGRESS', 'La operación todavía se está procesando');
    return prev.resourceId;
  }

  /**
   * Atajo: ejecuta `run` una sola vez por clave (en la transacción dada). En una repetición
   * devuelve `replay(id)` en lugar de volver a aplicar la operación.
   */
  async once<T>(
    tx: Tx,
    tenantId: string,
    key: string | undefined,
    scope: string,
    payload: unknown,
    run: () => Promise<T>,
    idOf: (result: T) => string,
    replay: (resourceId: string) => Promise<T>,
  ): Promise<T> {
    const prev = await this.begin(tx, tenantId, key, scope, payload);
    if (prev) return replay(prev);
    const result = await run();
    await this.complete(tx, tenantId, key, idOf(result));
    return result;
  }

  async complete(tx: Tx, tenantId: string, key: string | undefined, resourceId: string) {
    if (!key) return;
    await tx.update(idempotencyKeys).set({ resourceId }).where(and(eq(idempotencyKeys.tenantId, tenantId), eq(idempotencyKeys.key, key)));
  }
}

@Global()
@Module({ providers: [IdempotencyService], exports: [IdempotencyService] })
export class IdempotencyModule {}
