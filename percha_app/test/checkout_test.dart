import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/pos/domain/checkout.dart';

void main() {
  test('sin vale: todo con el medio elegido', () {
    final p = splitPayments(totalCents: 18990, method: 'card');
    expect(p.map((x) => x.toJson()), [
      {'method': 'card', 'amountCents': 18990},
    ]);
  });

  test('vale que no alcanza: el resto con el otro medio', () {
    final p = splitPayments(totalCents: 18990, method: 'cash', credit: (code: 'VALE-2345-6789-ABCD', amountCents: 10000));
    expect(p.map((x) => x.toJson()), [
      {'method': 'store_credit', 'amountCents': 10000, 'creditCode': 'VALE-2345-6789-ABCD'},
      {'method': 'cash', 'amountCents': 8990},
    ]);
    expect(cashDue(p), 8990);
  });

  test('vale que sobra: solo se usa hasta el total', () {
    final p = splitPayments(totalCents: 5000, method: 'cash', credit: (code: 'X', amountCents: 9000));
    expect(p.single.toJson(), {'method': 'store_credit', 'amountCents': 5000, 'creditCode': 'X'});
    expect(cashDue(p), 0);
  });

  test('vuelto y billetes sugeridos', () {
    expect(changeFor(cashReceivedCents: 20000, cashDueCents: 18990), 1010);
    expect(changeFor(cashReceivedCents: 10000, cashDueCents: 18990), isNull);
    expect(cashSuggestions(18990), [18990, 20000]);
    expect(cashSuggestions(3500), [3500, 5000, 10000, 20000]);
  });
}
