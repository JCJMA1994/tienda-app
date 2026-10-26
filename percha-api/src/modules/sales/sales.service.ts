import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { and, asc, desc, eq, gte, inArray, lt } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { allocate, applyBp, computeTax } from '../../common/money';
import { cents, positiveQty } from '../../common/schemas';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import { branches, cashSessions, customers, einvoiceDocuments, einvoiceSettings, memberships, payments, products, returns, saleItems, sales, stockLevels, tenants, variants } from '../../database/schema';
import { ApprovalService } from '../access/approval.service';
import { hasPermission } from '../../common/authz/permissions';
import { AuditService } from '../audit/audit.service';
import { EventBus } from '../../common/events';
import { IdempotencyService } from '../../common/idempotency';
import { applyPromotions } from '../promotions/engine';
import { PromotionsService } from '../promotions/promotions.service';
import { DocumentRequestSchema } from '../einvoice/einvoice.service';
import { InventoryService } from '../inventory/inventory.service';
import { CreditsService } from '../credits/credits.service';
import { CashService } from './cash.service';

export const PaymentSchema = z.object({
  method: z.enum(['cash', 'card', 'wallet', 'transfer', 'store_credit']),
  amountCents: cents.refine((n) => n > 0, 'El monto debe ser mayor a 0'),
  reference: z.string().trim().max(60).optional(),
  /** Código del vale cuando se PAGA con saldo a favor o gift card (en un reembolso no va: se emite uno nuevo). */
  creditCode: z.string().trim().max(30).optional(),
});

export function assertCreditCodes(list: { method: string; creditCode?: string }[]) {
  if (list.some((p) => p.method === 'store_credit' && !p.creditCode)) {
    throw new BadRequestException({ message: 'Indica el código del vale', code: 'CREDIT_CODE_REQUIRED' });
  }
}

/** Pagos que solo crea el servidor (no se aceptan desde la app). */
export type InternalPayment = { method: 'layaway'; amountCents: number; reference?: string; layawayId: string };
export type SalePayment = z.infer<typeof PaymentSchema> | InternalPayment;
export type SaleInput = Omit<z.infer<typeof CreateSaleSchema>, 'payments'> & { payments: SalePayment[] };

export const ItemSchema = z.object({ variantId: z.string().uuid(), quantity: positiveQty });

export const CreateSaleSchema = z.object({
  branchId: z.string().uuid(),
  items: z.array(ItemSchema).min(1).max(100),
  discountCents: cents.default(0),
  payments: z.array(PaymentSchema).min(1).max(5),
  /** Efectivo entregado por el cliente, para calcular el vuelto. */
  cashReceivedCents: cents.optional(),
  approverPin: z.string().regex(/^\d{4,6}$/).optional(),
  /** Comprobante electrónico (si la tienda lo tiene activo). Por defecto: boleta sin DNI. */
  document: DocumentRequestSchema.optional(),
  /** Cliente elegido en el POS (si no, se toma del documento del comprobante, si lo hay). */
  customerId: z.string().uuid().optional(),
  /**
   * Venta hecha SIN CONEXIÓN que el POS sincroniza después. `occurredAt` es el momento real
   * de la venta (fecha del reporte y del comprobante). Máximo 72 h de antigüedad.
   */
  offline: z
    .object({
      occurredAt: z.string().datetime(),
      /** Quien vendió en el equipo (si otra persona sincroniza después con su PIN). */
      sellerMembershipId: z.string().uuid().optional(),
    })
    .optional(),
});

export const OFFLINE_MAX_AGE_MS = 72 * 3_600_000;

export const VoidSaleSchema = z.object({
  reason: z.string().trim().min(3).max(200),
  approverPin: z.string().regex(/^\d{4,6}$/).optional(),
});

