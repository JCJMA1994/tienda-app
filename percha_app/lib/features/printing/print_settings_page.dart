// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/theme/tokens.dart';
import 'labels.dart';
import 'print_settings.dart';
import 'ticket.dart';
import 'ticket_pdf.dart';
import '../pos/data/sales_api.dart';

/// Impresora de este dispositivo: ancho del rollo, formato de etiquetas e impresión automática.
class PrintSettingsPage extends ConsumerWidget {
  const PrintSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(printSettingsProvider);
    final ctrl = ref.read(printSettingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Impresora y etiquetas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text('Se guarda en este dispositivo: cada caja puede tener su impresora.', style: text.bodySmall),
          const SizedBox(height: PerchaSpace.lg),
          Text('Ticket', style: text.titleMedium),
          const SizedBox(height: PerchaSpace.sm),
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 58, label: Text('Rollo 58 mm')), ButtonSegment(value: 80, label: Text('Rollo 80 mm'))],
            selected: {s.paperMm},
            showSelectedIcon: false,
            onSelectionChanged: (v) => ctrl.update(s.copyWith(paperMm: v.first)),
          ),
          Card(
            margin: const EdgeInsets.only(top: PerchaSpace.md),
            child: SwitchListTile(
              title: const Text('Imprimir el ticket al cobrar'),
              subtitle: const Text('Abre la impresión sin tocar "Imprimir"'),
              value: s.autoPrint,
              onChanged: (v) => ctrl.update(s.copyWith(autoPrint: v)),
            ),
          ),
          const SizedBox(height: PerchaSpace.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir ticket de prueba'),
            onPressed: () => Printing.layoutPdf(name: 'Prueba', onLayout: (_) => ticketPdf(buildTicket(_sample), paperMm: s.paperMm)),
          ),
          const SizedBox(height: PerchaSpace.xl),
          Text('Etiquetas de precio', style: text.titleMedium),
          const SizedBox(height: PerchaSpace.sm),
          RadioListTile<LabelFormat>(
            value: LabelFormat.a4Sheet,
            groupValue: s.labelFormat,
            onChanged: (v) => ctrl.update(s.copyWith(labelFormat: v)),
            title: const Text('Hoja A4 (3 × 8 etiquetas de 70 × 37 mm)'),
            subtitle: const Text('Impresora común con hojas adhesivas'),
          ),
          RadioListTile<LabelFormat>(
            value: LabelFormat.roll50x25,
            groupValue: s.labelFormat,
            onChanged: (v) => ctrl.update(s.copyWith(labelFormat: v)),
            title: const Text('Rollo de etiquetas 50 × 25 mm'),
            subtitle: const Text('Impresora de etiquetas (Zebra, Xprinter, etc.)'),
          ),
          const SizedBox(height: PerchaSpace.lg),
          Card(
            color: PerchaColors.surfaceAlt,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Cómo conectar la térmica: en Android instala el servicio de impresión del fabricante (o uno genérico ESC/POS) y aparecerá al imprimir; en iPhone, impresoras con AirPrint; en la web, cualquier impresora instalada en la computadora. También puedes guardar o compartir el PDF.',
                style: text.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _sample = SaleDetail.fromJson({
  'id': 'prueba',
  'number': 1,
  'branchId': '-',
  'status': 'completed',
  'subtotalCents': 18990,
  'discountCents': 0,
  'totalCents': 18990,
  'taxCents': 2897,
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'items': [
    {'id': '1', 'variantId': '1', 'productName': 'Prenda de prueba', 'sku': 'PRUEBA', 'options': {'Talla': 'M'}, 'quantity': 1, 'returnedQuantity': 0, 'unitPriceCents': 18990, 'lineTotalCents': 18990},
  ],
  'payments': [
    {'method': 'cash', 'amountCents': 18990},
  ],
  'store': {'name': 'Ticket de prueba'},
});
