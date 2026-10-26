import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../auth/application/session_controller.dart';
import '../application/checkout.dart';
import 'pos_models.dart';

class PosApi {
  const PosApi(this._api);
  final ApiClient _api;

  /// Escaneo: código de barras o SKU exacto. null si no existe.
  Future<SellableVariant?> lookup(String code, String branchId) async {
    try {
      final res = await _api.get('/variants/lookup', query: {'code': code, 'branchId': branchId});
      return SellableVariant.fromLookup(res as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<List<ProductSummary>> products({String? search, required String branchId}) async {
    final res = await _api.get('/products', query: {'search': search, 'branchId': branchId, 'active': 'true', 'pageSize': 60})
        as Map<String, dynamic>;
    return (res['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(ProductSummary.fromJson).toList();
  }

  Future<ProductDetail> product(String id, String branchId) async =>
      ProductDetail.fromJson(await _api.get('/products/$id') as Map<String, dynamic>, branchId: branchId);

  Future<CashSession?> currentCash(String branchId) async {
    try {
      return CashSession.fromJson(await _api.get('/cash-sessions/current', query: {'branchId': branchId}) as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<CashSession> openCash(String branchId, int openingCents) async => CashSession.fromJson(
        await _api.post('/cash-sessions', body: {'branchId': branchId, 'openingCents': openingCents}) as Map<String, dynamic>,
      );

  Future<Map<String, dynamic>> closeCash(String id, int countedCashCents) async =>
      await _api.post('/cash-sessions/$id/close', body: {'countedCashCents': countedCashCents}) as Map<String, dynamic>;

  /// Cuerpo de la venta (también lo guarda la cola sin conexión para enviarlo después).
  /// La API calcula precios, IGV y total; la app solo envía qué, cuánto y cómo se paga.
  static Map<String, Object?> saleBody({
    required String branchId,
    required List<({String variantId, int quantity})> items,
    required int discountCents,
    required PaymentMethod method,
    required int amountCents,
    int? cashReceivedCents,
    String? approverPin,
    Map<String, Object?>? document,
    String? customerId,
    ({String code, int amountCents})? credit,
  }) =>
      {
        'branchId': branchId,
        'items': [for (final i in items) {'variantId': i.variantId, 'quantity': i.quantity}],
        'discountCents': discountCents,
        // Con vale: primero el vale y el resto con el otro medio (regla en checkout.dart).
        'payments': [for (final p in splitPayments(totalCents: amountCents, method: method.api, credit: credit)) p.toJson()],
        if (cashReceivedCents != null) 'cashReceivedCents': cashReceivedCents,
        if (approverPin != null) 'approverPin': approverPin,
        if (document != null) 'document': document,
        if (customerId != null) 'customerId': customerId,
      };

  /// Registra la venta. La [idempotencyKey] hace que un reintento devuelva la MISMA venta.
  Future<SaleReceipt> postSale(Map<String, Object?> body, {required String idempotencyKey}) async =>
      SaleReceipt.fromJson(await _api.post('/sales', body: body, idempotencyKey: idempotencyKey) as Map<String, dynamic>);

  /// Total exacto que cobrará el servidor (con promociones vigentes y descuento manual).
  Future<int> quoteTotal({required String branchId, required List<({String variantId, int quantity})> items, required int discountCents}) async {
    final res = await _api.post('/sales/quote', body: {
      'branchId': branchId,
      'items': [for (final i in items) {'variantId': i.variantId, 'quantity': i.quantity}],
      'discountCents': discountCents,
    }) as Map<String, dynamic>;
    return res['totalCents'] as int;
  }

  /// Foto de variantes, precios y stock de la sucursal para vender sin conexión.
  Future<Map<String, dynamic>> snapshot(String branchId) async => await _api.get('/inventory/snapshot', query: {'branchId': branchId}) as Map<String, dynamic>;
}

final posApiProvider = Provider<PosApi>((ref) => PosApi(ref.watch(apiClientProvider)));
