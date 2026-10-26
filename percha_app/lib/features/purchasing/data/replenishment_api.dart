import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';

/// Variante (talla × color) que conviene reponer.
class SuggestionItem {
  const SuggestionItem({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.options,
    required this.stock,
    required this.minQuantity,
    required this.soldInWindow,
    required this.incoming,
    required this.quantity,
    required this.unitCostCents,
    required this.ratePerWeek,
    required this.urgency,
    this.coverageDays,
    this.supplierId,
  });

  final String variantId;
  final String productId;
  final String productName;
  final Map<String, String> options;
  final int stock;
  final int minQuantity;
  final int soldInWindow;
  final int incoming;

  /// Cantidad sugerida (editable en la pantalla).
  final int quantity;
  final int unitCostCents;
  final double ratePerWeek;

  /// out · critical · soon · planned
  final String urgency;
  final int? coverageDays;
  final String? supplierId;

  String get optionsLabel => options.values.join(' · ');

  String get urgencyLabel => switch (urgency) { 'out' => 'Agotada', 'critical' => 'Se agota pronto', 'soon' => 'Reponer este mes', _ => 'Planificada' };
  bool get urgent => urgency == 'out' || urgency == 'critical';

  factory SuggestionItem.fromJson(Map<String, dynamic> j) => SuggestionItem(
        variantId: j['variantId'] as String,
        productId: j['productId'] as String,
        productName: j['productName'] as String,
        options: (j['options'] as Map<String, dynamic>).cast<String, String>(),
        stock: j['stock'] as int,
        minQuantity: j['minQuantity'] as int,
        soldInWindow: j['soldInWindow'] as int,
        incoming: j['incoming'] as int,
        quantity: j['quantity'] as int,
        unitCostCents: j['unitCostCents'] as int,
        ratePerWeek: (j['ratePerWeek'] as num).toDouble(),
        urgency: j['urgency'] as String,
        coverageDays: j['coverageDays'] as int?,
        supplierId: j['supplierId'] as String?,
      );
}

class SupplierSuggestion {
  const SupplierSuggestion({required this.items, this.supplierId, this.supplierName});
  final String? supplierId;
  final String? supplierName;
  final List<SuggestionItem> items;

  factory SupplierSuggestion.fromJson(Map<String, dynamic> j) => SupplierSuggestion(
        supplierId: j['supplierId'] as String?,
        supplierName: j['supplierName'] as String?,
        items: (j['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(SuggestionItem.fromJson).toList(),
      );
}

typedef SuggestionParams = ({String branchId, int windowDays, int coverDays, int leadDays});

class ReplenishmentApi {
  const ReplenishmentApi(this._api);
  final ApiClient _api;

  Future<List<SupplierSuggestion>> suggestions(SuggestionParams p) async {
    final res = await _api.get('/purchasing/suggestions', query: {
      'branchId': p.branchId,
      'windowDays': p.windowDays,
      'coverDays': p.coverDays,
      'leadDays': p.leadDays,
    },) as Map<String, dynamic>;
    return (res['suppliers'] as List<dynamic>).cast<Map<String, dynamic>>().map(SupplierSuggestion.fromJson).toList();
  }
}

final replenishmentApiProvider = Provider<ReplenishmentApi>((ref) => ReplenishmentApi(ref.watch(apiClientProvider)));
final suggestionsProvider = FutureProvider.autoDispose.family<List<SupplierSuggestion>, SuggestionParams>((ref, p) => ref.watch(replenishmentApiProvider).suggestions(p));
