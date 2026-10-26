part of 'product_detail_page.dart';

class _VariantPanel extends ConsumerWidget {
  const _VariantPanel({required this.variant, required this.branchId, required this.canAdjust, required this.onChanged});
  final Variant variant;
  final String branchId;
  final bool canAdjust;
  final VoidCallback onChanged;

  Future<void> _adjust(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({int? delta, int? counted, String reason})>(
      context: context,
      builder: (_) => _AdjustDialog(current: variant.stockIn(branchId).quantity),
    );
    if (result == null) return;
    try {
      await ref.read(catalogApiProvider).adjust(
            branchId: branchId,
            variantId: variant.id,
            delta: result.delta,
            counted: result.counted,
            reason: result.reason,
          );
      onChanged();
      ref.invalidate(_movementsProvider((variantId: variant.id, branchId: branchId)));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  Future<void> _minStock(BuildContext context, WidgetRef ref) async {
    final value = await promptInt(
      context,
      title: 'Stock mínimo',
      label: 'Avisar cuando queden',
      initial: variant.stockIn(branchId).minQuantity,
      max: 100000,
      helper: 'Recibirás una notificación al llegar a este número',
    );
    if (value == null) return;
    try {
      await ref.read(catalogApiProvider).setMinStock(branchId: branchId, variantId: variant.id, minQuantity: value);
      onChanged();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = variant.stockIn(branchId);
    final white = TextStyle(color: PerchaColors.onInverse);
    return Container(
      padding: const EdgeInsets.all(PerchaSpace.lg),
      decoration: BoxDecoration(color: PerchaColors.inverse, borderRadius: BorderRadius.circular(PerchaRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(variant.options.values.join(' · ').isEmpty ? 'Única' : variant.options.values.join(' · '),
                        style: white.copyWith(fontWeight: FontWeight.w600, fontSize: PerchaType.strong),),
                    const SizedBox(height: 2),
                    SelectableText('SKU ${variant.sku} · ${variant.barcode}', style: TextStyle(color: PerchaColors.onInverse.withValues(alpha: 0.75), fontSize: PerchaType.meta)),
                    if (variant.avgCostCents != null)
                      Text('Costo promedio ${formatCents(variant.avgCostCents!)}', style: TextStyle(color: PerchaColors.onInverse.withValues(alpha: 0.75), fontSize: PerchaType.meta)),
                    Text('Mínimo: ${s.minQuantity}', style: TextStyle(color: PerchaColors.onInverse.withValues(alpha: 0.75), fontSize: PerchaType.meta)),
                  ],
                ),
              ),
              Text('${s.quantity}', style: white.copyWith(fontSize: PerchaType.display, fontWeight: FontWeight.w700)),
            ],
          ),
          if (canAdjust) ...[
            const SizedBox(height: PerchaSpace.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: PerchaColors.onInverse, foregroundColor: PerchaColors.inverse, minimumSize: const Size.fromHeight(44)),
                    onPressed: () => _adjust(context, ref),
                    child: const Text('Ajustar stock'),
                  ),
                ),
                const SizedBox(width: PerchaSpace.sm),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: PerchaColors.onInverse,
                      side: BorderSide(color: PerchaColors.onInverse.withValues(alpha: 0.4)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => _minStock(context, ref),
                    child: const Text('Stock mínimo'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Ajuste por conteo físico (lo normal en una boutique) o por variación con motivo.
class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.current});
  final int current;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  bool _byCount = true;
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();

  static const _reasons = ['Conteo físico', 'Merma o daño', 'Pérdida o robo', 'Carga inicial'];

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!submitForm(_form)) return;
    final n = int.parse(_qty.text.replaceAll('+', ''));
    Navigator.pop(context, (delta: _byCount ? null : n, counted: _byCount ? n : null, reason: _reason.text.trim()));
  }

  String? _qtyRule(String? v) {
    final n = int.tryParse((v ?? '').replaceAll('+', '').trim());
    if (n == null) return _byCount ? 'Ingresa cuántas contaste' : 'Ej. -1 o 3';
    if (_byCount && n < 0) return 'No puede ser negativo';
    if (!_byCount && n == 0) return 'La variación no puede ser 0';
    if (n.abs() > 100000) return 'Máximo 100 000';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajustar stock'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Actual: ${widget.current} unid.'),
            const SizedBox(height: PerchaSpace.md),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Conteo')), ButtonSegment(value: false, label: Text('Variación'))],
              selected: {_byCount},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _byCount = s.first),
            ),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(
              controller: _qty,
              autofocus: true,
              label: _byCount ? 'Unidades contadas' : 'Variación (ej. -1 o 3)',
              helper: _byCount ? 'El sistema calcula la diferencia' : 'Negativo para restar',
              kind: _byCount ? FieldKind.integer : FieldKind.text,
              validator: _qtyRule,
            ),
            const SizedBox(height: PerchaSpace.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final r in _reasons) ActionChip(label: Text(r), onPressed: () => setState(() => _reason.text = r))],
            ),
            const SizedBox(height: PerchaSpace.sm),
            AppTextField(
              controller: _reason,
              label: 'Motivo',
              validator: V.all([V.minLength(3, 'Indica el motivo'), V.maxLength(200)]),
              last: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

class _Movements extends ConsumerWidget {
  const _Movements({required this.variantId, required this.branchId});
  final String variantId;
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_movementsProvider((variantId: variantId, branchId: branchId)));
    final date = DateFormat('d MMM, HH:mm', 'es');
    return list.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => ErrorBanner(errorText(e)),
      data: (items) => items.isEmpty
          ? const Text('Sin movimientos en esta sucursal')
          : Column(
              children: [
                for (final m in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text([date.format(m.createdAt), if (m.reason != null) m.reason!].join(' · ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          m.quantity > 0 ? '+${m.quantity}' : '${m.quantity}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: m.quantity > 0 ? PerchaColors.accent : PerchaColors.warn),
                        ),
                        Text('Saldo ${m.balanceAfter}', style: TextStyle(fontSize: PerchaType.caption, color: PerchaColors.muted)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
