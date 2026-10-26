import { IdempotencyService } from '../../common/idempotency';
import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, desc, eq, lt, sql } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import { customers, layawayItems, layaways, payments, products, variants } from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { CreditsService } from '../credits/credits.service';
import { DocumentRequestSchema } from '../einvoice/einvoice.service';
import { InventoryService } from '../inventory/inventory.service';
import { EventBus } from '../../common/events';
import { CashService } from './cash.service';
import { assertPaymentsMatch, ItemSchema, mergeItems, PaymentSchema, priceLines, SalesService } from './sales.service';

/** Abonos de apartados: dinero que entra a caja (no vales ni pagos internos). */
const CashLikePayment = PaymentSchema.omit({ creditCode: true }).extend({ method: z.enum(['cash', 'card', 'wallet', 'transfer']) });

export const MIN_DEPOSIT_BP = 1000; // 10 %

export const CreateLayawaySchema = z.object({
  branchId: z.string().uuid(),
  customerId: z.string().uuid(),
  items: z.array(ItemSchema).min(1).max(30),
  /** Adelanto (al menos 10 % del total). */
  payments: z.array(CashLikePayment).min(1).max(3),
  days: z.number().int().min(1).max(60).default(15),
  notes: z.string().trim().max(300).optional(),
});

export const LayawayPaymentSchema = z.object({ payments: z.array(CashLikePayment).min(1).max(3) });

export const CompleteLayawaySchema = z.object({
  /** Saldo pendiente, si se paga al recoger. */
  payments: z.array(CashLikePayment).max(3).default([]),
  document: DocumentRequestSchema.optional(),
});

export const CancelLayawaySchema = z.object({
  reason: z.string().trim().min(3).max(200),
  /**
   * Qué pasa con lo abonado: devolver en efectivo, dejarlo como saldo a favor (vale) o, si la
   * política de la tienda lo indica, no devolverlo (queda auditado).
   */
  refund: z.enum(['cash', 'store_credit', 'none']),
});

export const ListLayawaysSchema = z.object({
  status: z.enum(['open', 'completed', 'cancelled']).optional(),
  branchId: z.string().uuid().optional(),
  customerId: z.string().uuid().optional(),
});

/**
 * Apartados (separados):
 *
 *   APARTAR  → adelanto ≥ 10 %; las prendas salen del DISPONIBLE (`layaway_reserve`) sin venderse
 *   ABONAR   → pagos parciales en cualquier caja de la sucursal
 *   ENTREGAR → con todo pagado: se libera la reserva y se registra la VENTA normal (kardex de
 *              venta, costo, comprobante) al precio congelado; se paga con método "layaway"
 *   CANCELAR → vuelve el stock; lo abonado se devuelve en efectivo, como vale o se retiene
 *
 * Los abonos ya entraron a caja cuando se pagaron: la venta final no vuelve a sumar efectivo.
 * Comprobante: se emite al entregar (ver docs: los anticipos pueden requerir comprobante al
 * recibirlos según el caso; consúltalo con tu contador).
 */
