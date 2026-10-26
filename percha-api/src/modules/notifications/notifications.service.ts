import { Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { and, desc, eq, inArray, isNull, lt, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { DatabaseService, Tx } from '../../database/database.service';
import { deviceTokens, memberships, notifications } from '../../database/schema';
import { hasPermission, Permission } from '../../common/authz/permissions';
import { PUSH_SENDER, PushSender } from './push';

export const ListNotificationsSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(30),
  before: z.string().datetime().optional(),
});

export const RegisterDeviceSchema = z.object({
  token: z.string().min(20).max(4096),
  platform: z.enum(['android', 'ios', 'web']),
});

export type NotificationType =
  | 'transfer.incoming'
  | 'stock.low'
  | 'einvoice.rejected'
  | 'billing.past_due'
  | 'billing.suspended'
  | 'team.joined'
  | 'layaway.expired'
  | 'catalog.order';

export interface NotifyInput {
  tenantId: string;
  type: NotificationType;
  title: string;
  body: string;
  link?: string;
  data?: Record<string, unknown>;
  /** Destinatarios: quienes tengan este permiso... */
  permission: Permission;
  /** ...y acceso a esta sucursal (null = cualquiera). */
  branchId?: string | null;
  /** No notificar a quien hizo la acción. */
  exceptMembershipId?: string;
}

/**
 * Notificaciones por ROL y SUCURSAL: "a quien puede actuar sobre esto". Se crean dentro de la
 * misma transacción del evento (si el evento se revierte, no hay aviso de algo que no pasó).
 * El push se envía después con un job (outbox `pushedAt`).
 *
 * Se agrupan avisos repetidos: no se crea un "stock bajo" igual si ya hay uno sin leer.
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger('Notifications');

  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(PUSH_SENDER) private readonly push: PushSender,
  ) {}

  async notify(tx: Tx, n: NotifyInput) {
    const members = await tx
      .select({ id: memberships.id, role: memberships.role, branchId: memberships.branchId })
      .from(memberships)
      .where(and(eq(memberships.tenantId, n.tenantId), eq(memberships.status, 'active')));
    const recipients = members.filter(
      (m) =>
        hasPermission(m.role, n.permission) &&
        m.id !== n.exceptMembershipId &&
        (!n.branchId || !m.branchId || m.branchId === n.branchId),
    );
    if (!recipients.length) return 0;

    // Antiruido: el mismo aviso (tipo + enlace + título) sin leer → no se duplica.
    const pending = n.link
      ? await tx
          .select({ membershipId: notifications.membershipId })
          .from(notifications)
          .where(and(eq(notifications.tenantId, n.tenantId), eq(notifications.type, n.type), eq(notifications.link, n.link), eq(notifications.title, n.title.slice(0, 120)), isNull(notifications.readAt)))
      : [];
    const skip = new Set(pending.map((p) => p.membershipId));
    const rows = recipients
      .filter((r) => !skip.has(r.id))
      .map((r) => ({ tenantId: n.tenantId, membershipId: r.id, type: n.type, title: n.title.slice(0, 120), body: n.body.slice(0, 300), link: n.link, data: n.data }));
    if (rows.length) await tx.insert(notifications).values(rows);
    return rows.length;
  }

  list(user: AuthUser, q: z.infer<typeof ListNotificationsSchema>) {
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select({
          id: notifications.id,
          type: notifications.type,
          title: notifications.title,
          body: notifications.body,
          link: notifications.link,
          readAt: notifications.readAt,
          createdAt: notifications.createdAt,
        })
        .from(notifications)
        .where(and(eq(notifications.membershipId, user.membershipId), q.before ? lt(notifications.createdAt, new Date(q.before)) : undefined))
        .orderBy(desc(notifications.createdAt))
        .limit(q.limit),
    );
  }

  unreadCount(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [{ c }] = await tx
        .select({ c: sql<number>`count(*)::int` })
        .from(notifications)
        .where(and(eq(notifications.membershipId, user.membershipId), isNull(notifications.readAt)));
      return { unread: c };
    });
  }

  /** Solo el destinatario puede marcarla (además de RLS por tienda). */
  markRead(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const rows = await tx
        .update(notifications)
        .set({ readAt: new Date() })
        .where(and(eq(notifications.id, id), eq(notifications.membershipId, user.membershipId), isNull(notifications.readAt)))
        .returning({ id: notifications.id });
      if (!rows.length) {
        const [exists] = await tx.select({ id: notifications.id }).from(notifications).where(and(eq(notifications.id, id), eq(notifications.membershipId, user.membershipId)));
        if (!exists) throw new NotFoundException('Notificación no encontrada');
      }
      return { ok: true };
    });
  }

  markAllRead(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const rows = await tx
        .update(notifications)
        .set({ readAt: new Date() })
        .where(and(eq(notifications.membershipId, user.membershipId), isNull(notifications.readAt)))
        .returning({ id: notifications.id });
      return { marked: rows.length };
    });
  }

  registerDevice(user: AuthUser, input: z.infer<typeof RegisterDeviceSchema>) {
    return this.db.withSystem(async (tx) => {
      // Un token pasa a ser de la persona que inició sesión por última vez en ese dispositivo
      // (tablet compartida del POS): nadie recibe avisos de otro usuario.
      await tx.delete(deviceTokens).where(eq(deviceTokens.token, input.token));
      await tx.insert(deviceTokens).values({ tenantId: user.tenantId, membershipId: user.membershipId, ...input });
      return { ok: true };
    });
  }

  unregisterDevice(user: AuthUser, token: string) {
    return this.db.withSystem((tx) => tx.delete(deviceTokens).where(and(eq(deviceTokens.token, token), eq(deviceTokens.membershipId, user.membershipId))));
  }

  /** Job: envía por push las notificaciones nuevas (máx. 500 por corrida). */
  async dispatchPush() {
    return this.db.withSystem(async (tx) => {
      const pending = await tx
        .select()
        .from(notifications)
        .where(and(isNull(notifications.pushedAt), isNull(notifications.readAt)))
        .orderBy(notifications.createdAt)
        .limit(500)
        .for('update', { skipLocked: true });
      if (!pending.length) return { sent: 0 };
      const devices = await tx.select().from(deviceTokens).where(inArray(deviceTokens.membershipId, [...new Set(pending.map((p) => p.membershipId))]));
      const messages = pending.flatMap((n) => devices.filter((d) => d.membershipId === n.membershipId).map((d) => ({ token: d.token, title: n.title, body: n.body, link: n.link })));
      try {
        const { invalidTokens } = await this.push.send(messages);
        if (invalidTokens.length) await tx.delete(deviceTokens).where(inArray(deviceTokens.token, invalidTokens));
      } catch (e) {
        this.logger.warn(`Push falló: ${e instanceof Error ? e.message : e}`);
        return { sent: 0 };
      }
      await tx.update(notifications).set({ pushedAt: new Date() }).where(inArray(notifications.id, pending.map((p) => p.id)));
      return { sent: messages.length };
    });
  }
}

