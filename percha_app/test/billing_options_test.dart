import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/billing/data/billing_api.dart';

void main() {
  test('Yape y billeteras van por Culqi; Stripe solo ofrece tarjeta', () {
    final options = payOptions({
      'culqi': ['card', 'yape', 'wallet_qr'],
      'stripe': ['card'],
    });
    expect(options.map((o) => '${o.provider}:${o.method}'), ['culqi:yape', 'culqi:wallet_qr', 'stripe:card']);
  });

  test('sin pasarelas configuradas no se ofrece nada (queda Plin manual)', () {
    expect(payOptions({}), isEmpty);
  });
}
