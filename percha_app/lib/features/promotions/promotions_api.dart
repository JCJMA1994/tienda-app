import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';
import '../pos/domain/promotions.dart';

/// Promoción con su vigencia (para administrarla).
class PromotionRow {
  const PromotionRow({required this.promo, required this.startsAt, this.endsAt, required this.active});
  final Promo promo;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool active;

  String get status {
    final now = DateTime.now();
    if (!active) return 'Pausada';
    if (startsAt.isAfter(now)) return 'Programada';
    if (endsAt != null && !endsAt!.isAfter(now)) return 'Terminada';
    return 'Vigente';
  }

  factory PromotionRow.fromJson(Map<String, dynamic> j) => PromotionRow(
        promo: Promo.fromJson(j),
        startsAt: DateTime.parse(j['startsAt'] as String).toLocal(),
        endsAt: j['endsAt'] == null ? null : DateTime.parse(j['endsAt'] as String).toLocal(),
        active: j['active'] as bool,
      );
}

class PromotionsApi {
  const PromotionsApi(this._api);
  final ApiClient _api;

  Future<List<PromotionRow>> list() async =>
      (await _api.get('/promotions') as List<dynamic>).cast<Map<String, dynamic>>().map(PromotionRow.fromJson).toList();

  Future<void> save({String? id, required Map<String, Object?> body}) => id == null ? _api.post('/promotions', body: body) : _api.put('/promotions/$id', body: body);
}

final promotionsApiProvider = Provider<PromotionsApi>((ref) => PromotionsApi(ref.watch(apiClientProvider)));
final promotionsProvider = FutureProvider.autoDispose<List<PromotionRow>>((ref) => ref.watch(promotionsApiProvider).list());
