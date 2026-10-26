import { IdempotencyService } from '../../common/idempotency';
import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { and, eq, sql } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { computeTax } from '../../common/money';
import { positiveQty } from '../../common/schemas';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import { payments, returnItems, returns, saleItems, sales, tenants } from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { CreditsService } from '../credits/credits.service';
import { EventBus } from '../../common/events';
import { InventoryService } from '../inventory/inventory.service';
import { CashService } from './cash.service';
import { assertCreditCodes, assertPaymentsMatch, ItemSchema, PaymentSchema, priceLines } from './sales.service';

export const CreateReturnSchema = z.object({
  /** Sucursal donde se atiende (puede ser distinta a la de la venta). */
  branchId: z.string().uuid(),
  items: z.array(z.object({ saleItemId: z.string().uuid(), quantity: positiveQty })).min(1),
  /** Si viene, es un CAMBIO: prendas que se lleva a cambio (p. ej. otra talla). */
  replacements: z.array(ItemSchema).default([]),
  /** Movimiento de dinero por la diferencia (montos positivos; el signo lo decide el servidor). */
  payments: z.array(PaymentSchema).default([]),
  reason: z.string().trim().min(3).max(200),
});

/**
 * Devoluciones y cambios. Un cambio de talla es el caso más común en una boutique:
 * entra la prenda devuelta, sale la nueva y solo se cobra/reembolsa la diferencia.
 * Todo en una transacción y con su propio correlativo.
 */
