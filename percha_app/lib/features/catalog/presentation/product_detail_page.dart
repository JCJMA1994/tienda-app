import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/dialogs.dart';
import '../../../core/forms/validators.dart';
import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/data/store_api.dart';
import '../../printing/print_actions.dart';
import '../../storefront/storefront_api.dart';
import '../data/catalog_api.dart';
import 'product_gallery.dart';

part 'product_stock_matrix.dart';
part 'product_variant_panel.dart';
part 'product_matrix_picker.dart';

final _movementsProvider = FutureProvider.autoDispose.family<List<Movement>, ({String variantId, String branchId})>(
  (ref, k) => ref.watch(catalogApiProvider).movements(k.variantId, k.branchId),
);

class ProductDetailPage extends ConsumerStatefulWidget {
  const ProductDetailPage({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productDetailProvider(widget.productId));
    final branch = ref.watch(currentBranchProvider).valueOrNull;
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (product.hasValue && branch != null)
            IconButton(
              tooltip: 'Imprimir etiquetas',
              icon: const Icon(Icons.local_offer_outlined),
              onPressed: () => printLabelsFor(context, ref, product.value!, branch.id),
            ),
          if (me.can('catalog.write') && product.hasValue)
            IconButton(
              tooltip: 'Agregar combinaciones',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () => _addCombinations(product.value!),
            ),
        ],
      ),
      body: switch ((product, branch)) {
        (AsyncError(:final error), _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(error))),
        (AsyncData(value: final p), final Branch b) => _body(p, b, me.can('inventory.adjust')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(Product p, Branch branch, bool canAdjust) {
    final text = Theme.of(context).textTheme;
    final selected = p.variants.where((v) => v.id == _selectedId).firstOrNull ?? p.variants.firstOrNull;
    final total = p.variants.fold<int>(0, (a, v) => a + v.stockIn(branch.id).quantity);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(productDetailProvider(p.id)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          ProductGallery(product: p, canEdit: ref.watch(meProvider).can('catalog.write')),
          if (ref.watch(meProvider).can('catalog.write'))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.storefront_outlined),
              title: const Text('Publicar en el catálogo en línea'),
              subtitle: Text(p.images.isEmpty ? 'Agrega al menos una foto antes de publicar' : 'Los clientes lo verán con su disponibilidad'),
              value: p.published,
              onChanged: (v) async {
                await ref.read(storefrontApiProvider).setPublished(p.id, v);
                ref.invalidate(productDetailProvider(p.id));
              },
            ),
          const SizedBox(height: PerchaSpace.lg),
          Text(p.name, style: text.headlineSmall),
          const SizedBox(height: 4),
          Text([p.skuBase, if (p.season != null) p.season!].join(' · '), style: text.bodySmall),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(formatCents(p.priceCents), style: text.titleMedium),
              if (p.costCents != null) ...[
                const SizedBox(width: PerchaSpace.md),
                Text('Costo ${formatCents(p.costCents!)}', style: text.bodySmall),
              ],
            ],
          ),
          const SizedBox(height: PerchaSpace.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Stock por variante', style: text.titleMedium),
                      Text('Total: $total unid.', style: text.bodySmall),
                    ],
                  ),
                  const SizedBox(height: PerchaSpace.md),
                  _StockMatrix(
                    product: p,
                    branchId: branch.id,
                    selectedId: selected?.id,
                    onSelect: (v) => setState(() => _selectedId = v.id),
                  ),
                  const SizedBox(height: PerchaSpace.sm),
                  const _Legend(),
                ],
              ),
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: PerchaSpace.lg),
            _VariantPanel(variant: selected, branchId: branch.id, canAdjust: canAdjust, onChanged: () => ref.invalidate(productDetailProvider(p.id))),
            const SizedBox(height: PerchaSpace.lg),
            Text('Movimientos recientes', style: text.titleMedium),
            const SizedBox(height: PerchaSpace.sm),
            _Movements(variantId: selected.id, branchId: branch.id),
          ],
        ],
      ),
    );
  }

  Future<void> _addCombinations(Product p) async {
    final attrs = await ref.read(attributesProvider.future);
    if (!mounted) return;
    final matrix = await showModalBottomSheet<Map<String, List<String>>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MatrixPicker(
        attributes: attrs.where((a) => p.attributes.any((pa) => pa.name == a.name)).toList(),
        initial: {for (final a in p.attributes) a.name: a.values.toSet()},
      ),
    );
    if (matrix == null || !mounted) return;
    try {
      await ref.read(catalogApiProvider).addVariants(p.id, matrix);
      ref.invalidate(productDetailProvider(p.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }
}

