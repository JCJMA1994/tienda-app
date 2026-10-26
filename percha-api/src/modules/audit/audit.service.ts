import { Injectable } from '@nestjs/common';
import type { AuthUser } from '../../common/auth-user';
import type { Tx } from '../../database/database.service';
import { auditLogs } from '../../database/schema';

/**
 * Bitácora de acciones sensibles. Se escribe DENTRO de la misma transacción del cambio:
 * si el cambio se revierte, el registro también (nunca hay auditoría de algo que no pasó).
 */
@Injectable()
export class AuditService {
  async log(
    tx: Tx,
    user: AuthUser,
    action: string,
    entity: string,
    entityId: string | null,
    data?: Record<string, unknown>,
  ) {
    await tx.insert(auditLogs).values({
      tenantId: user.tenantId,
      actorMembershipId: user.membershipId,
      action,
      entity,
      entityId,
      data,
    });
  }
}
