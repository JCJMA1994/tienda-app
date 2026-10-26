import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';

typedef SellerCommission = ({String name, int tickets, int returns, int netCents, int netExTaxCents, int? commissionBp, int commissionCents});

final commissionsProvider = FutureProvider.autoDispose.family<({List<SellerCommission> sellers, int totalCents}), ({String from, String to})>((ref, r) async {
  final res = await ref.watch(apiClientProvider).get('/reports/commissions', query: {'from': r.from, 'to': r.to}) as Map<String, dynamic>;
  return (
    sellers: [
      for (final s in (res['sellers'] as List<dynamic>).cast<Map<String, dynamic>>())
        (
          name: s['name'] as String,
          tickets: s['tickets'] as int,
          returns: s['returns'] as int,
          netCents: s['netCents'] as int,
          netExTaxCents: s['netExTaxCents'] as int,
          commissionBp: s['commissionBp'] as int?,
          commissionCents: s['commissionCents'] as int,
        ),
    ],
    totalCents: (res['totals'] as Map<String, dynamic>)['commissionCents'] as int,
  );
});

