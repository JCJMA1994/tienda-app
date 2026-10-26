import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/purchasing/application/drafts.dart';
import 'package:percha_app/features/purchasing/data/purchasing_api.dart';

PurchaseOrder order() => const PurchaseOrder(
      id: 'po1',
      number: 1,
      status: PoStatus.ordered,
      supplierId: 's1',
      branchId: 'b1',
      totalCents: 38000,
      lines: [
        PoLine(id: 'i1', variantId: 'v1', productName: 'Vestido midi', sku: 'VST-014-M-NEG', options: {'Talla': 'M'}, ordered: 4, received: 2, unitCostCents: 9500),
        PoLine(id: 'i2', variantId: 'v2', productName: 'Vestido midi', sku: 'VST-014-L-NEG', options: {'Talla': 'L'}, ordered: 1, received: 1, unitCostCents: 9500),
      ],
    );

void main() {
  group('PoDraft', () {
    test('la misma variante se suma en una línea y el total se recalcula', () {
      var d = const PoDraft().merge([const PoDraftLine(variantId: 'v1', label: 'M', quantity: 2, unitCostCents: 9500)]);
      d = d.merge([const PoDraftLine(variantId: 'v1', label: 'M', quantity: 3, unitCostCents: 9000)]);
      expect(d.lines.single.quantity, 5);
      expect(d.totalCents, 45000);
    });

    test('cantidad 0 quita la línea', () {
      final d = const PoDraft([PoDraftLine(variantId: 'v1', label: 'M', quantity: 2, unitCostCents: 100)]).update('v1', quantity: 0);
      expect(d.isEmpty, isTrue);
    });
  });

  group('ReceiveDraft', () {
    test('cada escaneo suma uno con tope en lo pendiente', () {
      var r = ReceiveDraft(order: order());
      ScanResult res;
      (r, res) = r.scan('v1');
      expect(res, ScanResult.counted);
      (r, _) = r.scan('v1');
      (r, res) = r.scan('v1');
      expect(res, ScanResult.alreadyComplete);
      expect(r.counts['i1'], 2);
      expect(r.completesOrder, isTrue); // la línea L ya estaba completa
    });

    test('avisa si la prenda no es de esta orden', () {
      final (_, res) = ReceiveDraft(order: order()).scan('otra');
      expect(res, ScanResult.notInOrder);
    });

    test('solo envía el costo cuando difiere del de la orden', () {
      final line = order().lines.first;
      var r = ReceiveDraft(order: order()).all().setCost(line, 9500);
      expect(r.toItems().single.unitCostCents, isNull);
      r = r.setCost(line, 9900);
      expect(r.toItems().single, (itemId: 'i1', quantity: 2, unitCostCents: 9900));
    });
  });
}
