import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/einvoice/data/einvoice_api.dart';
import 'package:percha_app/features/pos/data/sales_api.dart';
import 'package:percha_app/features/printing/labels.dart';
import 'package:percha_app/features/printing/ticket.dart';

SaleDetail sale({List<EDocument> docs = const [], int discount = 0}) => SaleDetail.fromJson({
      'id': 's1',
      'number': 42,
      'branchId': 'b',
      'status': 'completed',
      'subtotalCents': 37980,
      'discountCents': discount,
      'totalCents': 37980 - discount,
      'taxCents': ((37980 - discount) * 18 / 118).round(),
      'createdAt': '2026-10-25T15:30:00Z',
      'items': [
        {'id': 'i1', 'variantId': 'v', 'productName': 'Vestido midi', 'sku': 'VST-1-M', 'options': {'Talla': 'M'}, 'quantity': 2, 'returnedQuantity': 0, 'unitPriceCents': 18990, 'lineTotalCents': 37980 - discount},
      ],
      'payments': [
        {'method': 'cash', 'amountCents': 37980 - discount},
      ],
      'documents': [for (final d in docs) {'id': d.id, 'kind': d.kind, 'serie': d.serie, 'numero': d.numero, 'status': d.status, 'totalCents': d.totalCents, 'qr': d.qr, 'hash': d.hash, 'customerDocType': d.customerDocType, 'customerDocNumber': d.customerDocNumber, 'customerName': d.customerName}],
      'store': {'name': 'Boutique Alma', 'legalName': 'ALMA BOUTIQUE S.A.C.', 'ruc': '20601234565', 'fiscalAddress': 'Av. Larco 345'},
    });

void main() {
  test('ticket interno: encabezado, ítems y total', () {
    final t = buildTicket(sale(), changeCents: 2020);
    expect(t.header.first, 'ALMA BOUTIQUE S.A.C.');
    expect(t.header, contains('RUC 20601234565'));
    expect(t.title, 'TICKET DE VENTA #42');
    expect(t.items.single.left, '2 x Vestido midi');
    expect(t.items.single.detail, 'M · S/ 189.90 c/u');
    expect(t.totals.last, (label: 'TOTAL', value: 'S/ 379.80', strong: true));
    expect(t.payments.last.label, 'Vuelto');
    expect(t.qr, isNull);
  });

  test('con boleta: representación impresa con serie, cliente, IGV, QR y resumen', () {
    const doc = EDocument(id: 'd', kind: 'boleta', serie: 'B001', numero: 12, status: 'accepted', totalCents: 37980, customerName: 'LUCIA RAMOS', customerDocType: 'dni', customerDocNumber: '45678912', qr: '20601234565|03|B001|12|...', hash: 'abc123');
    final t = buildTicket(sale(docs: [doc]));
    expect(t.title, 'BOLETA DE VENTA ELECTRÓNICA\nB001-12');
    expect(t.meta, contains('Cliente: DNI 45678912 · LUCIA RAMOS'));
    expect(t.totals.map((x) => x.label), ['Op. gravada', 'IGV', 'TOTAL']);
    expect(t.footer.first, 'Representación impresa de la Boleta de Venta Electrónica.');
    expect(t.qr, isNotNull);
    expect(t.hash, 'abc123');
  });

  test('etiquetas: una por prenda; EAN-13 válido o, si no, el SKU en Code 128', () {
    expect(isValidEan13('2000000000015'), isTrue);
    expect(isValidEan13('2000000000016'), isFalse);
    final labels = buildLabels([
      (name: 'Vestido', options: {'Talla': 'M', 'Color': 'Negro'}, priceCents: 18990, barcode: '2000000000015', sku: 'VST-1-M-NEG', copies: 2),
      (name: 'Blusa', options: const {}, priceCents: 7990, barcode: '123', sku: 'BLU-2', copies: 1),
    ]);
    expect(labels, hasLength(3));
    expect(labels.first.options, 'M · Negro');
    expect(labels.first.barcodeKind, BarcodeKind.ean13);
    expect(labels.last.barcodeKind, BarcodeKind.code128);
    expect(labels.last.barcodeData, 'BLU-2');
  });
}
