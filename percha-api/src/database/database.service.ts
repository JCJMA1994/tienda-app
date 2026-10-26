import { Inject, Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { sql } from 'drizzle-orm';
import { drizzle, NodePgDatabase } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import { ENV, Env } from '../config/env';
import * as schema from './schema';

export type Db = NodePgDatabase<typeof schema>;
export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];

/**
 * Punto único de acceso a Postgres.
 *
 * - `withTenant`: TODA operación de negocio pasa por aquí. Abre una transacción con el rol
 *   percha_app y fija `app.tenant_id` con `set_config(..., true)` (local a la transacción),
 *   así las políticas RLS filtran por tienda aunque el código olvide un WHERE.
 *   Al ser local, la variable desaparece al terminar y no contamina la conexión del pool.
 * - `withSystem`: rol percha_system (omite RLS). Uso restringido a autenticación/registro.
 */
@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly appPool: Pool;
  private readonly systemPool: Pool;
  private readonly app: Db;
  private readonly system: Db;

  constructor(@Inject(ENV) env: Env) {
    this.appPool = new Pool({ connectionString: env.DATABASE_APP_URL, max: 10 });
    this.systemPool = new Pool({ connectionString: env.DATABASE_SYSTEM_URL, max: 3 });
    this.app = drizzle(this.appPool, { schema });
    this.system = drizzle(this.systemPool, { schema });
  }

  /** Tareas a ejecutar después del COMMIT de cada transacción abierta. */
  private readonly pending = new WeakMap<Tx, (() => Promise<unknown>)[]>();
  private readonly logger = new Logger('Database');

  withTenant<T>(tenantId: string, fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.run(this.app, async (tx) => {
      await tx.execute(sql`select set_config('app.tenant_id', ${tenantId}, true)`);
      return fn(tx);
    });
  }

  withSystem<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.run(this.system, fn);
  }

  /**
   * Programa algo para DESPUÉS de que la transacción se confirme (p. ej. enviar un comprobante
   * al OSE). Si la transacción se revierte, no se ejecuta: nunca se envía algo que no existe.
   * Se esperan en orden; un fallo se registra y no afecta a lo ya confirmado.
   */
  afterCommit(tx: Tx, task: () => Promise<unknown>) {
    const list = this.pending.get(tx);
    if (!list) throw new Error('afterCommit fuera de una transacción de DatabaseService');
    list.push(task);
  }

  private async run<T>(db: Db, fn: (tx: Tx) => Promise<T>): Promise<T> {
    let tasks: (() => Promise<unknown>)[] = [];
    const result = await db.transaction(async (tx) => {
      tasks = [];
      this.pending.set(tx, tasks);
      return fn(tx);
    });
    for (const task of tasks) {
      await task().catch((e) => this.logger.error(`Tarea posterior al commit falló: ${e instanceof Error ? e.message : e}`));
    }
    return result;
  }

  async onModuleDestroy() {
    await Promise.all([this.appPool.end(), this.systemPool.end()]);
  }
}
