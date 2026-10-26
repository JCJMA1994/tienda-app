import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/core/money.dart';

void main() {
  test('formatea céntimos en soles', () {
    expect(formatCents(124000), 'S/ 1,240.00');
    expect(formatCents(-2020), '−S/ 20.20');
  });

  test('parsea montos con punto o coma', () {
    expect(parseCents('189.90'), 18990);
    expect(parseCents('189,9'), 18990);
    expect(parseCents('50'), 5000);
    expect(parseCents('1.2.3'), isNull);
    expect(parseCents('10.123'), isNull);
    expect(parseCents(''), isNull);
  });
}
