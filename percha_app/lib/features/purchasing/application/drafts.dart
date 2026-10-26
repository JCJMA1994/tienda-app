import '../data/purchasing_api.dart';

/// Línea de una orden en edición (antes de guardarla).
class PoDraftLine {
  const PoDraftLine({required this.variantId, required this.label, required this.quantity, required this.unitCostCents});
  final String variantId;

  /// "Vestido midi · M · Negro"
  final String label;
  final int quantity;
  final int unitCostCents;

  int get totalCents => quantity * unitCostCents;
  PoDraftLine copyWith({int? quantity, int? unitCostCents}) =>
      PoDraftLine(variantId: variantId, label: label, quantity: quantity ?? this.quantity, unitCostCents: unitCostCents ?? this.unitCostCents);
}

/// Orden en edición. La API exige una línea por variante: agregar la misma variante suma.
class PoDraft {
  const PoDraft([this.lines = const []]);
  final List<PoDraftLine> lines;

  int get totalCents => lines.fold(0, (a, l) => a + l.totalCents);
  int get units => lines.fold(0, (a, l) => a + l.quantity);
  bool get isEmpty => lines.isEmpty;

  PoDraft merge(Iterable<PoDraftLine> incoming) {
    final map = {for (final l in lines) l.variantId: l};
    for (final n in incoming) {
      if (n.quantity <= 0) continue;
      final current = map[n.variantId];
      map[n.variantId] = current == null ? n : current.copyWith(quantity: current.quantity + n.quantity, unitCostCents: n.unitCostCents);
    }
    return PoDraft(map.values.toList());
  }

  PoDraft update(String variantId, {int? quantity, int? unitCostCents}) => PoDraft([
        for (final l in lines)
          if (l.variantId != variantId)
            l
          else if ((quantity ?? l.quantity) > 0)
            l.copyWith(quantity: quantity, unitCostCents: unitCostCents),
      ]);

  List<PoItemInput> toItems() => [for (final l in lines) (variantId: l.variantId, quantity: l.quantity, unitCostCents: l.unitCostCents)];

  static PoDraft fromOrder(PurchaseOrder o) => PoDraft([
        for (final l in o.lines)
          PoDraftLine(
            variantId: l.variantId,
            label: [l.productName, if (l.optionsLabel.isNotEmpty) l.optionsLabel].join(' · '),
            quantity: l.ordered,
            unitCostCents: l.unitCostCents,
          ),
      ]);
}

enum ScanResult { counted, notInOrder, alreadyComplete }

/// Recepción en curso. Pensada para contar al desempacar: cada escaneo suma uno a su línea,
/// con tope en lo pendiente (la API rechazaría recibir de más).
class ReceiveDraft {
  const ReceiveDraft({required this.order, this.counts = const {}, this.costs = const {}});
  final PurchaseOrder order;

  /// itemId -> unidades a recibir ahora.
  final Map<String, int> counts;

  /// itemId -> costo de factura si difiere del de la orden.
  final Map<String, int> costs;

  List<PoLine> get pendingLines => order.lines.where((l) => l.pending > 0).toList();
  int get units => counts.values.fold(0, (a, b) => a + b);
  bool get isEmpty => units == 0;
  bool get completesOrder => pendingLines.every((l) => (counts[l.id] ?? 0) == l.pending);

  ReceiveDraft set(PoLine line, int quantity) =>
      ReceiveDraft(order: order, counts: {...counts, line.id: quantity.clamp(0, line.pending)}, costs: costs);

  ReceiveDraft setCost(PoLine line, int? cents) {
    final next = {...costs};
    if (cents == null || cents == line.unitCostCents) {
      next.remove(line.id);
    } else {
      next[line.id] = cents;
    }
    return ReceiveDraft(order: order, counts: counts, costs: next);
  }

  ReceiveDraft all() => ReceiveDraft(order: order, counts: {for (final l in pendingLines) l.id: l.pending}, costs: costs);

  (ReceiveDraft, ScanResult) scan(String variantId) {
    final line = order.lines.where((l) => l.variantId == variantId).firstOrNull;
    if (line == null) return (this, ScanResult.notInOrder);
    final current = counts[line.id] ?? 0;
    if (current >= line.pending) return (this, ScanResult.alreadyComplete);
    return (set(line, current + 1), ScanResult.counted);
  }

  List<({String itemId, int quantity, int? unitCostCents})> toItems() => [
        for (final e in counts.entries)
          if (e.value > 0) (itemId: e.key, quantity: e.value, unitCostCents: costs[e.key]),
      ];
}
