import {
  BadRequestException,
  ConflictException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { and, asc, desc, eq, inArray, lte, or, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { ENV, Env } from '../../config/env';
import { DatabaseService, Tx } from '../../database/database.service';
import { auditLogs, branches, invoices, memberships, paymentEvents, plans, subscriptions, users } from '../../database/schema';
import { EventBus } from '../../common/events';
import { LimitedResource, LimitsService } from './limits.service';
import { PAYMENT_PROVIDERS, PaymentProvider, ProviderName } from './providers/provider';

export const PaySchema = z.object({
  provider: z.enum(['culqi', 'stripe', 'fake']),
  method: z.enum(['card', 'yape', 'wallet_qr']),
});
export const ChangePlanSchema = z.object({ planCode: z.string().min(2) });
export const SaveCardSchema = z.object({
  /** Token de Culqi.js (la tarjeta nunca pasa por nuestro servidor). */
  token: z.string().min(5),
  phone: z.string().regex(/^\d{9}$/, 'Celular de 9 dígitos'),
});

/** Suma meses respetando fin de mes: 31 ene + 1 mes = 28/29 feb (no 3 mar). */
export function addMonths(date: Date, months: number): Date {
  const d = new Date(date);
  const day = d.getUTCDate();
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + months);
  const last = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(day, last));
  return d;
}

const addDays = (d: Date, days: number) => new Date(d.getTime() + days * 86_400_000);

/** Estados en los que la tienda queda en solo lectura (bloqueo suave). */
export const READ_ONLY_STATUSES = new Set(['suspended', 'canceled']);

/**
 * Motor de facturación SaaS. Decisiones clave:
 *
 * 1. **Nuestra BD manda**, no la pasarela. Así podemos cobrar con Culqi o Stripe (o
 *    registrar un pago manual por Plin/transferencia) con un solo ciclo de vida.
 * 2. **Facturas por periodo, por adelantado**: al vencer un periodo se emite la factura del
 *    siguiente. Con tarjeta guardada se cobra sola; con Yape/billeteras queda abierta y el
 *    dueño la paga desde la app (Yape y Plin no permiten débito automático).
 * 3. **Gracia y bloqueo suave**: sin pago, la tienda sigue operando BILLING_GRACE_DAYS días
 *    (past_due); luego queda en solo lectura (suspended). Nunca se borran datos.
 * 4. Todo lo de facturación escribe con el pool de sistema: el rol de la API de negocio solo
 *    puede LEER su suscripción (RLS), nunca modificarla.
 */
