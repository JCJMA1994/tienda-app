import '../../core/ids.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

typedef LayawayItem = ({String name, String options, int quantity, int unitPriceCents});
typedef LayawayPayment = ({String method, int amountCents, DateTime at});

/// Apartado (modelo tipado: el resto de la app no toca el JSON).
class Layaway {
  const Layaway({
    required this.id,
    required this.number,
    required this.status,
    required this.totalCents,
    required this.paidCents,
    required this.expiresAt,
    required this.customerId,
    required this.customerName,
    this.branchId = '',
    this.saleId,
    this.items = const [],
    this.payments = const [],
  });

  final String id;
  final int number;
  final String status; // open · completed · cancelled
  final int totalCents;
  final int paidCents;
  final DateTime expiresAt;
  final String customerId;
  final String customerName;
  final String branchId;
  final String? saleId;
  final List<LayawayItem> items;
  final List<LayawayPayment> payments;

  int get pendingCents => totalCents - paidCents;
  bool get expired => status == 'open' && expiresAt.isBefore(DateTime.now());
  String get statusLabel => switch (status) { 'completed' => 'Entregado', 'cancelled' => 'Cancelado', _ => expired ? 'Vencido' : 'Vigente' };

  factory Layaway.fromJson(Map<String, dynamic> j) => Layaway(
        id: j['id'] as String,
        number: j['number'] as int,
        status: j['status'] as String,
        totalCents: j['totalCents'] as int,
        paidCents: j['paidCents'] as int,
        expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
        customerId: j['customerId'] as String,
        customerName: j['customerName'] as String? ?? '',
        branchId: j['branchId'] as String? ?? '',
        saleId: j['saleId'] as String?,
        items: [
          for (final i in ((j['items'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>())
            (
              name: i['productName'] as String,
              options: (i['options'] as Map<String, dynamic>).values.join(' · '),
              quantity: i['quantity'] as int,
              unitPriceCents: i['unitPriceCents'] as int,
            ),
        ],
        payments: [
          for (final p in ((j['payments'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>())
            (method: p['method'] as String, amountCents: p['amountCents'] as int, at: DateTime.parse(p['createdAt'] as String).toLocal()),
        ],
      );
}

class LayawaysApi {
  const LayawaysApi(this._api);
  final ApiClient _api;

  Future<List<Layaway>> list({String? status, String? customerId}) async =>
      (await _api.get('/layaways', query: {'status': status, 'customerId': customerId}) as List<dynamic>).cast<Map<String, dynamic>>().map(Layaway.fromJson).toList();

  Future<Layaway> get(String id) async => Layaway.fromJson(await _api.get('/layaways/$id') as Map<String, dynamic>);

  Future<Layaway> create({
    required String branchId,
    required String customerId,
    required List<({String variantId, int quantity})> items,
    required int depositCents,
    required String method,
    required int days,
  }) async =>
      Layaway.fromJson(await _api.post('/layaways', idempotencyKey: newUuid(), body: {
        'branchId': branchId,
        'customerId': customerId,
        'items': [for (final i in items) {'variantId': i.variantId, 'quantity': i.quantity}],
        'payments': [
          {'method': method, 'amountCents': depositCents},
        ],
        'days': days,
      },) as Map<String, dynamic>,);

  Future<Layaway> pay(String id, int amountCents, String method) async => Layaway.fromJson(await _api.post('/layaways/$id/payments', idempotencyKey: newUuid(), body: {
        'payments': [
          {'method': method, 'amountCents': amountCents},
        ],
      },) as Map<String, dynamic>,);

  /// Entregar: paga el saldo (si queda) y registra la venta. Devuelve el id de la venta.
  Future<String> complete(String id, {int pendingCents = 0, String method = 'cash', Map<String, Object?>? document}) async {
    final r = await _api.post('/layaways/$id/complete', body: {
      'payments': [
        if (pendingCents > 0) {'method': method, 'amountCents': pendingCents},
      ],
      if (document != null) 'document': document,
    },) as Map<String, dynamic>;
    return (r['sale'] as Map<String, dynamic>)['id'] as String;
  }

  /// Cancelar. Si lo abonado queda como vale, devuelve su código (se muestra una sola vez).
  Future<({String? creditCode, int creditCents})> cancel(String id, {required String reason, required String refund}) async {
    final r = await _api.post('/layaways/$id/cancel', body: {'reason': reason, 'refund': refund}) as Map<String, dynamic>;
    final c = r['credit'] as Map<String, dynamic>?;
    return (creditCode: c?['code'] as String?, creditCents: (c?['balanceCents'] as int?) ?? 0);
  }
}

final layawaysApiProvider = Provider<LayawaysApi>((ref) => LayawaysApi(ref.watch(apiClientProvider)));
final layawaysProvider = FutureProvider.autoDispose<List<Layaway>>((ref) => ref.watch(layawaysApiProvider).list());
/// Controlador del detalle de un apartado: la pantalla solo dibuja y pide acciones; aquí se
/// llama a la API y se actualiza el estado (y la lista).
class LayawayController extends AutoDisposeFamilyAsyncNotifier<Layaway, String> {
  LayawaysApi get _api => ref.read(layawaysApiProvider);

  @override
  Future<Layaway> build(String id) => ref.watch(layawaysApiProvider).get(id);

  Future<Layaway> pay(int amountCents, String method) => _apply(() => _api.pay(arg, amountCents, method));

  /// Entrega: cobra el saldo pendiente (si queda) y registra la venta. Devuelve el id de la venta.
  Future<String> deliver({String method = 'cash'}) async {
    final l = await future;
    final saleId = await _api.complete(arg, pendingCents: l.pendingCents, method: method);
    ref.invalidateSelf();
    ref.invalidate(layawaysProvider);
    return saleId;
  }

  Future<({String? creditCode, int creditCents})> cancel({required String reason, required String refund}) async {
    final l = await future;
    final r = await _api.cancel(arg, reason: reason, refund: l.paidCents > 0 ? refund : 'none');
    ref.invalidateSelf();
    ref.invalidate(layawaysProvider);
    return r;
  }

  Future<Layaway> _apply(Future<Layaway> Function() call) async {
    final updated = await call();
    state = AsyncData(updated);
    ref.invalidate(layawaysProvider);
    return updated;
  }
}

final layawayProvider = AsyncNotifierProvider.autoDispose.family<LayawayController, Layaway, String>(LayawayController.new);