@Injectable()
export class LayawaysService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(CashService) private readonly cash: CashService,
    @Inject(InventoryService) private readonly inventory: InventoryService,
    @Inject(SalesService) private readonly sales: SalesService,
    @Inject(CreditsService) private readonly credits: CreditsService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(EventBus) private readonly events: EventBus,
    @Inject(IdempotencyService) private readonly idem: IdempotencyService,
  ) {}

  create(user: AuthUser, input: z.infer<typeof CreateLayawaySchema>, idempotencyKey?: string) {
    assertBranchAccess(user, input.branchId);
    return this.db.withTenant(user.tenantId, async (tx) =>
      this.idem.once(tx, user.tenantId, idempotencyKey, 'layaway.create', input, async () => {
      const session = await this.cash.requireOpen(tx, input.branchId);
      const [customer] = await tx.select({ id: customers.id }).from(customers).where(eq(customers.id, input.customerId));
      if (!customer) throw new BadRequestException('Cliente no encontrado');

      const lines = await priceLines(tx, mergeItems(input.items));
      const total = lines.reduce((a, l) => a + l.grossCents, 0);
      const deposit = input.payments.reduce((a, p) => a + p.amountCents, 0);
      const min = Math.ceil((total * MIN_DEPOSIT_BP) / 10_000);
      if (deposit < min) throw new BadRequestException({ message: `El adelanto mínimo es ${(min / 100).toFixed(2)} (10 %)`, code: 'DEPOSIT_TOO_LOW', minCents: min });
      if (deposit > total) throw new BadRequestException('El adelanto supera el total');

      const number = await nextNumber(tx, user.tenantId, 'layaway');
      const [l] = await tx
        .insert(layaways)
        .values({
          tenantId: user.tenantId,
          number,
          branchId: input.branchId,
          customerId: input.customerId,
          totalCents: total,
          paidCents: deposit,
          expiresAt: new Date(Date.now() + input.days * 86_400_000),
          notes: input.notes,
          createdBy: user.membershipId,
        })
        .returning();
      await tx.insert(layawayItems).values(lines.map((x) => ({ tenantId: user.tenantId, layawayId: l.id, variantId: x.variantId, quantity: x.quantity, unitPriceCents: x.unitPriceCents })));
      // Reserva: si falta stock de una prenda, no se aparta nada.
      await this.inventory.apply(
        tx,
        user,
        input.branchId,
        lines.map((x) => ({ variantId: x.variantId, quantity: -x.quantity, type: 'layaway_reserve' as const, unitCostCents: x.unitCostCents, referenceType: 'layaway', referenceId: l.id })),
      );
      await this.insertPayments(tx, user, session.id, l.id, input.payments, 1);
      await this.audit.log(tx, user, 'layaway.created', 'layaway', l.id, { totalCents: total, depositCents: deposit });
      return this.load(tx, l.id);
    }, (l) => l.id, (lid) => this.load(tx, lid)));
  }

  pay(user: AuthUser, id: string, input: z.infer<typeof LayawayPaymentSchema>, idempotencyKey?: string) {
    return this.db.withTenant(user.tenantId, async (tx) =>
      this.idem.once(tx, user.tenantId, idempotencyKey, 'layaway.pay', { id, ...input }, async () => {
      const l = await this.lockOpen(tx, user, id);
      const session = await this.cash.requireOpen(tx, l.branchId);
      const amount = input.payments.reduce((a, p) => a + p.amountCents, 0);
      if (amount > l.totalCents - l.paidCents) throw new BadRequestException({ message: 'El abono supera el saldo pendiente', code: 'OVERPAYMENT', pendingCents: l.totalCents - l.paidCents });
      await this.insertPayments(tx, user, session.id, id, input.payments, 1);
      await tx.update(layaways).set({ paidCents: sql`${layaways.paidCents} + ${amount}` }).where(eq(layaways.id, id));
      return this.load(tx, id);
    }, () => id, () => this.load(tx, id)));
  }

  async complete(user: AuthUser, id: string, input: z.infer<typeof CompleteLayawaySchema>) {
    const result = await this.db.withTenant(user.tenantId, async (tx) => {
      const l = await this.lockOpen(tx, user, id);
      const session = await this.cash.requireOpen(tx, l.branchId);
      const extra = input.payments.reduce((a, p) => a + p.amountCents, 0);
      if (l.paidCents + extra !== l.totalCents) {
        throw new BadRequestException({ message: 'Falta pagar el saldo para entregar', code: 'LAYAWAY_UNPAID', pendingCents: l.totalCents - l.paidCents });
      }
      if (extra) await this.insertPayments(tx, user, session.id, id, input.payments, 1);

      const items = await tx.select().from(layawayItems).where(eq(layawayItems.layawayId, id));
      // 1) Se libera la reserva y 2) se registra la venta: el kardex queda como una venta normal.
      await this.inventory.apply(
        tx,
        user,
        l.branchId,
        items.map((i) => ({ variantId: i.variantId, quantity: i.quantity, type: 'layaway_release' as const, referenceType: 'layaway', referenceId: id, reason: 'Entrega de apartado' })),
      );
      const sale = await this.sales.createTx(
        tx,
        user,
        {
          branchId: l.branchId,
          items: items.map((i) => ({ variantId: i.variantId, quantity: i.quantity })),
          discountCents: 0,
          payments: [{ method: 'layaway', amountCents: l.totalCents, reference: `Apartado #${l.number}`, layawayId: id }],
          document: input.document,
          customerId: l.customerId,
        },
        { priceOverrides: new Map(items.map((i) => [i.variantId, i.unitPriceCents])) },
      );
      await tx.update(layaways).set({ status: 'completed', paidCents: l.totalCents, saleId: sale.id, closedAt: new Date() }).where(eq(layaways.id, id));
      await this.audit.log(tx, user, 'layaway.completed', 'layaway', id, { saleId: sale.id });
      return { layaway: await this.load(tx, id), sale };
    });
    return { ...result, sale: await this.sales.refreshed(user, result.sale) };
  }

  cancel(user: AuthUser, id: string, input: z.infer<typeof CancelLayawaySchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const l = await this.lockOpen(tx, user, id);
      const items = await tx.select().from(layawayItems).where(eq(layawayItems.layawayId, id));
      await this.inventory.apply(
        tx,
        user,
        l.branchId,
        items.map((i) => ({ variantId: i.variantId, quantity: i.quantity, type: 'layaway_release' as const, referenceType: 'layaway', referenceId: id, reason: input.reason })),
      );

      let credit: { code: string; balanceCents: number } | null = null;
      if (l.paidCents > 0 && input.refund === 'cash') {
        const session = await this.cash.requireOpen(tx, l.branchId);
        await this.insertPayments(tx, user, session.id, id, [{ method: 'cash', amountCents: l.paidCents, reference: 'Devolución de apartado' }], -1);
      } else if (l.paidCents > 0 && input.refund === 'store_credit') {
        const c = await this.credits.issueTx(tx, user, { kind: 'refund', amountCents: l.paidCents, customerId: l.customerId, note: `Apartado #${l.number} cancelado` });
        credit = { code: c.code, balanceCents: c.balanceCents };
      }
      await tx.update(layaways).set({ status: 'cancelled', closedAt: new Date(), closeReason: input.reason }).where(eq(layaways.id, id));
      await this.audit.log(tx, user, 'layaway.cancelled', 'layaway', id, { reason: input.reason, refund: input.refund, paidCents: l.paidCents });
      return { layaway: await this.load(tx, id), credit };
    });
  }

  list(user: AuthUser, q: z.infer<typeof ListLayawaysSchema>) {
    const branchId = q.branchId ?? user.branchId ?? undefined;
    if (branchId) assertBranchAccess(user, branchId);
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select({
          id: layaways.id,
          number: layaways.number,
          status: layaways.status,
          totalCents: layaways.totalCents,
          paidCents: layaways.paidCents,
          expiresAt: layaways.expiresAt,
          customerId: layaways.customerId,
          customerName: customers.name,
          createdAt: layaways.createdAt,
        })
        .from(layaways)
        .innerJoin(customers, eq(customers.id, layaways.customerId))
        .where(
          and(
            q.status ? eq(layaways.status, q.status) : undefined,
            branchId ? eq(layaways.branchId, branchId) : undefined,
            q.customerId ? eq(layaways.customerId, q.customerId) : undefined,
          ),
        )
        // Abiertos primero, por fecha de vencimiento (lo urgente arriba).
        .orderBy(asc(sql`case when ${layaways.status} = 'open' then 0 else 1 end`), asc(layaways.expiresAt), desc(layaways.createdAt))
        .limit(100),
    );
  }

  get(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const l = await this.load(tx, id);
      assertBranchAccess(user, l.branchId);
      return l;
    });
  }

  /** Job diario: avisa a la sucursal de los apartados vencidos (la tienda decide qué hacer). */
  async notifyExpired() {
    const expired = await this.db.withSystem((tx) =>
      tx
        .select({ id: layaways.id, tenantId: layaways.tenantId, branchId: layaways.branchId, number: layaways.number, customerName: customers.name })
        .from(layaways)
        .innerJoin(customers, eq(customers.id, layaways.customerId))
        .where(and(eq(layaways.status, 'open'), lt(layaways.expiresAt, new Date()))),
    );
    for (const e of expired) {
      await this.db.withSystem((tx) =>
        this.events.publish(tx, { type: 'layaway.expired', tenantId: e.tenantId, branchId: e.branchId, layawayId: e.id, number: e.number, customerName: e.customerName }),
      );
    }
    return { expired: expired.length };
  }

  private async lockOpen(tx: Tx, user: AuthUser, id: string) {
    const [l] = await tx.select().from(layaways).where(eq(layaways.id, id)).for('update');
    if (!l) throw new NotFoundException('Apartado no encontrado');
    assertBranchAccess(user, l.branchId);
    if (l.status !== 'open') throw new ConflictException(`El apartado ya está ${l.status === 'completed' ? 'entregado' : 'cancelado'}`);
    return l;
  }

  private async insertPayments(tx: Tx, user: AuthUser, sessionId: string, layawayId: string, list: { method: 'cash' | 'card' | 'wallet' | 'transfer'; amountCents: number; reference?: string }[], sign: 1 | -1) {
    assertPaymentsMatch(list, list.reduce((a, p) => a + p.amountCents, 0));
    await tx.insert(payments).values(
      list.map((p) => ({ tenantId: user.tenantId, cashSessionId: sessionId, layawayId, method: p.method, amountCents: sign * p.amountCents, reference: p.reference ?? 'Abono de apartado' })),
    );
  }

  private async load(tx: Tx, id: string) {
    const [l] = await tx
      .select({ layaway: layaways, customerName: customers.name })
      .from(layaways)
      .innerJoin(customers, eq(customers.id, layaways.customerId))
      .where(eq(layaways.id, id));
    if (!l) throw new NotFoundException('Apartado no encontrado');
    const items = await tx
      .select({ item: layawayItems, sku: variants.sku, options: variants.options, productName: products.name })
      .from(layawayItems)
      .innerJoin(variants, eq(variants.id, layawayItems.variantId))
      .innerJoin(products, eq(products.id, variants.productId))
      .where(eq(layawayItems.layawayId, id));
    const pays = await tx.select({ method: payments.method, amountCents: payments.amountCents, createdAt: payments.createdAt }).from(payments).where(eq(payments.layawayId, id)).orderBy(asc(payments.createdAt));
    return {
      ...l.layaway,
      customerName: l.customerName,
      pendingCents: l.layaway.totalCents - l.layaway.paidCents,
      expired: l.layaway.status === 'open' && l.layaway.expiresAt < new Date(),
      items: items.map(({ item, ...rest }) => ({ ...item, ...rest })),
      payments: pays,
    };
  }
}
