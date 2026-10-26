import '../../../core/money.dart';

/// Convierte una hoja (filas de texto) en filas para POST /catalog/import.
///
/// Columnas conocidas (sin importar mayúsculas ni tildes):
///   Nombre*, Precio*, SKU, Categoría, Costo, Stock, Código de barras
/// Cualquier otra columna se toma como ATRIBUTO (Talla, Color, Material...).
/// Lógica pura: se prueba sin Flutter ni archivos.
class SheetParseResult {
  const SheetParseResult({required this.rows, required this.errors, required this.attributeColumns});
  final List<Map<String, Object?>> rows;

  /// `line` es el número de fila tal como se ve en Excel (1 = encabezado).
  final List<({int line, String message})> errors;
  final List<String> attributeColumns;
}

String _norm(String s) => s
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úù]'), 'u');

const _known = {
  'nombre': 'name',
  'producto': 'name',
  'precio': 'price',
  'sku': 'skuBase',
  'sku base': 'skuBase',
  'categoria': 'category',
  'costo': 'cost',
  'stock': 'quantity',
  'cantidad': 'quantity',
  'codigo de barras': 'barcode',
  'codigo': 'barcode',
  'ean': 'barcode',
};

SheetParseResult parseSheet(List<List<String?>> sheet) {
  if (sheet.isEmpty) {
    return const SheetParseResult(rows: [], errors: [(line: 1, message: 'La hoja está vacía')], attributeColumns: []);
  }
  final header = sheet.first.map((h) => (h ?? '').trim()).toList();
  final fields = <int, String>{};
  final attrs = <int, String>{};
  for (var i = 0; i < header.length; i++) {
    if (header[i].isEmpty) continue;
    final known = _known[_norm(header[i])];
    if (known != null) {
      fields[i] = known;
    } else {
      attrs[i] = header[i];
    }
  }

  final errors = <({int line, String message})>[];
  if (!fields.containsValue('name')) errors.add((line: 1, message: 'Falta la columna "Nombre"'));
  if (!fields.containsValue('price')) errors.add((line: 1, message: 'Falta la columna "Precio"'));
  if (errors.isNotEmpty) return SheetParseResult(rows: const [], errors: errors, attributeColumns: attrs.values.toList());

  final rows = <Map<String, Object?>>[];
  for (var r = 1; r < sheet.length; r++) {
    final cells = sheet[r];
    String cell(int i) => i < cells.length ? (cells[i] ?? '').trim() : '';
    if (cells.every((c) => (c ?? '').trim().isEmpty)) continue; // fila en blanco

    final line = r + 1;
    final row = <String, Object?>{};
    final options = <String, String>{};
    for (final e in fields.entries) {
      final v = cell(e.key);
      if (v.isEmpty) continue;
      switch (e.value) {
        case 'price' || 'cost':
          final c = parseCents(v);
          if (c == null) {
            errors.add((line: line, message: 'Monto inválido en ${header[e.key]}: "$v"'));
          } else {
            row[e.value == 'price' ? 'priceCents' : 'costCents'] = c;
          }
        case 'quantity':
          final q = num.tryParse(v);
          if (q == null || q < 0 || q != q.roundToDouble()) {
            errors.add((line: line, message: 'Stock inválido: "$v"'));
          } else {
            row['quantity'] = q.toInt();
          }
        case 'skuBase':
          row['skuBase'] = v.toUpperCase();
        case 'barcode':
          // Excel suele guardar códigos como número: "7751234567890.0" -> "7751234567890"
          row['barcode'] = v.endsWith('.0') ? v.substring(0, v.length - 2) : v;
        default:
          row[e.value] = v;
      }
    }
    for (final e in attrs.entries) {
      final v = cell(e.key);
      if (v.isNotEmpty) options[e.value] = v.endsWith('.0') ? v.substring(0, v.length - 2) : v; // tallas numéricas: 28.0 -> 28
    }
    if (row['name'] == null) errors.add((line: line, message: 'Falta el nombre'));
    if (row['priceCents'] == null) errors.add((line: line, message: 'Falta el precio'));
    row['options'] = options;
    row['_line'] = line;
    rows.add(row);
  }
  if (rows.isEmpty && errors.isEmpty) errors.add((line: 2, message: 'No hay filas con datos'));
  return SheetParseResult(rows: rows, errors: errors, attributeColumns: attrs.values.toList());
}
