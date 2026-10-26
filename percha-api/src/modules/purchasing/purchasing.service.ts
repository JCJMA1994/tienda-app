import { IdempotencyService } from '../../common/idempotency';
import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { and, asc, desc, eq, inArray, sql } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { cents, positiveQty } from '../../common/schemas';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import {
  goodsReceiptItems,
  goodsReceipts,
  products,
  purchaseOrderItems,
  purchaseOrders,
  stockLevels,
  suppliers,
  variants,
} from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { InventoryService } from '../inventory/inventory.service';
import { LookupService } from '../lookup/lookup.service';

export const SupplierSchema = z.object({
  name: z.string().trim().min(2).max(120),
  ruc: z.string().regex(/^\d{11}$/).nullable().optional(),
  contactName: z.string().trim().max(80).nullable().optional(),
  phone: z.string().trim().max(30).nullable().optional(),
  email: z.string().email().nullable().optional(),
  active: z.boolean().optional(),
});

const PoItem = z.object({ variantId: z.string().uuid(), quantity: positiveQty, unitCostCents: cents });

export const CreatePoSchema = z.object({
  supplierId: z.string().uuid(),
  branchId: z.string().uuid(),
  expectedAt: z.string().date().optional(),
  notes: z.string().max(500).optional(),
  items: z.array(PoItem).min(1).max(500),
});

export const UpdatePoSchema = CreatePoSchema.omit({ branchId: true }).partial();

export const ReceiveSchema = z.object({
  items: z
    .array(
      z.object({
        purchaseOrderItemId: z.string().uuid(),
        quantity: positiveQty,
        /** Si la factura trae otro costo que la OC. */
        unitCostCents: cents.optional(),
      }),
    )
    .min(1),
  notes: z.string().max(500).optional(),
  /** Factura (o boleta) del proveedor que respalda la mercadería: se valida en SUNAT. */
  supplierInvoice: z
    .object({
      type: z.enum(['01', '03']).default('01'),
      serie: z.string().regex(/^[A-Z0-9]{1,4}$/i).transform((s) => s.toUpperCase()),
      numero: z.number().int().positive().max(99_999_999),
      date: z.string().date(),
      totalCents: cents.optional(),
    })
    .optional(),
});

export const ListPoSchema = z.object({
  status: z.enum(['draft', 'ordered', 'partial', 'received', 'cancelled']).optional(),
  supplierId: z.string().uuid().optional(),
});

/**
 * Ciclo de una orden de compra:
 *   draft ──confirm──▶ ordered ──receive──▶ partial ──receive──▶ received
 *     └──────────── cancel ◀────┘  (solo si aún no se recibió nada)
 */
