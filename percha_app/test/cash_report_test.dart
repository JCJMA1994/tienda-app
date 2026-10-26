import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:percha_app/features/cash/cash_api.dart';
import 'package:percha_app/features/printing/cash_report.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  CashReport report({int? counted, int? diff, String status = 'closed'}) => CashReport.fromJson({
        'id': 'c1',
        'branchName': 'Miraflores',
        'status': status,
        'openedAt': '2026-10-27T13:00:00Z',
        'openedBy': 'Joao',
        'closedAt': status == 'closed' ? '2026-10-28T01:00:00Z' : null,
        'closedBy': status == 'closed' ? 'Joao' : null,
        'openingCents': 5000,
        'byMethod': [
          {'method': 'cash', 'totalCents': 23600},
          {'method': 'card', 'totalCents': 11800},
        ],
        'sales': {'count': 2, 'totalCents': 47200, 'voidedCount': 1, 'voidedCents': 11800},
        'returns': {'count': 1, 'differenceCents': -11800},
        'layawayPayments': {'count': 0, 'totalCents': 0},
        'expectedCashCents': 28600,
        'countedCashCents': counted,
        'differenceCents': diff,
      });

  test('cierre: medios de pago, anuladas aparte, faltante y firma', () {
    final t = buildCashReport(report(counted: 28500, diff: -100), storeName: 'Alma');
    expect(t.title, 'CIERRE DE CAJA');
    expect(t.items.map((i) => i.left), ['Ventas (2)', 'Anuladas (1)', 'Devoluciones y cambios (1)']);
    expect(t.totals.map((x) => x.label), ['Fondo inicial', 'Efectivo esperado', 'Efectivo contado', 'Faltante']);
    expect(t.payments.map((p) => p.label), ['Efectivo', 'Tarjeta']);
    expect(t.footer.last, contains('Firma'));
  });

  test('corte parcial: sin conteo ni firma', () {
    final t = buildCashReport(report(status: 'open'), storeName: 'Alma');
    expect(t.title, 'CORTE PARCIAL DE CAJA');
    expect(t.totals.map((x) => x.label), ['Fondo inicial', 'Efectivo esperado']);
    expect(t.footer.any((f) => f.contains('Firma')), isFalse);
  });

  test('cuadra exacto', () {
    expect(buildCashReport(report(counted: 28600, diff: 0), storeName: 'Alma').totals.last.label, 'Cuadra');
  });
}