@Injectable()
export class BillingService {
  private readonly logger = new Logger('Billing');
  /** Caché del estado por tienda para el guard (evita una consulta por request). */
  private readonly statusCache = new Map<string, { status: string; expires: number }>();

  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(LimitsService) private readonly limits: LimitsService,
    @Inject(PAYMENT_PROVIDERS) private readonly providers: PaymentProvider[],
    @Inject(ENV) private readonly env: Env,
    @Inject(EventBus) private readonly events: EventBus,
  ) {}

  // ---------------------------------------------------------------- alta

  /** Se llama dentro de la transacción de registro de la tienda. */
  async startTrial(tx: Tx, tenantId: string, now = new Date()) {
    const [plan] = await tx.select().from(plans).where(eq(plans.code, this.env.TRIAL_PLAN));
    if (!plan) throw new Error(`Plan de prueba "${this.env.TRIAL_PLAN}" no existe`);
    const end = addDays(now, this.env.TRIAL_DAYS);
    await tx.insert(subscriptions).values({
      tenantId,
      planId: plan.id,
      status: 'trialing',
      trialEndsAt: end,
      currentPeriodStart: now,
      currentPeriodEnd: end,
    });
  }

  // ---------------------------------------------------------------- consultas de la tienda

  plans() {
    return this.db.withSystem((tx) =>
      tx.select().from(plans).where(eq(plans.active, true)).orderBy(asc(plans.position)),
    );
  }

  overview(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx
        .select({ sub: subscriptions, plan: plans })
        .from(subscriptions)
        .innerJoin(plans, eq(plans.id, subscriptions.planId));
      if (!row) throw new NotFoundException('La tienda no tiene suscripción');
      const open = await tx.select().from(invoices).where(eq(invoices.status, 'open')).orderBy(asc(invoices.dueAt));
      const history = await tx.select().from(invoices).orderBy(desc(invoices.createdAt)).limit(12);
      const graceEndsAt = row.sub.status === 'past_due' ? addDays(row.sub.currentPeriodEnd, this.env.BILLING_GRACE_DAYS) : null;
      return {
        status: row.sub.status,
        readOnly: READ_ONLY_STATUSES.has(row.sub.status),
        plan: { code: row.plan.code, name: row.plan.name, priceCents: row.plan.priceCents, currency: row.plan.currency, limits: row.plan.limits },
        trialEndsAt: row.sub.trialEndsAt,
        currentPeriodEnd: row.sub.currentPeriodEnd,
        graceEndsAt,
        cancelAtPeriodEnd: row.sub.cancelAtPeriodEnd,
        autopay: row.sub.autopay,
        usage: await this.limits.usage(tx, user.tenantId),
        openInvoices: open,
        history,
        providers: this.providers.map((p) => ({ name: p.name, methods: p.methods })),
        culqiPublicKey: this.env.CULQI_PUBLIC_KEY ?? null,
      };
    });
  }

  // ---------------------------------------------------------------- acciones del dueño

  /**
   * Cambiar de plan. Al subir, los límites nuevos aplican al instante; el precio nuevo, desde
   * la próxima factura (sin prorrateo: más simple de entender para una boutique). No se puede
   * bajar a un plan cuyo límite ya se supera.
   */
  changePlan(user: AuthUser, planCode: string) {
    return this.db.withSystem(async (tx) => {
      const [plan] = await tx.select().from(plans).where(and(eq(plans.code, planCode), eq(plans.active, true)));
      if (!plan) throw new NotFoundException('Plan no encontrado');
      const usage = await this.limits.usage(tx, user.tenantId);
      const exceeded = (Object.keys(usage) as LimitedResource[]).filter((k) => plan.limits[k] !== null && usage[k] > plan.limits[k]!);
      if (exceeded.length) {
        throw new ConflictException({ message: 'Tu uso actual supera los límites de ese plan', code: 'PLAN_USAGE_EXCEEDS', exceeded, usage, limits: plan.limits });
      }
      await tx.update(subscriptions).set({ planId: plan.id, updatedAt: new Date() }).where(eq(subscriptions.tenantId, user.tenantId));
      await this.audit(tx, user, 'billing.plan_changed', { planCode });
      return { planCode: plan.code };
    });
  }

  /** Genera el checkout de la pasarela elegida para pagar una factura abierta. */
  pay(user: AuthUser, invoiceId: string, input: z.infer<typeof PaySchema>) {
    const provider = this.provider(input.provider);
    if (!provider.methods.includes(input.method)) {
      throw new BadRequestException(`${provider.name} no admite ${input.method === 'yape' ? 'Yape' : input.method}`);
    }
    return this.db.withSystem(async (tx) => {
      const [inv] = await tx
        .select({ inv: invoices, plan: plans })
        .from(invoices)
        .innerJoin(plans, eq(plans.id, invoices.planId))
        .where(and(eq(invoices.id, invoiceId), eq(invoices.tenantId, user.tenantId)));
      if (!inv) throw new NotFoundException('Factura no encontrada');
      if (inv.inv.status !== 'open') throw new ConflictException('La factura no está pendiente');
      const [owner] = await tx.select({ email: users.email, name: users.name }).from(users).where(eq(users.id, user.userId));

      const checkout = await provider.createCheckout({
        invoiceId,
        invoiceNumber: inv.inv.number,
        amountCents: inv.inv.amountCents,
        currency: inv.inv.currency,
        description: `Percha ${inv.plan.name} · factura ${inv.inv.number}`,
        method: input.method,
        customer: owner,
      });
      await tx.update(invoices).set({ provider: provider.name, providerRef: checkout.providerRef, method: input.method }).where(eq(invoices.id, invoiceId));
      // Culqi Checkout es JavaScript: la app abre una página nuestra (enlace firmado, 1 hora).
      if (checkout.kind === 'culqi_checkout') {
        return { ...checkout, url: `${this.env.PUBLIC_API_URL}/v1/billing/pay/${invoiceId}?t=${this.signPayLink(invoiceId)}` };
      }
      return checkout;
    });
  }

  /** Guarda la tarjeta (token de Culqi.js) y activa el cobro automático. */
  saveCard(user: Pick<AuthUser, 'tenantId' | 'userId' | 'membershipId'>, input: z.infer<typeof SaveCardSchema>) {
    const provider = this.providers.find((p) => p.saveCard && (p.name === 'culqi' || p.name === 'fake'));
    if (!provider?.saveCard) throw new BadRequestException('No hay pasarela con tarjeta guardada configurada');
    return this.db.withSystem(async (tx) => {
      const [owner] = await tx.select({ email: users.email, name: users.name }).from(users).where(eq(users.id, user.userId));
      const [branch] = await tx.select().from(branches).where(and(eq(branches.tenantId, user.tenantId), eq(branches.isDefault, true)));
      const card = await provider.saveCard!({ ...owner, token: input.token, phone: input.phone, address: branch?.address ?? 'Perú', city: 'Lima' });
      await tx
        .update(subscriptions)
        .set({ autopay: true, providerCustomerId: card.customerId, providerCardId: card.cardId, updatedAt: new Date() })
        .where(eq(subscriptions.tenantId, user.tenantId));
      await this.audit(tx, user, 'billing.card_saved', {});
      return { autopay: true };
    });
  }

  setCancel(user: AuthUser, cancel: boolean) {
    return this.db.withSystem(async (tx) => {
      await tx.update(subscriptions).set({ cancelAtPeriodEnd: cancel, updatedAt: new Date() }).where(eq(subscriptions.tenantId, user.tenantId));
      await this.audit(tx, user, cancel ? 'billing.cancel_scheduled' : 'billing.cancel_reverted', {});
      return { cancelAtPeriodEnd: cancel };
    });
  }

  // ---------------------------------------------------------------- página de pago (Culqi)

  /**
   * Enlaces firmados para páginas públicas (pagar, registrar tarjeta): propósito + sujeto +
   * vencimiento, con HMAC del secreto del JWT. No exponen la sesión del usuario y no sirven
   * para otro propósito ni otra factura.
   */
  signLink(purpose: string, subject: string, ttlMs = 3_600_000, now = Date.now()) {
    const exp = Math.floor((now + ttlMs) / 1000);
    return `${exp}.${this.mac(purpose, subject, exp)}`;
  }

  verifyLink(purpose: string, subject: string, token: string, now = Date.now()) {
    const [expRaw, mac] = token.split('.');
    const exp = Number(expRaw);
    if (!exp || !mac || exp * 1000 < now) return false;
    const a = Buffer.from(this.mac(purpose, subject, exp));
    const b = Buffer.from(mac);
    return a.length === b.length && timingSafeEqual(a, b);
  }

  private mac(purpose: string, subject: string, exp: number) {
    return createHmac('sha256', this.env.JWT_ACCESS_SECRET).update(`${purpose}:${subject}:${exp}`).digest('base64url');
  }

  signPayLink(invoiceId: string, ttlMs?: number, now?: number) {
    return this.signLink('pay', invoiceId, ttlMs, now);
  }

  verifyPayLink(invoiceId: string, token: string, now?: number) {
    return this.verifyLink('pay', invoiceId, token, now);
  }

  // ---------------------------------------------------------------- registrar tarjeta (Culqi.js)

  /**
   * La tarjeta se tokeniza en el navegador con Culqi Checkout (nunca pasa por nuestro
   * servidor). La app pide un enlace firmado de 30 minutos que identifica tienda y dueño.
   */
  cardSetupLink(user: AuthUser) {
    if (!this.providers.some((p) => p.saveCard)) throw new BadRequestException('No hay pasarela con tarjeta guardada configurada');
    const subject = `${user.tenantId}:${user.userId}:${user.membershipId}`;
    const t = `${Buffer.from(subject).toString('base64url')}.${this.signLink('card', subject, 30 * 60_000)}`;
    return { url: `${this.env.PUBLIC_API_URL}/v1/billing/card-setup?t=${t}` };
  }

  /** Valida el enlace y devuelve a quién pertenece. */
  cardSetupIdentity(t: string) {
    const [encoded, ...rest] = (t ?? '').split('.');
    const subject = Buffer.from(encoded ?? '', 'base64url').toString('utf8');
    const [tenantId, userId, membershipId] = subject.split(':');
    if (!tenantId || !userId || !membershipId || !this.verifyLink('card', subject, rest.join('.'))) {
      throw new UnauthorizedException('Enlace inválido o vencido. Genera uno nuevo desde la app.');
    }
    return { tenantId, userId, membershipId };
  }

  cardSetupPageData(t: string) {
    this.cardSetupIdentity(t);
    return { publicKey: this.env.CULQI_PUBLIC_KEY ?? '', token: t, returnUrl: `${this.env.APP_URL}/billing` };
  }

  completeCardSetup(t: string, input: z.infer<typeof SaveCardSchema>) {
    return this.saveCard(this.cardSetupIdentity(t), input);
  }

  /** Datos para renderizar Culqi Checkout de una factura abierta ya asociada a una orden. */
  async payPageData(invoiceId: string, token: string) {
    if (!this.verifyPayLink(invoiceId, token)) throw new UnauthorizedException('Enlace de pago inválido o vencido');
    return this.db.withSystem(async (tx) => {
      const [row] = await tx
        .select({ inv: invoices, plan: plans, tenantName: sql<string>`(select name from tenants where id = ${invoices.tenantId})` })
        .from(invoices)
        .innerJoin(plans, eq(plans.id, invoices.planId))
        .where(eq(invoices.id, invoiceId));
      if (!row || row.inv.status !== 'open' || row.inv.provider !== 'culqi' || !row.inv.providerRef) {
        throw new NotFoundException('Esta factura ya fue pagada o no tiene una orden de Culqi');
      }
      return {
        publicKey: this.env.CULQI_PUBLIC_KEY ?? '',
        orderId: row.inv.providerRef,
        amountCents: row.inv.amountCents,
        currency: row.inv.currency,
        title: `Percha ${row.plan.name}`,
        store: row.tenantName,
        returnUrl: `${this.env.APP_URL}/billing`,
      };
    });
  }

  // ---------------------------------------------------------------- webhooks

  /**
   * Idempotente: el evento se registra con (pasarela, id) único. Si la pasarela reintenta, el
   * segundo intento no hace nada. La factura se busca por referencia de pasarela o por id.
   */
  async handleWebhook(providerName: ProviderName, rawBody: Buffer | undefined, headers: Record<string, string | string[] | undefined>) {
    if (!rawBody) throw new BadRequestException('Cuerpo vacío');
    const provider = this.provider(providerName);
    const event = await provider.parseWebhook(rawBody, headers);
    if (!event) throw new UnauthorizedException('Firma de webhook inválida');

    return this.db.withSystem(async (tx) => {
      const inserted = await tx
        .insert(paymentEvents)
        .values({ provider: provider.name, eventId: event.eventId, type: event.type, payload: event.raw as object })
        .onConflictDoNothing()
        .returning({ id: paymentEvents.id });
      if (!inserted.length) return { duplicate: true };
      if (event.type !== 'payment.succeeded') return { ignored: true };

      const [inv] = await tx
        .select()
        .from(invoices)
        .where(
          or(
            event.providerRef ? eq(invoices.providerRef, event.providerRef) : undefined,
            event.invoiceId ? eq(invoices.id, event.invoiceId) : undefined,
          ),
        );
      if (!inv) {
        this.logger.warn(`Pago ${event.eventId} sin factura asociada`);
        return { unmatched: true };
      }
      await this.markPaid(tx, inv.id, { provider: provider.name, providerRef: event.providerRef, method: event.method });
      return { paid: inv.id };
    });
  }

  // ---------------------------------------------------------------- ciclo (job diario)

  /**
   * Avanza el estado de todas las suscripciones. Pensado para correr cada hora o diario
   * (Railway Cron, GitHub Actions...). Es seguro correrlo varias veces: las facturas son
   * únicas por (tienda, periodo) y cada suscripción se procesa con bloqueo de fila.
   */
  /**
   * Ciclo de cobro (cron cada hora). Por cada tienda con el periodo vencido, en su propia
   * transacción (si una falla, las demás siguen):
   *   en gracia → ¿venció la gracia? → solo lectura
   *   pidió cancelar → cancelada
   *   si no → factura del periodo → cobro automático con tarjeta → si no se pudo, en gracia
   */
  async run(now = new Date()) {
    const result = { invoiced: 0, charged: 0, chargeFailed: 0, pastDue: 0, suspended: 0, canceled: 0 };
    const due = await this.db.withSystem((tx) =>
      tx
        .select({ tenantId: subscriptions.tenantId })
        .from(subscriptions)
        .where(and(inArray(subscriptions.status, ['trialing', 'active', 'past_due']), lte(subscriptions.currentPeriodEnd, now))),
    );
    for (const { tenantId } of due) {
      try {
        const outcome = await this.db.withSystem((tx) => this.processTenant(tx, tenantId, now));
        if (outcome.invoiced) result.invoiced++;
        if (outcome.chargeFailed) result.chargeFailed++;
        if (outcome.status) result[outcome.status]++;
      } catch (e) {
        this.logger.error(`Facturación de ${tenantId} falló: ${e instanceof Error ? e.message : e}`);
      } finally {
        this.statusCache.delete(tenantId);
      }
    }
    return result;
  }

  private async processTenant(
    tx: Tx,
    tenantId: string,
    now: Date,
  ): Promise<{ invoiced?: boolean; chargeFailed?: boolean; status?: 'charged' | 'pastDue' | 'suspended' | 'canceled' }> {
    const [row] = await tx
      .select({ sub: subscriptions, plan: plans })
      .from(subscriptions)
      .innerJoin(plans, eq(plans.id, subscriptions.planId))
      .where(eq(subscriptions.tenantId, tenantId))
      .for('update', { of: subscriptions, skipLocked: true });
    if (!row) return {};
    const { sub, plan } = row;

    if (sub.status === 'past_due') {
      if (now < addDays(sub.currentPeriodEnd, this.env.BILLING_GRACE_DAYS)) return {};
      await this.setStatus(tx, tenantId, 'suspended', now);
      await this.events.publish(tx, { type: 'subscription.suspended', tenantId });
      return { status: 'suspended' };
    }
    if (sub.cancelAtPeriodEnd) {
      await this.setStatus(tx, tenantId, 'canceled', now);
      return { status: 'canceled' };
    }

    const inv = await this.ensureInvoice(tx, tenantId, plan, sub.currentPeriodEnd);
    const charged = sub.autopay && sub.providerCardId ? await this.chargeSavedCard(tx, tenantId, sub.providerCardId, inv, plan.name) : null;
    if (charged) return { invoiced: inv.created, status: 'charged' };

    await this.setStatus(tx, tenantId, 'past_due', now);
    await this.events.publish(tx, { type: 'subscription.past_due', tenantId, graceDays: this.env.BILLING_GRACE_DAYS });
    return { invoiced: inv.created, chargeFailed: charged === false, status: 'pastDue' };
  }

  /** true: cobrado · false: la tarjeta rechazó. */
  private async chargeSavedCard(tx: Tx, tenantId: string, cardId: string, inv: { id: string; amountCents: number; currency: string }, planName: string) {
    const provider = this.providers.find((p) => p.chargeSavedCard && (p.name === 'culqi' || p.name === 'fake'));
    if (!provider?.chargeSavedCard) return false;
    const [owner] = await tx
      .select({ email: users.email })
      .from(memberships)
      .innerJoin(users, eq(users.id, memberships.userId))
      .where(and(eq(memberships.tenantId, tenantId), eq(memberships.role, 'owner')))
      .limit(1);
    const charge = await provider.chargeSavedCard({ invoiceId: inv.id, amountCents: inv.amountCents, currency: inv.currency, email: owner.email, cardId, description: `Percha ${planName}` });
    if (!charge.paid) return false;
    await this.markPaid(tx, inv.id, { provider: provider.name, providerRef: charge.providerRef, method: 'card' });
    return true;
  }

  private setStatus(tx: Tx, tenantId: string, status: 'past_due' | 'suspended' | 'canceled', now: Date) {
    return tx.update(subscriptions).set({ status, updatedAt: now }).where(eq(subscriptions.tenantId, tenantId));
  }


  /** Pago confirmado: la factura se marca pagada y la suscripción avanza a ese periodo. */
  async markPaid(tx: Tx, invoiceId: string, by: { provider: ProviderName | 'manual'; providerRef?: string; method?: string }, now = new Date()) {
    const [inv] = await tx
      .update(invoices)
      .set({ status: 'paid', paidAt: now, provider: by.provider, providerRef: by.providerRef ?? undefined, method: by.method })
      .where(and(eq(invoices.id, invoiceId), eq(invoices.status, 'open')))
      .returning();
    if (!inv) return; // ya estaba pagada (webhook y cobro automático compitiendo): no se cobra dos veces

    await tx
      .update(subscriptions)
      .set({
        status: 'active',
        planId: inv.planId,
        currentPeriodStart: inv.periodStart,
        currentPeriodEnd: inv.periodEnd,
        updatedAt: now,
      })
      .where(and(eq(subscriptions.tenantId, inv.tenantId), sql`${subscriptions.currentPeriodEnd} <= ${inv.periodEnd}`));
    this.statusCache.delete(inv.tenantId);
  }

  // ---------------------------------------------------------------- guard

  /** Estado de la suscripción con caché de 30 s (un request no debería pagar una consulta extra). */
  async status(tenantId: string): Promise<string | null> {
    const hit = this.statusCache.get(tenantId);
    if (hit && hit.expires > Date.now()) return hit.status;
    const [row] = await this.db.withSystem((tx) =>
      tx.select({ status: subscriptions.status }).from(subscriptions).where(eq(subscriptions.tenantId, tenantId)),
    );
    const status = row?.status ?? null;
    if (status) this.statusCache.set(tenantId, { status, expires: Date.now() + 30_000 });
    return status;
  }

  forget(tenantId: string) {
    this.statusCache.delete(tenantId);
  }

  // ---------------------------------------------------------------- helpers

  private async ensureInvoice(tx: Tx, tenantId: string, plan: typeof plans.$inferSelect, periodStart: Date) {
    const inserted = await tx
      .insert(invoices)
      .values({
        tenantId,
        planId: plan.id,
        periodStart,
        periodEnd: addMonths(periodStart, 1),
        amountCents: plan.priceCents,
        currency: plan.currency,
        dueAt: periodStart,
      })
      .onConflictDoNothing()
      .returning();
    if (inserted.length) return { ...inserted[0], created: true };
    const [existing] = await tx.select().from(invoices).where(and(eq(invoices.tenantId, tenantId), eq(invoices.periodStart, periodStart)));
    return { ...existing, created: false };
  }

  provider(name: string): PaymentProvider {
    const p = this.providers.find((x) => x.name === name);
    if (!p) throw new HttpException({ message: `Pasarela ${name} no configurada`, code: 'PROVIDER_UNAVAILABLE' }, HttpStatus.SERVICE_UNAVAILABLE);
    return p;
  }

  private async audit(tx: Tx, user: Pick<AuthUser, 'tenantId' | 'membershipId'>, action: string, data: Record<string, unknown>) {
    await tx.insert(auditLogs).values({ tenantId: user.tenantId, actorMembershipId: user.membershipId, action, entity: 'subscription', entityId: null, data });
  }
}

