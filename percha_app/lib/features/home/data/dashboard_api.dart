import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../onboarding/data/store_api.dart';

class LowStockItem {
  const LowStockItem({required this.productName, required this.options, required this.quantity});
  final String productName;
  final String options;
  final int quantity;
}

/// Mientras no existan los reportes (fase 7), el inicio usa lo que ya expone la API:
/// progreso del onboarding y stock bajo.
final lowStockProvider = FutureProvider.autoDispose<List<LowStockItem>>((ref) async {
  final me = ref.watch(meProvider);
  if (!me.can('inventory.read')) return const [];
  final branch = await ref.watch(currentBranchProvider.future);
  final res = await ref.watch(apiClientProvider).get('/inventory/stock', query: {'branchId': branch.id, 'lowOnly': 'true'})
      as List<dynamic>;
  return res
      .cast<Map<String, dynamic>>()
      .map((r) => LowStockItem(
            productName: r['productName'] as String,
            options: (r['options'] as Map<String, dynamic>).values.join(' · '),
            quantity: r['quantity'] as int,
          ),)
      .toList();
});
