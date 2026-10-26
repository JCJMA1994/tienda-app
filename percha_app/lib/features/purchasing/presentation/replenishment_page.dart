import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/action_runner.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/data/store_api.dart';
import '../data/purchasing_api.dart';
import '../data/replenishment_api.dart';

/// Reposición sugerida: qué pedir por talla y color según lo que se vende, agrupado por
/// proveedor. Las cantidades se pueden ajustar antes de crear la orden de compra (borrador).
class ReplenishmentPage extends ConsumerStatefulWidget {
  const ReplenishmentPage({super.key});

  @override
  ConsumerState<ReplenishmentPage> createState() => _ReplenishmentPageState();
}

class _ReplenishmentPageState extends ConsumerState<ReplenishmentPage> with ActionRunner {
  int _windowDays = 28;
  int _coverDays = 30;
  int _leadDays = 7;

  /// Cantidades editadas por variante (si no, la sugerida). 0 = no pedir.
  final Map<String, int> _qty = {};

  int _q(SuggestionItem i) => _qty[i.variantId] ?? i.quantity;

  Future<void> _createOrder(String branchId, SupplierSuggestion g) async {
    var supplierId = g.supplierId;
    if (supplierId == null) {
      supplierId = await _pickSupplier();
      if (supplierId == null || !mounted) return;
    }
    final items = [
      for (final i in g.items)
        if (_q(i) > 0) (variantId: i.variantId, quantity: _q(i), unitCostCents: i.unitCostCents),
    ];
    if (items.isEmpty) return snack('Todas las cantidades están en 0');
    final po = await runAction(
      () => ref.read(purchasingApiProvider).create(supplierId: supplierId!, branchId: branchId, notes: 'Creada desde la reposición sugerida', items: items),
      errorAsSnack: true,
    );
    if (po == null || !mounted) return;
    snack('Orden #${po.number} creada como borrador: revísala y confírmala');
    await context.push('/purchases/${po.id}');
    ref.invalidate(suggestionsProvider);
  }

  Future<String?> _pickSupplier() async {
    final suppliers = await ref.read(suppliersProvider.future);
    if (!mounted) return null;
    if (suppliers.isEmpty) {
      snack('Primero registra un proveedor en Compras → Proveedores');
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('¿A qué proveedor se lo pides?'),
        children: [for (final s in suppliers.where((s) => s.active)) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, s.id), child: Text(s.name))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(currentBranchProvider).valueOrNull;
    final text = Theme.of(context).textTheme;
    if (branch == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final params = (branchId: branch.id, windowDays: _windowDays, coverDays: _coverDays, leadDays: _leadDays);

    Widget chips<T>(String label, T value, List<(T, String)> options, void Function(T) onPick) => Padding(
          padding: const EdgeInsets.only(bottom: PerchaSpace.sm),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 112, child: Text(label, style: text.bodySmall)),
            for (final (v, l) in options) ChoiceChip(label: Text(l), selected: v == value, onSelected: (_) => setState(() => onPick(v))),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Reposición sugerida')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(suggestionsProvider(params)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            Text('Según lo vendido en ${branch.name}, por talla y color. Ya resta el stock y lo que viene en órdenes abiertas.', style: text.bodySmall),
            const SizedBox(height: PerchaSpace.md),
            chips('Mirar ventas de', _windowDays, const [(14, '2 semanas'), (28, '4 semanas'), (56, '8 semanas')], (v) => _windowDays = v),
            chips('Pedir para', _coverDays, const [(15, '15 días'), (30, '30 días'), (60, '60 días')], (v) => _coverDays = v),
            chips('El proveedor tarda', _leadDays, const [(3, '3 días'), (7, '1 semana'), (14, '2 semanas')], (v) => _leadDays = v),
            const SizedBox(height: PerchaSpace.md),
            ...ref.watch(suggestionsProvider(params)).when(
                  loading: () => const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
                  error: (e, _) => [ErrorBanner(errorText(e))],
                  data: (groups) => groups.isEmpty
                      ? [
                          const SizedBox(height: 40),
                          Icon(Icons.check_circle_outline, size: 48, color: PerchaColors.success),
                          const SizedBox(height: PerchaSpace.sm),
                          const Text('No hace falta reponer nada por ahora.', textAlign: TextAlign.center),
                        ]
                      : [for (final g in groups) _SupplierCard(group: g, qtyOf: _q, onChange: (v, q) => setState(() => _qty[v] = q), busy: busy, onCreate: () => _createOrder(branch.id, g))],
                ),
          ],
        ),
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.group, required this.qtyOf, required this.onChange, required this.busy, required this.onCreate});
  final SupplierSuggestion group;
  final int Function(SuggestionItem) qtyOf;
  final void Function(String variantId, int qty) onChange;
  final bool busy;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final units = group.items.fold(0, (a, i) => a + qtyOf(i));
    final cost = group.items.fold(0, (a, i) => a + qtyOf(i) * i.unitCostCents);
    // Por producto: se ve la curva de tallas junta.
    final byProduct = <String, List<SuggestionItem>>{};
    for (final i in group.items) {
      byProduct.putIfAbsent(i.productName, () => []).add(i);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: PerchaSpace.md),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(group.supplierName ?? 'Sin proveedor anterior', style: text.titleMedium),
          if (group.supplierId == null) Text('Nunca se compraron: eliges el proveedor al crear la orden.', style: text.bodySmall),
          const SizedBox(height: PerchaSpace.sm),
          for (final e in byProduct.entries) ...[
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
            for (final i in e.value) _ItemRow(item: i, qty: qtyOf(i), onChange: (q) => onChange(i.variantId, q)),
          ],
          const SizedBox(height: PerchaSpace.md),
          FilledButton.icon(
            onPressed: busy || units == 0 ? null : onCreate,
            icon: const Icon(Icons.post_add),
            label: Text('Crear orden · $units prenda${units == 1 ? '' : 's'} · ${formatCents(cost)}'),
          ),
        ]),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.qty, required this.onChange});
  final SuggestionItem item;
  final int qty;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final why = [
      'Stock ${item.stock}',
      if (item.incoming > 0) 'vienen ${item.incoming}',
      if (item.soldInWindow > 0) 'vende ${item.ratePerWeek.toStringAsFixed(1).replaceAll('.', ',')}/sem',
      if (item.minQuantity > 0) 'mínimo ${item.minQuantity}',
      if (item.coverageDays != null && item.stock > 0) 'alcanza ~${item.coverageDays} días',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(item.optionsLabel.isEmpty ? 'Única' : item.optionsLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Pill(item.urgencyLabel, warn: item.urgent),
            ]),
            Text(why, style: text.bodySmall),
          ]),
        ),
        IconButton(tooltip: 'Menos', icon: const Icon(Icons.remove_circle_outline), onPressed: qty > 0 ? () => onChange(qty - 1) : null),
        SizedBox(width: 32, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: PerchaType.title))),
        IconButton(tooltip: 'Más', icon: const Icon(Icons.add_circle_outline), onPressed: () => onChange(qty + 1)),
      ]),
    );
  }
}
