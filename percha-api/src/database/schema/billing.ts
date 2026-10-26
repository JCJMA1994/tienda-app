import { boolean, index, integer, jsonb, pgEnum, pgTable, serial, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
import { createdAt, id, updatedAt } from './_helpers';
import { tenants, users } from './identity';

export const subscriptionStatus = pgEnum('subscription_status', [
  'trialing', // periodo de prueba
  'active', // al día
  'past_due', // venció el periodo sin pago: periodo de gracia, todo sigue funcionando
  'suspended', // terminó la gracia: solo lectura (bloqueo suave)
  'canceled', // cancelada por el dueño al final del periodo
]);
export const invoiceStatus = pgEnum('invoice_status', ['open', 'paid', 'void']);
export const billingProvider = pgEnum('billing_provider', ['culqi', 'stripe', 'manual', 'fake']);

export type PlanLimits = { branches: number | null; members: number | null; products: number | null };

/** Catálogo de planes de la plataforma (no pertenece a ninguna tienda). */
export const plans = pgTable('plans', {
  id: id(),
  code: text('code').notNull().unique(),
  name: text('name').notNull(),
  priceCents: integer('price_cents').notNull(),
  currency: text('currency').notNull().default('PEN'),
  /** null en un límite = ilimitado. */
  limits: jsonb('limits').$type<PlanLimits>().notNull(),
  position: integer('position').notNull().default(0),
  active: boolean('active').notNull().default(true),
  createdAt: createdAt(),
});

/** Una suscripción por tienda. Nuestra BD es la fuente de verdad, no la pasarela. */
export const subscriptions = pgTable('subscriptions', {
  tenantId: uuid('tenant_id').primaryKey().references(() => tenants.id),
  planId: uuid('plan_id').notNull().references(() => plans.id),
  status: subscriptionStatus('status').notNull(),
  trialEndsAt: timestamp('trial_ends_at', { withTimezone: true }),
  currentPeriodStart: timestamp('current_period_start', { withTimezone: true }).notNull(),
  currentPeriodEnd: timestamp('current_period_end', { withTimezone: true }).notNull(),
  cancelAtPeriodEnd: boolean('cancel_at_period_end').notNull().default(false),
  /** Cobro automático con tarjeta guardada (Culqi). Yape/Plin no permiten débito automático. */
  autopay: boolean('autopay').notNull().default(false),
  providerCustomerId: text('provider_customer_id'),
  providerCardId: text('provider_card_id'),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

export const invoices = pgTable(
  'invoices',
  {
    id: id(),
    number: serial('number').notNull().unique(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    planId: uuid('plan_id').notNull().references(() => plans.id),
    periodStart: timestamp('period_start', { withTimezone: true }).notNull(),
    periodEnd: timestamp('period_end', { withTimezone: true }).notNull(),
    amountCents: integer('amount_cents').notNull(),
    currency: text('currency').notNull(),
    status: invoiceStatus('status').notNull().default('open'),
    dueAt: timestamp('due_at', { withTimezone: true }).notNull(),
    paidAt: timestamp('paid_at', { withTimezone: true }),
    provider: billingProvider('provider'),
    /** Id de la orden/cargo/sesión en la pasarela. */
    providerRef: text('provider_ref'),
    method: text('method'),
    createdAt: createdAt(),
  },
  (t) => [
    // Nunca dos facturas para el mismo periodo de una tienda (el job puede correr dos veces).
    unique('invoices_tenant_period_uq').on(t.tenantId, t.periodStart),
    index('invoices_provider_ref_idx').on(t.providerRef),
  ],
);

/** Webhooks recibidos: el id del evento es único, así procesar dos veces el mismo es inocuo. */
export const paymentEvents = pgTable(
  'payment_events',
  {
    id: id(),
    provider: billingProvider('provider').notNull(),
    eventId: text('event_id').notNull(),
    type: text('type').notNull(),
    payload: jsonb('payload').notNull(),
    receivedAt: createdAt(),
  },
  (t) => [unique('payment_events_provider_event_uq').on(t.provider, t.eventId)],
);

/** Superadmins de la plataforma (tú). Se agregan con scripts/make-admin.mjs. */
export const platformAdmins = pgTable('platform_admins', {
  userId: uuid('user_id').primaryKey().references(() => users.id),
  createdAt: createdAt(),
});