@Injectable()
export class PurchasingService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(InventoryService) private readonly inventory: InventoryService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(LookupService) private readonly lookup: LookupService,
    @Inject(IdempotencyService) private readonly idem: IdempotencyService,
  ) {}

  // ---------- proveedores ----------

  listSuppliers(user: AuthUser) {
    return this.db.withTenant(user.tenantId, (tx) => tx.select().from(suppliers).orderBy(asc(suppliers.name)));
  }

  createSupplier(user: AuthUser, input: z.infer<typeof SupplierSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => (await tx.insert(suppliers).values({ tenantId: user.tenantId, ...input }).returning())[0]);
  }

  updateSupplier(user: AuthUser, id: string, input: Partial<z.infer<typeof SupplierSchema>>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx.update(suppliers).set(input).where(eq(suppliers.id, id)).returning();
      if (!row) throw new NotFoundException('Proveedor no encontrado');
      return row;
    });
  }

  // ---------- órdenes de compra ----------

  create(user: AuthUser, input: z.infer<typeof CreatePoSchema>) {
    assertBranchAccess(user, input.branchId);
    this.assertUniqueVariants(input.items);
    return this.db.withTenant(user.tenantId, async (tx) => {
      const number = await nextNumber(tx, user.tenantId, 'purchase_order');
      const [po] = await tx
        .insert(purchaseOrders)
        .values({
          tenantId: user.tenantId,
          number,
          supplierId: input.supplierId,
          branchId: input.branchId,
          expectedAt: input.expectedAt,
          notes: input.notes,
          totalCents: this.total(input.items),
          createdBy: user.membershipId,
        })
        .returning();
      await this.insertItems(tx, user, po.id, input.items);
      return this.load(tx, user, po.id);
    });
  }

  /** Solo editable en borrador: una OC enviada al proveedor es un compromiso. */
  update(user: AuthUser, id: string, input: z.infer<typeof UpdatePoSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const po = await this.lock(tx, user, id);
      if (po.status !== 'draft') throw new ConflictException('Solo se puede editar una orden en borrador');
      if (input.items) {
        this.assertUniqueVariants(input.items);
        await tx.delete(purchaseOrderItems).where(eq(purchaseOrderItems.purchaseOrderId, id));
        await this.insertItems(tx, user, id, input.items);
      }
      const { items, ...rest } = input;
      await tx
        .update(purchaseOrders)
        .set({ ...rest, ...(items ? { totalCents: this.total(items) } : {}) })
        .where(eq(purchaseOrders.id, id));
      return this.load(tx, user, id);
    });
  }

  confirm(user: AuthUser, id: string) {
    return this.transition(user, id, ['draft'], 'ordered');
  }

  cancel(user: AuthUser, id: string) {
    return this.transition(user, id, ['draft', 'ordered'], 'cancelled');
  }

  /**
   * Recepción (total o parcial). En una transacción:
   * 1) valida que no se reciba más de lo pendiente,
   * 2) recalcula el costo promedio ponderado de cada variante,
   * 3) registra la entrada en el kardex,
   * 4) actualiza el estado de la OC.
   */
  receive(user: AuthUser, id: string, input: z.infer<typeof ReceiveSchema>, idempotencyKey?: string) {
    return this.db.withTenant(user.tenantId, async (tx) =>
      this.idem.once(tx, user.tenantId, idempotencyKey, 'purchase.receive', { id, ...input }, async () => {
      const po = await this.lock(tx, user, id);
      if (po.status !== 'ordered' && po.status !== 'partial') {
        throw new ConflictException(`No se puede recibir una orden en estado ${po.status}`);
      }

      const lines = await tx.select().from(purchaseOrderItems).where(eq(purchaseOrderItems.purchaseOrderId, id));
      const received = input.items.map((r) => {
        const line = lines.find((l) => l.id === r.purchaseOrderItemId);
        if (!line) throw new BadRequestException(`Ítem ${r.purchaseOrderItemId} no pertenece a esta orden`);
        const pending = line.quantityOrdered - line.quantityReceived;
        if (r.quantity > pending) {
          throw new UnprocessableEntityException({ message: 'Se intenta recibir más de lo pendiente', purchaseOrderItemId: line.id, pending });
        }
        return { line, quantity: r.quantity, unitCostCents: r.unitCostCents ?? line.unitCostCents };
      });

      const invoice = input.supplierInvoice ? await this.validateSupplierInvoice(tx, po.supplierId, input.supplierInvoice) : null;

      const number = await nextNumber(tx, user.tenantId, 'goods_receipt');
      const [receipt] = await tx
        .insert(goodsReceipts)
        .values({
          tenantId: user.tenantId,
          number,
          purchaseOrderId: id,
          branchId: po.branchId,
          receivedBy: user.membershipId,
          notes: input.notes,
          supplierInvoiceSerie: input.supplierInvoice?.serie,
          supplierInvoiceNumber: input.supplierInvoice?.numero,
          supplierInvoiceDate: input.supplierInvoice?.date,
          supplierInvoiceTotalCents: input.supplierInvoice?.totalCents,
          supplierInvoiceStatus: invoice?.status,
          supplierInvoiceDetail: invoice?.detail,
        })
        .returning();

      for (const r of received) {
        await tx
          .update(purchaseOrderItems)
          .set({ quantityReceived: sql`${purchaseOrderItems.quantityReceived} + ${r.quantity}` })
          .where(eq(purchaseOrderItems.id, r.line.id));
        await tx.insert(goodsReceiptItems).values({
          tenantId: user.tenantId,
          receiptId: receipt.id,
          purchaseOrderItemId: r.line.id,
          variantId: r.line.variantId,
          quantity: r.quantity,
          unitCostCents: r.unitCostCents,
        });
        await this.updateAverageCost(tx, r.line.variantId, r.quantity, r.unitCostCents);
      }

      await this.inventory.apply(
        tx,
        user,
        po.branchId,
        received.map((r) => ({ variantId: r.line.variantId, quantity: r.quantity, type: 'purchase_receipt' as const, unitCostCents: r.unitCostCents, referenceType: 'goods_receipt', referenceId: receipt.id })),
      );

      const [{ pending }] = await tx
        .select({ pending: sql<number>`coalesce(sum(${purchaseOrderItems.quantityOrdered} - ${purchaseOrderItems.quantityReceived}),0)::int` })
        .from(purchaseOrderItems)
        .where(eq(purchaseOrderItems.purchaseOrderId, id));
      const status = pending === 0 ? 'received' : 'partial';
      await tx.update(purchaseOrders).set({ status }).where(eq(purchaseOrders.id, id));
      await this.audit.log(tx, user, 'purchase.received', 'goods_receipt', receipt.id, { purchaseOrderId: id, status });

      return { receipt, status, invoice, order: await this.load(tx, user, id) };
    }, (r) => r.receipt.id, async (receiptId) => ({ receipt: (await tx.select().from(goodsReceipts).where(eq(goodsReceipts.id, receiptId)))[0], status: (await this.load(tx, user, id)).status, invoice: null, order: await this.load(tx, user, id), replayed: true })));
  }

  list(user: AuthUser, q: z.infer<typeof ListPoSchema>) {
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select({ order: purchaseOrders, supplierName: suppliers.name })
        .from(purchaseOrders)
        .innerJoin(suppliers, eq(suppliers.id, purchaseOrders.supplierId))
        .where(
          and(
            q.status ? eq(purchaseOrders.status, q.status) : undefined,
            q.supplierId ? eq(purchaseOrders.supplierId, q.supplierId) : undefined,
            user.branchId ? eq(purchaseOrders.branchId, user.branchId) : undefined,
          ),
        )
        .orderBy(desc(purchaseOrders.createdAt))
        .then((rows) => rows.map((r) => ({ ...r.order, supplierName: r.supplierName }))),
    );
  }

  get(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, (tx) => this.load(tx, user, id));
  }

  receipts(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      await this.load(tx, user, id);
      const rs = await tx.select().from(goodsReceipts).where(eq(goodsReceipts.purchaseOrderId, id)).orderBy(asc(goodsReceipts.createdAt));
      const items = rs.length ? await tx.select().from(goodsReceiptItems).where(inArray(goodsReceiptItems.receiptId, rs.map((r) => r.id))) : [];
      return rs.map((r) => ({ ...r, items: items.filter((i) => i.receiptId === r.id) }));
    });
  }

  // ---------- helpers ----------

  /**
   * Costo promedio ponderado (método permitido por SUNAT y el más simple para retail):
   *   nuevo = (stock_actual × costo_actual + cantidad × costo_compra) / (stock_actual + cantidad)
   * Se bloquea la variante para que dos recepciones simultáneas no pisen el cálculo.
   * Si el stock es negativo o cero, el costo de la compra pasa a ser el nuevo promedio.
   */
  private async updateAverageCost(tx: Tx, variantId: string, quantity: number, unitCostCents: number) {
    const [v] = await tx.select({ avg: variants.avgCostCents }).from(variants).where(eq(variants.id, variantId)).for('update');
    const [{ onHand }] = await tx
      .select({ onHand: sql<number>`coalesce(sum(${stockLevels.quantity}),0)::int` })
      .from(stockLevels)
      .where(eq(stockLevels.variantId, variantId));
    const base = Math.max(onHand, 0);
    const newAvg = Math.round((base * v.avg + quantity * unitCostCents) / (base + quantity));
    await tx.update(variants).set({ avgCostCents: newAvg }).where(eq(variants.id, variantId));
  }

  private async transition(user: AuthUser, id: string, from: string[], to: 'ordered' | 'cancelled') {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const po = await this.lock(tx, user, id);
      if (!from.includes(po.status)) throw new ConflictException(`No se puede pasar de ${po.status} a ${to}`);
      await tx.update(purchaseOrders).set({ status: to }).where(eq(purchaseOrders.id, id));
      await this.audit.log(tx, user, `purchase.${to}`, 'purchase_order', id);
      return this.load(tx, user, id);
    });
  }

  private async lock(tx: Tx, user: AuthUser, id: string) {
    const [po] = await tx.select().from(purchaseOrders).where(eq(purchaseOrders.id, id)).for('update');
    if (!po) throw new NotFoundException('Orden no encontrada');
    assertBranchAccess(user, po.branchId);
    return po;
  }

  private async load(tx: Tx, user: AuthUser, id: string) {
    const [po] = await tx.select().from(purchaseOrders).where(eq(purchaseOrders.id, id));
    if (!po) throw new NotFoundException('Orden no encontrada');
    assertBranchAccess(user, po.branchId);
    const items = await tx
      .select({ item: purchaseOrderItems, sku: variants.sku, options: variants.options, productName: products.name })
      .from(purchaseOrderItems)
      .innerJoin(variants, eq(variants.id, purchaseOrderItems.variantId))
      .innerJoin(products, eq(products.id, variants.productId))
      .where(eq(purchaseOrderItems.purchaseOrderId, id));
    return { ...po, items: items.map(({ item, ...rest }) => ({ ...item, ...rest, pending: item.quantityOrdered - item.quantityReceived })) };
  }

  private async insertItems(tx: Tx, user: AuthUser, poId: string, items: z.infer<typeof PoItem>[]) {
    await tx.insert(purchaseOrderItems).values(
      items.map((i) => ({ tenantId: user.tenantId, purchaseOrderId: poId, variantId: i.variantId, quantityOrdered: i.quantity, unitCostCents: i.unitCostCents })),
    );
  }

  private total(items: z.infer<typeof PoItem>[]) {
    return items.reduce((a, i) => a + i.quantity * i.unitCostCents, 0);
  }

  private assertUniqueVariants(items: { variantId: string }[]) {
    if (new Set(items.map((i) => i.variantId)).size !== items.length) {
      throw new BadRequestException('Cada variante debe aparecer una sola vez en la orden');
    }
  }

  /**
   * Factura del proveedor en SUNAT: anulada o inexistente → no se registra la compra (no
   * sustenta costo ni crédito fiscal). Servicio caído → se registra como "sin verificar".
   */
  private async validateSupplierInvoice(tx: Tx, supplierId: string, inv: NonNullable<z.infer<typeof ReceiveSchema>['supplierInvoice']>) {
    const [sup] = await tx.select({ ruc: suppliers.ruc }).from(suppliers).where(eq(suppliers.id, supplierId));
    if (!sup?.ruc) throw new BadRequestException({ message: 'El proveedor no tiene RUC: agrégalo para validar su factura', code: 'SUPPLIER_RUC_MISSING' });
    const r = await this.lookup.validateCpe({ ruc: sup.ruc, ...inv });
    if (r && r.verdict === 'invalid') {
      throw new UnprocessableEntityException({ message: `La factura ${inv.serie}-${inv.numero} figura como ${r.status} en SUNAT`, code: 'SUPPLIER_INVOICE_INVALID', status: r.status, observations: r.observations });
    }
    return r ? { status: 'valid', detail: [r.status, r.rucCondition].filter(Boolean).join(' · ') } : { status: 'unverified', detail: 'Servicio de validación no disponible' };
  }

}
