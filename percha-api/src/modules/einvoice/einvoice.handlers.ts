import { Inject, Injectable } from '@nestjs/common';
import { EventBus } from '../../common/events';
import { DatabaseService, Tx } from '../../database/database.service';
import { EInvoiceService } from './einvoice.service';
import { ShipmentSchema } from './guide';

/**
 * Cuándo se emite cada comprobante, como reacción a los hechos del negocio. Ventas,
 * devoluciones y transferencias no conocen a SUNAT: solo publican lo que pasó.
 *
 * Todo se numera dentro de la transacción del hecho (si falla, no se consume número) y se
 * envía al OSE después del commit.
 */
@Injectable()
export class EInvoiceHandlers {
  constructor(
    @Inject(EventBus) bus: EventBus,
    @Inject(EInvoiceService) private readonly einvoice: EInvoiceService,
    @Inject(DatabaseService) private readonly db: DatabaseService,
  ) {
    bus.on('sale.recorded', 'emitir boleta o factura', async (tx, e) => {
      const doc = await this.einvoice.issueForSale(tx, e.user, { saleId: e.saleId, branchId: e.branchId, lines: e.lines, request: e.document, issuedAt: e.occurredAt });
      this.dispatchAfterCommit(tx, e.user.tenantId, doc?.id);
    });

    bus.on('sale.voided', 'nota de crédito por anulación (01)', async (tx, e) => {
      const source = await this.einvoice.saleDocument(tx, e.saleId);
      if (!source) return;
      const nc = await this.einvoice.issueCreditNote(tx, e.user, { source, branchId: e.branchId, reasonCode: '01', reasonText: e.reason });
      this.dispatchAfterCommit(tx, e.user.tenantId, nc?.id);
    });

    bus.on('return.recorded', 'nota de crédito por devolución (07) y comprobante del cambio', async (tx, e) => {
      const source = await this.einvoice.saleDocument(tx, e.saleId);
      if (!source) return;
      const nc = await this.einvoice.issueCreditNote(tx, e.user, { source, branchId: e.branchId, returnId: e.returnId, reasonCode: '07', reasonText: e.reason, lines: e.incoming });
      const replacement = e.outgoing.length ? await this.einvoice.issueReplacement(tx, e.user, { source, branchId: e.branchId, returnId: e.returnId, lines: e.outgoing }) : null;
      this.dispatchAfterCommit(tx, e.user.tenantId, nc?.id, replacement?.id);
    });

    bus.on('transfer.sent', 'guía de remisión (motivo 04)', async (tx, e) => {
      const guide = await this.einvoice.issueGuideForTransfer(tx, e.user, {
        transferId: e.transferId,
        fromBranchId: e.fromBranchId,
        toBranchId: e.toBranchId,
        items: e.items,
        shipment: e.shipment ? ShipmentSchema.parse(e.shipment) : undefined,
        note: e.notes,
      });
      this.dispatchAfterCommit(tx, e.user.tenantId, guide?.id);
    });

    bus.on('transfer.cancelled', 'pedir baja de guías aceptadas', async (tx, e) => {
      for (const g of (await this.einvoice.forTransfer(tx, e.transferId)).filter((d) => d.status === 'accepted')) {
        await bus.publish(tx, { type: 'einvoice.guide_void_needed', tenantId: e.user.tenantId, transferId: e.transferId, serie: g.serie, numero: g.numero });
      }
    });
  }

  private dispatchAfterCommit(tx: Tx, tenantId: string, ...ids: (string | undefined)[]) {
    const pending = ids.filter((x): x is string => Boolean(x));
    if (pending.length) this.db.afterCommit(tx, () => this.einvoice.afterCommit(tenantId, pending));
  }
}
