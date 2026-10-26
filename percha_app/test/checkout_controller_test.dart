import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/einvoice/data/einvoice_api.dart';
import 'package:percha_app/features/einvoice/domain/document_choice.dart';
import 'package:percha_app/features/pos/application/checkout_controller.dart';
import 'package:percha_app/core/network/api_error.dart';
import 'package:percha_app/features/pos/data/pos_api.dart';
import 'package:percha_app/features/pos/data/pos_models.dart';

/// El caso de uso "cobrar" se prueba sin pantalla: las preguntas se responden con funciones.
void main() {
  CheckoutRequest req({PaymentMethod method = PaymentMethod.cash, bool approval = false}) => CheckoutRequest(
        branchId: 'b',
        items: const [(variantId: 'v', quantity: 1)],
        discountCents: 0,
        totalCents: 18990,
        method: method,
        document: const DocumentChoice(),
        needsDiscountApproval: approval,
      );

  final asked = <String>[];
  CheckoutPrompts prompts({int? cash = 20000, String? pin = '4321', ({String code, int amountCents})? credit, PaymentMethod? rest = PaymentMethod.card}) => CheckoutPrompts(
        fixDocument: (p) async {
          asked.add('documento');
          return null;
        },
        askCredit: (t) async {
          asked.add('vale');
          return credit;
        },
        askRestMethod: (r) async {
          asked.add('resto $r');
          return rest;
        },
        askCashReceived: (d) async {
          asked.add('efectivo $d');
          return cash;
        },
        askApproval: (r) async {
          asked.add('pin');
          return pin;
        },
        confirmTotal: (shown, server) async {
          asked.add('total $server');
          return true;
        },
      );

  ProviderContainer container() => ProviderContainer(overrides: [
        // Sin comprobantes electrónicos en esta prueba.
        einvoiceStatusProvider.overrideWith((ref) async => const EInvoiceStatus(enabled: false, anonLimitCents: 70000)),
        // Sin servidor: la cotización falla por red y se usa el total local.
        posApiProvider.overrideWithValue(_OfflinePosApi()),
      ]);

  setUp(asked.clear);

  test('si quien cobra cancela, no se registra nada', () async {
    final c = container();
    final out = await c.read(checkoutProvider.notifier).checkout(req(), prompts(cash: null));
    expect(out, isA<CheckoutCancelled>());
    expect(asked, ['efectivo 18990']);
    expect(c.read(checkoutProvider), isFalse);
  });

  test('con vale que no alcanza: pide el medio para el resto (y se puede cancelar ahí)', () async {
    final c = container();
    final out = await c.read(checkoutProvider.notifier).checkout(req(method: PaymentMethod.storeCredit), prompts(credit: (code: 'VALE-2345-6789-ABCD', amountCents: 10000), rest: null));
    expect(out, isA<CheckoutCancelled>());
    expect(asked, ['vale', 'resto 8990']);
  });

  test('con vale que cubre todo: no pregunta resto ni efectivo', () async {
    final c = container();
    final out = await c.read(checkoutProvider.notifier).checkout(req(method: PaymentMethod.storeCredit, approval: true), prompts(credit: (code: 'X', amountCents: 18990), pin: null));
    expect(out, isA<CheckoutCancelled>());
    expect(asked, ['vale', 'pin']);
  });

  test('descuento sobre el límite: pide el PIN antes de enviar; sin PIN, se cancela', () async {
    final c = container();
    final out = await c.read(checkoutProvider.notifier).checkout(req(approval: true), prompts(pin: null));
    expect(out, isA<CheckoutCancelled>());
    expect(asked, ['efectivo 18990', 'pin']);
  });
}

/// PosApi que siempre está "sin conexión" (no toca la red ni el almacenamiento).
class _OfflinePosApi implements PosApi {
  @override
  Future<int> quoteTotal({required String branchId, required List<({String variantId, int quantity})> items, required int discountCents}) =>
      Future.error(const ApiError(status: 0, message: 'Sin conexión'));

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<dynamic>.error(const ApiError(status: 0, message: 'Sin conexión'));
}
