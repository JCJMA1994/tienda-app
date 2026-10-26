import '../../../core/ids.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';

class Category {
  const Category({required this.id, required this.name});
  final String id;
  final String name;
  factory Category.fromJson(Map<String, dynamic> j) => Category(id: j['id'] as String, name: j['name'] as String);
}

class Attribute {
  const Attribute({required this.id, required this.name, required this.position, required this.values});
  final String id;
  final String name;
  final int position;
  final List<String> values;

  factory Attribute.fromJson(Map<String, dynamic> j) => Attribute(
        id: j['id'] as String,
        name: j['name'] as String,
        position: j['position'] as int,
        values: (j['values'] as List<dynamic>).map((v) => (v as Map<String, dynamic>)['value'] as String).toList(),
      );
}

class ProductListItem {
  const ProductListItem({
    required this.id,
    required this.name,
    required this.skuBase,
    required this.priceCents,
    required this.variantCount,
    required this.totalStock,
    required this.lowVariants,
    required this.active,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String skuBase;

  /// Miniatura de la portada (primera foto), si tiene.
  final String? imageUrl;
  final int priceCents;
  final int variantCount;
  final int totalStock;
  final int lowVariants;
  final bool active;

  factory ProductListItem.fromJson(Map<String, dynamic> j) => ProductListItem(
        id: j['id'] as String,
        name: j['name'] as String,
        skuBase: j['skuBase'] as String,
        priceCents: j['priceCents'] as int,
        variantCount: j['variantCount'] as int,
        totalStock: j['totalStock'] as int,
        lowVariants: j['lowVariants'] as int,
        active: j['active'] as bool,
        imageUrl: j['imageUrl'] as String?,
      );
}

class ProductPage {
  const ProductPage({required this.items, required this.total, required this.page, required this.pageSize});
  final List<ProductListItem> items;
  final int total;
  final int page;
  final int pageSize;
  bool get hasMore => page * pageSize < total;
}

class VariantStock {
  const VariantStock({required this.branchId, required this.quantity, required this.minQuantity});
  final String branchId;
  final int quantity;
  final int minQuantity;
}

class Variant {
  const Variant({
    required this.id,
    required this.sku,
    required this.barcode,
    required this.options,
    required this.priceCents,
    required this.active,
    required this.stock,
    this.avgCostCents,
  });

  final String id;
  final String sku;
  final String barcode;
  final Map<String, String> options;
  final int priceCents;
  final bool active;
  final List<VariantStock> stock;

  /// null si el rol no tiene costs.read (la API no lo envía).
  final int? avgCostCents;

  VariantStock stockIn(String branchId) =>
      stock.firstWhere((s) => s.branchId == branchId, orElse: () => VariantStock(branchId: branchId, quantity: 0, minQuantity: 0));

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(
        id: j['id'] as String,
        sku: j['sku'] as String,
        barcode: j['barcode'] as String,
        options: (j['options'] as Map<String, dynamic>).cast<String, String>(),
        priceCents: j['effectivePriceCents'] as int,
        active: j['active'] as bool,
        avgCostCents: j['avgCostCents'] as int?,
        stock: (j['stock'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((s) => VariantStock(
                  branchId: s['branchId'] as String,
                  quantity: s['quantity'] as int,
                  minQuantity: s['minQuantity'] as int,
                ),)
            .toList(),
      );
}

class ProductImage {
  const ProductImage({required this.id, required this.url, required this.thumbUrl, required this.width, required this.height, this.optionValue});
  final String id;
  final String url;
  final String thumbUrl;
  final int width;
  final int height;

  /// Valor de atributo de la foto (p. ej. "Negro"), o null si es general.
  final String? optionValue;

  factory ProductImage.fromJson(Map<String, dynamic> j) => ProductImage(
        id: j['id'] as String,
        url: j['url'] as String,
        thumbUrl: j['thumbUrl'] as String,
        width: j['width'] as int,
        height: j['height'] as int,
        optionValue: j['optionValue'] as String?,
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.skuBase,
    required this.priceCents,
    required this.categoryId,
    required this.active,
    required this.attributes,
    required this.variants,
    this.costCents,
    this.season,
    this.images = const [],
    this.published = false,
  });

  final String id;
  final String name;
  final String skuBase;
  final int priceCents;
  final int? costCents;
  final String? categoryId;
  final String? season;
  final bool active;

  /// Atributos usados, en orden (p. ej. Talla y Color) con los valores presentes.
  final List<({String name, List<String> values})> attributes;
  final List<Variant> variants;

  /// Fotos en orden (la primera es la portada).
  final List<ProductImage> images;

  /// Visible en el catálogo en línea.
  final bool published;

  /// Foto para una variante: la de su color (u otro valor) si existe; si no, la portada.
  ProductImage? imageFor(Variant v) =>
      images.where((i) => i.optionValue != null && v.options.values.contains(i.optionValue)).firstOrNull ?? images.firstOrNull;

  /// Busca la variante de una combinación (celda de la matriz).
  Variant? variantFor(Map<String, String> options) => variants
      .where((v) => options.entries.every((e) => v.options[e.key] == e.value) && v.options.length == options.length)
      .firstOrNull;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        skuBase: j['skuBase'] as String,
        priceCents: j['priceCents'] as int,
        costCents: j['costCents'] as int?,
        categoryId: j['categoryId'] as String?,
        season: j['season'] as String?,
        active: j['active'] as bool,
        attributes: (j['attributes'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((a) => (name: a['name'] as String, values: (a['values'] as List<dynamic>).cast<String>()))
            .toList(),
        variants: (j['variants'] as List<dynamic>).cast<Map<String, dynamic>>().map(Variant.fromJson).toList(),
        images: ((j['images'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(ProductImage.fromJson).toList(),
        published: j['published'] as bool? ?? false,
      );
}

class Movement {
  const Movement({required this.type, required this.quantity, required this.balanceAfter, required this.createdAt, this.reason});
  final String type;
  final int quantity;
  final int balanceAfter;
  final DateTime createdAt;
  final String? reason;

  static const labels = {
    'initial': 'Carga inicial',
    'adjustment': 'Ajuste',
    'purchase_receipt': 'Recepción de compra',
    'sale': 'Venta',
    'sale_void': 'Anulación',
    'return_in': 'Devolución',
    'exchange_out': 'Cambio',
    'transfer_out': 'Transferencia enviada',
    'transfer_in': 'Transferencia recibida',
  };

  String get label => labels[type] ?? type;

  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
        type: j['type'] as String,
        quantity: j['quantity'] as int,
        balanceAfter: j['balanceAfter'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        reason: j['reason'] as String?,
      );
}

class CatalogApi {
  const CatalogApi(this._api);
  final ApiClient _api;

  Future<ProductImage> uploadImage(String productId, List<int> bytes, {required String contentType, String? option}) async => ProductImage.fromJson(
        await _api.postBytes('/products/$productId/images', bytes, contentType: contentType, query: {if (option != null) 'option': option}) as Map<String, dynamic>,
      );

  Future<void> deleteImage(String productId, String imageId) => _api.delete('/products/$productId/images/$imageId');

  Future<void> reorderImages(String productId, List<String> ids) => _api.put('/products/$productId/images/order', body: {'ids': ids});

  Future<ProductPage> products({String? search, required String branchId, int page = 1}) async {
    final res = await _api.get('/products', query: {'search': search, 'branchId': branchId, 'page': page, 'pageSize': 30})
        as Map<String, dynamic>;
    return ProductPage(
      items: (res['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(ProductListItem.fromJson).toList(),
      total: res['total'] as int,
      page: res['page'] as int,
      pageSize: res['pageSize'] as int,
    );
  }

  Future<Product> product(String id) async => Product.fromJson(await _api.get('/products/$id') as Map<String, dynamic>);

  Future<List<Category>> categories() async =>
      (await _api.get('/categories') as List<dynamic>).cast<Map<String, dynamic>>().map(Category.fromJson).toList();

  Future<Category> createCategory(String name) async =>
      Category.fromJson(await _api.post('/categories', body: {'name': name}) as Map<String, dynamic>);

  Future<List<Attribute>> attributes() async =>
      (await _api.get('/attributes') as List<dynamic>).cast<Map<String, dynamic>>().map(Attribute.fromJson).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  Future<Product> createProduct({
    required String name,
    String? categoryId,
    String? season,
    required int priceCents,
    required int costCents,
    required Map<String, List<String>> matrix,
    ({String branchId, List<({Map<String, String> options, int quantity})> items})? initialStock,
  }) async {
    final res = await _api.post('/products', body: {
      'name': name,
      if (categoryId != null) 'categoryId': categoryId,
      if (season != null && season.isNotEmpty) 'season': season,
      'priceCents': priceCents,
      'costCents': costCents,
      'matrix': matrix,
      if (initialStock != null && initialStock.items.isNotEmpty)
        'initialStock': {
          'branchId': initialStock.branchId,
          'items': [for (final i in initialStock.items) {'options': i.options, 'quantity': i.quantity}],
        },
    },);
    return Product.fromJson(res as Map<String, dynamic>);
  }

  Future<void> addVariants(String productId, Map<String, List<String>> matrix) =>
      _api.post('/products/$productId/variants', body: {'matrix': matrix});

  Future<void> updateProduct(String id, Map<String, Object?> changes) => _api.patch('/products/$id', body: changes);

  /// Ajuste con conteo físico (`counted`) o variación (`delta`). El motivo queda en el kardex.
  Future<void> adjust({required String branchId, required String variantId, int? delta, int? counted, required String reason}) =>
      _api.post('/inventory/adjustments', idempotencyKey: newUuid(), body: {
        'branchId': branchId,
        'reason': reason,
        'items': [
          {'variantId': variantId, if (delta != null) 'delta': delta, if (counted != null) 'counted': counted},
        ],
      },);

  Future<void> setMinStock({required String branchId, required String variantId, required int minQuantity}) =>
      _api.put('/inventory/min-stock', body: {'branchId': branchId, 'variantId': variantId, 'minQuantity': minQuantity});

  Future<List<Movement>> movements(String variantId, String branchId) async =>
      (await _api.get('/inventory/movements', query: {'variantId': variantId, 'branchId': branchId, 'limit': 20}) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Movement.fromJson)
          .toList();

  Future<Map<String, dynamic>> import({required String branchId, required List<Map<String, Object?>> rows}) async =>
      await _api.post('/catalog/import', body: {'branchId': branchId, 'rows': rows}) as Map<String, dynamic>;
}

final catalogApiProvider = Provider<CatalogApi>((ref) => CatalogApi(ref.watch(apiClientProvider)));

final productDetailProvider = FutureProvider.autoDispose.family<Product, String>(
  (ref, id) => ref.watch(catalogApiProvider).product(id),
);

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) => ref.watch(catalogApiProvider).categories());

final attributesProvider = FutureProvider.autoDispose<List<Attribute>>((ref) => ref.watch(catalogApiProvider).attributes());
