import 'package:intl/intl.dart';

import '../../core/catalogs.dart';
import '../../core/money.dart';
import '../cash/cash_api.dart';
import 'ticket.dart';

/// Contenido del cierre de caja para el ticket de 80/58 mm (puro: se prueba sin Flutter).
TicketModel buildCashReport(CashReport r, {required String storeName}) {
  final date = DateFormat('dd/MM/yyyy HH:mm', 'es');
  final diff = r.differenceCents;
  return TicketModel(
    header: [storeName, r.branchName],
    title: r.closed ? 'CIERRE DE CAJA' : 'CORTE PARCIAL DE CAJA',
    meta: [
      'Apertura: ${date.format(r.openedAt)}${r.openedBy == null ? '' : ' · ${r.openedBy}'}',
      if (r.closedAt != null) 'Cierre: ${date.format(r.closedAt!)}${r.closedBy == null ? '' : ' · ${r.closedBy}'}',
    ],
    items: [
      (left: 'Ventas (${r.salesCount})', right: formatCents(r.salesCents), detail: null),
      if (r.voidedCount > 0) (left: 'Anuladas (${r.voidedCount})', right: formatCents(r.voidedCents), detail: 'No suman en el total'),
      if (r.returnsCount > 0) (left: 'Devoluciones y cambios (${r.returnsCount})', right: formatCents(r.returnsDifferenceCents), detail: null),
      if (r.layawayCount > 0) (left: 'Abonos de apartados (${r.layawayCount})', right: formatCents(r.layawayCents), detail: null),
    ],
    totals: [
      (label: 'Fondo inicial', value: formatCents(r.openingCents), strong: false),
      (label: 'Efectivo esperado', value: formatCents(r.expectedCashCents), strong: true),
      if (r.countedCashCents != null) (label: 'Efectivo contado', value: formatCents(r.countedCashCents!), strong: true),
      if (diff != null) (label: diff == 0 ? 'Cuadra' : diff > 0 ? 'Sobrante' : 'Faltante', value: formatCents(diff.abs()), strong: true),
    ],
    payments: [for (final e in r.byMethod.entries) (label: Labels.paymentMethod(e.key), value: formatCents(e.value))],
    footer: [
      'Por medio de pago: incluye ventas, abonos y devoluciones.',
      if (r.closed) '\nFirma: ______________________',
    ],
  );
}
