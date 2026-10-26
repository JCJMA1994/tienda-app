import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/pos/domain/promotions.dart';

/// Mismos casos que la API: si alguno falla aquí o allá, los totales no coincidirían.
void main() {
  final data = jsonDecode(File('test/fixtures/promotions-vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final promos = {for (final e in (data['promotions'] as Map<String, dynamic>).entries) e.key: Promo.fromJson(e.value as Map<String, dynamic>)};
  for (final c in (data['cases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(c['name'] as String, () {
      final lines = [
        for (final l in (c['lines'] as List<dynamic>).cast<Map<String, dynamic>>())
          (productId: l['productId'] as String, categoryId: l['categoryId'] as String?, quantity: l['quantity'] as int, unitPriceCents: l['unitPriceCents'] as int),
      ];
      final r = applyPromotions(lines, [for (final id in (c['promos'] as List<dynamic>).cast<String>()) promos[id]!]);
      final expected = c['expect'] as Map<String, dynamic>;
      expect([for (final l in r.lines) [l.discountCents, l.promotionId]], expected['lines']);
      expect(r.totalCents, expected['total']);
    });
  }

  test('etiquetas', () {
    expect(promos['p20']!.label, '−20 %');
    expect(promos['b32']!.label, '3x2');
  });
}
