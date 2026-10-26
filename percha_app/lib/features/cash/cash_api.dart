import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

/// Reporte de una caja (cierre o corte parcial) para mostrar e imprimir.
class CashReport {
  const CashReport({
    required this.id,
    required this.branchName,
    required this.status,
    required this.openedAt,
    required this.openingCents,
    required this.byMethod,
    required this.salesCount,
    required this.salesCents,
    required this.voidedCount,
    required this.voidedCents,
    required this.returnsCount,
    required this.returnsDifferenceCents,
    required this.layawayCount,
    required this.layawayCents,
    required this.expectedCashCents,
    this.openedBy,
    this.closedAt,
    this.closedBy,
    this.countedCashCents,
    this.differenceCents,
  });

  final String id;
  final String branchName;
  final String status;
  final DateTime openedAt;
  final String? openedBy;
  final DateTime? closedAt;
  final String? closedBy;
  final int openingCents;
  final Map<String, int> byMethod;
  final int salesCount;
  final int salesCents;
  final int voidedCount;
  final int voidedCents;
  final int returnsCount;
  final int returnsDifferenceCents;
  final int layawayCount;
  final int layawayCents;
  final int expectedCashCents;
  final int? countedCashCents;
  final int? differenceCents;

  bool get closed => status == 'closed';

  factory CashReport.fromJson(Map<String, dynamic> j) {
    final sales = j['sales'] as Map<String, dynamic>;
    final ret = j['returns'] as Map<String, dynamic>;
    final lay = j['layawayPayments'] as Map<String, dynamic>;
    DateTime? date(String k) => j[k] == null ? null : DateTime.parse(j[k] as String).toLocal();
    return CashReport(
      id: j['id'] as String,
      branchName: j['branchName'] as String? ?? '',
      status: j['status'] as String,
      openedAt: date('openedAt')!,
      openedBy: j['openedBy'] as String?,
      closedAt: date('closedAt'),
      closedBy: j['closedBy'] as String?,
      openingCents: j['openingCents'] as int,
      byMethod: {for (final m in (j['byMethod'] as List<dynamic>).cast<Map<String, dynamic>>()) m['method'] as String: m['totalCents'] as int},
      salesCount: sales['count'] as int,
      salesCents: sales['totalCents'] as int,
      voidedCount: sales['voidedCount'] as int,
      voidedCents: sales['voidedCents'] as int,
      returnsCount: ret['count'] as int,
      returnsDifferenceCents: ret['differenceCents'] as int,
      layawayCount: lay['count'] as int,
      layawayCents: lay['totalCents'] as int,
      expectedCashCents: j['expectedCashCents'] as int,
      countedCashCents: j['countedCashCents'] as int?,
      differenceCents: j['differenceCents'] as int?,
    );
  }
}

class CashSessionRow {
  const CashSessionRow({required this.id, required this.status, required this.openedAt, this.closedAt, this.differenceCents});
  final String id;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int? differenceCents;

  factory CashSessionRow.fromJson(Map<String, dynamic> j) => CashSessionRow(
        id: j['id'] as String,
        status: j['status'] as String,
        openedAt: DateTime.parse(j['openedAt'] as String).toLocal(),
        closedAt: j['closedAt'] == null ? null : DateTime.parse(j['closedAt'] as String).toLocal(),
        differenceCents: j['differenceCents'] as int?,
      );
}

class CashApi {
  const CashApi(this._api);
  final ApiClient _api;

  Future<CashReport> report(String id) async => CashReport.fromJson(await _api.get('/cash-sessions/$id/report') as Map<String, dynamic>);
  Future<List<CashSessionRow>> list(String branchId) async =>
      (await _api.get('/cash-sessions', query: {'branchId': branchId}) as List<dynamic>).cast<Map<String, dynamic>>().map(CashSessionRow.fromJson).toList();
}

final cashApiProvider = Provider<CashApi>((ref) => CashApi(ref.watch(apiClientProvider)));
