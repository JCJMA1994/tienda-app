import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';

class CatalogSettings {
  const CatalogSettings({required this.enabled, this.slug, this.whatsapp, this.branchId, this.description, this.url, this.published = 0});
  final bool enabled;
  final String? slug;
  final String? whatsapp;
  final String? branchId;
  final String? description;
  final String? url;

  /// Productos publicados (visibles en el catálogo).
  final int published;

  factory CatalogSettings.fromJson(Map<String, dynamic> j) => CatalogSettings(
        enabled: j['enabled'] as bool? ?? false,
        slug: j['slug'] as String?,
        whatsapp: j['whatsapp'] as String?,
        branchId: j['branchId'] as String?,
        description: j['description'] as String?,
        url: j['url'] as String?,
        published: (j['published'] as num?)?.toInt() ?? 0,
      );
}

class CatalogOrder {
  const CatalogOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.customerName,
    required this.customerPhone,
    required this.totalCents,
    required this.createdAt,
    this.note,
    this.customerId,
    this.items = const [],
  });

  final String id;
  final int number;
  final String status; // new · contacted · completed · cancelled
  final String customerName;
  final String customerPhone;
  final int totalCents;
  final DateTime createdAt;
  final String? note;
  final String? customerId;
  final List<({String variantId, String name, String options, int quantity, int unitPriceCents})> items;

  String get statusLabel => switch (status) { 'new' => 'Nuevo', 'contacted' => 'Contactado', 'completed' => 'Atendido', _ => 'Cancelado' };
  bool get open => status == 'new' || status == 'contacted';

  factory CatalogOrder.fromJson(Map<String, dynamic> j) => CatalogOrder(
        id: j['id'] as String,
        number: j['number'] as int,
        status: j['status'] as String,
        customerName: j['customerName'] as String,
        customerPhone: j['customerPhone'] as String,
        totalCents: j['totalCents'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        note: j['note'] as String?,
        customerId: j['customerId'] as String?,
        items: [
          for (final i in ((j['items'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>())
            (
              variantId: i['variantId'] as String,
              name: i['productName'] as String,
              options: (i['options'] as Map<String, dynamic>).values.join(' · '),
              quantity: i['quantity'] as int,
              unitPriceCents: i['unitPriceCents'] as int,
            ),
        ],
      );
}

class StorefrontApi {
  const StorefrontApi(this._api);
  final ApiClient _api;

  Future<CatalogSettings> settings() async => CatalogSettings.fromJson(await _api.get('/catalog/settings') as Map<String, dynamic>);
  Future<CatalogSettings> save(Map<String, Object?> body) async => CatalogSettings.fromJson(await _api.put('/catalog/settings', body: body) as Map<String, dynamic>);
  Future<void> setPublished(String productId, bool published) => _api.put('/catalog/products/$productId/published', body: {'published': published});

  Future<List<CatalogOrder>> orders() async =>
      (await _api.get('/catalog/orders') as List<dynamic>).cast<Map<String, dynamic>>().map(CatalogOrder.fromJson).toList();
  Future<CatalogOrder> order(String id) async => CatalogOrder.fromJson(await _api.get('/catalog/orders/$id') as Map<String, dynamic>);
  Future<void> setStatus(String id, String status) => _api.post('/catalog/orders/$id/status', body: {'status': status});

  /// Crea o reutiliza (por celular) la ficha del cliente. Devuelve su id.
  Future<String> linkCustomer(String id) async => ((await _api.post('/catalog/orders/$id/customer') as Map<String, dynamic>)['customerId']) as String;
}

final storefrontApiProvider = Provider<StorefrontApi>((ref) => StorefrontApi(ref.watch(apiClientProvider)));
final catalogSettingsProvider = FutureProvider.autoDispose<CatalogSettings>((ref) => ref.watch(storefrontApiProvider).settings());
final catalogOrdersProvider = FutureProvider.autoDispose<List<CatalogOrder>>((ref) => ref.watch(storefrontApiProvider).orders());
final catalogOrderProvider = FutureProvider.autoDispose.family<CatalogOrder, String>((ref, id) => ref.watch(storefrontApiProvider).order(id));
