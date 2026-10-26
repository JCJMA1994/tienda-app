import { pgEnum } from 'drizzle-orm/pg-core';

export const tenantStatus = pgEnum('tenant_status', ['active', 'suspended']);
export const roleEnum = pgEnum('member_role', ['owner', 'manager', 'seller', 'stock']);
export const memberStatus = pgEnum('member_status', ['active', 'disabled']);

export const movementType = pgEnum('movement_type', [
  'initial', // carga inicial (alta de producto / importación)
  'adjustment', // ajuste manual con motivo
  'purchase_receipt', // recepción de mercadería
  'sale', // venta
  'sale_void', // anulación de venta (reverso)
  'return_in', // prenda que el cliente devuelve
  'exchange_out', // prenda entregada en un cambio
  'transfer_out', // sale de una sucursal hacia otra (queda "en tránsito")
  'transfer_in', // llega a la sucursal destino (o vuelve al origen si se cancela)
  'layaway_reserve', // prenda separada (apartado): sale del disponible sin venderse
  'layaway_release', // vuelve al disponible (apartado cancelado o entregado)
]);

export const transferStatus = pgEnum('transfer_status', ['in_transit', 'received', 'cancelled']);

export const cashSessionStatus = pgEnum('cash_session_status', ['open', 'closed']);
export const saleStatus = pgEnum('sale_status', ['completed', 'voided']);
/**
 * store_credit: pago con vale / saldo a favor (no entra a caja).
 * layaway: venta que se paga con lo abonado en un apartado (los abonos ya entraron a caja).
 */
export const paymentMethod = pgEnum('payment_method', ['cash', 'card', 'wallet', 'transfer', 'store_credit', 'layaway']);
export const returnKind = pgEnum('return_kind', ['refund', 'exchange']);
export const returnDirection = pgEnum('return_direction', ['in', 'out']);

export const purchaseOrderStatus = pgEnum('purchase_order_status', [
  'draft',
  'ordered',
  'partial',
  'received',
  'cancelled',
]);
