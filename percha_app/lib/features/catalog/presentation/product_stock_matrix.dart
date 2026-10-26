part of 'product_detail_page.dart';

/// Matriz como en el mockup: columnas = primer atributo (talla), filas = segundo (color).
/// Con 1 atributo es una sola fila; con 3 o más, una lista de combinaciones.
class _StockMatrix extends StatelessWidget {
  const _StockMatrix({required this.product, required this.branchId, required this.selectedId, required this.onSelect});
  final Product product;
  final String branchId;
  final String? selectedId;
  final ValueChanged<Variant> onSelect;

  @override
  Widget build(BuildContext context) {
    final attrs = product.attributes;
    if (attrs.length > 2 || attrs.isEmpty) {
      return Wrap(
        spacing: PerchaSpace.sm,
        runSpacing: PerchaSpace.sm,
        children: [
          for (final v in product.variants)
            SizedBox(width: 120, child: _Cell(variant: v, branchId: branchId, selected: v.id == selectedId, onSelect: onSelect, label: v.options.values.join(' · '))),
        ],
      );
    }
    final cols = attrs[0];
    final rows = attrs.length == 2 ? attrs[1].values : const [''];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(56),
        columnWidths: const {0: FixedColumnWidth(80)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              const SizedBox(),
              for (final c in cols.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(c, textAlign: TextAlign.center, style: TextStyle(fontSize: PerchaType.meta, fontWeight: FontWeight.w600, color: PerchaColors.muted)),
                ),
            ],
          ),
          for (final r in rows)
            TableRow(
              children: [
                Text(r, style: const TextStyle(fontSize: PerchaType.small)),
                for (final c in cols.values)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: switch (product.variantFor({cols.name: c, if (attrs.length == 2) attrs[1].name: r})) {
                      final Variant v => _Cell(variant: v, branchId: branchId, selected: v.id == selectedId, onSelect: onSelect),
                      null => Container(
                          height: 44,
                          alignment: Alignment.center,
                          child: Text('—', style: TextStyle(color: PerchaColors.borderStrong)),
                        ),
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.variant, required this.branchId, required this.selected, required this.onSelect, this.label});
  final Variant variant;
  final String branchId;
  final bool selected;
  final ValueChanged<Variant> onSelect;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final s = variant.stockIn(branchId);
    final out = s.quantity <= 0;
    final low = !out && s.quantity <= (s.minQuantity > 0 ? s.minQuantity : 2);
    final (bg, fg) = out
        ? (PerchaColors.border, PerchaColors.muted)
        : low
            ? (PerchaColors.warnSoft, PerchaColors.warn)
            : (PerchaColors.surfaceAlt, PerchaColors.ink);
    return Semantics(
      button: true,
      selected: selected,
      label: '${variant.options.values.join(' ')}: ${s.quantity}',
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? PerchaColors.accent : Colors.transparent, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(variant),
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label == null ? '${s.quantity}' : '$label\n${s.quantity}',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, color: fg, fontSize: label == null ? PerchaType.strong : PerchaType.meta),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 4),
            Text(t, style: TextStyle(fontSize: PerchaType.caption, color: PerchaColors.muted)),
          ],
        );
    return Wrap(spacing: 12, children: [dot(PerchaColors.warnSoft, 'Bajo'), dot(PerchaColors.border, 'Agotado')]);
  }
}
