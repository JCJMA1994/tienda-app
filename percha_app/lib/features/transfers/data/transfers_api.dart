import '../../../core/ids.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import '../../einvoice/data/einvoice_api.dart';

class TransferItem {
  const TransferItem({
    required this.id,
    required this.variantId,
    required this.productName,
    required this.options,
    required this.sent,
    this.received,
  });
  final String id;
  final String variantId;
  final String productName;
  final Map<String, String> options;
  final int sent;
  final int? received;

  String get label => [productName, if (options.isNotEmpty) options.values.join(' · ')].join(' · ');
  int? get missing => received == null ? null : sent - received!;

  factory TransferItem.fromJson(Map<String, dynamic> j) => TransferItem(
        id: j['id'] as String,
        variantId: j['variantId'] as String,
        productName: j['productName'] as String,
        options: (j['options'] as Map<String, dynamic>).cast<String, String>(),
        sent: j['quantitySent'] as int,
        received: j['quantityReceived'] as int?,
      );
}

class Transfer {
  const Transfer({
    required this.id,
    required this.number,
    required this.fromBranchId,
    required this.toBranchId,
    required this.status,
    required this.sentAt,
    this.items = const [],
    this.notes,
    this.receiveNotes,
    this.documents = const [],
  });

  final String id;
  final int number;
  final String fromBranchId;
  final String toBranchId;
  final String status; // in_transit · received · cancelled
  final DateTime sentAt;
  final List<TransferItem> items;
  final String? notes;
  final String? receiveNotes;

  /// Guía de remisión electrónica (si la tienda emite comprobantes).
  final List<EDocument> documents;

  String get statusLabel => switch (status) { 'in_transit' => 'En tránsito', 'received' => 'Recibida', _ => 'Cancelada' };
  int get units => items.fold(0, (a, i) => a + i.sent);

  factory Transfer.fromJson(Map<String, dynamic> j) => Transfer(
        id: j['id'] as String,
        number: j['number'] as int,
        fromBranchId: j['fromBranchId'] as String,
        toBranchId: j['toBranchId'] as String,
        status: j['status'] as String,
        sentAt: DateTime.parse(j['sentAt'] as String).toLocal(),
        notes: j['notes'] as String?,
        receiveNotes: j['receiveNotes'] as String?,
        documents: ((j['documents'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(EDocument.fromJson).toList(),
        items: ((j['items'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(TransferItem.fromJson).toList(),
      );
}

class TransfersApi {
  const TransfersApi(this._api);
  final ApiClient _api;

  Future<List<Transfer>> list({String? status}) async =>
      (await _api.get('/transfers', query: {'status': status}) as List<dynamic>).cast<Map<String, dynamic>>().map(Transfer.fromJson).toList();

  Future<Transfer> get(String id) async => Transfer.fromJson(await _api.get('/transfers/$id') as Map<String, dynamic>);

  Future<Transfer> send({required String from, required String to, required Map<String, int> items, String? notes, Map<String, Object?>? shipment}) async =>
      Transfer.fromJson(await _api.post('/transfers', idempotencyKey: newUuid(), body: {
        'fromBranchId': from,
        'toBranchId': to,
        'items': [for (final e in items.entries) {'variantId': e.key, 'quantity': e.value}],
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (shipment != null) 'shipment': shipment,
      },) as Map<String, dynamic>,);

  Future<Transfer> receive(String id, Map<String, int> received, {String? notes}) async =>
      Transfer.fromJson(await _api.post('/transfers/$id/receive', body: {
        'items': [for (final e in received.entries) {'itemId': e.key, 'quantity': e.value}],
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },) as Map<String, dynamic>,);

  Future<void> cancel(String id) => _api.post('/transfers/$id/cancel');
}

final transfersApiProvider = Provider<TransfersApi>((ref) => TransfersApi(ref.watch(apiClientProvider)));
final transfersProvider = FutureProvider.autoDispose<List<Transfer>>((ref) => ref.watch(transfersApiProvider).list());
/// Controlador del detalle de una transferencia (recibir, cancelar, reintentar la guía).
class TransferController extends AutoDisposeFamilyAsyncNotifier<Transfer, String> {
  TransfersApi get _api => ref.read(transfersApiProvider);

  @override
  Future<Transfer> build(String id) => ref.watch(transfersApiProvider).get(id);

  Future<void> receive(Map<String, int> received, {String? notes}) => _apply(() => _api.receive(arg, received, notes: notes));

  Future<void> cancel() async {
    await _api.cancel(arg);
    ref.invalidateSelf();
    ref.invalidate(transfersProvider);
  }

  Future<void> _apply(Future<Transfer> Function() call) async {
    state = AsyncData(await call());
    ref.invalidate(transfersProvider);
  }
}

final transferProvider = AsyncNotifierProvider.autoDispose.family<TransferController, Transfer, String>(TransferController.new);
