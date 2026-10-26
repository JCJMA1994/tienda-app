import '../../../core/ids.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import 'pos_models.dart';
import 'sales_models.dart';

export 'sales_models.dart';

class SalesApi {
  const SalesApi(this._api);
  final ApiClient _api;

  Future<List<SaleSummary>> list({required String branchId, int? number, int limit = 50}) async =>
      (await _api.get('/sales', query: {'branchId': branchId, 'number': number, 'limit': limit}) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(SaleSummary.fromJson)
          .toList();

  Future<SaleDetail> get(String id) async => SaleDetail.fromJson(await _api.get('/sales/$id') as Map<String, dynamic>);

  Future<void> voidSale(String id, {required String reason, String? approverPin}) =>
      _api.post('/sales/$id/void', body: {'reason': reason, if (approverPin != null) 'approverPin': approverPin});

  Future<ReturnResult> createReturn({
    required String saleId,
    required String branchId,
    required List<({String saleItemId, int quantity})> items,
    required List<({String variantId, int quantity})> replacements,
    PaymentMethod? method,
    int amountCents = 0,
    String? creditCode,
    required String reason,
  }) async {
    final res = await _api.post('/sales/$saleId/returns', idempotencyKey: newUuid(), body: {
      'branchId': branchId,
      'items': [for (final i in items) {'saleItemId': i.saleItemId, 'quantity': i.quantity}],
      'replacements': [for (final r in replacements) {'variantId': r.variantId, 'quantity': r.quantity}],
      'payments': [
        if (method != null && amountCents > 0) {'method': method.api, 'amountCents': amountCents, if (creditCode != null) 'creditCode': creditCode},
      ],
      'reason': reason,
    },) as Map<String, dynamic>;
    final credit = res['credit'] as Map<String, dynamic>?;
    return ReturnResult(
      number: res['number'] as int,
      kind: res['kind'] as String,
      differenceCents: res['differenceCents'] as int,
      creditCode: credit?['code'] as String?,
      creditExpiresAt: credit?['expiresAt'] == null ? null : DateTime.parse(credit!['expiresAt'] as String).toLocal(),
    );
  }
}

final salesApiProvider = Provider<SalesApi>((ref) => SalesApi(ref.watch(apiClientProvider)));

final saleDetailProvider = FutureProvider.autoDispose.family<SaleDetail, String>((ref, id) => ref.watch(salesApiProvider).get(id));

