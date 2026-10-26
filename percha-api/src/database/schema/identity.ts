import { sql } from 'drizzle-orm';
import {
  boolean,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk } from './_helpers';
import { memberStatus, roleEnum, tenantStatus } from './enums';

/**
 * Tienda (tenant). Configuración fiscal y comercial que afecta cálculos en ventas.
 * Montos en céntimos y porcentajes en puntos básicos (1800 = 18%) para evitar floats.
 */
export const tenants = pgTable('tenants', {
  id: id(),
  name: text('name').notNull(),
  ruc: text('ruc'),
  currency: text('currency').notNull().default('PEN'),
  taxRateBp: integer('tax_rate_bp').notNull().default(1800),
  pricesIncludeTax: boolean('prices_include_tax').notNull().default(true),
  /** Descuento máximo que un vendedor aplica sin aprobación (1000 = 10%). */
  discountLimitBp: integer('discount_limit_bp').notNull().default(1000),
  allowNegativeStock: boolean('allow_negative_stock').notNull().default(false),
  /** Zona horaria IANA: define qué es "hoy" en los reportes (una venta a las 23:30 es de ese día). */
  timezone: text('timezone').notNull().default('America/Lima'),
  status: tenantStatus('status').notNull().default('active'),
  onboardingDismissed: boolean('onboarding_dismissed').notNull().default(false),
  createdAt: createdAt(),
});

/** Usuario global: una persona puede pertenecer a varias tiendas (vía memberships). */
export const users = pgTable(
  'users',
  {
    id: id(),
    email: text('email').notNull(),
    name: text('name').notNull(),
    passwordHash: text('password_hash').notNull(),
    /** Secreto TOTP de la verificación en dos pasos, cifrado (AES-256-GCM). */
    totpSecretEnc: text('totp_secret_enc'),
    totpEnabledAt: timestamp('totp_enabled_at', { withTimezone: true }),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('users_email_lower_uq').on(sql`lower(${t.email})`)],
);

export const branches = pgTable(
  'branches',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    name: text('name').notNull(),
    address: text('address'),
    /** Código de ubigeo INEI (6 dígitos): punto de partida/llegada en guías de remisión. */
    ubigeo: text('ubigeo'),
    isDefault: boolean('is_default').notNull().default(false),
    createdAt: createdAt(),
  },
  (t) => [unique('branches_tenant_id_uq').on(t.tenantId, t.id)],
);

/** Pertenencia usuario ↔ tienda con su rol y, opcionalmente, una sucursal fija. */
export const memberships = pgTable(
  'memberships',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    userId: uuid('user_id').notNull().references(() => users.id),
    role: roleEnum('role').notNull(),
    /** null = acceso a todas las sucursales. */
    branchId: uuid('branch_id'),
    pinHash: text('pin_hash'),
    /** Comisión sobre ventas netas sin IGV, en puntos básicos (300 = 3 %). null = sin comisión. */
    commissionBp: integer('commission_bp'),
    status: memberStatus('status').notNull().default('active'),
    createdAt: createdAt(),
  },
  (t) => [
    unique('memberships_tenant_id_uq').on(t.tenantId, t.id),
    unique('memberships_tenant_user_uq').on(t.tenantId, t.userId),
    tenantFk('memberships_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
  ],
);

export const invitations = pgTable(
  'invitations',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    email: text('email').notNull(),
    role: roleEnum('role').notNull(),
    branchId: uuid('branch_id'),
    tokenHash: text('token_hash').notNull().unique(),
    invitedBy: uuid('invited_by').notNull(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    acceptedAt: timestamp('accepted_at', { withTimezone: true }),
    createdAt: createdAt(),
  },
  (t) => [
    tenantFk('invitations_branch_fk', [t.tenantId, t.branchId], [branches.tenantId, branches.id]),
    tenantFk('invitations_inviter_fk', [t.tenantId, t.invitedBy], [memberships.tenantId, memberships.id]),
  ],
);

/**
 * Refresh tokens con rotación. Se guarda solo el hash (SHA-256) del token.
 * Tabla global: solo la toca el pool "system" durante login/refresh/logout.
 */
export const refreshTokens = pgTable(
  'refresh_tokens',
  {
    id: id(),
    userId: uuid('user_id').notNull().references(() => users.id),
    membershipId: uuid('membership_id').notNull().references(() => memberships.id),
    tokenHash: text('token_hash').notNull().unique(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    replacedBy: uuid('replaced_by'),
    createdAt: createdAt(),
  },
  (t) => [index('refresh_tokens_user_idx').on(t.userId)],
);

/** Correlativos por tienda (ventas, OC, recepciones). Se incrementan con UPDATE ... RETURNING. */
export const sequences = pgTable(
  'sequences',
  {
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    name: text('name').notNull(),
    value: integer('value').notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.tenantId, t.name] })],
);

/** Bitácora inmutable de acciones sensibles (anulaciones, ajustes, cambios de rol). */
export const auditLogs = pgTable(
  'audit_logs',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    actorMembershipId: uuid('actor_membership_id'),
    action: text('action').notNull(),
    entity: text('entity').notNull(),
    entityId: uuid('entity_id'),
    data: jsonb('data').$type<Record<string, unknown>>(),
    createdAt: createdAt(),
  },
  (t) => [index('audit_logs_tenant_created_idx').on(t.tenantId, t.createdAt)],
);
