import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/forms/app_form.dart';
import '../../core/forms/validators.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/action_runner.dart';
import '../../core/widgets/percha_widgets.dart';
import '../auth/application/session_controller.dart';
import '../catalog/data/catalog_api.dart';
import '../onboarding/data/store_api.dart';
import 'promotions_api.dart';

/// Promociones automáticas: se aplican solas en el POS y se muestran en el catálogo en línea.
class PromotionsPage extends ConsumerWidget {
  const PromotionsPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [PromotionRow? row]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PromotionFormPage(existing: row)));
    if (saved == true) ref.invalidate(promotionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('d MMM', 'es');
    final canEdit = ref.watch(meProvider).can('catalog.write');
    return Scaffold(
      appBar: AppBar(title: const Text('Promociones')),
      floatingActionButton: canEdit ? FloatingActionButton.extended(onPressed: () => _edit(context, ref), icon: const Icon(Icons.local_offer_outlined), label: const Text('Nueva')) : null,
      body: ref.watch(promotionsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (list) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
              children: [
                Text('Se aplican solas al cobrar (en el POS y sin conexión) y se ven en el catálogo en línea. Una prenda recibe una sola promoción: la que más le ahorra al cliente.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: PerchaSpace.md),
                if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('Aún no hay promociones. Crea un 2x1 o una liquidación de temporada.', textAlign: TextAlign.center)),
                for (final r in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: PerchaSpace.sm),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: PerchaColors.accentSoft, child: Text(r.promo.label, style: TextStyle(color: PerchaColors.accentInk, fontWeight: FontWeight.w700, fontSize: PerchaType.meta))),
                      title: Text(r.promo.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        switch (r.promo.scope) { 'categories' => '${r.promo.categoryIds.length} categoría(s)', 'products' => '${r.promo.productIds.length} producto(s)', _ => 'Todo el catálogo' },
                        'desde ${date.format(r.startsAt)}${r.endsAt == null ? '' : ' hasta ${date.format(r.endsAt!)}'}',
                      ].join(' · ')),
                      trailing: Pill(r.status, warn: r.status != 'Vigente'),
                      onTap: canEdit ? () => _edit(context, ref, r) : null,
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}

class PromotionFormPage extends ConsumerStatefulWidget {
  const PromotionFormPage({super.key, this.existing});
  final PromotionRow? existing;

  @override
  ConsumerState<PromotionFormPage> createState() => _PromotionFormPageState();
}

class _PromotionFormPageState extends ConsumerState<PromotionFormPage> with ActionRunner {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.promo.name ?? '');
  late final _percent = TextEditingController(text: widget.existing?.promo.percentBp == null ? '20' : '${widget.existing!.promo.percentBp! ~/ 100}');
  late String _kind = widget.existing?.promo.kind ?? 'percent';
  late int _buy = widget.existing?.promo.buyQty ?? 2;
  late int _pay = widget.existing?.promo.payQty ?? 1;
  late String _scope = widget.existing?.promo.scope ?? 'all';
  late final Set<String> _categories = {...?widget.existing?.promo.categoryIds};
  late final Map<String, String> _products = {for (final id in widget.existing?.promo.productIds ?? const <String>[]) id: 'Cargando…'};
  late DateTime _start = widget.existing?.startsAt ?? DateTime.now();
  late DateTime? _end = widget.existing?.endsAt;
  late bool _active = widget.existing?.active ?? true;

  @override
  void initState() {
    super.initState();
    // Nombres de los productos ya elegidos (la promoción guarda solo sus ids).
    for (final id in _products.keys.toList()) {
      ref.read(catalogApiProvider).product(id).then((p) {
        if (mounted) setState(() => _products[id] = p.name);
      }).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!submitForm(_form)) return;
    if (_scope == 'categories' && _categories.isEmpty) return setState(() => error = 'Elige al menos una categoría');
    if (_scope == 'products' && _products.isEmpty) return setState(() => error = 'Elige al menos un producto');
    final ok = await runAction(() async {
      await ref.read(promotionsApiProvider).save(id: widget.existing?.promo.id, body: {
        'name': _name.text.trim(),
        'kind': _kind,
        if (_kind == 'percent') 'percentBp': int.parse(_percent.text) * 100,
        if (_kind == 'buy_x_pay_y') ...{'buyQty': _buy, 'payQty': _pay},
        'scope': _scope,
        'categoryIds': _categories.toList(),
        'productIds': _products.keys.toList(),
        'startsAt': _start.toUtc().toIso8601String(),
        'endsAt': _end?.toUtc().toIso8601String(),
        'active': _active,
      });
      return true;
    });
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(context: context, initialDate: initial, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 730)));

  Future<void> _addProduct() async {
    final branch = await ref.read(currentBranchProvider.future);
    if (!mounted) return;
    final picked = await showModalBottomSheet<ProductListItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPicker(branchId: branch.id),
    );
    if (picked != null) setState(() => _products[picked.id] = picked.name);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final date = DateFormat("d 'de' MMMM", 'es');
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nueva promoción' : 'Editar promoción')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          children: [
            if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
            AppTextField(controller: _name, label: 'Nombre', hint: 'Liquidación de verano', validator: V.all([V.minLength(2, 'Ingresa un nombre'), V.maxLength(60)])),
            const SizedBox(height: PerchaSpace.lg),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'percent', label: Text('Porcentaje')), ButtonSegment(value: 'buy_x_pay_y', label: Text('Lleva X, paga Y'))],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: PerchaSpace.md),
            if (_kind == 'percent')
              AppTextField(
                controller: _percent,
                label: 'Descuento (%)',
                kind: FieldKind.integer,
                maxLength: 2,
                validator: V.intRange(min: 1, max: 90),
              )
            else
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _buy,
                    decoration: const InputDecoration(labelText: 'Lleva'),
                    items: [for (var i = 2; i <= 6; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setState(() {
                      _buy = v!;
                      if (_pay >= _buy) _pay = _buy - 1;
                    }),
                  ),
                ),
                const SizedBox(width: PerchaSpace.md),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _pay,
                    decoration: const InputDecoration(labelText: 'Paga'),
                    items: [for (var i = 1; i < _buy; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setState(() => _pay = v!),
                  ),
                ),
              ]),
            if (_kind == 'buy_x_pay_y') Padding(padding: const EdgeInsets.only(top: 6), child: Text('Salen gratis las más baratas de cada grupo de $_buy (pueden ser prendas distintas).', style: text.bodySmall)),
            const SizedBox(height: PerchaSpace.lg),
            Text('¿A qué se aplica?', style: text.titleMedium),
            const SizedBox(height: PerchaSpace.sm),
            Wrap(spacing: 8, children: [
              for (final (v, l) in const [('all', 'Todo'), ('categories', 'Categorías'), ('products', 'Productos')]) ChoiceChip(label: Text(l), selected: _scope == v, onSelected: (_) => setState(() => _scope = v)),
            ]),
            const SizedBox(height: PerchaSpace.sm),
            if (_scope == 'categories')
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final c in categories)
                  FilterChip(label: Text(c.name), selected: _categories.contains(c.id), onSelected: (v) => setState(() => v ? _categories.add(c.id) : _categories.remove(c.id))),
                if (categories.isEmpty) Text('Aún no hay categorías: créalas desde Productos.', style: text.bodySmall),
              ]),
            if (_scope == 'products') ...[
              for (final e in _products.entries)
                ListTile(contentPadding: EdgeInsets.zero, title: Text(e.value), trailing: IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => setState(() => _products.remove(e.key)))),
              OutlinedButton.icon(onPressed: _addProduct, icon: const Icon(Icons.add), label: const Text('Agregar producto')),
            ],
            const SizedBox(height: PerchaSpace.lg),
            Text('Vigencia', style: text.titleMedium),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text('Desde el ${date.format(_start)}'),
              onTap: () async {
                final d = await _pickDate(_start);
                if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(_end == null ? 'Sin fecha de fin' : 'Hasta el ${date.format(_end!)} (inclusive)'),
              trailing: _end == null ? null : IconButton(tooltip: 'Quitar fecha de fin', icon: const Icon(Icons.close), onPressed: () => setState(() => _end = null)),
              onTap: () async {
                final d = await _pickDate(_end ?? _start.add(const Duration(days: 7)));
                // "Hasta el día X inclusive": termina al empezar el día siguiente.
                if (d != null) setState(() => _end = DateTime(d.year, d.month, d.day + 1));
              },
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Activa'), subtitle: const Text('Desactívala para pausarla sin borrarla')),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: BusyButton(label: 'Guardar', busy: busy, onPressed: _save))),
    );
  }
}

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.branchId});
  final String branchId;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  String _q = '';
  Future<ProductPage>? _future;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  void _search(String q) => setState(() {
        _q = q;
        _future = ref.read(catalogApiProvider).products(search: q.isEmpty ? null : q, branchId: widget.branchId);
      });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar producto'), onSubmitted: _search, onChanged: (v) => v.isEmpty && _q.isNotEmpty ? _search('') : null),
        ),
        Expanded(
          child: FutureBuilder<ProductPage>(
            future: _future,
            builder: (_, snap) => !snap.hasData
                ? const Center(child: CircularProgressIndicator())
                : ListView(children: [for (final p in snap.data!.items) ListTile(title: Text(p.name), subtitle: Text(p.skuBase), onTap: () => Navigator.pop(context, p))]),
          ),
        ),
      ]),
    );
  }
}
