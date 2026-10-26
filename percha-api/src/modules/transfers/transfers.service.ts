import { IdempotencyService } from '../../common/idempotency';
import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, desc, eq, inArray, or } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { positiveQty } from '../../common/schemas';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import { branches, products, transferItems, transfers, variants } from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { InventoryService } from '../inventory/inventory.service';
import { EInvoiceService } from '../einvoice/einvoice.service';
import { ShipmentSchema } from '../einvoice/guide';
import { EventBus } from '../../common/events';

export const CreateTransferSchema = z
  .object({
    fromBranchId: z.string().uuid(),
    toBranchId: z.string().uuid(),
    items: z.array(z.object({ variantId: z.string().uuid(), quantity: positiveQty })).min(1).max(500),
    notes: z.string().trim().max(500).optional(),
    /** Datos del traslado para la guía de remisión (obligatorio si la tienda emite comprobantes). */
    shipment: ShipmentSchema.optional(),
  })
  .refine((t) => t.fromBranchId !== t.toBranchId, 'El origen y el destino deben ser distintos')
  .refine((t) => new Set(t.items.map((i) => i.variantId)).size === t.items.length, 'Cada variante una sola vez');

export const ReceiveTransferSchema = z.object({
  /** Lo que realmente llegó por ítem. Si falta un ítem, se asume que llegó completo. */
  items: z.array(z.object({ itemId: z.string().uuid(), quantity: z.number().int().min(0) })).default([]),
  notes: z.string().trim().max(500).optional(),
});

export const ListTransfersSchema = z.object({
  status: z.enum(['in_transit', 'received', 'cancelled']).optional(),
  branchId: z.string().uuid().optional(),
});

/**
 * Transferencias entre sucursales en dos pasos, como ocurre en la realidad:
 *
 *   ENVIAR (origen)  → sale el stock del origen; la mercadería queda "en tránsito"
 *   RECIBIR (destino) → entra al destino lo que realmente llegó (puede ser menos)
 *   CANCELAR          → solo en tránsito: el stock vuelve al origen
 *
 * En tránsito el stock no está disponible en ninguna sucursal: no se puede vender dos veces
 * la misma prenda. Las diferencias al recibir (faltantes) quedan registradas y auditadas.
 */