export const ListSalesSchema = z.object({
  branchId: z.string().uuid().optional(),
  /** Buscar por número de ticket (el cliente regresa con su comprobante). */
  number: z.coerce.number().int().positive().optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

export interface PricedLine {
  variantId: string;
  productId: string;
  categoryId: string | null;
  quantity: number;
  unitPriceCents: number;
  grossCents: number;
  unitCostCents: number;
}

/** Une ítems repetidos (el mismo código escaneado dos veces). */
export function mergeItems(items: { variantId: string; quantity: number }[]) {
  const map = new Map<string, number>();
  for (const i of items) map.set(i.variantId, (map.get(i.variantId) ?? 0) + i.quantity);
  return [...map.entries()].map(([variantId, quantity]) => ({ variantId, quantity }));
}

/**
 * Precios SIEMPRE desde la BD: el cliente (app) solo envía qué y cuánto.
 * Así una app manipulada no puede vender a otro precio.
 */
export async function priceLines(tx: Tx, items: { variantId: string; quantity: number }[]): Promise<PricedLine[]> {
  const merged = mergeItems(items);
  const rows = await tx
    .select({ variant: variants, productPrice: products.priceCents, productActive: products.active, categoryId: products.categoryId })
    .from(variants)
    .innerJoin(products, eq(products.id, variants.productId))
    .where(inArray(variants.id, merged.map((i) => i.variantId)));
  return merged.map((i) => {
    const row = rows.find((r) => r.variant.id === i.variantId);
    if (!row) throw new BadRequestException(`Variante inexistente: ${i.variantId}`);
    if (!row.variant.active || !row.productActive) throw new UnprocessableEntityException(`${row.variant.sku} no está a la venta`);
    const unit = row.variant.priceCents ?? row.productPrice;
    return { variantId: i.variantId, productId: row.variant.productId, categoryId: row.categoryId, quantity: i.quantity, unitPriceCents: unit, grossCents: unit * i.quantity, unitCostCents: row.variant.avgCostCents };
  });
}

export function assertPaymentsMatch(list: { amountCents: number }[], expected: number) {
  const paid = list.reduce((a, p) => a + p.amountCents, 0);
  if (paid !== expected) {
    throw new BadRequestException({ message: 'La suma de pagos no coincide con el total', code: 'PAYMENT_MISMATCH', expectedCents: expected, paidCents: paid });
  }
}

@Injectable()
export class SalesService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(CashService) private readonly cash: CashService,
    @Inject(InventoryService) private readonly inventory: InventoryService,
    @Inject(ApprovalService) private readonly approvals: ApprovalService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(EventBus) private readonly events: EventBus,
    @Inject(CreditsService) private readonly credits: CreditsService,
    @Inject(IdempotencyService) private readonly idem: IdempotencyService,
    @Inject(PromotionsService) private readonly promotions: PromotionsService,
  ) {}

  /**
   * Una venta es UNA transacción: caja, correlativo, líneas, pagos y descuento de stock.
   * Si falta stock de una sola prenda, no se guarda nada.
   */
  /**
   * Con `Idempotency-Key`, un reintento (red inestable, POS sin conexión que sincroniza, doble
   * toque) devuelve la MISMA venta: no se descuenta stock ni se cobra dos veces.
   */
  async create(user: AuthUser, input: z.infer<typeof CreateSaleSchema>, idempotencyKey?: string) {
    assertBranchAccess(user, input.branchId);
    let replayId: string | undefined;
    const result = await this.db.withTenant(user.tenantId, async (tx) => {
      // `offline` no entra en la huella: si el POS envió la venta, no recibió respuesta (corte) y la
      // reenvía desde la cola sin conexión, sigue siendo la MISMA venta.
      replayId = await this.idem.begin(tx, user.tenantId, idempotencyKey, 'sale.create', { ...input, offline: undefined });
      if (replayId) return null;
      const sale = await this.createTx(tx, user, input);
      await this.idem.complete(tx, user.tenantId, idempotencyKey, sale.id);
      return sale;
    });
    if (!result) return { ...(await this.get(user, replayId!)), changeCents: 0, replayed: true };
    return this.refreshed(user, result);
  }

  /** Tras el commit (y el envío al OSE) se releen la venta y sus comprobantes. */
  async refreshed<T extends { id: string }>(user: AuthUser, result: T): Promise<T> {
    return { ...result, ...(await this.get(user, result.id)) };
  }

  /**
   * Venta dentro de una transacción existente. Además del POS, la usan los apartados al
   * entregar (con el precio congelado del apartado y el pago "layaway").
   */
  async createTx(
    tx: Tx,
    user: AuthUser,
    input: SaleInput,
    opts: { priceOverrides?: Map<string, number> } = {},
  ) {
    const session = await this.cash.requireOpen(tx, input.branchId);
    const [store] = await tx.select().from(tenants);
    const occurredAt = this.occurredAt(input);

    // 1. Precios (de la BD, o congelados si viene de un apartado), promociones y descuento manual.
    const q = await this.priceTx(tx, store, input, occurredAt, opts.priceOverrides);
    const { lines, subtotal, total, tax, lineDiscounts } = q;
    const discountApprovedBy = await this.authorizeDiscount(tx, user, input, subtotal - q.promoCents, store.discountLimitBp);

    // 2. Pagos coherentes con el total.
    const cashPaid = this.validatePayments(input, total);

    // 3. Registro, cobro y stock.
    const sellerId = await this.offlineSeller(tx, user, input);
    const sale = await this.insertSale(tx, user, { input, sessionId: session.id, lines, subtotal, total, tax, discountApprovedBy, occurredAt, sellerId, promoCents: q.promoCents });
    await this.insertItems(tx, user, sale.id, lines, lineDiscounts, q.promo.lines);
    await this.collectPayments(tx, user, sale.id, session.id, input.payments);
    // Venta sin conexión: la prenda YA salió con el cliente. Si al sincronizar el sistema tiene
    // menos stock (otro la vendió, o el conteo estaba mal), se registra un ajuste explícito por
    // la diferencia antes de la venta: el kardex lo muestra y nunca queda stock negativo oculto.
    if (input.offline && !store.allowNegativeStock) await this.coverOfflineShortfall(tx, user, input.branchId, sale.id, lines);
    await this.inventory.apply(
      tx,
      user,
      input.branchId,
      lines.map((l) => ({ variantId: l.variantId, quantity: -l.quantity, type: 'sale' as const, unitCostCents: l.unitCostCents, referenceType: 'sale', referenceId: sale.id })),
    );
    if (discountApprovedBy) {
      await this.audit.log(tx, user, 'sale.discount_approved', 'sale', sale.id, { discountCents: input.discountCents, approvedBy: discountApprovedBy });
    }

    // 4. Comprobante electrónico, cliente y demás reacciones: suscriptores del evento.
    await this.events.publish(tx, {
      type: 'sale.recorded',
      user,
      saleId: sale.id,
      branchId: input.branchId,
      lines: lines.map((l, i) => ({ variantId: l.variantId, quantity: l.quantity, amountCents: l.grossCents - lineDiscounts[i] })),
      document: input.document,
      customerId: input.customerId,
      occurredAt,
    });

    const detail = await this.load(tx, user, sale.id);
    return { ...detail, changeCents: input.cashReceivedCents !== undefined ? input.cashReceivedCents - cashPaid : 0 };
  }

  /**
   * Vendedor de una venta sin conexión: quien la hizo en el equipo, si es un integrante activo
   * con acceso a la sucursal. Si no se puede verificar, queda quien sincroniza (nunca alguien
   * ajeno a la tienda).
   */
  private async offlineSeller(tx: Tx, user: AuthUser, input: SaleInput) {
    const id = input.offline?.sellerMembershipId;
    if (!id || id === user.membershipId) return user.membershipId;
    const [m] = await tx.select({ id: memberships.id, branchId: memberships.branchId, status: memberships.status }).from(memberships).where(eq(memberships.id, id));
    if (!m || m.status !== 'active' || (m.branchId && m.branchId !== input.branchId)) return user.membershipId;
    return m.id;
  }

  /** Momento real de la venta: ahora, o el de la venta sin conexión (máx. 72 h, sin futuro). */
  private occurredAt(input: SaleInput) {
    if (!input.offline) return new Date();
    const at = new Date(input.offline.occurredAt);
    const now = Date.now();
    if (at.getTime() > now + 5 * 60_000) throw new BadRequestException({ message: 'La fecha de la venta está en el futuro: revisa la hora del dispositivo', code: 'OFFLINE_CLOCK' });
    if (now - at.getTime() > OFFLINE_MAX_AGE_MS) throw new BadRequestException({ message: 'La venta sin conexión tiene más de 72 horas: regístrala manualmente', code: 'OFFLINE_TOO_OLD' });
    return at;
  }

  private async coverOfflineShortfall(tx: Tx, user: AuthUser, branchId: string, saleId: string, lines: PricedLine[]) {
    const levels = await tx
      .select({ variantId: stockLevels.variantId, quantity: stockLevels.quantity })
      .from(stockLevels)
      .where(and(eq(stockLevels.branchId, branchId), inArray(stockLevels.variantId, lines.map((l) => l.variantId))));
    const shortfalls = lines
      .map((l) => ({ line: l, missing: l.quantity - Math.max(levels.find((x) => x.variantId === l.variantId)?.quantity ?? 0, 0) }))
      .filter((x) => x.missing > 0);
    if (!shortfalls.length) return;
    await this.inventory.apply(
      tx,
      user,
      branchId,
      shortfalls.map((s) => ({
        variantId: s.line.variantId,
        quantity: s.missing,
        type: 'adjustment' as const,
        unitCostCents: s.line.unitCostCents,
        referenceType: 'sale_offline',
        referenceId: saleId,
        reason: 'Ajuste automático: venta sin conexión con stock insuficiente al sincronizar (revisa el conteo)',
      })),
    );
    await this.events.publish(tx, { type: 'stock.offline_shortfall', tenantId: user.tenantId, branchId, saleId, variants: shortfalls.map((s) => ({ variantId: s.line.variantId, missing: s.missing })) });
  }

  /**
   * Precio de una venta (también lo usa la cotización del POS): promociones vigentes en el
   * momento de la venta y, sobre lo que queda, el descuento manual. Los apartados entregados
   * conservan su precio congelado: no se les aplican promociones nuevas.
   */
  async priceTx(tx: Tx, store: typeof tenants.$inferSelect, input: Pick<SaleInput, 'items' | 'discountCents'>, at: Date, overrides?: Map<string, number>) {
    const lines = (await priceLines(tx, input.items)).map((l) => {
      const override = overrides?.get(l.variantId);
      return override === undefined ? l : { ...l, unitPriceCents: override, grossCents: override * l.quantity };
    });
    const subtotal = lines.reduce((a, l) => a + l.grossCents, 0);
    const promo = overrides ? applyPromotions([], []) : applyPromotions(lines, await this.promotions.activeAt(tx, at));
    const promoLines = overrides ? lines.map(() => ({ discountCents: 0, promotionId: null })) : promo.lines;
    const promoCents = overrides ? 0 : promo.totalCents;
    if (input.discountCents > subtotal - promoCents) throw new BadRequestException('El descuento supera el subtotal');
    // Descuento manual repartido sobre lo que queda después de las promociones.
    const manual = allocate(input.discountCents, lines.map((l, i) => l.grossCents - promoLines[i].discountCents));
    const lineDiscounts = lines.map((_, i) => promoLines[i].discountCents + manual[i]);
    const { total, tax } = computeTax(subtotal - promoCents - input.discountCents, store.taxRateBp, store.pricesIncludeTax);
    return { lines, subtotal, promoCents, promo: { lines: promoLines, totalCents: promoCents }, lineDiscounts, total, tax };
  }

  /** Cotización para el POS: el total exacto que cobrará el servidor (con promociones). */
  quote(user: AuthUser, input: { branchId: string; items: { variantId: string; quantity: number }[]; discountCents: number }) {
    assertBranchAccess(user, input.branchId);
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [store] = await tx.select().from(tenants);
      const q = await this.priceTx(tx, store, input, new Date());
      const names = new Map((await this.promotions.activeAt(tx, new Date())).map((p) => [p.id, p.name]));
      return {
        subtotalCents: q.subtotal,
        promoDiscountCents: q.promoCents,
        discountCents: input.discountCents,
        totalCents: q.total,
        taxCents: q.tax,
        lines: q.lines.map((l, i) => ({
          variantId: l.variantId,
          quantity: l.quantity,
          unitPriceCents: l.unitPriceCents,
          promoDiscountCents: q.promo.lines[i].discountCents,
          promotionName: q.promo.lines[i].promotionId ? (names.get(q.promo.lines[i].promotionId!) ?? null) : null,
        })),
      };
    });
  }

  /** Descuento sobre el límite de la tienda: requiere PIN de un supervisor. */
  private async authorizeDiscount(tx: Tx, user: AuthUser, input: SaleInput, subtotal: number, limitBp: number) {
    if (input.discountCents <= applyBp(subtotal, limitBp)) return null;
    const { approvedBy } = await this.approvals.authorize(tx, user, input.branchId, 'sales.discount_over_limit', input.approverPin);
    return approvedBy;
  }

  /** Devuelve lo pagado en efectivo (para el vuelto). */
  private validatePayments(input: SaleInput, total: number) {
    assertPaymentsMatch(input.payments, total);
    assertCreditCodes(input.payments as { method: string; creditCode?: string }[]);
    const cashPaid = input.payments.filter((p) => p.method === 'cash').reduce((a, p) => a + p.amountCents, 0);
    if (input.cashReceivedCents !== undefined && input.cashReceivedCents < cashPaid) {
      throw new BadRequestException('El efectivo recibido es menor al monto en efectivo');
    }
    return cashPaid;
  }

  private async insertSale(
    tx: Tx,
    user: AuthUser,
    p: { input: SaleInput; sessionId: string; lines: PricedLine[]; subtotal: number; total: number; tax: number; discountApprovedBy: string | null; occurredAt: Date; sellerId: string; promoCents: number },
  ) {
    const number = await nextNumber(tx, user.tenantId, 'sale');
    const [sale] = await tx
      .insert(sales)
      .values({
        tenantId: user.tenantId,
        branchId: p.input.branchId,
        cashSessionId: p.sessionId,
        number,
        sellerId: p.sellerId,
        subtotalCents: p.subtotal,
        // Total de descuentos (promociones + manual): así subtotal − descuento = neto, como antes.
        discountCents: p.promoCents + p.input.discountCents,
        promoDiscountCents: p.promoCents,
        totalCents: p.total,
        taxCents: p.tax,
        discountApprovedBy: p.discountApprovedBy,
        createdAt: p.occurredAt,
      })
      .returning();
    return sale;
  }

  private insertItems(tx: Tx, user: AuthUser, saleId: string, lines: PricedLine[], lineDiscounts: number[], promos: { discountCents: number; promotionId: string | null }[]) {
    return tx.insert(saleItems).values(
      lines.map((l, i) => ({
        tenantId: user.tenantId,
        saleId,
        variantId: l.variantId,
        quantity: l.quantity,
        unitPriceCents: l.unitPriceCents,
        discountCents: lineDiscounts[i],
        promoDiscountCents: promos[i].discountCents,
        promotionId: promos[i].promotionId,
        lineTotalCents: l.grossCents - lineDiscounts[i],
        unitCostCents: l.unitCostCents,
      })),
    );
  }

  /** Pagos; con vale se descuenta el saldo aquí mismo (atómico: sin saldo, no hay venta). */
  private async collectPayments(tx: Tx, user: AuthUser, saleId: string, sessionId: string, list: SalePayment[]) {
    for (const p of list) {
      const credit = p.method === 'store_credit' ? await this.credits.redeemTx(tx, user, p.creditCode!, p.amountCents, saleId) : null;
      await tx.insert(payments).values({
        tenantId: user.tenantId,
        cashSessionId: sessionId,
        saleId,
        method: p.method,
        amountCents: p.amountCents,
        reference: credit ? `Vale …${credit.codeLast4}` : p.reference,
        storeCreditId: credit?.id,
        layawayId: 'layawayId' in p ? p.layawayId : undefined,
      });
    }
  }




  /**
   * Anular = "esta venta no debió existir" (error de digitación, cobro duplicado).
   * Solo dentro del mismo turno de caja y sin devoluciones. Para lo demás está la devolución,
   * que deja rastro de qué volvió y cuánto se reembolsó.
   */
  async void(user: AuthUser, saleId: string, input: z.infer<typeof VoidSaleSchema>) {
    const result = await this.db.withTenant(user.tenantId, async (tx) => {
      const [sale] = await tx.select().from(sales).where(eq(sales.id, saleId)).for('update');
      if (!sale) throw new NotFoundException('Venta no encontrada');
      assertBranchAccess(user, sale.branchId);
      if (sale.status === 'voided') throw new ConflictException('La venta ya está anulada');

      const [session] = await tx.select().from(cashSessions).where(eq(cashSessions.id, sale.cashSessionId)).for('share');
      if (session.status !== 'open') {
        throw new ConflictException({ message: 'El turno de esa venta ya cerró: registra una devolución', code: 'USE_RETURN' });
      }
      const [anyReturn] = await tx.select({ id: returns.id }).from(returns).where(eq(returns.saleId, saleId)).limit(1);
      if (anyReturn) throw new ConflictException({ message: 'La venta tiene devoluciones: no se puede anular', code: 'USE_RETURN' });

      const original = await tx.select().from(payments).where(eq(payments.saleId, saleId));
      if (original.some((p) => p.method === 'layaway')) {
        throw new ConflictException({ message: 'Una venta de apartado no se anula: registra una devolución', code: 'LAYAWAY_SALE' });
      }

      const { approvedBy } = await this.approvals.authorize(tx, user, sale.branchId, 'sales.void', input.approverPin);

      await tx
        .update(sales)
        .set({ status: 'voided', voidedAt: new Date(), voidedBy: user.membershipId, voidApprovedBy: approvedBy, voidReason: input.reason })
        .where(eq(sales.id, saleId));

      const items = await tx.select().from(saleItems).where(eq(saleItems.saleId, saleId));
      await this.inventory.apply(
        tx,
        user,
        sale.branchId,
        items.map((i) => ({ variantId: i.variantId, quantity: i.quantity, type: 'sale_void' as const, unitCostCents: i.unitCostCents, referenceType: 'sale', referenceId: saleId, reason: input.reason })),
      );

      // Los pagos se revierten con movimientos negativos (nunca se borran): el cierre de caja cuadra.
      await tx.insert(payments).values(
        original.map((p) => ({ tenantId: user.tenantId, cashSessionId: sale.cashSessionId, saleId, method: p.method, amountCents: -p.amountCents, reference: 'Anulación', storeCreditId: p.storeCreditId })),
      );
      // Lo pagado con vales vuelve a su saldo.
      for (const p of original.filter((x) => x.method === 'store_credit' && x.storeCreditId)) {
        await this.credits.restoreTx(tx, user, p.storeCreditId!, p.amountCents, saleId);
      }

      await this.audit.log(tx, user, 'sale.voided', 'sale', saleId, { reason: input.reason, approvedBy, totalCents: sale.totalCents });

      await this.events.publish(tx, { type: 'sale.voided', user, saleId, branchId: sale.branchId, reason: input.reason });

      return this.load(tx, user, saleId);
    });
    return this.refreshed(user, result);
  }

  list(user: AuthUser, q: z.infer<typeof ListSalesSchema>) {
    const branchId = q.branchId ?? user.branchId ?? undefined;
    if (branchId) assertBranchAccess(user, branchId);
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select()
        .from(sales)
        .where(
          and(
            branchId ? eq(sales.branchId, branchId) : undefined,
            q.number ? eq(sales.number, q.number) : undefined,
            q.from ? gte(sales.createdAt, new Date(q.from)) : undefined,
            q.to ? lt(sales.createdAt, new Date(q.to)) : undefined,
          ),
        )
        .orderBy(desc(sales.createdAt))
        .limit(q.limit),
    );
  }

  get(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, (tx) => this.load(tx, user, id));
  }

  async load(tx: Tx, user: AuthUser, id: string) {
    const [sale] = await tx.select().from(sales).where(eq(sales.id, id));
    if (!sale) throw new NotFoundException('Venta no encontrada');
    assertBranchAccess(user, sale.branchId);
    const items = await tx
      .select({ item: saleItems, sku: variants.sku, options: variants.options, productName: products.name })
      .from(saleItems)
      .innerJoin(variants, eq(variants.id, saleItems.variantId))
      .innerJoin(products, eq(products.id, variants.productId))
      .where(eq(saleItems.saleId, id));
    const pays = await tx.select().from(payments).where(eq(payments.saleId, id));
    const showCost = hasPermission(user.role, 'costs.read');
    // Lectura: comprobantes de la venta (sin el detalle interno enviado al OSE).
    const documents = (await tx.select().from(einvoiceDocuments).where(eq(einvoiceDocuments.saleId, id)).orderBy(asc(einvoiceDocuments.createdAt))).map(({ payload: _p, ...d }) => d);
    const [customer] = sale.customerId ? await tx.select({ id: customers.id, name: customers.name }).from(customers).where(eq(customers.id, sale.customerId)) : [];
    return {
      documents,
      customer: customer ?? null,
      // Datos para imprimir el ticket / representación impresa del comprobante.
      store: await this.storeForTicket(tx, sale.branchId),
      ...sale,
      items: items.map(({ item, ...rest }) => {
        const { unitCostCents, ...publicItem } = item;
        return { ...publicItem, ...(showCost ? { unitCostCents } : {}), ...rest };
      }),
      payments: pays,
    };
  }

  private async storeForTicket(tx: Tx, branchId: string) {
    const [t] = await tx.select({ name: tenants.name, ruc: tenants.ruc }).from(tenants);
    const [b] = await tx.select({ name: branches.name, address: branches.address }).from(branches).where(eq(branches.id, branchId));
    const [e] = await tx.select({ legalName: einvoiceSettings.legalName, fiscalAddress: einvoiceSettings.fiscalAddress }).from(einvoiceSettings);
    return { name: t?.name ?? '', ruc: t?.ruc ?? null, legalName: e?.legalName ?? null, fiscalAddress: e?.fiscalAddress ?? null, branchName: b?.name ?? '', branchAddress: b?.address ?? null };
  }
}
