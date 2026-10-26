import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../onboarding/data/store_api.dart';
import '../application/return_draft.dart';
import '../data/pos_api.dart';
import '../data/pos_models.dart';
import '../../credits/credit_widgets.dart';
import '../data/sales_api.dart';
import 'scanner_page.dart';
import 'variant_picker.dart';

/// Devolución o cambio sobre una venta. Paso a paso en una sola pantalla:
/// 1) qué vuelve, 2) qué se lleva (opcional), 3) diferencia y cómo se paga.
class ReturnPage extends ConsumerStatefulWidget {
  const ReturnPage({super.key, required this.saleId});
  final String saleId;

  @override
  ConsumerState<ReturnPage> createState() => _ReturnPageState();
}

class _ReturnPageState extends ConsumerState<ReturnPage> with ActionRunner {
  ReturnDraft _draft = const ReturnDraft();
  PaymentMethod _method = PaymentMethod.cash;
  final _reason = TextEditingController();
  final _search = TextEditingController();

  static const _reasons = ['Cambio de talla', 'No le gustó', 'Fallado', 'Regalo'];

  @override
  void dispose() {
    _reason.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _addByCode(String code, String branchId) async {
    if (code.trim().isEmpty) return;
    try {
      final v = await ref.read(posApiProvider).lookup(code.trim(), branchId);
      if (v == null) {
        // No es un código: se busca por nombre y se elige talla/color.
        final found = await ref.read(posApiProvider).products(search: code.trim(), branchId: branchId);
        if (!mounted) return;
        if (found.isEmpty) {
          setState(() => error = 'No se encontró "$code"');
          return;
        }
        final picked = await pickVariant(context, productId: found.first.id, branchId: branchId);
        if (picked != null) _addReplacement(picked);
      } else {
        _addReplacement(v);
      }
      _search.clear();
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  void _addReplacement(SellableVariant v) {
    if (!v.sellable || (v.stock ?? 1) <= 0) {
      setState(() => error = '${v.productName} ${v.optionsLabel} no tiene stock');
      return;
    }
    setState(() {
      error = null;
      _draft = _draft.addReplacement(v);
    });
  }

  Future<void> _submit(SaleDetail sale, Branch branch, StoreSettings store) async {
    if (_draft.isEmpty) {
      setState(() => error = 'Elige al menos una prenda que vuelve');
      return;
    }
    if (_reason.text.trim().length < 3) {
      setState(() => error = 'Indica el motivo');
      return;
    }
    final diff = _draft.difference(sale, taxRateBp: store.taxRateBp, pricesIncludeTax: store.pricesIncludeTax);

    // Si el cliente PAGA la diferencia con un vale, se pide (y verifica) su código antes.
    String? creditCode;
    if (diff > 0 && _method == PaymentMethod.storeCredit) {
      final c = await askCreditCode(context, totalCents: diff);
      if (c == null || !mounted) return;
      if (c.amountCents < diff) return setState(() => error = 'El vale no cubre la diferencia: elige otro medio de pago.');
      creditCode = c.code;
    }

    final result = await runAction(
      () => ref.read(salesApiProvider).createReturn(
            saleId: sale.id,
            branchId: branch.id,
            items: [
              for (final e in _draft.returning.entries)
                if (e.value > 0) (saleItemId: e.key, quantity: e.value),
            ],
            replacements: [for (final r in _draft.replacements) (variantId: r.variant.id, quantity: r.quantity)],
            method: diff == 0 ? null : _method,
            amountCents: diff.abs(),
            creditCode: creditCode,
            reason: _reason.text.trim(),
          ),
      describeError: (e) => switch (e) {
        ApiError(code: 'CASH_CLOSED') => 'Abre la caja para registrar devoluciones (mueven dinero).',
        ApiError(code: 'INSUFFICIENT_STOCK', :final data) => 'No hay stock de la prenda de cambio (quedan ${data['available']}).',
        _ => errorText(e),
      },
    );
    if (result == null || !mounted) return;
    ref.invalidate(saleDetailProvider(sale.id));

    if (result.creditCode != null) {
      await showCreditIssued(context, ref, code: result.creditCode!, amountCents: -result.differenceCents, expiresAt: result.creditExpiresAt);
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.check_circle_outline, color: PerchaColors.success, size: 40),
          title: Text('${result.kind == 'exchange' ? 'Cambio' : 'Devolución'} #${result.number}'),
          content: Text(
            result.differenceCents == 0
                ? 'Cambio parejo, sin movimiento de dinero.'
                : result.differenceCents > 0
                    ? 'El cliente pagó ${formatCents(result.differenceCents)} (${_method.label}).'
                    : 'Se devolvió ${formatCents(-result.differenceCents)} (${_method.label}).',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo'))],
        ),
      );
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final sale = ref.watch(saleDetailProvider(widget.saleId));
    final branch = ref.watch(currentBranchProvider).valueOrNull;
    final store = ref.watch(storeSettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Devolver o cambiar')),
      body: switch (sale) {
        AsyncError(:final error) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(error))),
        AsyncData(value: final s) when branch != null && store != null => _form(s, branch, store),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _form(SaleDetail sale, Branch branch, StoreSettings store) {
    final text = Theme.of(context).textTheme;
    final returned = _draft.returnedCents(sale);
    final replacement = _draft.replacementCents(taxRateBp: store.taxRateBp, pricesIncludeTax: store.pricesIncludeTax);
    final diff = replacement - returned;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Text('Ticket #${sale.number}', style: text.bodySmall),
        const SizedBox(height: PerchaSpace.md),
        Text('1. ¿Qué devuelve?', style: text.titleMedium),
        const SizedBox(height: PerchaSpace.sm),
        Card(
          child: Column(
            children: [
              for (final l in sale.lines)
                ListTile(
                  enabled: l.returnable > 0,
                  title: Text(l.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(l.returnable == 0
                      ? 'Ya devuelta'
                      : [if (l.optionsLabel.isNotEmpty) l.optionsLabel, 'pagó ${formatCents((l.lineTotalCents / l.quantity).round())} c/u'].join(' · ')),
                  trailing: l.returnable == 0
                      ? null
                      : _Stepper(
                          value: _draft.returning[l.id] ?? 0,
                          max: l.returnable,
                          onChanged: (q) => setState(() => _draft = _draft.setReturning(l, q)),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: PerchaSpace.xl),
        Text('2. ¿Se lleva algo a cambio?', style: text.titleMedium),
        const SizedBox(height: 4),
        Text('Opcional. Si no agregas nada, es una devolución con reembolso.', style: text.bodySmall),
        const SizedBox(height: PerchaSpace.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: 'Escanea o busca la prenda nueva', prefixIcon: Icon(Icons.search)),
                onSubmitted: (v) => _addByCode(v, branch.id),
              ),
            ),
            const SizedBox(width: PerchaSpace.sm),
            IconButton.outlined(
              tooltip: 'Escanear',
              constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
                if (code != null) await _addByCode(code, branch.id);
              },
            ),
          ],
        ),
        for (final r in _draft.replacements)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${r.variant.productName} · ${r.variant.optionsLabel}', style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('${r.quantity} × ${formatCents(r.variant.priceCents)}'),
            trailing: IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _draft = _draft.removeReplacement(r.variant.id)),
            ),
          ),
        const SizedBox(height: PerchaSpace.xl),
        Text('3. Motivo', style: text.titleMedium),
        const SizedBox(height: PerchaSpace.sm),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in _reasons) ActionChip(label: Text(r), onPressed: () => setState(() => _reason.text = r)),
        ]),
        const SizedBox(height: PerchaSpace.sm),
        TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Motivo')),
        const SizedBox(height: PerchaSpace.xl),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Row('Vuelve', formatCents(returned)),
                if (_draft.isExchange) _Row('Se lleva', formatCents(replacement)),
                const Divider(height: 20),
                _Row(
                  diff > 0
                      ? 'Cliente paga'
                      : diff < 0
                          ? 'Devolver al cliente'
                          : 'Diferencia',
                  formatCents(diff.abs()),
                  bold: true,
                ),
                if (diff != 0) ...[
                  const SizedBox(height: PerchaSpace.md),
                  SegmentedButton<PaymentMethod>(
                    segments: [for (final m in PaymentMethod.values) ButtonSegment(value: m, label: Text(m.label))],
                    selected: {_method},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _method = s.first),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (error != null) ...[const SizedBox(height: PerchaSpace.lg), ErrorBanner(error!)],
        const SizedBox(height: PerchaSpace.lg),
        BusyButton(
          label: _draft.isExchange ? 'Registrar cambio' : 'Registrar devolución',
          busy: busy,
          onPressed: _draft.isEmpty ? null : () => _submit(sale, branch, store),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.max, required this.onChanged});
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(tooltip: 'Menos', icon: const Icon(Icons.remove, size: 18), onPressed: value > 0 ? () => onChanged(value - 1) : null),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton.outlined(tooltip: 'Más', icon: const Icon(Icons.add, size: 18), onPressed: value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
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
