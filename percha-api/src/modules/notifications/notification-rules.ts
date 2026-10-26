import { Inject, Injectable } from '@nestjs/common';
import { EventBus } from '../../common/events';
import { NotificationsService } from './notifications.service';

/**
 * QUÉ se notifica, A QUIÉN y CON QUÉ TEXTO, en un solo lugar. Los módulos solo publican
 * eventos ("se envió una transferencia"); para avisar algo nuevo se agrega una regla aquí sin
 * tocar el módulo que origina el hecho (principio abierto/cerrado).
 */
@Injectable()
export class NotificationRules {
  constructor(
    @Inject(EventBus) bus: EventBus,
    @Inject(NotificationsService) n: NotificationsService,
  ) {
    bus.on('transfer.sent', 'notificar a la sucursal destino', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.user.tenantId,
          type: 'transfer.incoming',
          title: `Mercadería en camino · #${e.number}`,
          body: `${e.items.reduce((a, i) => a + i.quantity, 0)} prendas desde ${e.fromBranchName}. Recíbelas al llegar.`,
          link: `/transfers/${e.transferId}`,
          permission: 'inventory.adjust',
          branchId: e.toBranchId,
          exceptMembershipId: e.user.membershipId,
        })
        .then(() => undefined),
    );

    bus.on('stock.below_minimum', 'avisar stock bajo', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'stock.low',
          title: e.balance <= 0 ? `Agotado: ${e.productName}` : `Stock bajo: ${e.productName}`,
          body: `${[e.productName, e.options].filter(Boolean).join(' ')} · quedan ${Math.max(e.balance, 0)}`,
          link: `/products/${e.productId}`,
          permission: 'inventory.adjust',
          branchId: e.branchId,
          data: { variantId: e.variantId, balance: e.balance },
        })
        .then(() => undefined),
    );

    bus.on('einvoice.rejected', 'avisar comprobante rechazado', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'einvoice.rejected',
          title: `${e.kind === 'guia_remitente' ? 'Guía rechazada' : 'Comprobante rechazado'} · ${e.serie}-${e.numero}`,
          body: (e.description ?? 'Revisa los datos del cliente y emite uno nuevo.').slice(0, 200),
          link: e.saleId ? `/sales/${e.saleId}` : e.transferId ? `/transfers/${e.transferId}` : '/settings/einvoice',
          permission: 'settings.manage',
        })
        .then(() => undefined),
    );

    bus.on('einvoice.guide_void_needed', 'pedir baja de la guía', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'einvoice.rejected',
          title: `Da de baja la guía ${e.serie}-${e.numero}`,
          body: 'La transferencia se canceló: anula la guía de remisión en el portal de tu OSE.',
          link: `/transfers/${e.transferId}`,
          permission: 'settings.manage',
        })
        .then(() => undefined),
    );

    bus.on('subscription.past_due', 'avisar pago pendiente', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'billing.past_due',
          title: 'Pago pendiente de tu plan',
          body: `Todo sigue funcionando ${e.graceDays} días más. Paga para evitar el bloqueo.`,
          link: '/billing',
          permission: 'billing.manage',
        })
        .then(() => undefined),
    );

    bus.on('subscription.suspended', 'avisar solo lectura', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'billing.suspended',
          title: 'Tienda en solo lectura',
          body: 'No registramos el pago de tu plan. Tus datos están a salvo: paga para seguir vendiendo.',
          link: '/billing',
          permission: 'billing.manage',
        })
        .then(() => undefined),
    );

    bus.on('team.member_joined', 'avisar nuevo integrante', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'team.joined',
          title: `${e.name} se unió al equipo`,
          body: 'Asígnale un PIN para que pueda usar el POS.',
          link: '/team',
          permission: 'team.manage',
          exceptMembershipId: e.membershipId,
        })
        .then(() => undefined),
    );

    bus.on('stock.offline_shortfall', 'pedir conteo tras venta sin conexión', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'stock.low',
          title: 'Revisa el stock: venta sin conexión',
          body: `Al sincronizar faltaban ${e.variants.reduce((a, v) => a + v.missing, 0)} unidad(es). Se registró un ajuste automático; cuenta esas prendas.`,
          link: `/sales/${e.saleId}`,
          permission: 'inventory.adjust',
          branchId: e.branchId,
        })
        .then(() => undefined),
    );

    bus.on('catalog.order_received', 'avisar pedido del catálogo', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'catalog.order',
          title: `Nuevo pedido del catálogo · #${e.number}`,
          body: `${e.customerName} · S/ ${(e.totalCents / 100).toFixed(2)}. Escríbele para confirmar.`,
          link: `/catalog/orders/${e.orderId}`,
          permission: 'sales.create',
          branchId: e.branchId,
        })
        .then(() => undefined),
    );

    bus.on('layaway.expired', 'avisar apartado vencido', (tx, e) =>
      n
        .notify(tx, {
          tenantId: e.tenantId,
          type: 'layaway.expired',
          title: `Apartado #${e.number} vencido`,
          body: `${e.customerName} no recogió su apartado. Contáctala o cancélalo para liberar las prendas.`,
          link: `/layaways/${e.layawayId}`,
          permission: 'sales.create',
          branchId: e.branchId,
        })
        .then(() => undefined),
    );
  }
}
