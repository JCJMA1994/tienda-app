import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/barcodes.dart';
import '../../../core/network/api_error.dart';
import '../data/pos_api.dart';
import '../data/pos_models.dart';
import '../domain/promotions.dart';

/// Foto local de variantes, precios y stock de la sucursal: con ella el POS busca por código o
/// SKU y vende aunque se caiga el internet. Se refresca cuando hay conexión.
class PosSnapshot {
  const PosSnapshot({required this.branchId, required this.generatedAt, required this.variants, this.promotions = const []});
  final String branchId;
  final DateTime generatedAt;
  final Map<String, Map<String, dynamic>> variants; // id → datos

  /// Promociones vigentes cuando se tomó la foto (para calcular el total sin conexión).
  final List<Promo> promotions;

  /// Promociones del ticket: misma regla que la API. Las variantes que no estén en la foto
  /// (recién creadas) no reciben promoción aquí; el servidor igual cotiza el total exacto.
  ({List<PromoLineResult> lines, int totalCents}) promosFor(List<({String variantId, int quantity, int unitPriceCents})> items) {
    final known = [for (final i in items) if (variants[i.variantId] != null) i];
    final lines = [
      for (final i in known) (productId: variants[i.variantId]!['productId'] as String, categoryId: variants[i.variantId]!['categoryId'] as String?, quantity: i.quantity, unitPriceCents: i.unitPriceCents),
    ];
    final r = applyPromotions(lines, promotions);
    final byVariant = {for (var k = 0; k < known.length; k++) known[k].variantId: r.lines[k]};
    return (lines: [for (final i in items) byVariant[i.variantId] ?? (discountCents: 0, promotionId: null)], totalCents: r.totalCents);
  }

  String? promoName(String? id) => id == null ? null : promotions.where((p) => p.id == id).map((p) => p.name).firstOrNull;

  /// Misma regla que la API: código limpio y UPC-A ⇄ EAN-13.
  SellableVariant? lookup(String code) {
    final candidates = barcodeCandidates(code);
    if (candidates.isEmpty) return null;
    final sku = candidates.first.toUpperCase();
    for (final v in variants.values) {
      if (candidates.contains(v['barcode'] as String?) || (v['sku'] as String).toUpperCase() == sku) return _toSellable(v);
    }
    return null;
  }

  SellableVariant? byId(String id) => variants[id] == null ? null : _toSellable(variants[id]!);

  /// Grilla del POS sin conexión: productos de la foto (filtrados por nombre o SKU).
  List<ProductSummary> products(String query) {
    final q = query.trim().toLowerCase();
    final byProduct = <String, List<Map<String, dynamic>>>{};
    for (final v in variants.values) {
      if (q.isNotEmpty && !(v['productName'] as String).toLowerCase().contains(q) && !(v['sku'] as String).toLowerCase().contains(q)) continue;
      byProduct.putIfAbsent(v['productId'] as String, () => []).add(v);
    }
    return [
      for (final e in byProduct.entries)
        ProductSummary(
          id: e.key,
          name: e.value.first['productName'] as String,
          priceCents: e.value.map((v) => (v['priceCents'] as num).toInt()).reduce((a, b) => a < b ? a : b),
          totalStock: e.value.fold(0, (a, v) => a + (v['stock'] as num).toInt().clamp(0, 1 << 30)),
          variantCount: e.value.length,
          imageUrl: e.value.first['imageUrl'] as String?,
        ),
    ];
  }

  /// Detalle para elegir talla/color sin conexión.
  ProductDetail? product(String productId) {
    final own = variants.values.where((v) => v['productId'] == productId).toList();
    if (own.isEmpty) return null;
    final attrNames = <String>{for (final v in own) ...(v['options'] as Map<String, dynamic>).keys};
    return ProductDetail(
      id: productId,
      name: own.first['productName'] as String,
      attributes: [for (final a in attrNames) (name: a, values: {for (final v in own) (v['options'] as Map<String, dynamic>)[a] as String?}.whereType<String>().toList())],
      variants: own.map(_toSellable).toList(),
    );
  }

  static SellableVariant _toSellable(Map<String, dynamic> v) => SellableVariant(
        id: v['id'] as String,
        sku: v['sku'] as String,
        productName: v['productName'] as String,
        options: (v['options'] as Map<String, dynamic>).cast<String, String>(),
        priceCents: (v['priceCents'] as num).toInt(),
        sellable: true,
        stock: (v['stock'] as num).toInt(),
      );

  Map<String, Object?> toJson() => {'branchId': branchId, 'generatedAt': generatedAt.toIso8601String(), 'variants': variants.values.toList(), 'promotions': [for (final p in promotions) p.toJson()]};

  factory PosSnapshot.fromJson(Map<String, dynamic> j) => PosSnapshot(
        branchId: j['branchId'] as String,
        generatedAt: DateTime.parse(j['generatedAt'] as String),
        variants: {for (final v in (j['variants'] as List<dynamic>).cast<Map<String, dynamic>>()) v['id'] as String: Map.of(v)},
        promotions: [for (final p in ((j['promotions'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>()) Promo.fromJson(p)],
      );
}

class PosSnapshotController extends AutoDisposeFamilyAsyncNotifier<PosSnapshot?, String> {
  String get _key => 'percha.pos.snapshot.$arg';

  @override
  Future<PosSnapshot?> build(String branchId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final cached = raw == null ? null : PosSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    // Se intenta actualizar en segundo plano; si no hay red, queda la foto guardada.
    Future.microtask(refresh);
    return cached;
  }

  Future<void> refresh() async {
    try {
      final fresh = PosSnapshot.fromJson(await ref.read(posApiProvider).snapshot(arg));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(fresh.toJson()));
      state = AsyncData(fresh);
    } catch (_) {
      // Sin conexión: se mantiene la última foto.
    }
  }

  /// Tras una venta sin conexión, baja el stock local para no vender lo que ya salió.
  Future<void> discount(List<({String variantId, int quantity})> items) async {
    final s = state.valueOrNull;
    if (s == null) return;
    for (final i in items) {
      final v = s.variants[i.variantId];
      if (v != null) v['stock'] = (v['stock'] as num).toInt() - i.quantity;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(s.toJson()));
    state = AsyncData(s);
  }
}

final posSnapshotProvider = AsyncNotifierProvider.autoDispose.family<PosSnapshotController, PosSnapshot?, String>(PosSnapshotController.new);

/// Ejecuta [online]; si no hay conexión, usa [offline] (la foto local u otro respaldo).
Future<T> withOfflineFallback<T>(Future<T> Function() online, T? Function() offline) async {
  try {
    return await online();
  } on ApiError catch (e) {
    final fallback = e.isNetwork ? offline() : null;
    if (fallback == null) rethrow;
    return fallback;
  }
}

/// Busca por código de barras o SKU: en el servidor si hay conexión; si no, en la foto local.
Future<SellableVariant?> lookupVariant(WidgetRef ref, String code, String branchId) async {
  try {
    return await ref.read(posApiProvider).lookup(code, branchId);
  } on ApiError catch (e) {
    if (!e.isNetwork) rethrow;
    final snap = ref.read(posSnapshotProvider(branchId)).valueOrNull;
    return snap?.lookup(code);
  }
}
