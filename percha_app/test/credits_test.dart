import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/credits/credits_api.dart';

void main() {
  test('el código del vale se acepta como lo dicte el cliente (mismas reglas que la API)', () {
    expect(normalizeCreditCode('vale 2345 6789 abcd'), 'VALE-2345-6789-ABCD');
    expect(normalizeCreditCode('VALE-2345-6789-ABCD'), 'VALE-2345-6789-ABCD');
    expect(normalizeCreditCode('2345-6789-ABC'), isNull);
    expect(normalizeCreditCode('VALE-0000-0000-0000'), isNull); // 0, 1, I, L, O no se usan
  });
}