@Injectable()
export class TransfersService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(InventoryService) private readonly inventory: InventoryService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(EventBus) private readonly events: EventBus,
    @Inject(EInvoiceService) private readonly einvoice: EInvoiceService,
    @Inject(IdempotencyService) private readonly idem: IdempotencyService,
  ) {}

  async send(user: AuthUser, input: z.infer<typeof CreateTransferSchema>, idempotencyKey?: string) {
    assertBranchAccess(user, input.fromBranchId);
    const result = await this.db.withTenant(user.tenantId, async (tx) =>
      this.idem.once(tx, user.tenantId, idempotencyKey, 'transfer.send', input, async () => {
      const vs = await tx
        .select({ id: variants.id, avg: variants.avgCostCents })
        .from(variants)
        .where(inArray(variants.id, input.items.map((i) => i.variantId)));
      if (vs.length !== input.items.length) throw new BadRequestException('Hay variantes inexistentes');

      const number = await nextNumber(tx, user.tenantId, 'transfer');
      const [t] = await tx
        .insert(transfers)
        .values({ tenantId: user.tenantId, number, fromBranchId: input.fromBranchId, toBranchId: input.toBranchId, notes: input.notes, sentBy: user.membershipId })
        .returning();
      await tx.insert(transferItems).values(
        input.items.map((i) => ({
          tenantId: user.tenantId,
          transferId: t.id,
          variantId: i.variantId,
          quantitySent: i.quantity,
          unitCostCents: vs.find((v) => v.id === i.variantId)!.avg,
        })),
      );
      // Si falta stock de una prenda, no se envía nada (misma regla que una venta).
      await this.inventory.apply(
        tx,
        user,
        input.fromBranchId,
        input.items.map((i) => ({
          variantId: i.variantId,
          quantity: -i.quantity,
          type: 'transfer_out' as const,
          unitCostCents: vs.find((v) => v.id === i.variantId)!.avg,
          referenceType: 'transfer',
          referenceId: t.id,
        })),
      );
      const units = input.items.reduce((a, i) => a + i.quantity, 0);
      await this.audit.log(tx, user, 'transfer.sent', 'transfer', t.id, { to: input.toBranchId, units });
      const [from] = await tx.select({ name: branches.name }).from(branches).where(eq(branches.id, input.fromBranchId));
      // Lo que pasa después (guía de remisión, aviso al destino) lo deciden los suscriptores.
      await this.events.publish(tx, {
        type: 'transfer.sent',
        user,
        transferId: t.id,
        number,
        fromBranchId: input.fromBranchId,
        fromBranchName: from?.name ?? 'otra sucursal',
        toBranchId: input.toBranchId,
        items: input.items,
        shipment: input.shipment,
        notes: input.notes,
      });
      return this.load(tx, t.id);
    }, (t) => t.id, (id) => this.load(tx, id)));
    // La guía se envía al OSE después del commit: se relee para mostrar su estado.
    return this.db.withTenant(user.tenantId, (tx) => this.load(tx, result.id));
  }

  receive(user: AuthUser, id: string, input: z.infer<typeof ReceiveTransferSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const t = await this.lockInTransit(tx, id);
      assertBranchAccess(user, t.toBranchId);
      const items = await tx.select().from(transferItems).where(eq(transferItems.transferId, id));

      const received = items.map((it) => {
        const declared = input.items.find((x) => x.itemId === it.id);
        const qty = declared?.quantity ?? it.quantitySent;
        if (qty > it.quantitySent) throw new BadRequestException('No se puede recibir más de lo enviado');
        return { it, qty };
      });
      if (input.items.some((x) => !items.some((it) => it.id === x.itemId))) throw new BadRequestException('Ítem que no pertenece a la transferencia');

      for (const r of received) {
        await tx.update(transferItems).set({ quantityReceived: r.qty }).where(eq(transferItems.id, r.it.id));
      }
      await this.inventory.apply(
        tx,
        user,
        t.toBranchId,
        received
          .filter((r) => r.qty > 0)
          .map((r) => ({ variantId: r.it.variantId, quantity: r.qty, type: 'transfer_in' as const, unitCostCents: r.it.unitCostCents, referenceType: 'transfer', referenceId: id })),
      );
      await tx
        .update(transfers)
        .set({ status: 'received', receivedBy: user.membershipId, receivedAt: new Date(), receiveNotes: input.notes })
        .where(eq(transfers.id, id));

      const missing = received.filter((r) => r.qty < r.it.quantitySent).map((r) => ({ variantId: r.it.variantId, missing: r.it.quantitySent - r.qty }));
      await this.audit.log(tx, user, missing.length ? 'transfer.received_with_shortage' : 'transfer.received', 'transfer', id, { missing, notes: input.notes });
      return this.load(tx, id);
    });
  }

  cancel(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const t = await this.lockInTransit(tx, id);
      assertBranchAccess(user, t.fromBranchId);
      const items = await tx.select().from(transferItems).where(eq(transferItems.transferId, id));
      await this.inventory.apply(
        tx,
        user,
        t.fromBranchId,
        items.map((i) => ({ variantId: i.variantId, quantity: i.quantitySent, type: 'transfer_in' as const, unitCostCents: i.unitCostCents, referenceType: 'transfer', referenceId: id, reason: 'Transferencia cancelada' })),
      );
      await tx.update(transfers).set({ status: 'cancelled' }).where(eq(transfers.id, id));
      await this.audit.log(tx, user, 'transfer.cancelled', 'transfer', id);
      await this.events.publish(tx, { type: 'transfer.cancelled', user, transferId: id });
      return this.load(tx, id);
    });
  }

  list(user: AuthUser, q: z.infer<typeof ListTransfersSchema>) {
    const branchId = q.branchId ?? user.branchId ?? undefined;
    if (branchId) assertBranchAccess(user, branchId);
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select()
        .from(transfers)
        .where(
          and(
            q.status ? eq(transfers.status, q.status) : undefined,
            // Una sucursal ve lo que envió y lo que le llega.
            branchId ? or(eq(transfers.fromBranchId, branchId), eq(transfers.toBranchId, branchId)) : undefined,
          ),
        )
        .orderBy(desc(transfers.sentAt))
        .limit(100),
    );
  }

  get(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const t = await this.load(tx, id);
      if (user.branchId && user.branchId !== t.fromBranchId && user.branchId !== t.toBranchId) {
        throw new NotFoundException('Transferencia no encontrada');
      }
      return t;
    });
  }

  private async lockInTransit(tx: Tx, id: string) {
    const [t] = await tx.select().from(transfers).where(eq(transfers.id, id)).for('update');
    if (!t) throw new NotFoundException('Transferencia no encontrada');
    if (t.status !== 'in_transit') throw new ConflictException(`La transferencia ya está ${t.status === 'received' ? 'recibida' : 'cancelada'}`);
    return t;
  }

  private async load(tx: Tx, id: string) {
    const [t] = await tx.select().from(transfers).where(eq(transfers.id, id));
    if (!t) throw new NotFoundException('Transferencia no encontrada');
    const items = await tx
      .select({ item: transferItems, sku: variants.sku, options: variants.options, productName: products.name })
      .from(transferItems)
      .innerJoin(variants, eq(variants.id, transferItems.variantId))
      .innerJoin(products, eq(products.id, variants.productId))
      .where(eq(transferItems.transferId, id));
    const documents = (await this.einvoice.forTransfer(tx, id)).map(({ payload: _p, ...d }) => d);
    return {
      ...t,
      documents,
      items: items.map(({ item, ...rest }) => ({
        ...item,
        ...rest,
        missing: item.quantityReceived == null ? null : item.quantitySent - item.quantityReceived,
      })),
    };
  }
}
