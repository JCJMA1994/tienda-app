import '../data/pos_models.dart';
import '../data/sales_api.dart';

/// Borrador de devolución o cambio. Lógica pura con la MISMA fórmula que la API
/// (returns.service.ts), para que la vista previa coincida con lo que se cobrará.
class ReturnDraft {
  const ReturnDraft({this.returning = const {}, this.replacements = const []});

  /// saleItemId -> unidades que vuelven.
  final Map<String, int> returning;

  /// Prendas que se lleva a cambio (vacío = devolución con reembolso).
  final List<({SellableVariant variant, int quantity})> replacements;

  bool get isExchange => replacements.isNotEmpty;
  bool get isEmpty => returning.values.every((q) => q == 0);

  /// Se valora al precio realmente pagado: la línea ya trae su parte del descuento y el
  /// factor total/neto agrega el IGV si los precios no lo incluían.
  int returnedCents(SaleDetail sale) {
    final net = sale.subtotalCents - sale.discountCents;
    final ratio = net > 0 ? sale.totalCents / net : 0;
    var sum = 0;
    for (final line in sale.lines) {
      final q = returning[line.id] ?? 0;
      if (q > 0) sum += ((line.lineTotalCents * q / line.quantity) * ratio).round();
    }
    return sum;
  }

  /// Las prendas nuevas van a precio vigente.
  int replacementCents({required int taxRateBp, required bool pricesIncludeTax}) {
    final net = replacements.fold<int>(0, (a, r) => a + r.variant.priceCents * r.quantity);
    return pricesIncludeTax ? net : net + (net * taxRateBp / 10000).round();
  }

  /// > 0: paga el cliente. < 0: se le devuelve. 0: cambio parejo.
  int difference(SaleDetail sale, {required int taxRateBp, required bool pricesIncludeTax}) =>
      replacementCents(taxRateBp: taxRateBp, pricesIncludeTax: pricesIncludeTax) - returnedCents(sale);

  ReturnDraft setReturning(SaleLine line, int quantity) =>
      ReturnDraft(returning: {...returning, line.id: quantity.clamp(0, line.returnable)}, replacements: replacements);

  ReturnDraft addReplacement(SellableVariant v) {
    final i = replacements.indexWhere((r) => r.variant.id == v.id);
    if (i == -1) return ReturnDraft(returning: returning, replacements: [...replacements, (variant: v, quantity: 1)]);
    final copy = [...replacements];
    copy[i] = (variant: v, quantity: copy[i].quantity + 1);
    return ReturnDraft(returning: returning, replacements: copy);
  }

  ReturnDraft removeReplacement(String variantId) =>
      ReturnDraft(returning: returning, replacements: replacements.where((r) => r.variant.id != variantId).toList());
}
