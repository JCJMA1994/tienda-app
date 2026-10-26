import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// Período en fechas locales (YYYY-MM-DD), igual que espera la API.
typedef Period = ({String from, String to});

String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum PeriodPreset {
  today('Hoy'),
  week('7 días'),
  month('30 días'),
  thisMonth('Este mes');

  const PeriodPreset(this.label);
  final String label;

  Period resolve(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    // Aritmética por calendario (día - n), no por horas: evita saltos con horario de verano.
    final from = switch (this) {
      PeriodPreset.today => today,
      PeriodPreset.week => DateTime(today.year, today.month, today.day - 6),
      PeriodPreset.month => DateTime(today.year, today.month, today.day - 29),
      PeriodPreset.thisMonth => DateTime(today.year, today.month),
    };
    return (from: ymd(from), to: ymd(today));
  }
}

class Summary {
  const Summary({
    required this.tickets,
    required this.units,
    required this.netSalesCents,
    required this.averageTicketCents,
    required this.discountsCents,
    required this.voidedSales,
    required this.returns,
    this.grossMarginCents,
    this.grossMarginPct,
    this.costOfSalesCents,
  });

  final int tickets;
  final int units;
  final int netSalesCents;
  final int averageTicketCents;
  final int discountsCents;
  final int voidedSales;
  final int returns;

  /// null si el rol no ve costos.
  final int? grossMarginCents;
  final double? grossMarginPct;
  final int? costOfSalesCents;

  factory Summary.fromJson(Map<String, dynamic> j) => Summary(
        tickets: _i(j['tickets']),
        units: _i(j['units']),
        netSalesCents: _i(j['netSalesCents']),
        averageTicketCents: _i(j['averageTicketCents']),
        discountsCents: _i(j['discountsCents']),
        voidedSales: _i(j['voidedSales']),
        returns: _i(j['returns']),
        grossMarginCents: j['grossMarginCents'] == null ? null : _i(j['grossMarginCents']),
        grossMarginPct: (j['grossMarginPct'] as num?)?.toDouble(),
        costOfSalesCents: j['costOfSalesCents'] == null ? null : _i(j['costOfSalesCents']),
      );
}

class DayPoint {
  const DayPoint({required this.date, required this.tickets, required this.netSalesCents});
  final DateTime date;
  final int tickets;
  final int netSalesCents;
}

class TopProduct {
  const TopProduct({required this.productId, required this.name, required this.units, required this.netSalesCents, this.grossMarginCents});
  final String productId;
  final String name;
  final int units;
  final int netSalesCents;
  final int? grossMarginCents;
}

class AttributeRotation {
  const AttributeRotation({required this.name, required this.values});
  final String name;
  final List<({String value, int sold, int stock, double? sellThroughPct})> values;
}

class DeadItem {
  const DeadItem({
    required this.productName,
    required this.options,
    required this.quantity,
    required this.daysWithoutSale,
    required this.neverSold,
    required this.retailValueCents,
    this.costValueCents,
  });
  final String productName;
  final String options;
  final int quantity;
  final int daysWithoutSale;
  final bool neverSold;
  final int retailValueCents;
  final int? costValueCents;
}

class Valuation {
  const Valuation({required this.categories, required this.totalUnits, required this.totalRetailValueCents, this.totalCostValueCents, this.potentialMarginCents});
  final List<({String category, int units, int retailValueCents, int? costValueCents})> categories;
  final int totalUnits;
  final int totalRetailValueCents;
  final int? totalCostValueCents;
  final int? potentialMarginCents;
}

class ReportsApi {
  const ReportsApi(this._api);
  final ApiClient _api;

  Map<String, dynamic> _q(Period p) => {'from': p.from, 'to': p.to};

  Future<Summary> summary(Period p) async => Summary.fromJson(await _api.get('/reports/summary', query: _q(p)) as Map<String, dynamic>);

