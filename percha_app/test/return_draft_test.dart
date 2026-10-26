import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/pos/application/return_draft.dart';
import 'package:percha_app/features/pos/data/pos_models.dart';
import 'package:percha_app/features/pos/data/sales_api.dart';

/// Mismo caso que la prueba de la API: vestido de S/ 189.90 con S/ 50 de descuento.
SaleDetail sale() => SaleDetail(
      id: 's1',
      number: 2,
      branchId: 'b1',
      voided: false,
      subtotalCents: 18990,
      discountCents: 5000,
      totalCents: 13990,
      taxCents: 2134,
      createdAt: DateTime(2026, 10, 25),
      payments: const [],
      lines: const [
        SaleLine(
          id: 'l1',
          variantId: 'v-m-neg',
          productName: 'Vestido midi',
          sku: 'VST-014-M-NEG',
          options: {'Talla': 'M', 'Color': 'Negro'},
          quantity: 1,
          returnedQuantity: 0,
          unitPriceCents: 18990,
          lineTotalCents: 13990,
        ),
      ],
    );

const sBeige = SellableVariant(
  id: 'v-s-bei',
  sku: 'VST-014-S-BEI',
  productName: 'Vestido midi',
  options: {'Talla': 'S', 'Color': 'Beige'},
  priceCents: 18990,
  sellable: true,
  stock: 2,
);

void main() {
  test('cambio de talla: devuelve al precio pagado y cobra la diferencia (igual que la API)', () {
    final s = sale();
    final draft = const ReturnDraft().setReturning(s.lines.first, 1).addReplacement(sBeige);
    expect(draft.returnedCents(s), 13990);
    expect(draft.replacementCents(taxRateBp: 1800, pricesIncludeTax: true), 18990);
    expect(draft.difference(s, taxRateBp: 1800, pricesIncludeTax: true), 5000);
    expect(draft.isExchange, isTrue);
  });

  test('devolución simple: diferencia negativa = reembolso', () {
    final s = sale();
    final draft = const ReturnDraft().setReturning(s.lines.first, 1);
    expect(draft.difference(s, taxRateBp: 1800, pricesIncludeTax: true), -13990);
  });

  test('no permite devolver más de lo vendido', () {
    final s = sale();
    final draft = const ReturnDraft().setReturning(s.lines.first, 5);
    expect(draft.returning['l1'], 1);
  });
}
