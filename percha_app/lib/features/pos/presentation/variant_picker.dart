import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../offline/pos_snapshot.dart';
import '../data/pos_api.dart';
import '../data/pos_models.dart';

/// Elegir talla/color de un producto. Las combinaciones sin stock se ven, pero deshabilitadas:
/// el vendedor sabe al instante que "la M negra se agotó" sin preguntar.
Future<SellableVariant?> pickVariant(BuildContext context, {required String productId, required String branchId}) {
  return showModalBottomSheet<SellableVariant>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VariantPicker(productId: productId, branchId: branchId),
  );
}

final _productProvider = FutureProvider.autoDispose.family<ProductDetail, ({String id, String branchId})>(
  (ref, k) => withOfflineFallback(
    () => ref.watch(posApiProvider).product(k.id, k.branchId),
    () => ref.read(posSnapshotProvider(k.branchId)).valueOrNull?.product(k.id),
  ),
);

class _VariantPicker extends ConsumerWidget {
  const _VariantPicker({required this.productId, required this.branchId});
  final String productId;
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_productProvider((id: productId, branchId: branchId)));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: async.when(
          loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (p) {
            // Producto sin variantes (p. ej. una correa): se agrega directo.
            if (p.variants.length == 1 && p.variants.first.options.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context, p.variants.first));
              return const SizedBox(height: 80);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: PerchaSpace.lg),
                Wrap(
                  spacing: PerchaSpace.sm,
                  runSpacing: PerchaSpace.sm,
                  children: [
                    for (final v in p.variants)
                      _VariantButton(
                        variant: v,
                        onTap: v.sellable && (v.stock ?? 0) > 0 ? () => Navigator.pop(context, v) : null,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VariantButton extends StatelessWidget {
  const _VariantButton({required this.variant, this.onTap});
  final SellableVariant variant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stock = variant.stock ?? 0;
    final low = stock > 0 && stock <= 2;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '${variant.optionsLabel}, $stock en stock',
      child: Material(
        color: onTap == null ? PerchaColors.border : PerchaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PerchaRadius.field),
          side: BorderSide(color: PerchaColors.borderStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(PerchaRadius.field),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 104, minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(variant.optionsLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    stock == 0 ? 'Agotado' : '$stock en stock · ${formatCents(variant.priceCents)}',
                    style: TextStyle(fontSize: PerchaType.meta, color: low || stock == 0 ? PerchaColors.warn : PerchaColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