  Future<List<DayPoint>> daily(Period p) async {
    final res = await _api.get('/reports/daily', query: _q(p)) as Map<String, dynamic>;
    return (res['days'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((d) => DayPoint(date: DateTime.parse(d['date'] as String), tickets: _i(d['tickets']), netSalesCents: _i(d['netSalesCents'])))
        .toList();
  }

  Future<List<TopProduct>> top(Period p) async {
    final res = await _api.get('/reports/top-products', query: {..._q(p), 'limit': 10}) as Map<String, dynamic>;
    return (res['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((t) => TopProduct(
              productId: t['productId'] as String,
              name: t['name'] as String,
              units: _i(t['units']),
              netSalesCents: _i(t['netSalesCents']),
              grossMarginCents: t['grossMarginCents'] == null ? null : _i(t['grossMarginCents']),
            ))
        .toList();
  }

  Future<List<AttributeRotation>> attributes(Period p) async {
    final res = await _api.get('/reports/attributes', query: _q(p)) as Map<String, dynamic>;
    return (res['attributes'] as List<dynamic>).cast<Map<String, dynamic>>().map((a) {
      final values = (a['values'] as List<dynamic>).cast<Map<String, dynamic>>().map((v) => (
            value: v['value'] as String,
            sold: _i(v['sold']),
            stock: _i(v['stock']),
            sellThroughPct: (v['sellThroughPct'] as num?)?.toDouble(),
          ));
      return AttributeRotation(name: a['name'] as String, values: values.toList());
    }).toList();
  }

  Future<List<DeadItem>> deadStock({int days = 60}) async {
    final res = await _api.get('/reports/dead-stock', query: {'days': days}) as Map<String, dynamic>;
    return (res['items'] as List<dynamic>).cast<Map<String, dynamic>>().map((d) {
      final options = (d['options'] as Map<String, dynamic>).values.join(' · ');
      return DeadItem(
        productName: d['productName'] as String,
        options: options,
        quantity: _i(d['quantity']),
        daysWithoutSale: _i(d['daysWithoutSale']),
        neverSold: d['neverSold'] as bool,
        retailValueCents: _i(d['retailValueCents']),
        costValueCents: d['costValueCents'] == null ? null : _i(d['costValueCents']),
      );
    }).toList();
  }

  Future<Valuation> valuation() async {
    final res = await _api.get('/reports/valuation') as Map<String, dynamic>;
    return Valuation(
      categories: (res['categories'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((c) => (
                category: c['category'] as String,
                units: _i(c['units']),
                retailValueCents: _i(c['retailValueCents']),
                costValueCents: c['costValueCents'] == null ? null : _i(c['costValueCents']),
              ))
          .toList(),
      totalUnits: _i(res['totalUnits']),
      totalRetailValueCents: _i(res['totalRetailValueCents']),
      totalCostValueCents: res['totalCostValueCents'] == null ? null : _i(res['totalCostValueCents']),
      potentialMarginCents: res['potentialMarginCents'] == null ? null : _i(res['potentialMarginCents']),
    );
  }
}

final reportsApiProvider = Provider<ReportsApi>((ref) => ReportsApi(ref.watch(apiClientProvider)));

final summaryProvider = FutureProvider.autoDispose.family<Summary, Period>((ref, p) => ref.watch(reportsApiProvider).summary(p));
final dailyProvider = FutureProvider.autoDispose.family<List<DayPoint>, Period>((ref, p) => ref.watch(reportsApiProvider).daily(p));
final topProvider = FutureProvider.autoDispose.family<List<TopProduct>, Period>((ref, p) => ref.watch(reportsApiProvider).top(p));
final attributesRotationProvider =
    FutureProvider.autoDispose.family<List<AttributeRotation>, Period>((ref, p) => ref.watch(reportsApiProvider).attributes(p));
final deadStockProvider = FutureProvider.autoDispose.family<List<DeadItem>, int>((ref, days) => ref.watch(reportsApiProvider).deadStock(days: days));
final valuationProvider = FutureProvider.autoDispose<Valuation>((ref) => ref.watch(reportsApiProvider).valuation());
