import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/core/barcodes.dart';
import 'package:percha_app/features/pos/offline/pos_snapshot.dart';

/// Mismas reglas que la API (`percha-api/src/modules/catalog/barcodes.ts`).
void main() {
  test('limpia lo que agregan los lectores y equipara UPC-A con EAN-13', () {
    expect(barcodeCandidates(' 7751234567893\r\n'), ['7751234567893']);
    expect(barcodeCandidates('012345678905'), ['012345678905', '0012345678905']);
    expect(barcodeCandidates('0012345678905'), ['0012345678905', '012345678905']);
    expect(barcodeCandidates('VST-001-S'), ['VST-001-S']);
    expect(barcodeCandidates('  '), isEmpty);
  });

  test('reconoce el QR de un vale', () {
    expect(isCreditCode('vale-2345-6789-abcd'), isTrue);
    expect(isCreditCode('7751234567893'), isFalse);
  });

  test('sin conexión, la foto local encuentra la prenda por UPC-A aunque esté como EAN-13', () {
    final snap = PosSnapshot.fromJson({
      'branchId': 'b',
      'generatedAt': '2026-10-27T10:00:00Z',
      'variants': [
        {'id': 'v1', 'productId': 'p1', 'productName': 'Jean importado', 'sku': 'JEA-1', 'barcode': '0012345678905', 'options': {}, 'priceCents': 19990, 'stock': 2, 'imageUrl': null},
      ],
    });
    expect(snap.lookup('012345678905')?.id, 'v1');
    expect(snap.lookup(' jea-1 ')?.id, 'v1');
  });
}
