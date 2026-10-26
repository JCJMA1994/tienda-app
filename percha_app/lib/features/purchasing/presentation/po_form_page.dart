import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/forms/dialogs.dart';
import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../catalog/data/catalog_api.dart';
import '../../onboarding/data/store_api.dart';
import '../application/drafts.dart';
import '../data/purchasing_api.dart';
import 'suppliers_sheet.dart';

/// Crear una orden nueva o editar un borrador (`orderId`).
class PoFormPage extends ConsumerStatefulWidget {
  const PoFormPage({super.key, this.orderId});
  final String? orderId;

  @override
  ConsumerState<PoFormPage> createState() => _PoFormPageState();
}

class _PoFormPageState extends ConsumerState<PoFormPage> {
  PoDraft _draft = const PoDraft();
  String? _supplierId;
  DateTime? _expectedAt;
  final _notes = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.orderId != null) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final o = await ref.read(purchasingApiProvider).order(widget.orderId!);
      setState(() {
        _draft = PoDraft.fromOrder(o);
        _supplierId = o.supplierId;
        _expectedAt = o.expectedAt;
        _notes.text = o.notes ?? '';
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addProducts() async {
    final lines = await showModalBottomSheet<List<PoDraftLine>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ProductQuantitiesSheet(),
    );
    if (lines != null) setState(() => _draft = _draft.merge(lines));
  }

  Future<void> _save({required bool send}) async {
    if (_supplierId == null) return setState(() => _error = 'Elige un proveedor');
    if (_draft.isEmpty) return setState(() => _error = 'Agrega al menos una prenda');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(purchasingApiProvider);
      final PurchaseOrder order;
      if (widget.orderId == null) {
        final branch = await ref.read(currentBranchProvider.future);
        order = await api.create(
          supplierId: _supplierId!,
          branchId: branch.id,
          expectedAt: _expectedAt,
          notes: _notes.text.trim(),
          items: _draft.toItems(),
        );
      } else {
        order = await api.update(widget.orderId!, supplierId: _supplierId, expectedAt: _expectedAt, notes: _notes.text.trim(), items: _draft.toItems());
      }
      if (send) await api.confirm(order.id);
      ref.invalidate(poDetailProvider(order.id));
      if (mounted) context.pop(order.id);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[];
    final text = Theme.of(context).textTheme;
    final date = DateFormat("d 'de' MMMM", 'es');

    return Scaffold(
      appBar: AppBar(title: Text(widget.orderId == null ? 'Nueva orden de compra' : 'Editar borrador')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
              children: [
                if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: PerchaSpace.lg)],
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: suppliers.any((s) => s.id == _supplierId) ? _supplierId : null,
                        decoration: const InputDecoration(labelText: 'Proveedor'),
                        items: [for (final s in suppliers.where((s) => s.active)) DropdownMenuItem(value: s.id, child: Text(s.name))],
                        onChanged: (v) => setState(() => _supplierId = v),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Nuevo proveedor',
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final s = await editSupplier(context, ref);
                        if (s != null) setState(() => _supplierId = s.id);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: PerchaSpace.md),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_expectedAt == null ? 'Fecha estimada de llegada (opcional)' : 'Llega el ${date.format(_expectedAt!)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: _expectedAt ?? now.add(const Duration(days: 7)),
                    );
                    if (d != null) setState(() => _expectedAt = d);
                  },
                ),
                const SizedBox(height: PerchaSpace.md),
                TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas (opcional)'), maxLines: 2),
                const SizedBox(height: PerchaSpace.xl),
                Row(
                  children: [
                    Expanded(child: Text('Prendas', style: text.titleMedium)),
                    TextButton.icon(onPressed: _addProducts, icon: const Icon(Icons.add), label: const Text('Agregar')),
                  ],
                ),
                if (_draft.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Agrega productos y cantidades')))
                else
                  Card(
                    child: Column(
                      children: [
                        for (final l in _draft.lines)
                          _DraftLineTile(
                            line: l,
                            onQuantity: (q) => setState(() => _draft = _draft.update(l.variantId, quantity: q)),
                            onCost: (c) => setState(() => _draft = _draft.update(l.variantId, unitCostCents: c)),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: PerchaSpace.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('${_draft.units} unidades', style: text.bodySmall), Text(formatCents(_draft.totalCents), style: text.titleLarge)],
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: _saving ? null : () => _save(send: false), child: const Text('Guardar borrador')),
              ),
              const SizedBox(width: PerchaSpace.md),
              Expanded(child: BusyButton(label: 'Confirmar pedido', busy: _saving, onPressed: () => _save(send: true))),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftLineTile extends StatelessWidget {
  const _DraftLineTile({required this.line, required this.onQuantity, required this.onCost});
  final PoDraftLine line;
  final ValueChanged<int> onQuantity;
  final ValueChanged<int> onCost;

  Future<void> _editCost(BuildContext context) async {
    final v = await promptMoney(context, title: 'Costo unitario', label: 'Costo por unidad', initialCents: line.unitCostCents, confirm: 'Guardar');
    if (v != null) onCost(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(line.label, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: InkWell(
        onTap: () => _editCost(context),
        child: Text('${formatCents(line.unitCostCents)} c/u · editar', style: TextStyle(color: PerchaColors.accentInk)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(tooltip: 'Menos', icon: const Icon(Icons.remove), onPressed: () => onQuantity(line.quantity - 1)),
          Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(tooltip: 'Más', icon: const Icon(Icons.add), onPressed: () => onQuantity(line.quantity + 1)),
        ],
      ),
    );
  }
}

/// Buscar un producto y escribir cuántas unidades pedir de cada combinación.
/// A diferencia del POS, aquí se muestran también las variantes agotadas (son las que más se piden).
class _ProductQuantitiesSheet extends ConsumerStatefulWidget {
  const _ProductQuantitiesSheet();

  @override
  ConsumerState<_ProductQuantitiesSheet> createState() => _ProductQuantitiesSheetState();
}

class _ProductQuantitiesSheetState extends ConsumerState<_ProductQuantitiesSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ProductListItem> _results = const [];
  Product? _product;
  final Map<String, TextEditingController> _qty = {};
  final _cost = TextEditingController();

  @override
  void initState() {
    super.initState();
    _find('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _cost.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _find(String q) async {
    final branch = await ref.read(currentBranchProvider.future);
    final page = await ref.read(catalogApiProvider).products(search: q.trim().isEmpty ? null : q.trim(), branchId: branch.id);
    if (mounted) setState(() => _results = page.items);
  }

  Future<void> _open(String id) async {
    final p = await ref.read(catalogApiProvider).product(id);
    if (!mounted) return;
    final cost = p.costCents ?? p.variants.firstOrNull?.avgCostCents ?? 0;
    _cost.text = (cost / 100).toStringAsFixed(2);
    setState(() => _product = p);
  }

  void _done() {
    final p = _product!;
    final cost = parseCents(_cost.text) ?? 0;
    Navigator.pop(context, [
      for (final v in p.variants)
        if ((int.tryParse(_qty[v.id]?.text ?? '') ?? 0) > 0)
          PoDraftLine(
            variantId: v.id,
            label: [p.name, if (v.options.isNotEmpty) v.options.values.join(' · ')].join(' · '),
            quantity: int.parse(_qty[v.id]!.text),
            unitCostCents: cost,
          ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    final branchId = ref.watch(currentBranchProvider).valueOrNull?.id;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
          child: p == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Buscar producto', prefixIcon: Icon(Icons.search)),
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 300), () => _find(v));
                      },
                    ),
                    const SizedBox(height: PerchaSpace.md),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final r in _results)
                            ListTile(
                              title: Text(r.name),
                              subtitle: Text('${r.variantCount} variantes · ${r.totalStock} en stock'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _open(r.id),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(tooltip: 'Otro producto', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _product = null)),
                        Expanded(child: Text(p.name, style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    TextField(
                      controller: _cost,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Costo unitario', prefixText: 'S/ ', helperText: 'Se aplica a todas las combinaciones; luego se ajusta por línea'),
                    ),
                    const SizedBox(height: PerchaSpace.md),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final v in p.variants)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(v.options.isEmpty ? 'Única' : v.options.values.join(' · '), style: const TextStyle(fontWeight: FontWeight.w500)),
                                        if (branchId != null)
                                          Text(
                                            'Hay ${v.stockIn(branchId).quantity}',
                                            style: TextStyle(fontSize: PerchaType.meta, color: v.stockIn(branchId).quantity <= 0 ? PerchaColors.warn : PerchaColors.muted),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 96,
                                    child: TextField(
                                      controller: _qty.putIfAbsent(v.id, TextEditingController.new),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(hintText: '0', isDense: true, suffixText: 'u.'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    FilledButton(onPressed: _done, child: const Text('Agregar a la orden')),
                  ],
                ),
        ),
      ),
    );
  }
}
