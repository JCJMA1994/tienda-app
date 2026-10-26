import '../../einvoice/data/einvoice_models.dart';

/// Una variante lista para vender (resultado de escanear o elegir en la grilla).
class SellableVariant {
  const SellableVariant({
    required this.id,
    required this.sku,
    required this.productName,
    required this.options,
    required this.priceCents,
    required this.sellable,
    this.stock,
  });

  final String id;
  final String sku;
  final String productName;
  final Map<String, String> options;
  final int priceCents;
  final bool sellable;

  /// Stock en la sucursal actual (null si no se conoce).
  final int? stock;

  /// "M · Negro"
  String get optionsLabel => options.values.join(' · ');

  factory SellableVariant.fromLookup(Map<String, dynamic> j) => SellableVariant(
        id: j['id'] as String,
        sku: j['sku'] as String,
        productName: j['productName'] as String,
        options: (j['options'] as Map<String, dynamic>).cast<String, String>(),
        priceCents: j['effectivePriceCents'] as int,
        sellable: j['sellable'] as bool,
        stock: j['stock'] as int?,
      );
}

class ProductSummary {
  const ProductSummary({required this.id, required this.name, required this.priceCents, required this.totalStock, required this.variantCount, this.imageUrl});
  final String id;
  final String? imageUrl;
  final String name;
  final int priceCents;
  final int totalStock;
  final int variantCount;

  factory ProductSummary.fromJson(Map<String, dynamic> j) => ProductSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        priceCents: j['priceCents'] as int,
        totalStock: j['totalStock'] as int,
        variantCount: j['variantCount'] as int,
        imageUrl: j['imageUrl'] as String?,
      );
}

/// Producto con variantes y stock por sucursal (para elegir talla/color).
class ProductDetail {
  const ProductDetail({required this.id, required this.name, required this.attributes, required this.variants});
  final String id;
  final String name;
  final List<({String name, List<String> values})> attributes;
  final List<SellableVariant> variants;

  factory ProductDetail.fromJson(Map<String, dynamic> j, {required String branchId}) {
    final name = j['name'] as String;
    final productActive = j['active'] as bool;
    return ProductDetail(
      id: j['id'] as String,
      name: name,
      attributes: (j['attributes'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((a) => (name: a['name'] as String, values: (a['values'] as List<dynamic>).cast<String>()))
          .toList(),
      variants: (j['variants'] as List<dynamic>).cast<Map<String, dynamic>>().map((v) {
        final stock = (v['stock'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((s) => s['branchId'] == branchId)
            .fold<int>(0, (a, s) => a + (s['quantity'] as int));
        return SellableVariant(
          id: v['id'] as String,
          sku: v['sku'] as String,
          productName: name,
          options: (v['options'] as Map<String, dynamic>).cast<String, String>(),
          priceCents: v['effectivePriceCents'] as int,
          sellable: (v['active'] as bool) && productActive,
          stock: stock,
        );
      }).toList(),
    );
  }
}

class CashSession {
  const CashSession({required this.id, required this.openingCents, required this.expectedCashCents});
  final String id;
  final int openingCents;
  final int expectedCashCents;

  factory CashSession.fromJson(Map<String, dynamic> j) => CashSession(
        id: j['id'] as String,
        openingCents: j['openingCents'] as int,
        expectedCashCents: (j['summary'] as Map<String, dynamic>?)?['expectedCashCents'] as int? ?? j['openingCents'] as int,
      );

  Map<String, Object?> toJson() => {'id': id, 'openingCents': openingCents, 'summary': {'expectedCashCents': expectedCashCents}};
}

enum PaymentMethod {
  cash('cash', 'Efectivo'),
  card('card', 'Tarjeta'),
  wallet('wallet', 'Yape / Plin'),

  /// Vale, saldo a favor o gift card (no entra a caja).
  storeCredit('store_credit', 'Vale');

  const PaymentMethod(this.api, this.label);
  final String api;
  final String label;
}

class SaleReceipt {
  const SaleReceipt({
    required this.id,
    required this.number,
    required this.totalCents,
    required this.taxCents,
    required this.changeCents,
    this.documents = const [],
  });
  final String id;
  final int number;
  final int totalCents;
  final int taxCents;
  final int changeCents;

  /// Comprobantes electrónicos emitidos (boleta/factura); vacío si la tienda no los usa.
  final List<EDocument> documents;

  factory SaleReceipt.fromJson(Map<String, dynamic> j) => SaleReceipt(
        documents: ((j['documents'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(EDocument.fromJson).toList(),
        id: j['id'] as String,
        number: j['number'] as int,
        totalCents: j['totalCents'] as int,
        taxCents: j['taxCents'] as int,
        changeCents: j['changeCents'] as int? ?? 0,
      );
}
