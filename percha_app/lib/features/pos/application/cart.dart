import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_models.dart';

class CartLine {
  const CartLine({required this.variant, required this.quantity});
  final SellableVariant variant;
  final int quantity;

  int get totalCents => variant.priceCents * quantity;
  CartLine withQuantity(int q) => CartLine(variant: variant, quantity: q);
}

/// Resultado de intentar agregar una prenda, para que la UI avise sin adivinar.
enum AddResult { added, incremented, outOfStock, notSellable }

/// Carrito inmutable. Toda la lógica es pura (sin Flutter ni red): se prueba con tests simples.
///
/// Los montos que muestra son una VISTA PREVIA con la misma fórmula de la API.
/// El total que vale es el que devuelve el servidor al crear la venta.
class Cart {
  const Cart({this.lines = const [], this.discountCents = 0});

  final List<CartLine> lines;
  final int discountCents;

  bool get isEmpty => lines.isEmpty;
  int get units => lines.fold(0, (a, l) => a + l.quantity);
  int get subtotalCents => lines.fold(0, (a, l) => a + l.totalCents);

  /// Descuento nunca mayor al subtotal (si se quitan prendas, se recorta solo).
  int get effectiveDiscountCents => discountCents.clamp(0, subtotalCents);

  /// Descuento manual efectivo después de las promociones.
  int manualDiscountAfter(int promoCents) => discountCents.clamp(0, subtotalCents - promoCents);

  int netCents({int promoCents = 0}) => subtotalCents - promoCents - manualDiscountAfter(promoCents);

  /// Igual que computeTax() de la API: con IGV incluido, igv = total × t / (1 + t).
  /// [promoCents]: lo que descuentan las promociones automáticas (se resta antes del manual).
  ({int total, int tax}) totals({required int taxRateBp, required bool pricesIncludeTax, int promoCents = 0}) {
    final net = netCents(promoCents: promoCents);
    if (pricesIncludeTax) {
      return (total: net, tax: (net * taxRateBp / (10000 + taxRateBp)).round());
    }
    final tax = (net * taxRateBp / 10000).round();
    return (total: net + tax, tax: tax);
  }

  /// ¿Requiere PIN de supervisor? (misma regla que la API: descuento > límite del subtotal)
  /// El límite se mide sobre lo que queda después de las promociones (igual que la API).
  bool needsDiscountApproval(int discountLimitBp, {int promoCents = 0}) =>
      manualDiscountAfter(promoCents) > ((subtotalCents - promoCents) * discountLimitBp / 10000).round();

  (Cart, AddResult) add(SellableVariant v) {
    if (!v.sellable) return (this, AddResult.notSellable);
    final i = lines.indexWhere((l) => l.variant.id == v.id);
    final current = i == -1 ? 0 : lines[i].quantity;
    if (v.stock != null && current + 1 > v.stock!) return (this, AddResult.outOfStock);
    if (i == -1) {
      return (Cart(lines: [...lines, CartLine(variant: v, quantity: 1)], discountCents: discountCents), AddResult.added);
    }
    return (_replace(i, lines[i].withQuantity(current + 1)), AddResult.incremented);
  }

  Cart setQuantity(String variantId, int quantity) {
    final i = lines.indexWhere((l) => l.variant.id == variantId);
    if (i == -1) return this;
    if (quantity <= 0) {
      return Cart(lines: [...lines]..removeAt(i), discountCents: discountCents);
    }
    final stock = lines[i].variant.stock;
    final q = stock == null || stock < 1 ? quantity : quantity.clamp(1, stock);
    return _replace(i, lines[i].withQuantity(q));
  }

  Cart withDiscount(int cents) => Cart(lines: lines, discountCents: cents < 0 ? 0 : cents);

  List<({String variantId, int quantity})> toItems() =>
      [for (final l in lines) (variantId: l.variant.id, quantity: l.quantity)];

  Cart _replace(int i, CartLine line) {
    final copy = [...lines];
    copy[i] = line;
    return Cart(lines: copy, discountCents: discountCents);
  }
}

class CartController extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  AddResult add(SellableVariant v) {
    final (next, result) = state.add(v);
    state = next;
    return result;
  }

  void setQuantity(String variantId, int q) => state = state.setQuantity(variantId, q);
  void setDiscount(int cents) => state = state.withDiscount(cents);
  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);
