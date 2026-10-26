import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/widgets/percha_widgets.dart';
import '../cash/cash_api.dart';
import '../catalog/data/catalog_api.dart';
import '../onboarding/data/store_api.dart';
import '../pos/data/sales_api.dart';
import 'cash_report.dart';
import 'labels.dart';
import 'print_settings.dart';
import 'ticket.dart';
import 'ticket_pdf.dart';

/// Imprime (o comparte como PDF) el ticket de una venta. Usa el diálogo del sistema:
/// impresoras térmicas con servicio de impresión en Android, AirPrint en iOS, cualquier
/// impresora en la web. En la web o sin impresora, se puede guardar o compartir el PDF.
Future<void> printTicket(BuildContext context, WidgetRef ref, String saleId, {int changeCents = 0}) async {
  try {
    final sale = await ref.read(salesApiProvider).get(saleId);
    final settings = ref.read(printSettingsProvider);
    final model = buildTicket(sale, changeCents: changeCents);
    await Printing.layoutPdf(
      name: 'Ticket-${sale.number}',
      // Rollos estándar del paquete pdf (57/58 y 80 mm).
      format: settings.paperMm == 58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80,
      onLayout: (_) => ticketPdf(model, paperMm: settings.paperMm),
    );
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo imprimir: ${errorText(e)}')));
  }
}

/// Elige cuántas etiquetas por variante (por defecto, el stock de la sucursal) e imprime.
Future<void> printLabelsFor(BuildContext context, WidgetRef ref, Product product, String branchId) async {
  final copies = await showModalBottomSheet<Map<String, int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LabelCopiesSheet(product: product, branchId: branchId),
  );
  if (copies == null || copies.values.every((c) => c == 0) || !context.mounted) return;
  final labels = buildLabels([
    for (final v in product.variants)
      if ((copies[v.id] ?? 0) > 0)
        (name: product.name, options: v.options, priceCents: v.priceCents, barcode: v.barcode, sku: v.sku, copies: copies[v.id]!),
  ]);
  final format = ref.read(printSettingsProvider).labelFormat;
  try {
    await Printing.layoutPdf(name: 'Etiquetas-${product.skuBase}', onLayout: (_) => labelsPdf(labels, format: format));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo imprimir: ${errorText(e)}')));
  }
}

class _LabelCopiesSheet extends StatefulWidget {
  const _LabelCopiesSheet({required this.product, required this.branchId});
  final Product product;
  final String branchId;

  @override
  State<_LabelCopiesSheet> createState() => _LabelCopiesSheetState();
}

class _LabelCopiesSheetState extends State<_LabelCopiesSheet> {
  late final Map<String, int> _copies = {
    for (final v in widget.product.variants) v.id: v.stockIn(widget.branchId).quantity.clamp(0, 200),
  };

  @override
  Widget build(BuildContext context) {
    final total = _copies.values.fold(0, (a, b) => a + b);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Etiquetas · ${widget.product.name}', style: Theme.of(context).textTheme.titleLarge),
            Text('Una por prenda. Por defecto, el stock de esta sucursal.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                for (final v in widget.product.variants)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.options.isEmpty ? 'Única' : v.options.values.join(' · ')),
                    subtitle: Text(v.sku),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Menos',
                        icon: const Icon(Icons.remove),
                        onPressed: (_copies[v.id] ?? 0) > 0 ? () => setState(() => _copies[v.id] = _copies[v.id]! - 1) : null,
                      ),
                      SizedBox(width: 28, child: Text('${_copies[v.id]}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
                      IconButton(tooltip: 'Más', icon: const Icon(Icons.add), onPressed: () => setState(() => _copies[v.id] = (_copies[v.id] ?? 0) + 1)),
                    ],),
                  ),
              ],),
            ),
            FilledButton.icon(
              onPressed: total == 0 ? null : () => Navigator.pop(context, _copies),
              icon: const Icon(Icons.print_outlined),
              label: Text('Imprimir $total etiquetas'),
            ),
          ],),
        ),
      ),
    );
  }
}

/// Imprime el cierre (o corte parcial) de una caja en el rollo configurado.
Future<void> printCashReport(BuildContext context, WidgetRef ref, String sessionId) async {
  try {
    final report = await ref.read(cashApiProvider).report(sessionId);
    final store = await ref.read(storeSettingsProvider.future);
    final settings = ref.read(printSettingsProvider);
    await Printing.layoutPdf(
      name: 'Cierre-${report.openedAt.toIso8601String().substring(0, 10)}',
      format: settings.paperMm == 58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80,
      onLayout: (_) => ticketPdf(buildCashReport(report, storeName: store.name), paperMm: settings.paperMm),
    );
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo imprimir: ${errorText(e)}')));
  }
}
