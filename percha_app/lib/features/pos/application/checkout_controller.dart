import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../auth/application/session_controller.dart';
import '../../einvoice/domain/customer_rules.dart';
import '../../einvoice/data/einvoice_api.dart';
import '../../einvoice/domain/document_choice.dart';
import '../data/pos_api.dart';
import '../data/pos_models.dart';
import '../domain/checkout.dart';
import '../offline/offline_queue.dart';
import '../offline/pos_snapshot.dart';
import '../../../core/ids.dart';

/// Lo que el cobro necesita PREGUNTAR a quien cobra. La pantalla pone los diálogos; el
/// controlador decide cuándo preguntar y qué hacer con la respuesta (null = canceló).
class CheckoutPrompts {
  const CheckoutPrompts({
    required this.fixDocument,
    required this.askCredit,
    required this.askRestMethod,
    required this.askCashReceived,
    required this.askApproval,
    required this.confirmTotal,
  });

  /// El comprobante elegido no cumple una regla SUNAT (p. ej. boleta > S/ 700 sin DNI).
  final Future<DocumentChoice?> Function(String problem) fixDocument;
  final Future<CreditUse?> Function(int totalCents) askCredit;
  final Future<PaymentMethod?> Function(int restCents) askRestMethod;
  final Future<int?> Function(int cashDueCents) askCashReceived;
  final Future<String?> Function(String reason) askApproval;

  /// El servidor calculó otro total (una promoción empezó o terminó, cambió un precio):
  /// se muestra y se confirma antes de cobrar.
  final Future<bool> Function(int shownCents, int serverCents) confirmTotal;
}

class CheckoutRequest {
  const CheckoutRequest({
    required this.branchId,
    required this.items,
    required this.discountCents,
    required this.totalCents,
    required this.method,
    required this.document,
    required this.needsDiscountApproval,
    this.customerId,
  });

  final String branchId;
  final List<({String variantId, int quantity})> items;
  final int discountCents;
  final int totalCents;
  final PaymentMethod method;
  final DocumentChoice document;

  /// El descuento supera el límite y quien vende no puede aprobarlo.
  final bool needsDiscountApproval;
  final String? customerId;

  CheckoutRequest withTotal(int cents) => CheckoutRequest(
        branchId: branchId,
        items: items,
        discountCents: discountCents,
        totalCents: cents,
        method: method,
        document: document,
        needsDiscountApproval: needsDiscountApproval,
        customerId: customerId,
      );
}

sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

class CheckoutDone extends CheckoutOutcome {
  const CheckoutDone(this.receipt);
  final SaleReceipt receipt;
}

class CheckoutCancelled extends CheckoutOutcome {
  const CheckoutCancelled();
}

/// Sin conexión: la venta quedó en la cola del dispositivo y se enviará sola.
class CheckoutQueued extends CheckoutOutcome {
  const CheckoutQueued(this.totalCents);
  final int totalCents;
}

class CheckoutFailed extends CheckoutOutcome {
  const CheckoutFailed(this.message);
  final String message;
}

/// Caso de uso "cobrar": comprobante válido → vale y resto → efectivo y vuelto → aprobación del
/// descuento → registrar la venta (con un reintento si el PIN de aprobación falló).
/// El estado es "ocupado" (true mientras cobra): evita cobrar dos veces con un doble toque.
class CheckoutController extends AutoDisposeNotifier<bool> {
  @override
  bool build() => false;

