import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

class CountItem {
  const CountItem({required this.variantId, required this.productName, required this.optionsLabel, required this.sku, required this.counted, required this.stockAtFirstScan});
  final String variantId;
  final String productName;
  final String optionsLabel;
  final String sku;
  final int counted;

  /// Stock del sistema cuando se contó por primera vez (lo vendido después no es faltante).
  final int stockAtFirstScan;
  int get difference => counted - stockAtFirstScan;

  factory CountItem.fromJson(Map<String, dynamic> j) => CountItem(
        variantId: j['variantId'] as String,
        productName: j['productName'] as String,
        optionsLabel: (j['options'] as Map<String, dynamic>).values.join(' · '),
        sku: j['sku'] as String,
        counted: j['counted'] as int,
        stockAtFirstScan: j['stockAtFirstScan'] as int,
      );
}

class StockCount {
  const StockCount({required this.id, required this.number, required this.status, required this.createdAt, this.note, this.items = const [], this.missing = 0, this.extra = 0, this.counted = 0});
  final String id;
  final int number;
  final String status; // open · applied · cancelled
  final DateTime createdAt;
  final String? note;
  final List<CountItem> items;
  final int missing;
  final int extra;
  final int counted;

  bool get open => status == 'open';
  String get statusLabel => switch (status) { 'open' => 'En curso', 'applied' => 'Aplicado', _ => 'Cancelado' };

  factory StockCount.fromJson(Map<String, dynamic> j) {
    final t = j['totals'] as Map<String, dynamic>?;
    return StockCount(
      id: j['id'] as String,
      number: j['number'] as int,
      status: j['status'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      note: j['note'] as String?,
      items: ((j['items'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(CountItem.fromJson).toList(),
      missing: (t?['missing'] as int?) ?? 0,
      extra: (t?['extra'] as int?) ?? 0,
      counted: (t?['counted'] as int?) ?? 0,
    );
  }
}

class CountsApi {
  const CountsApi(this._api);
  final ApiClient _api;

  Future<List<StockCount>> list(String branchId) async =>
      (await _api.get('/stock-counts', query: {'branchId': branchId}) as List<dynamic>).cast<Map<String, dynamic>>().map(StockCount.fromJson).toList();
  Future<StockCount> start(String branchId, {String? note}) async =>
      StockCount.fromJson(await _api.post('/stock-counts', body: {'branchId': branchId, if (note != null && note.isNotEmpty) 'note': note}) as Map<String, dynamic>);
  Future<StockCount> get(String id) async => StockCount.fromJson(await _api.get('/stock-counts/$id') as Map<String, dynamic>);
  Future<StockCount> add(String id, String variantId) async =>
      StockCount.fromJson(await _api.post('/stock-counts/$id/items', body: {'variantId': variantId, 'mode': 'add', 'quantity': 1}) as Map<String, dynamic>);
  Future<StockCount> set(String id, String variantId, int quantity) async =>
      StockCount.fromJson(await _api.post('/stock-counts/$id/items', body: {'variantId': variantId, 'mode': 'set', 'quantity': quantity}) as Map<String, dynamic>);
  Future<StockCount> remove(String id, String variantId) async => StockCount.fromJson(await _api.delete('/stock-counts/$id/items/$variantId') as Map<String, dynamic>);
  Future<Map<String, dynamic>> apply(String id, {required bool zeroUncounted}) async =>
      await _api.post('/stock-counts/$id/apply', body: {'zeroUncounted': zeroUncounted}) as Map<String, dynamic>;
  Future<void> cancel(String id) => _api.post('/stock-counts/$id/cancel');
}

final countsApiProvider = Provider<CountsApi>((ref) => CountsApi(ref.watch(apiClientProvider)));
final countsProvider = FutureProvider.autoDispose.family<List<StockCount>, String>((ref, branchId) => ref.watch(countsApiProvider).list(branchId));
