import { Global, Injectable, Logger, Module } from '@nestjs/common';
import type { Tx } from '../database/database.service';
import type { AuthUser } from './auth-user';

/**
 * Eventos de dominio: "esto pasó". Quien publica no sabe quién reacciona; cada módulo se
 * suscribe a lo que le interesa (comprobantes, notificaciones, clientes…). Así una función
 * nueva se agrega SUSCRIBIÉNDOSE, sin editar el servicio que origina el hecho.
 *
 * Los manejadores corren DENTRO de la transacción del evento (con el mismo `tx`): si uno falla,
 * se revierte todo (p. ej. sin guía de remisión válida no se envía la mercadería). Para lo que
 * debe ocurrir después del commit (enviar al OSE), usan `DatabaseService.afterCommit`.
 */
export interface SaleLine {
  variantId: string;
  quantity: number;
  /** Lo cobrado por la línea (ya con su parte del descuento). */
  amountCents: number;
}

export type DomainEvent =
  | {
      type: 'sale.recorded';
      user: AuthUser;
      saleId: string;
      branchId: string;
      lines: SaleLine[];
      document?: { type: 'boleta' | 'factura'; customer?: { docType: 'none' | 'dni' | 'ruc' | 'ce'; docNumber?: string; name?: string; address?: string } };
      customerId?: string;
      /** Momento real de la venta (difiere de "ahora" en ventas sin conexión). */
      occurredAt: Date;
    }
  | { type: 'sale.voided'; user: AuthUser; saleId: string; branchId: string; reason: string }
  | {
      type: 'return.recorded';
      user: AuthUser;
      saleId: string;
      returnId: string;
      branchId: string;
      reason: string;
      incoming: SaleLine[];
      outgoing: SaleLine[];
    }
  | {
      type: 'transfer.sent';
      user: AuthUser;
      transferId: string;
      number: number;
      fromBranchId: string;
      fromBranchName: string;
      toBranchId: string;
      items: { variantId: string; quantity: number }[];
      shipment?: unknown;
      notes?: string;
    }
  | { type: 'transfer.cancelled'; user: AuthUser; transferId: string }
  | { type: 'einvoice.guide_void_needed'; tenantId: string; transferId: string; serie: string; numero: number }
  | { type: 'einvoice.rejected'; tenantId: string; kind: string; serie: string; numero: number; description: string | null; saleId: string | null; transferId: string | null }
  | { type: 'stock.below_minimum'; tenantId: string; branchId: string; productId: string; productName: string; options: string; balance: number; variantId: string }
  | { type: 'subscription.past_due'; tenantId: string; graceDays: number }
  | { type: 'subscription.suspended'; tenantId: string }
  | { type: 'team.member_joined'; tenantId: string; membershipId: string; name: string }
  | { type: 'layaway.expired'; tenantId: string; branchId: string; layawayId: string; number: number; customerName: string }
  | { type: 'stock.offline_shortfall'; tenantId: string; branchId: string; saleId: string; variants: { variantId: string; missing: number }[] }
  | { type: 'catalog.order_received'; tenantId: string; orderId: string; number: number; customerName: string; totalCents: number; branchId: string | null };

export type EventOf<T extends DomainEvent['type']> = Extract<DomainEvent, { type: T }>;
type Handler<T extends DomainEvent['type']> = (tx: Tx, event: EventOf<T>) => Promise<void>;

@Injectable()
export class EventBus {
  private readonly logger = new Logger('Eventos');
  private readonly handlers = new Map<string, { name: string; fn: (tx: Tx, event: DomainEvent) => Promise<void> }[]>();

  /** Registrar un manejador (normalmente en el constructor de un servicio del módulo que reacciona). */
  on<T extends DomainEvent['type']>(type: T, name: string, fn: Handler<T>) {
    const list = this.handlers.get(type) ?? [];
    list.push({ name, fn: fn as unknown as (tx: Tx, event: DomainEvent) => Promise<void> });
    this.handlers.set(type, list);
  }

  /** Publica en la transacción actual. Los manejadores corren en orden de registro. */
  async publish(tx: Tx, event: DomainEvent) {
    for (const h of this.handlers.get(event.type) ?? []) {
      try {
        await h.fn(tx, event);
      } catch (e) {
        this.logger.debug(`${event.type} → ${h.name} falló: ${e instanceof Error ? e.message : e}`);
        throw e;
      }
    }
  }

  /** Para pruebas y diagnóstico. */
  subscribers(type: DomainEvent['type']) {
    return (this.handlers.get(type) ?? []).map((h) => h.name);
  }
}

@Global()
@Module({ providers: [EventBus], exports: [EventBus] })
export class EventsModule {}
