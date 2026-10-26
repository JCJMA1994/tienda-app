/// Motor de promociones: MISMAS reglas que la API (`percha-api/src/modules/promotions/engine.ts`),
/// probado con los mismos casos (`test/fixtures/promotions-vectors.json`). Así el total que ve
/// la cajera es el que cobra el servidor, también sin conexión.
///
///  1. Una prenda recibe a lo sumo UNA promoción.
///  2. "Lleva X, paga Y": prendas elegibles de todo el ticket, de la más cara a la más barata;
///     en cada grupo completo de X, las (X − Y) más baratas salen gratis.
///  3. Porcentaje: a lo que quede, el mejor porcentaje vigente (redondeo por prenda).
///  4. Se prueban dos formas (con y sin "lleva X, paga Y") y gana la que más ahorra.
class Promo {
  const Promo({
    required this.id,
    required this.name,
    required this.kind,
    this.percentBp,
    this.buyQty,
    this.payQty,
    this.scope = 'all',
    this.categoryIds = const [],
    this.productIds = const [],
  });

  final String id;
  final String name;
  final String kind; // percent · buy_x_pay_y
  final int? percentBp;
  final int? buyQty;
  final int? payQty;
  final String scope; // all · categories · products
  final List<String> categoryIds;
  final List<String> productIds;

  bool appliesTo(String productId, String? categoryId) => switch (scope) {
        'all' => true,
        'products' => productIds.contains(productId),
        _ => categoryId != null && categoryIds.contains(categoryId),
      };

  /// "−20 %" o "2x1".
  String get label => kind == 'percent' ? '−${(percentBp ?? 0) ~/ 100} %' : '${buyQty}x$payQty';

  factory Promo.fromJson(Map<String, dynamic> j) => Promo(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String,
        percentBp: (j['percentBp'] as num?)?.toInt(),
        buyQty: (j['buyQty'] as num?)?.toInt(),
        payQty: (j['payQty'] as num?)?.toInt(),
        scope: j['scope'] as String? ?? 'all',
        categoryIds: ((j['categoryIds'] as List<dynamic>?) ?? const []).cast<String>(),
        productIds: ((j['productIds'] as List<dynamic>?) ?? const []).cast<String>(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'percentBp': percentBp,
        'buyQty': buyQty,
        'payQty': payQty,
        'scope': scope,
        'categoryIds': categoryIds,
        'productIds': productIds,
      };
}

typedef PromoLine = ({String productId, String? categoryId, int quantity, int unitPriceCents});
typedef PromoLineResult = ({int discountCents, String? promotionId});

class _Unit {
  _Unit(this.line, this.price);
  final int line;
  final int price;
  int discount = 0;
  String? promo;
}

List<_Unit> _run(List<PromoLine> lines, List<Promo> promos, {required bool withBundles}) {
  final units = <_Unit>[
    for (var i = 0; i < lines.length; i++)
      for (var q = 0; q < lines[i].quantity; q++) _Unit(i, lines[i].unitPriceCents),
  ];
  final sorted = [...promos]..sort((a, b) => a.id.compareTo(b.id));

  if (withBundles) {
    for (final p in sorted.where((x) => x.kind == 'buy_x_pay_y' && x.buyQty != null && x.payQty != null)) {
      final eligible = [
        for (var i = 0; i < units.length; i++)
          if (units[i].promo == null && p.appliesTo(lines[units[i].line].productId, lines[units[i].line].categoryId)) (u: units[i], i: i),
      ]..sort((a, b) {
          final byPrice = b.u.price.compareTo(a.u.price);
          return byPrice != 0 ? byPrice : a.i.compareTo(b.i);
        });
      final groups = eligible.length ~/ p.buyQty!;
      for (var g = 0; g < groups; g++) {
        final group = eligible.sublist(g * p.buyQty!, (g + 1) * p.buyQty!);
        for (final e in group) {
          e.u.promo = p.id;
        }
        for (final e in group.skip(p.payQty!)) {
          e.u.discount = e.u.price;
        }
      }
    }
  }

  for (final u in units) {
    if (u.promo != null) continue;
    String? bestId;
    var bestOff = 0;
    for (final p in sorted) {
      if (p.kind != 'percent' || p.percentBp == null || !p.appliesTo(lines[u.line].productId, lines[u.line].categoryId)) continue;
      // Igual que Math.round de JavaScript para valores positivos.
      final off = (u.price * p.percentBp! / 10000 + 0.5).floor();
      if (bestId == null || off > bestOff) {
        bestId = p.id;
        bestOff = off;
      }
    }
    if (bestId != null && bestOff > 0) {
      u.discount = bestOff;
      u.promo = bestId;
    }
  }
  return units;
}

({List<PromoLineResult> lines, int totalCents}) applyPromotions(List<PromoLine> lines, List<Promo> promos) {
  if (promos.isEmpty || lines.isEmpty) return (lines: [for (final _ in lines) (discountCents: 0, promotionId: null)], totalCents: 0);
  int sum(List<_Unit> u) => u.fold(0, (s, x) => s + x.discount);
  final a = _run(lines, promos, withBundles: true);
  final b = _run(lines, promos, withBundles: false);
  final best = sum(a) >= sum(b) ? a : b;
  final discounts = List<int>.filled(lines.length, 0);
  final ids = List<String?>.filled(lines.length, null);
  for (final u in best) {
    discounts[u.line] += u.discount;
    if (u.promo != null && u.discount > 0) ids[u.line] ??= u.promo;
  }
  return (lines: [for (var i = 0; i < lines.length; i++) (discountCents: discounts[i], promotionId: ids[i])], totalCents: sum(best));
}
