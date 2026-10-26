import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

class CustomerSummary {
  const CustomerSummary({required this.id, required this.name, this.docType, this.docNumber, this.phone, this.whatsappOptIn = false});
  final String id;
  final String name;
  final String? docType;
  final String? docNumber;
  final String? phone;
  final bool whatsappOptIn;

  String get docLabel => docNumber == null ? '' : '${(docType ?? '').toUpperCase()} $docNumber';

  factory CustomerSummary.fromJson(Map<String, dynamic> j) => CustomerSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        docType: j['docType'] as String?,
        docNumber: j['docNumber'] as String?,
        phone: j['phone'] as String?,
        whatsappOptIn: j['whatsappOptIn'] as bool? ?? false,
      );
}

typedef CustomerSale = ({String id, int number, int totalCents, bool voided, DateTime at});

/// Ficha del cliente con estadísticas (modelo tipado).
class CustomerDetail {
  const CustomerDetail({
    required this.summary,
    required this.purchases,
    required this.spentCents,
    required this.topSizes,
    required this.recentSales,
    this.email,
    this.birthday,
    this.notes,
    this.lastPurchaseAt,
    this.creditBalanceCents = 0,
    this.openLayaways = 0,
  });

  final CustomerSummary summary;
  final String? email;
  final String? birthday; // MM-DD
  final String? notes;
  final int purchases;
  final int spentCents;
  final DateTime? lastPurchaseAt;
  final List<String> topSizes;
  final int creditBalanceCents;
  final int openLayaways;
  final List<CustomerSale> recentSales;

  factory CustomerDetail.fromJson(Map<String, dynamic> j) {
    final stats = j['stats'] as Map<String, dynamic>;
    int n(String k) => ((stats[k] as num?) ?? 0).toInt();
    return CustomerDetail(
      summary: CustomerSummary.fromJson(j),
      email: j['email'] as String?,
      birthday: j['birthday'] as String?,
      notes: j['notes'] as String?,
      purchases: n('purchases'),
      spentCents: n('spentCents'),
      lastPurchaseAt: stats['lastPurchaseAt'] == null ? null : DateTime.parse(stats['lastPurchaseAt'] as String).toLocal(),
      topSizes: ((stats['topSizes'] as List<dynamic>?) ?? const []).cast<String>(),
      creditBalanceCents: n('creditBalanceCents'),
      openLayaways: n('openLayaways'),
      recentSales: [
        for (final s in ((j['recentSales'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>())
          (id: s['id'] as String, number: s['number'] as int, totalCents: s['totalCents'] as int, voided: s['status'] == 'voided', at: DateTime.parse(s['createdAt'] as String).toLocal()),
      ],
    );
  }
}

class CustomersApi {
  const CustomersApi(this._api);
  final ApiClient _api;

  Future<List<CustomerSummary>> search(String? q) async =>
      (await _api.get('/customers', query: {'search': q}) as List<dynamic>).cast<Map<String, dynamic>>().map(CustomerSummary.fromJson).toList();

  Future<CustomerDetail> get(String id) async => CustomerDetail.fromJson(await _api.get('/customers/$id') as Map<String, dynamic>);
  Future<CustomerSummary> create(Map<String, Object?> body) async => CustomerSummary.fromJson(await _api.post('/customers', body: body) as Map<String, dynamic>);
  Future<void> update(String id, Map<String, Object?> body) => _api.patch('/customers/$id', body: body);
  Future<void> anonymize(String id) => _api.delete('/customers/$id');
}

final customersApiProvider = Provider<CustomersApi>((ref) => CustomersApi(ref.watch(apiClientProvider)));
final customerDetailProvider = FutureProvider.autoDispose.family<CustomerDetail, String>((ref, id) => ref.watch(customersApiProvider).get(id));