@Injectable()
export class ReturnsService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(CashService) private readonly cash: CashService,
    @Inject(InventoryService) private readonly inventory: InventoryService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(EventBus) private readonly events: EventBus,
    @Inject(CreditsService) private readonly credits: CreditsService,
    @Inject(IdempotencyService) private readonly idem: IdempotencyService,
  ) {}

  /**
   * Devolución o cambio, en pasos con nombre (una transacción):
   *   1. valorar lo que vuelve (al precio pagado)   2. valorar lo que se lleva (precio vigente)
   *   3. liquidar la diferencia (cobro, reembolso o vale)   4. mover el stock   5. publicar el hecho
   */
  create(user: AuthUser, saleId: string, input: z.infer<typeof CreateReturnSchema>, idempotencyKey?: string) {
    assertBranchAccess(user, input.branchId);
    return this.db.withTenant(user.tenantId, async (tx) =>
      this.idem.once(tx, user.tenantId, idempotencyKey, 'return.create', { saleId, ...input }, async () => {
      const sale = await this.lockReturnableSale(tx, saleId);
      const session = await this.cash.requireOpen(tx, input.branchId);
      const [store] = await tx.select().from(tenants);

      const incoming = await this.valueReturnedItems(tx, sale, input.items);
      const returnedCents = incoming.reduce((a, i) => a + i.valueCents, 0);
      const outgoing = input.replacements.length ? await priceLines(tx, input.replacements) : [];
      const replacementCents = computeTax(outgoing.reduce((a, l) => a + l.grossCents, 0), store.taxRateBp, store.pricesIncludeTax).total;

      // Diferencia: > 0 paga el cliente, < 0 se le reembolsa.
      const difference = replacementCents - returnedCents;
      if (difference === 0 && input.payments.length) throw new BadRequestException('No hay diferencia que cobrar ni reembolsar');
      if (difference !== 0) assertPaymentsMatch(input.payments, Math.abs(difference));
      if (difference > 0) assertCreditCodes(input.payments);

      const ret = await this.insertReturn(tx, user, { sale, input, sessionId: session.id, incoming, outgoing, returnedCents, replacementCents, difference });
      const credit = await this.settleDifference(tx, user, { sale, ret, sessionId: session.id, payments: input.payments, difference });

      await this.inventory.apply(tx, user, input.branchId, [
        ...incoming.map((i) => ({ variantId: i.item.variantId, quantity: i.quantity, type: 'return_in' as const, unitCostCents: i.item.unitCostCents, referenceType: 'return', referenceId: ret.id, reason: input.reason })),
        ...outgoing.map((l) => ({ variantId: l.variantId, quantity: -l.quantity, type: 'exchange_out' as const, unitCostCents: l.unitCostCents, referenceType: 'return', referenceId: ret.id })),
      ]);
      await this.audit.log(tx, user, 'sale.returned', 'return', ret.id, { saleId, returnedCents, replacementCents, difference });
      await this.events.publish(tx, {
        type: 'return.recorded',
        user,
        saleId,
        returnId: ret.id,
        branchId: input.branchId,
        reason: input.reason,
        incoming: incoming.map((i) => ({ variantId: i.item.variantId, quantity: i.quantity, amountCents: i.valueCents })),
        outgoing: outgoing.map((l) => ({ variantId: l.variantId, quantity: l.quantity, amountCents: l.grossCents })),
      });

      // El código del vale se devuelve UNA sola vez (para imprimirlo o enviarlo al cliente).
      return { ...ret, credit, items: { in: incoming.map((i) => ({ saleItemId: i.item.id, quantity: i.quantity, valueCents: i.valueCents })), out: outgoing } };
    }, (r) => r.id, async (id) => ({ ...(await tx.select().from(returns).where(eq(returns.id, id)))[0], credit: null, items: { in: [], out: [] }, replayed: true })));
  }

  private async lockReturnableSale(tx: Tx, saleId: string) {
    const [sale] = await tx.select().from(sales).where(eq(sales.id, saleId)).for('update');
    if (!sale) throw new NotFoundException('Venta no encontrada');
    if (sale.status !== 'completed') throw new ConflictException('La venta está anulada');
    return sale;
  }

  /**
   * Lo que vuelve se valora al precio REALMENTE pagado (con su parte del descuento). El factor
   * total/neto incluye el IGV si los precios no lo incluían. UPDATE condicional: no se devuelve
   * más de lo vendido, ni con dos devoluciones simultáneas.
   */
  private async valueReturnedItems(tx: Tx, sale: typeof sales.$inferSelect, items: { saleItemId: string; quantity: number }[]) {
    const net = sale.subtotalCents - sale.discountCents;
    const ratio = net > 0 ? sale.totalCents / net : 0;
    const out: { item: typeof saleItems.$inferSelect; quantity: number; valueCents: number }[] = [];
    for (const r of items) {
      const [item] = await tx
        .update(saleItems)
        .set({ returnedQuantity: sql`${saleItems.returnedQuantity} + ${r.quantity}` })
        .where(and(eq(saleItems.id, r.saleItemId), eq(saleItems.saleId, sale.id), sql`${saleItems.returnedQuantity} + ${r.quantity} <= ${saleItems.quantity}`))
        .returning();
      if (!item) throw new UnprocessableEntityException({ message: 'Cantidad a devolver inválida', saleItemId: r.saleItemId });
      out.push({ item, quantity: r.quantity, valueCents: Math.round(((item.lineTotalCents * r.quantity) / item.quantity) * ratio) });
    }
    return out;
  }

  private async insertReturn(
    tx: Tx,
    user: AuthUser,
    p: {
      sale: typeof sales.$inferSelect;
      input: z.infer<typeof CreateReturnSchema>;
      sessionId: string;
      incoming: Awaited<ReturnType<ReturnsService['valueReturnedItems']>>;
      outgoing: Awaited<ReturnType<typeof priceLines>>;
      returnedCents: number;
      replacementCents: number;
      difference: number;
    },
  ) {
    const number = await nextNumber(tx, user.tenantId, 'return');
    const [ret] = await tx
      .insert(returns)
      .values({
        tenantId: user.tenantId,
        saleId: p.sale.id,
        branchId: p.input.branchId,
        cashSessionId: p.sessionId,
        number,
        kind: p.outgoing.length ? 'exchange' : 'refund',
        returnedCents: p.returnedCents,
        replacementCents: p.replacementCents,
        differenceCents: p.difference,
        reason: p.input.reason,
        createdBy: user.membershipId,
      })
      .returning();
    await tx.insert(returnItems).values([
      ...p.incoming.map((i) => ({ tenantId: user.tenantId, returnId: ret.id, direction: 'in' as const, saleItemId: i.item.id, variantId: i.item.variantId, quantity: i.quantity, unitPriceCents: Math.round(i.valueCents / i.quantity) })),
      ...p.outgoing.map((l) => ({ tenantId: user.tenantId, returnId: ret.id, direction: 'out' as const, variantId: l.variantId, quantity: l.quantity, unitPriceCents: l.unitPriceCents })),
    ]);
    return ret;
  }

  /**
   * Liquida la diferencia: cobra (puede ser con vale), reembolsa, o emite SALDO A FAVOR a nombre
   * del cliente de la venta. Devuelve el vale emitido (si lo hubo) para mostrarlo una vez.
   */
  private async settleDifference(
    tx: Tx,
    user: AuthUser,
    p: { sale: typeof sales.$inferSelect; ret: typeof returns.$inferSelect; sessionId: string; payments: z.infer<typeof CreateReturnSchema>['payments']; difference: number },
  ) {
    if (p.difference === 0) return null;
    const sign = p.difference > 0 ? 1 : -1;
    let issued: { code: string; balanceCents: number; expiresAt: Date | null } | null = null;
    for (const pay of p.payments) {
      let creditId: string | undefined;
      let reference = pay.reference;
      if (pay.method === 'store_credit' && sign < 0) {
        const c = await this.credits.issueTx(tx, user, { kind: 'refund', amountCents: pay.amountCents, customerId: p.sale.customerId, note: `Devolución #${p.ret.number}` });
        issued = { code: c.code, balanceCents: c.balanceCents, expiresAt: c.expiresAt };
        creditId = c.id;
        reference = `Vale …${c.last4}`;
      } else if (pay.method === 'store_credit') {
        const c = await this.credits.redeemTx(tx, user, pay.creditCode!, pay.amountCents, p.sale.id);
        creditId = c.id;
        reference = `Vale …${c.codeLast4}`;
      }
      await tx.insert(payments).values({ tenantId: user.tenantId, cashSessionId: p.sessionId, returnId: p.ret.id, method: pay.method, amountCents: sign * pay.amountCents, reference, storeCreditId: creditId });
    }
    return issued;
  }


  listForSale(user: AuthUser, saleId: string) {
    return this.db.withTenant(user.tenantId, (tx) => tx.select().from(returns).where(eq(returns.saleId, saleId)));
  }
}
