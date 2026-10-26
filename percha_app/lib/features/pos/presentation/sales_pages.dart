import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/catalogs.dart';
import '../../../core/money.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/data/store_api.dart';
import '../../einvoice/data/einvoice_api.dart';
import '../../messaging/whatsapp_pages.dart';
import '../../printing/print_actions.dart';
import '../data/sales_api.dart';
import 'pin_dialog.dart';

final _salesListProvider = FutureProvider.autoDispose.family<List<SaleSummary>, ({String branchId, int? number})>(
  (ref, k) => ref.watch(salesApiProvider).list(branchId: k.branchId, number: k.number),
);

/// Ventas de la sucursal. Se busca por número de ticket: el cliente regresa con su comprobante.
class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  final _number = TextEditingController();
  int? _filter;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(currentBranchProvider).valueOrNull;
    final time = DateFormat('d MMM · HH:mm', 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Ventas')),
      body: branch == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: TextField(
                    controller: _number,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar por número de ticket',
                      prefixIcon: const Icon(Icons.receipt_long_outlined),
                      suffixIcon: _filter == null
                          ? null
                          : IconButton(
                              tooltip: 'Ver todas',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _number.clear();
                                _filter = null;
                              }),
                            ),
                    ),
                    onSubmitted: (v) => setState(() => _filter = int.tryParse(v)),
                  ),
                ),
                Expanded(
                  child: ref.watch(_salesListProvider((branchId: branch.id, number: _filter))).when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
                        data: (sales) => sales.isEmpty
                            ? Center(child: Text(_filter == null ? 'Aún no hay ventas' : 'No existe el ticket #$_filter'))
                            : RefreshIndicator(
                                onRefresh: () async => ref.invalidate(_salesListProvider),
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                  itemCount: sales.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: PerchaSpace.sm),
                                  itemBuilder: (_, i) {
                                    final s = sales[i];
                                    return Card(
                                      child: ListTile(
                                        title: Text('Ticket #${s.number}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                        subtitle: Text(time.format(s.createdAt)),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (s.voided) ...[const Pill('Anulada', warn: true), const SizedBox(width: 8)],
                                            Text(formatCents(s.totalCents), style: const TextStyle(fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                        onTap: () async {
                                          await context.push('/sales/${s.id}');
                                          ref.invalidate(_salesListProvider);
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                ),
              ],
            ),
    );
  }
}

class SaleDetailPage extends ConsumerWidget {
  const SaleDetailPage({super.key, required this.saleId});
  final String saleId;


  Future<void> _void(BuildContext context, WidgetRef ref, SaleDetail sale) async {
    final reason = await _askReason(context);
    if (reason == null || !context.mounted) return;
    final me = ref.read(meProvider);
    String? pin;
    if (!me.can('sales.void')) {
      pin = await askPin(context, title: 'Aprobación de supervisor', message: 'Anular requiere el PIN de un encargado.');
      if (pin == null) return;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await ref.read(salesApiProvider).voidSale(sale.id, reason: reason, approverPin: pin);
        ref.invalidate(saleDetailProvider(sale.id));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta anulada. El stock volvió y el pago se revirtió.')));
        return;
      } on ApiError catch (e) {
        if (!context.mounted) return;
        if (e.code == 'APPROVAL_INVALID' && attempt == 0) {
          pin = await askPin(context, title: 'Aprobación de supervisor', message: 'PIN incorrecto. Intenta de nuevo.');
          if (pin == null) return;
          continue;
        }
        final msg = e.code == 'USE_RETURN' ? '${e.message}. Usa "Devolver o cambiar".' : e.message;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
    }
  }

  Future<String?> _askReason(BuildContext context) {
    final controller = TextEditingController();
    const reasons = ['Cobro duplicado', 'Error de digitación', 'Cliente desistió'];
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Anular venta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Úsalo para errores del mismo turno. Si el cliente devuelve una prenda, usa "Devolver o cambiar".'),
              const SizedBox(height: PerchaSpace.md),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in reasons) ActionChip(label: Text(r), onPressed: () => setState(() => controller.text = r)),
              ]),
              const SizedBox(height: PerchaSpace.sm),
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'Motivo')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: PerchaColors.warn),
              onPressed: () {
                if (controller.text.trim().length >= 3) Navigator.pop(ctx, controller.text.trim());
              },
              child: const Text('Anular'),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final time = DateFormat("d 'de' MMMM, HH:mm", 'es');
    return Scaffold(
      appBar: AppBar(),
      body: ref.watch(saleDetailProvider(saleId)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (sale) {
              final text = Theme.of(context).textTheme;
              final canReturn = !sale.voided && !sale.fullyReturned && me.can('sales.return');
              final canVoid = !sale.voided && !sale.hasReturns && me.can('sales.create');
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Ticket #${sale.number}', style: text.headlineSmall)),
                      if (sale.voided) const Pill('Anulada', warn: true),
                    ],
                  ),
                  Text(time.format(sale.createdAt), style: text.bodySmall),
                  if (sale.voidReason != null) ...[const SizedBox(height: 4), Text('Motivo: ${sale.voidReason}', style: text.bodySmall)],
                  const SizedBox(height: PerchaSpace.lg),
                  Card(
                    child: Column(
                      children: [
                        for (final l in sale.lines)
                          ListTile(
                            title: Text(l.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([
                              if (l.optionsLabel.isNotEmpty) l.optionsLabel,
                              '${l.quantity} × ${formatCents(l.unitPriceCents)}',
                              if (l.returnedQuantity > 0) '${l.returnedQuantity} devuelta${l.returnedQuantity == 1 ? '' : 's'}',
                            ].join(' · ')),
                            trailing: Text(formatCents(l.lineTotalCents), style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PerchaSpace.lg),
                  _Line('Subtotal', formatCents(sale.subtotalCents)),
                  if (sale.discountCents > 0) _Line('Descuento', '− ${formatCents(sale.discountCents)}'),
                  _Line('IGV', formatCents(sale.taxCents)),
                  _Line('Total', formatCents(sale.totalCents), bold: true),
                  const SizedBox(height: PerchaSpace.md),
                  for (final p in sale.payments)
                    _Line(p.amountCents < 0 ? '${Labels.paymentMethod(p.method)} (reverso)' : Labels.paymentMethod(p.method), formatCents(p.amountCents)),
                  const SizedBox(height: PerchaSpace.md),
                  OutlinedButton.icon(
                    onPressed: () => printTicket(context, ref, sale.id),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(sale.documents.any((d) => d.kind != 'nota_credito') ? 'Imprimir comprobante' : 'Imprimir ticket'),
                  ),
                  if (sale.customer != null) ...[
                    const SizedBox(height: PerchaSpace.sm),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(sale.customer!.name),
                      subtitle: const Text('Ver ficha del cliente'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/customers/${sale.customer!.id}'),
                    ),
                  ],
                  if (!sale.voided && (ref.watch(whatsappEnabledProvider).valueOrNull ?? false)) ...[
                    const SizedBox(height: PerchaSpace.md),
                    OutlinedButton.icon(
                      onPressed: () => sendReceiptByWhatsApp(context, ref, sale.id),
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('Enviar comprobante por WhatsApp'),
                    ),
                  ],
                  if (sale.documents.isNotEmpty) ...[
                    const SizedBox(height: PerchaSpace.lg),
                    Text('Comprobantes', style: text.titleMedium),
                    for (final d in sale.documents) _DocumentTile(doc: d, onRetried: () => ref.invalidate(saleDetailProvider(sale.id))),
                  ],
                  const SizedBox(height: PerchaSpace.xl),
                  if (canReturn)
                    FilledButton(onPressed: () => context.push('/sales/${sale.id}/return'), child: const Text('Devolver o cambiar')),
                  if (canVoid) ...[
                    const SizedBox(height: PerchaSpace.sm),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: PerchaColors.warn),
                      onPressed: () => _void(context, ref, sale),
                      child: const Text('Anular venta'),
                    ),
                  ],
                ],
              );
            },
          ),
    );
  }
}

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile({required this.doc, required this.onRetried});
  final EDocument doc;
  final VoidCallback onRetried;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final problem = doc.status == 'rejected' || doc.status == 'error';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${doc.kindLabel} ${doc.code}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([formatCents(doc.totalCents), if (doc.sunatDescription != null) doc.sunatDescription!, if (doc.lastError != null) doc.lastError!].join(' · ')),
      trailing: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Pill(doc.statusLabel, warn: problem),
          if (doc.pdfUrl != null)
            IconButton(
              tooltip: 'Ver PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => launchUrl(Uri.parse(doc.pdfUrl!), mode: LaunchMode.externalApplication),
            ),
          if (doc.canRetry)
            IconButton(
              tooltip: 'Reintentar envío',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                try {
                  await ref.read(einvoiceApiProvider).retry(doc.id);
                  onRetried();
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
                }
              },
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: bold ? PerchaType.amount : PerchaType.body);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text(value, style: style)]),
    );
  }
}

