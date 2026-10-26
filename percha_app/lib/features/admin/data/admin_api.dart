import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import '../../billing/data/billing_api.dart';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class PlatformMetrics {
  const PlatformMetrics(this.raw);
  final Map<String, dynamic> raw;
  int get tenants => _i(raw['tenants']);
  int get trialing => _i(raw['trialing']);
  int get active => _i(raw['active']);
  int get pastDue => _i(raw['past_due']);
  int get suspended => _i(raw['suspended']);
  int get canceled => _i(raw['canceled']);
  int get mrrCents => _i(raw['mrr_cents']);
  int get trialsEnding7d => _i(raw['trials_ending_7d']);
}

class TenantRow {
  const TenantRow(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id'] as String;
  String get name => raw['name'] as String;
  bool get blocked => raw['tenant_status'] == 'suspended';
  String get status => (raw['subscription_status'] as String?) ?? 'sin suscripción';
  String? get planCode => raw['plan_code'] as String?;
  int get products => _i(raw['products']);
  int get members => _i(raw['members']);
  int get owedCents => _i(raw['owed_cents']);
  DateTime? get lastSaleAt => raw['last_sale_at'] == null ? null : DateTime.parse(raw['last_sale_at'] as String).toLocal();
  DateTime? get periodEnd => raw['current_period_end'] == null ? null : DateTime.parse(raw['current_period_end'] as String).toLocal();
}

class AdminApi {
  const AdminApi(this._api);
  final ApiClient _api;

  Future<PlatformMetrics> metrics() async => PlatformMetrics(await _api.get('/admin/metrics') as Map<String, dynamic>);

  Future<List<TenantRow>> tenants() async =>
      (await _api.get('/admin/tenants') as List<dynamic>).cast<Map<String, dynamic>>().map(TenantRow.new).toList();

  Future<List<Invoice>> invoices(String tenantId) async =>
      (await _api.get('/admin/tenants/$tenantId/invoices') as List<dynamic>).cast<Map<String, dynamic>>().map(Invoice.fromJson).toList();

  Future<void> update(String tenantId, {String? status, String? planCode, int? extendDays}) => _api.patch('/admin/tenants/$tenantId', body: {
        if (status != null) 'status': status,
        if (planCode != null) 'planCode': planCode,
        if (extendDays != null) 'extendDays': extendDays,
      });

  Future<void> markPaid(String invoiceId, {required String method, required String reference}) =>
      _api.post('/admin/invoices/$invoiceId/mark-paid', body: {'method': method, 'reference': reference});

  Future<Map<String, dynamic>> runBilling() async => await _api.post('/admin/billing/run') as Map<String, dynamic>;
}

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi(ref.watch(apiClientProvider)));
final metricsProvider = FutureProvider.autoDispose<PlatformMetrics>((ref) => ref.watch(adminApiProvider).metrics());
final tenantsProvider = FutureProvider.autoDispose<List<TenantRow>>((ref) => ref.watch(adminApiProvider).tenants());
final tenantInvoicesProvider = FutureProvider.autoDispose.family<List<Invoice>, String>((ref, id) => ref.watch(adminApiProvider).invoices(id));
