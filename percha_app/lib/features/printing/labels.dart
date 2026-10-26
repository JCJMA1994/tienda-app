import '../../core/money.dart';

enum LabelFormat { roll50x25, a4Sheet }

enum BarcodeKind { ean13, code128 }

/// Una etiqueta física (una por prenda).
class LabelData {
  const LabelData({required this.name, required this.options, required this.price, required this.barcodeData, required this.barcodeKind});
  final String name;
  final String options;
  final String price;
  final String barcodeData;
  final BarcodeKind barcodeKind;
}

/// EAN-13 válido: 13 dígitos con dígito verificador correcto.
bool isValidEan13(String code) {
  if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(code[i]) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10 == int.parse(code[12]);
}

/// Expande variantes × cantidad en etiquetas. Usa el EAN-13 de la variante; si no es válido
/// (códigos de proveedor u otros), imprime el SKU en Code 128 para que el escáner igual lo lea.
List<LabelData> buildLabels(List<({String name, Map<String, String> options, int priceCents, String barcode, String sku, int copies})> items) => [
      for (final it in items)
        for (var i = 0; i < it.copies; i++)
          LabelData(
            name: it.name,
            options: it.options.values.join(' · '),
            price: formatCents(it.priceCents),
            barcodeData: isValidEan13(it.barcode) ? it.barcode : it.sku,
            barcodeKind: isValidEan13(it.barcode) ? BarcodeKind.ean13 : BarcodeKind.code128,
          ),
    ];