  Future<CheckoutOutcome> checkout(CheckoutRequest request, CheckoutPrompts ask) async {
    if (state) return const CheckoutCancelled();

    // 0. Total exacto del servidor (promociones vigentes ahora). Sin conexión, vale el local:
    //    la foto trae las mismas promociones y el motor es el mismo.
    var r = request;
    try {
      final server = await ref.read(posApiProvider).quoteTotal(branchId: r.branchId, items: r.items, discountCents: r.discountCents);
      if (server != r.totalCents) {
        if (!await ask.confirmTotal(r.totalCents, server)) return const CheckoutCancelled();
        r = r.withTotal(server);
      }
    } on ApiError catch (e) {
      if (!e.isNetwork) return CheckoutFailed(e.message);
    }

    // 1. Comprobante electrónico: se valida ANTES de cobrar.
    var document = r.document;
    final einvoice = ref.read(einvoiceStatusProvider).valueOrNull;
    final emits = einvoice?.enabled ?? false;
    if (emits) {
      final problem = validateCustomer(
        factura: document.factura,
        totalCents: r.totalCents,
        anonLimitCents: einvoice!.anonLimitCents,
        type: document.factura ? DocType.ruc : document.type,
        number: document.number,
        name: document.name,
      );
      if (problem != null) {
        final fixed = await ask.fixDocument(problem);
        if (fixed == null) return const CheckoutCancelled();
        document = fixed;
      }
    }

    // 2. Vale (con saldo verificado) y medio para el resto.
    CreditUse? credit;
    var method = r.method;
    if (method == PaymentMethod.storeCredit) {
      credit = await ask.askCredit(r.totalCents);
      if (credit == null) return const CheckoutCancelled();
      method = PaymentMethod.cash;
      if (credit.amountCents < r.totalCents) {
        final rest = await ask.askRestMethod(r.totalCents - credit.amountCents);
        if (rest == null) return const CheckoutCancelled();
        method = rest;
      }
    }

    // 3. Efectivo recibido (solo si hay parte en efectivo).
    final due = cashDue(splitPayments(totalCents: r.totalCents, method: method.api, credit: credit));
    int? cashReceived;
    if (due > 0) {
      cashReceived = await ask.askCashReceived(due);
      if (cashReceived == null) return const CheckoutCancelled();
    }

    // 4. Aprobación del descuento, si ya se sabe que hace falta.
    String? pin;
    if (r.needsDiscountApproval) {
      pin = await ask.askApproval('El descuento supera el límite. Un supervisor debe aprobar.');
      if (pin == null) return const CheckoutCancelled();
    }

    // 5. Registrar (un reintento si el PIN de aprobación faltó o fue incorrecto). Cada intento
    //    lleva su clave de idempotencia: un reenvío por red lenta nunca duplica la venta.
    state = true;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final key = newUuid();
        final body = PosApi.saleBody(
          branchId: r.branchId,
          items: r.items,
          discountCents: r.discountCents,
          method: method,
          amountCents: r.totalCents,
          credit: credit,
          cashReceivedCents: cashReceived,
          approverPin: pin,
          document: emits ? document.toJson() : null,
          customerId: r.customerId,
        );
        try {
          return CheckoutDone(await ref.read(posApiProvider).postSale(body, idempotencyKey: key));
        } on ApiError catch (e) {
          if (e.isNetwork) return _queueOffline(r, body, key, offlineAllowed: credit == null && pin == null);
          final approval = e.code == 'APPROVAL_REQUIRED' || e.code == 'APPROVAL_INVALID';
          if (!approval || attempt > 0) rethrow;
          pin = await ask.askApproval(e.code == 'APPROVAL_INVALID' ? 'PIN incorrecto. Intenta de nuevo.' : 'Esta venta requiere aprobación.');
          if (pin == null) return const CheckoutCancelled();
        }
      }
      return const CheckoutCancelled();
    } on ApiError catch (e) {
      return CheckoutFailed(switch (e.code) {
        'INSUFFICIENT_STOCK' => 'Stock insuficiente: quedan ${e.data['available']} unidades de una prenda.',
        'CASH_CLOSED' => 'La caja está cerrada. Ábrela para seguir vendiendo.',
        _ => e.message,
      });
    } catch (_) {
      return const CheckoutFailed('No se pudo registrar la venta. Revisa la conexión e intenta de nuevo.');
    } finally {
      state = false;
    }
  }
}

/// Sin conexión se puede vender con efectivo, tarjeta o billetera. Los vales y los descuentos
/// con aprobación necesitan verificarse en el servidor en el momento: esos esperan conexión.
extension on CheckoutController {
  Future<CheckoutOutcome> _queueOffline(CheckoutRequest r, Map<String, Object?> body, String key, {required bool offlineAllowed}) async {
    if (!offlineAllowed) {
      return const CheckoutFailed('Sin conexión. Los pagos con vale y los descuentos con aprobación necesitan internet: cobra con otro medio o espera.');
    }
    // Misma clave que el intento en línea: si en realidad llegó al servidor, al sincronizar se
    // reconoce como la MISMA venta y no se duplica.
    await ref.read(offlineQueueProvider.notifier).enqueue(key: key, body: {
      ...body,
      'offline': {'occurredAt': DateTime.now().toUtc().toIso8601String(), 'sellerMembershipId': ref.read(meProvider).membershipId},
    });
    await ref.read(posSnapshotProvider(r.branchId).notifier).discount(r.items);
    return CheckoutQueued(r.totalCents);
  }
}

final checkoutProvider = NotifierProvider.autoDispose<CheckoutController, bool>(CheckoutController.new);
