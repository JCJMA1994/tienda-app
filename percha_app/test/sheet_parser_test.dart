import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/catalog/application/sheet_parser.dart';

void main() {
  test('reconoce columnas conocidas y toma el resto como atributos', () {
    final r = parseSheet([
      ['Nombre', 'Categoría', 'Precio', 'Costo', 'Talla', 'Color', 'Stock'],
      ['Polo básico', 'Polos', '49.90', '20', 'M', 'Blanco', '10'],
      ['Jean mom', 'Jeans', '149', '', '28.0', 'Azul', '2'],
      [null, null, null],
    ]);
    expect(r.errors, isEmpty);
    expect(r.attributeColumns, ['Talla', 'Color']);
    expect(r.rows, hasLength(2));
    expect(r.rows[0], containsPair('priceCents', 4990));
    expect(r.rows[0], containsPair('costCents', 2000));
    expect(r.rows[1]['options'], {'Talla': '28', 'Color': 'Azul'});
    expect(r.rows[1]['_line'], 3);
  });

  test('reporta columnas obligatorias faltantes', () {
    final r = parseSheet([
      ['Producto', 'Talla'],
      ['Polo', 'M'],
    ]);
    expect(r.errors.single.message, contains('Precio'));
  });

  test('reporta montos y stock inválidos con su número de fila', () {
    final r = parseSheet([
      ['Nombre', 'Precio', 'Stock'],
      ['Polo', 'abc', '1.5'],
    ]);
    expect(r.errors.map((e) => e.line), everyElement(2));
    expect(r.errors, hasLength(3)); // monto, stock y "falta el precio"
  });
}
