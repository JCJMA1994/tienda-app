import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/core/ids.dart';
import 'package:percha_app/features/pos/offline/offline_queue.dart';
import 'package:percha_app/features/pos/offline/pos_snapshot.dart';

void main() {
  test('claves de idempotencia: UUID v4 válidos y distintos', () {
    final keys = {for (var i = 0; i < 1000; i++) newUuid()};
    expect(keys, hasLength(1000));
    for (final k in keys.take(20)) {
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(k), isTrue, reason: k);
    }
  });

  final snap = PosSnapshot.fromJson({
    'branchId': 'b',
    'generatedAt': '2026-10-27T10:00:00Z',
    'variants': [
      {'id': 'v1', 'productId': 'p1', 'productName': 'Vestido midi', 'sku': 'VST-1-S', 'barcode': '2000000000015', 'options': {'Talla': 'S'}, 'priceCents': 18990, 'stock': 3, 'imageUrl': null},
      {'id': 'v2', 'productId': 'p1', 'productName': 'Vestido midi', 'sku': 'VST-1-M', 'barcode': '2000000000022', 'options': {'Talla': 'M'}, 'priceCents': 18990, 'stock': 0, 'imageUrl': null},
      {'id': 'v3', 'productId': 'p2', 'productName': 'Blusa', 'sku': 'BLU-2', 'barcode': null, 'options': {}, 'priceCents': 7990, 'stock': 5, 'imageUrl': null},
    ],
  });

  test('foto local: busca por código de barras o SKU, y arma grilla y detalle', () {
    expect(snap.lookup('2000000000015')!.id, 'v1');
    expect(snap.lookup('blu-2')!.id, 'v3');
    expect(snap.lookup('nada'), isNull);
    final grid = snap.products('');
    expect(grid.map((p) => (p.name, p.totalStock, p.variantCount)), containsAll([('Vestido midi', 3, 2), ('Blusa', 5, 1)]));
    expect(snap.products('blu').single.name, 'Blusa');
    final detail = snap.product('p1')!;
    expect(detail.attributes.single.values, containsAll(['S', 'M']));
  });

  test('venta pendiente: total desde sus pagos y serialización sin pérdidas', () {
    final p = PendingSale(key: newUuid(), createdAt: DateTime.utc(2026, 10, 27), body: {
      'payments': [
        {'method': 'cash', 'amountCents': 10000},
        {'method': 'card', 'amountCents': 8990},
      ],
    });
    expect(p.totalCents, 18990);
    final back = PendingSale.fromJson(p.toJson().cast<String, dynamic>());
    expect((back.key, back.totalCents, back.error), (p.key, 18990, null));
  });
}
