import { boolean, index, integer, jsonb, pgTable, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk } from './_helpers';
import { memberships, tenants, users } from './identity';
import { sales } from './sales';

/**
 * Notificación para UNA persona de una tienda. Bandeja en la app + push (outbox: `pushedAt`).
 * `link` es una ruta de la app (p. ej. /transfers/…), nunca una URL externa.
 */
export const notifications = pgTable(
  'notifications',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    membershipId: uuid('membership_id').notNull(),
    type: text('type').notNull(),
    title: text('title').notNull(),
    body: text('body').notNull(),
    link: text('link'),
    data: jsonb('data').$type<Record<string, unknown>>(),
    readAt: timestamp('read_at', { withTimezone: true }),
    pushedAt: timestamp('pushed_at', { withTimezone: true }),
    createdAt: createdAt(),
  },
  (t) => [
    tenantFk('notifications_member_fk', [t.tenantId, t.membershipId], [memberships.tenantId, memberships.id]),
    index('notifications_inbox_idx').on(t.tenantId, t.membershipId, t.createdAt),
    index('notifications_push_idx').on(t.pushedAt),
  ],
);

/** Dispositivos para push (token de FCM). Un token pertenece a una sola persona. */
export const deviceTokens = pgTable(
  'device_tokens',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    membershipId: uuid('membership_id').notNull(),
    token: text('token').notNull(),
    platform: text('platform').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    unique('device_tokens_token_uq').on(t.token),
    tenantFk('device_tokens_member_fk', [t.tenantId, t.membershipId], [memberships.tenantId, memberships.id]),
  ],
);

/**
 * Intentos fallidos (contraseña por correo, PIN por sucursal/actor). Tabla de PLATAFORMA:
 * solo la usa el pool de sistema. Bloquea por tiempo tras N fallos seguidos.
 */
export const authAttempts = pgTable('auth_attempts', {
  key: text('key').primaryKey(),
  failures: integer('failures').notNull().default(0),
  lockedUntil: timestamp('locked_until', { withTimezone: true }),
  lastFailureAt: timestamp('last_failure_at', { withTimezone: true }),
});

/** WhatsApp de la TIENDA (cada boutique envía desde su propio número). Token cifrado. */
export const messagingSettings = pgTable('messaging_settings', {
  tenantId: uuid('tenant_id').primaryKey().references(() => tenants.id),
  enabled: boolean('enabled').notNull().default(false),
  provider: text('provider').notNull().default('apachiy'),
  /** Número de la instancia vinculada (código de país + dígitos). */
  instance: text('instance'),
  tokenEnc: text('token_enc'),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});

/**
 * Registro de mensajes enviados. Del destinatario se guarda solo el número enmascarado
 * (datos personales: lo mínimo para soporte y para no reenviar por error).
 */
export const outboundMessages = pgTable(
  'outbound_messages',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    saleId: uuid('sale_id'),
    channel: text('channel').notNull(),
    toMasked: text('to_masked').notNull(),
    toHash: text('to_hash').notNull(),
    /** sent · failed · uncertain (el proveedor no confirmó: puede haber llegado). */
    status: text('status').notNull(),
    providerMessageId: text('provider_message_id'),
    requestId: text('request_id'),
    error: text('error'),
    createdBy: uuid('created_by').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    tenantFk('outbound_messages_sale_fk', [t.tenantId, t.saleId], [sales.tenantId, sales.id]),
    index('outbound_messages_sale_idx').on(t.saleId, t.createdAt),
  ],
);

/** Recuperación de contraseña: token de un solo uso (se guarda su hash), 30 min. */
export const passwordResets = pgTable('password_resets', {
  id: id(),
  userId: uuid('user_id').notNull().references(() => users.id),
  tokenHash: text('token_hash').notNull().unique(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  usedAt: timestamp('used_at', { withTimezone: true }),
  createdAt: createdAt(),
});

/** Códigos de recuperación de la verificación en dos pasos (hash; un solo uso). */
export const recoveryCodes = pgTable(
  'recovery_codes',
  {
    id: id(),
    userId: uuid('user_id').notNull().references(() => users.id),
    codeHash: text('code_hash').notNull(),
    usedAt: timestamp('used_at', { withTimezone: true }),
  },
  (t) => [index('recovery_codes_user_idx').on(t.userId)],
);
