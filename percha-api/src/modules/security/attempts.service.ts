import { HttpException, HttpStatus, Inject, Injectable, Logger } from '@nestjs/common';
import { eq, sql } from 'drizzle-orm';
import { DatabaseService } from '../../database/database.service';
import { authAttempts } from '../../database/schema';

export interface LockPolicy {
  maxFailures: number;
  lockMinutes: number;
}

/** Contraseña: 5 intentos → 15 min. PIN (4 dígitos = 10 000 combinaciones): 5 intentos → 5 min. */
export const LOGIN_POLICY: LockPolicy = { maxFailures: 5, lockMinutes: 15 };
export const PIN_POLICY: LockPolicy = { maxFailures: 5, lockMinutes: 5 };

/**
 * Bloqueo temporal tras intentos fallidos seguidos (contra fuerza bruta y relleno de
 * credenciales). Complementa el límite por IP: un atacante que rota IPs igual queda frenado
 * por cuenta, y un PIN de 4 dígitos deja de ser adivinable.
 *
 * Se escribe con el pool de sistema en SU PROPIA transacción: aunque la operación que falló
 * haga rollback, el fallo queda contado.
 */
@Injectable()
export class AttemptsService {
  private readonly logger = new Logger('Security');
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  async assertNotLocked(key: string) {
    const [row] = await this.db.withSystem((tx) => tx.select().from(authAttempts).where(eq(authAttempts.key, key)));
    if (row?.lockedUntil && row.lockedUntil > new Date()) {
      const seconds = Math.ceil((row.lockedUntil.getTime() - Date.now()) / 1000);
      throw new HttpException(
        { message: `Demasiados intentos. Vuelve a intentar en ${Math.ceil(seconds / 60)} min.`, code: 'TOO_MANY_ATTEMPTS', retryAfterSeconds: seconds },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  async fail(key: string, policy: LockPolicy) {
    const [row] = await this.db.withSystem((tx) =>
      tx
        .insert(authAttempts)
        .values({ key, failures: 1, lastFailureAt: new Date() })
        .onConflictDoUpdate({
          target: authAttempts.key,
          // Si ya venció un bloqueo anterior, se vuelve a contar desde 1.
          set: {
            failures: sql`case when ${authAttempts.lockedUntil} is not null and ${authAttempts.lockedUntil} < now() then 1 else ${authAttempts.failures} + 1 end`,
            lockedUntil: sql`case when ${authAttempts.lockedUntil} is not null and ${authAttempts.lockedUntil} < now() then null else ${authAttempts.lockedUntil} end`,
            lastFailureAt: new Date(),
          },
        })
        .returning(),
    );
    if (row.failures >= policy.maxFailures && !row.lockedUntil) {
      await this.db.withSystem((tx) =>
        tx.update(authAttempts).set({ lockedUntil: new Date(Date.now() + policy.lockMinutes * 60_000) }).where(eq(authAttempts.key, key)),
      );
      this.logger.warn(`Bloqueo temporal por intentos fallidos: ${key.split(':')[0]}`);
    }
  }

  async reset(key: string) {
    await this.db.withSystem((tx) => tx.delete(authAttempts).where(eq(authAttempts.key, key)));
  }
}
