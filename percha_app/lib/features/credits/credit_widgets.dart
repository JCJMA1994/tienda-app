import '../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/percha_widgets.dart';
import '../onboarding/data/store_api.dart';
import '../pos/presentation/scanner_page.dart';
import '../printing/print_settings.dart';
import '../printing/ticket.dart';
import '../printing/ticket_pdf.dart';
import 'credits_api.dart';

/// Comprobante del vale: código grande + QR (el POS lo escanea al pagar).
Future<void> printCreditVoucher(WidgetRef ref, {required String code, required int amountCents, DateTime? expiresAt, required String title}) async {
  final store = ref.read(storeSettingsProvider).valueOrNull;
  final model = TicketModel(
    header: [(store?.name ?? '').toUpperCase()],
    title: title.toUpperCase(),
    meta: [code, if (expiresAt != null) 'Válido hasta: ${DateFormat('dd/MM/yyyy').format(expiresAt)}'],
    items: const [],
    totals: [(label: 'SALDO', value: formatCents(amountCents), strong: true)],
    payments: const [],
    footer: const ['Preséntalo al pagar. Es al portador: cuídalo como dinero.', 'No canjeable por efectivo.'],
    qr: code,
  );
  final paper = ref.read(printSettingsProvider).paperMm;
  await Printing.layoutPdf(name: 'Vale-${code.substring(code.length - 4)}', onLayout: (_) => ticketPdf(model, paperMm: paper));
}

/// Muestra un vale recién emitido. El código completo solo se ve AQUÍ: imprimir o copiar.
Future<void> showCreditIssued(BuildContext context, WidgetRef ref, {required String code, required int amountCents, DateTime? expiresAt, String title = 'Saldo a favor'}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(formatCents(amountCents), style: Theme.of(ctx).textTheme.headlineMedium),
        const SizedBox(height: PerchaSpace.md),
        SelectableText(code, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: PerchaType.code, fontWeight: FontWeight.w700, letterSpacing: 1)),
        if (expiresAt != null) Text('Válido hasta ${DateFormat("d 'de' MMMM yyyy", 'es').format(expiresAt)}', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: PerchaSpace.md),
        Card(
          color: PerchaColors.warnSoft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Entrégalo al cliente: el código no se vuelve a mostrar. Es al portador.', style: TextStyle(color: PerchaColors.warn)),
          ),
        ),
      ],),
      actions: [
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: code)),
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
        ),
        TextButton.icon(
          onPressed: () => printCreditVoucher(ref, code: code, amountCents: amountCents, expiresAt: expiresAt, title: title),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Imprimir'),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
      ],
    ),
  );
}

/// Pide y valida el vale antes de cobrar. Devuelve el código y cuánto se usará (hasta el total).
Future<({String code, int amountCents})?> askCreditCode(BuildContext context, {required int totalCents}) =>
    showDialog<({String code, int amountCents})>(context: context, builder: (_) => _CreditCodeDialog(totalCents: totalCents));

class _CreditCodeDialog extends ConsumerStatefulWidget {
  const _CreditCodeDialog({required this.totalCents});
  final int totalCents;

  @override
  ConsumerState<_CreditCodeDialog> createState() => _CreditCodeDialogState();
}

class _CreditCodeDialogState extends ConsumerState<_CreditCodeDialog> with ActionRunner {
  final _code = TextEditingController();
  CreditInfo? _info;
  String? _normalized;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check([String? raw]) async {
    final code = normalizeCreditCode(raw ?? _code.text);
    if (code == null) return setState(() => error = 'Código incompleto: VALE-XXXX-XXXX-XXXX');
    setState(() => _info = null);
    final info = await runAction(() => ref.read(creditsApiProvider).lookup(code));
    if (info == null || !mounted) return;
    setState(() {
      _info = info;
      _normalized = code;
      if (info.status != 'active') error = info.status == 'expired' ? 'El vale venció' : 'El vale no tiene saldo';
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final usable = info != null && info.status == 'active';
    final use = usable ? (info.balanceCents < widget.totalCents ? info.balanceCents : widget.totalCents) : 0;
    return AlertDialog(
      title: const Text('Pagar con vale'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Código del vale',
            hintText: 'VALE-XXXX-XXXX-XXXX',
            suffixIcon: IconButton(
              tooltip: 'Escanear QR del vale',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final scanned = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
                if (scanned != null) {
                  _code.text = scanned;
                  await _check(scanned);
                }
              },
            ),
          ),
          onSubmitted: (_) => _check(),
        ),
        const SizedBox(height: PerchaSpace.md),
        if (busy) const Center(child: CircularProgressIndicator()),
        if (error != null) ErrorBanner(error!),
        if (usable)
          Card(
            child: ListTile(
              title: Text('${info.kindLabel} · saldo ${formatCents(info.balanceCents)}'),
              subtitle: Text([
                if (info.customerName != null) info.customerName!,
                use < widget.totalCents ? 'Cubre ${formatCents(use)}; el resto (${formatCents(widget.totalCents - use)}) se paga con otro medio' : 'Cubre el total',
              ].join('\n'),),
            ),
          ),
      ],),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (!usable) FilledButton(onPressed: busy ? null : _check, child: const Text('Verificar')),
        if (usable) FilledButton(onPressed: () => Navigator.pop(context, (code: _normalized!, amountCents: use)), child: Text('Usar ${formatCents(use)}')),
      ],
    );
  }
}
