import '../../core/ids.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

class CreditInfo {
  const CreditInfo({required this.kind, required this.last4, required this.balanceCents, required this.status, this.expiresAt, this.customerName, this.code});
  final String kind; // refund · gift · courtesy
  final String last4;
  final int balanceCents;
  final String status; // active · used · expired
  final DateTime? expiresAt;
  final String? customerName;

  /// Solo al emitirse: el código completo se muestra UNA vez.
  final String? code;

  String get kindLabel => switch (kind) { 'gift' => 'Gift card', 'courtesy' => 'Vale de cortesía', _ => 'Saldo a favor' };

  factory CreditInfo.fromJson(Map<String, dynamic> j) => CreditInfo(
        kind: j['kind'] as String,
        last4: j['last4'] as String,
        balanceCents: (j['balanceCents'] as num).toInt(),
        status: j['status'] as String,
        expiresAt: j['expiresAt'] == null ? null : DateTime.parse(j['expiresAt'] as String).toLocal(),
        customerName: j['customerName'] as String?,
        code: j['code'] as String?,
      );
}

/// Acepta el código con o sin guiones/espacios y en minúsculas (como lo dicta el cliente).
String? normalizeCreditCode(String raw) {
  final clean = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp('^VALE'), '');
  if (!RegExp(r'^[2-9A-HJKMNP-Z]{12}$').hasMatch(clean)) return null;
  return 'VALE-${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8)}';
}

class CreditsApi {
  const CreditsApi(this._api);
  final ApiClient _api;

  Future<CreditInfo> lookup(String code) async => CreditInfo.fromJson(await _api.get('/store-credits/lookup', query: {'code': code}) as Map<String, dynamic>);

  Future<List<CreditInfo>> forCustomer(String customerId) async =>
      (await _api.get('/store-credits', query: {'customerId': customerId}) as List<dynamic>).cast<Map<String, dynamic>>().map(CreditInfo.fromJson).toList();

  Future<CreditInfo> sellGiftCard({required String branchId, required int amountCents, required String method, String? customerId}) async =>
      CreditInfo.fromJson(await _api.post('/gift-cards', idempotencyKey: newUuid(), body: {
        'branchId': branchId,
        'amountCents': amountCents,
        if (customerId != null) 'customerId': customerId,
        'payments': [
          {'method': method, 'amountCents': amountCents},
        ],
      },) as Map<String, dynamic>,);
}

final creditsApiProvider = Provider<CreditsApi>((ref) => CreditsApi(ref.watch(apiClientProvider)));
