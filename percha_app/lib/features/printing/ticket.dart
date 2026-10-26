import 'package:intl/intl.dart';

import '../../core/catalogs.dart';
import '../../core/money.dart';
import '../pos/data/sales_models.dart';

/// Contenido del ticket, independiente del formato (PDF hoy, ESC/POS mañana). Lógica pura y
/// probada: qué se imprime y en qué orden.
///
/// Si la venta tiene boleta o factura electrónica, el ticket es su REPRESENTACIÓN IMPRESA:
/// lleva tipo y serie-número, datos del emisor y del cliente, IGV desglosado, el resumen
/// (hash) y el QR con la cadena que entrega el OSE.
class TicketModel {
  const TicketModel({
    required this.header,
    required this.title,
    required this.meta,
    required this.items,
    required this.totals,
    required this.payments,
    required this.footer,
    this.qr,
    this.hash,
  });

  final List<String> header;
  final String title;
  final List<String> meta;
  final List<({String left, String right, String? detail})> items;
  final List<({String label, String value, bool strong})> totals;
  final List<({String label, String value})> payments;
  final List<String> footer;
  final String? qr;
  final String? hash;
}

const _docTitles = {'boleta': 'BOLETA DE VENTA ELECTRÓNICA', 'factura': 'FACTURA ELECTRÓNICA'};
const _docNames = {'boleta': 'Boleta de Venta Electrónica', 'factura': 'Factura Electrónica'};

TicketModel buildTicket(SaleDetail sale, {String? sellerName, int changeCents = 0}) {
  final s = sale.store;
  final doc = sale.documents.where((d) => d.kind == 'boleta' || d.kind == 'factura').firstOrNull;
  final date = DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt);

  final header = <String>[
    (s.legalName ?? s.name).toUpperCase(),
    if (s.legalName != null && s.legalName!.toUpperCase() != s.name.toUpperCase()) s.name,
    if (s.ruc != null) 'RUC ${s.ruc}',
    if (s.fiscalAddress != null) s.fiscalAddress!,
    if (s.branchAddress != null && s.branchAddress != s.fiscalAddress) s.branchAddress!,
  ];

  final customer = doc != null && doc.customerDocNumber != null
      ? '${(doc.customerDocType ?? '').toUpperCase()} ${doc.customerDocNumber} · ${doc.customerName ?? ''}'
      : sale.customer?.name;

  final gravada = sale.totalCents - sale.taxCents;
  return TicketModel(
    header: header,
    title: doc != null ? '${_docTitles[doc.kind]}\n${doc.code}' : 'TICKET DE VENTA #${sale.number}',
    meta: [
      'Fecha: $date',
      if (doc != null) 'Ticket interno: #${sale.number}',
      if (customer != null && customer.trim().isNotEmpty) 'Cliente: $customer',
      if (sellerName != null) 'Atendió: $sellerName',
    ],
    items: [
      for (final l in sale.lines)
        (
          left: '${l.quantity} x ${l.productName}',
          right: formatCents(l.lineTotalCents),
          detail: [if (l.options.isNotEmpty) l.optionsLabel, if (l.quantity > 1) '${formatCents(l.unitPriceCents)} c/u'].join(' · ').ifEmptyNull,
        ),
    ],
    totals: [
      if (sale.discountCents > 0) (label: 'Subtotal', value: formatCents(sale.subtotalCents), strong: false),
      if (sale.discountCents > 0) (label: 'Descuento', value: '-${formatCents(sale.discountCents)}', strong: false),
      if (sale.taxCents > 0) (label: 'Op. gravada', value: formatCents(gravada), strong: false),
      if (sale.taxCents > 0) (label: 'IGV', value: formatCents(sale.taxCents), strong: false),
      (label: 'TOTAL', value: formatCents(sale.totalCents), strong: true),
    ],
    payments: [
      for (final p in sale.payments) (label: Labels.paymentMethod(p.method), value: formatCents(p.amountCents)),
      if (changeCents > 0) (label: 'Vuelto', value: formatCents(changeCents)),
    ],
    footer: [
      if (doc != null) 'Representación impresa de la ${_docNames[doc.kind]}.',
      if (doc != null && doc.status != 'accepted') 'Comprobante en proceso de envío a SUNAT.',
      'Cambios dentro de los 7 días con este ticket.',
      '¡Gracias por tu compra!',
    ],
    qr: doc?.qr,
    hash: doc?.hash,
  );
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
