import { ForbiddenException, Inject, Injectable } from '@nestjs/common';
import { and, eq, isNotNull, isNull, or } from 'drizzle-orm';
import type { AuthUser } from '../../common/auth-user';
import type { Tx } from '../../database/database.service';
import { memberships } from '../../database/schema';
import { verifySecret } from '../../common/crypto';
import { AttemptsService, PIN_POLICY } from '../security/attempts.service';
import { hasPermission, Permission } from '../../common/authz/permissions';

/**
 * Aprobaciones en mostrador ("Con aprobación" en la matriz de roles).
 * Si quien opera no tiene el permiso, un supervisor de la misma sucursal ingresa su PIN
 * en la tablet. Devuelve quién aprobó, para guardarlo en la venta y en auditoría.
 */
@Injectable()
export class ApprovalService {
  constructor(@Inject(AttemptsService) private readonly attempts: AttemptsService) {}

  async authorize(
    tx: Tx,
    actor: AuthUser,
    branchId: string,
    permission: Permission,
    approverPin?: string,
  ): Promise<{ approvedBy: string | null }> {
    if (hasPermission(actor.role, permission)) return { approvedBy: null };
    if (!approverPin) {
      throw new ForbiddenException({ message: 'Requiere aprobación de un supervisor', code: 'APPROVAL_REQUIRED', permission });
    }
    // Quien intenta adivinar el PIN de un supervisor queda bloqueado unos minutos.
    const key = `approve:${actor.membershipId}`;
    await this.attempts.assertNotLocked(key);
    const candidates = await tx
      .select()
      .from(memberships)
      .where(
        and(
          eq(memberships.status, 'active'),
          isNotNull(memberships.pinHash),
          or(isNull(memberships.branchId), eq(memberships.branchId, branchId)),
        ),
      );
    for (const m of candidates) {
      if (m.id === actor.membershipId || !hasPermission(m.role, permission)) continue;
      if (await verifySecret(m.pinHash!, approverPin)) {
        await this.attempts.reset(key);
        return { approvedBy: m.id };
      }
    }
    await this.attempts.fail(key, PIN_POLICY);
    throw new ForbiddenException({ message: 'PIN de aprobación inválido', code: 'APPROVAL_INVALID' });
  }
}
