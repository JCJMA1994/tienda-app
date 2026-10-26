import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../onboarding/data/store_api.dart';
import '../data/catalog_api.dart';

/// Alta de producto: datos, valores por atributo (se crean todas las combinaciones)
/// y, opcionalmente, el stock inicial de cada combinación.
class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({super.key});

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _season = TextEditingController();
  String? _categoryId;
  final Map<String, Set<String>> _selected = {};
  final Map<String, TextEditingController> _qty = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _price, _cost, _season, ..._qty.values]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Combinaciones en el orden de los atributos (igual que la API arma el SKU).
  List<Map<String, String>> _combos(List<Attribute> attrs) {
    var acc = <Map<String, String>>[{}];
    for (final a in attrs) {
      final values = a.values.where((v) => _selected[a.name]?.contains(v) ?? false).toList();
      if (values.isEmpty) continue;
      acc = [for (final c in acc) for (final v in values) {...c, a.name: v}];
    }
    return acc;
  }

  String _key(Map<String, String> c) => c.values.join(' · ');

  TextEditingController _qtyFor(Map<String, String> c) => _qty.putIfAbsent(_key(c), TextEditingController.new);

  Future<void> _newCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Crear')),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (name == null || name.isEmpty) return;
    try {
      final c = await ref.read(catalogApiProvider).createCategory(name);
      ref.invalidate(categoriesProvider);
      setState(() => _categoryId = c.id);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _save(List<Attribute> attrs) async {
    if (_saving || !submitForm(_form)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final branch = await ref.read(currentBranchProvider.future);
      final combos = _combos(attrs);
      final stock = [
        for (final c in combos)
          if ((int.tryParse(_qtyFor(c).text) ?? 0) > 0) (options: c, quantity: int.parse(_qtyFor(c).text)),
      ];
      final product = await ref.read(catalogApiProvider).createProduct(
            name: _name.text.trim(),
            categoryId: _categoryId,
            season: _season.text.trim(),
            priceCents: parseCents(_price.text)!,
            costCents: parseCents(_cost.text.isEmpty ? '0' : _cost.text)!,
            matrix: {for (final e in _selected.entries) if (e.value.isNotEmpty) e.key: e.value.toList()},
            initialStock: (branchId: branch.id, items: stock),
          );
      if (mounted) context.pop(product.id);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attrs = ref.watch(attributesProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo producto')),
      body: attrs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
        data: (attributes) {
          final combos = _combos(attributes);
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              children: [
                if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: PerchaSpace.lg)],
                AppTextField(
                  controller: _name,
                  label: 'Nombre',
                  hint: 'Ej. Vestido midi',
                  validator: V.all([V.minLength(2, 'Ingresa el nombre'), V.maxLength(120)]),
                  maxLength: 120,
                ),
                const SizedBox(height: PerchaSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _categoryId,
                        decoration: const InputDecoration(labelText: 'Categoría'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Sin categoría')),
                          for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ),
                    IconButton(tooltip: 'Nueva categoría', icon: const Icon(Icons.add), onPressed: _newCategory),
                  ],
                ),
                const SizedBox(height: PerchaSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(controller: _price, label: 'Precio de venta', kind: FieldKind.money, validator: V.money(positive: true)),
                    ),
                    const SizedBox(width: PerchaSpace.md),
                    Expanded(
                      child: AppTextField(
                        controller: _cost,
                        label: 'Costo',
                        kind: FieldKind.money,
                        helper: 'Solo lo ven dueño y encargado',
                        validator: V.money(optional: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PerchaSpace.lg),
                AppTextField(controller: _season, label: 'Temporada (opcional)', hint: 'Otoño 2026', validator: V.maxLength(40), last: true),
                const SizedBox(height: PerchaSpace.xl),
                Text('Variantes', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  attributes.isEmpty
                      ? 'No hay atributos. Créalos en el onboarding o el producto tendrá una sola variante.'
                      : 'Elige los valores; se crean todas las combinaciones.',
                  style: text.bodySmall,
                ),
                for (final a in attributes) ...[
                  const SizedBox(height: PerchaSpace.md),
                  Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in a.values)
                        FilterChip(
                          label: Text(v),
                          selected: _selected[a.name]?.contains(v) ?? false,
                          onSelected: (on) => setState(() {
                            final set = _selected.putIfAbsent(a.name, () => {});
                            on ? set.add(v) : set.remove(v);
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: PerchaSpace.xl),
                Text(
                  combos.length == 1 && combos.first.isEmpty ? 'Stock inicial' : 'Stock inicial · ${combos.length} combinaciones',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('Opcional. También puedes cargarlo luego con un ajuste o una compra.', style: text.bodySmall),
                const SizedBox(height: PerchaSpace.sm),
                for (final c in combos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(c.isEmpty ? 'Única' : _key(c))),
                        SizedBox(
                          width: 96,
                          child: TextField(
                            controller: _qtyFor(c),
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
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: BusyButton(
            label: 'Crear producto',
            busy: _saving,
            onPressed: attrs.hasValue ? () => _save(attrs.value!) : null,
          ),
        ),
      ),
    );
  }
}
