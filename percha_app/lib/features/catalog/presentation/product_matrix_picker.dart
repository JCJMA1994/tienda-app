part of 'product_detail_page.dart';

/// Elegir valores por atributo (para crear un producto o agregar combinaciones).
class _MatrixPicker extends StatefulWidget {
  const _MatrixPicker({required this.attributes, required this.initial});
  final List<Attribute> attributes;
  final Map<String, Set<String>> initial;

  @override
  State<_MatrixPicker> createState() => _MatrixPickerState();
}

class _MatrixPickerState extends State<_MatrixPicker> {
  late final Map<String, Set<String>> _sel = {for (final a in widget.attributes) a.name: {...?widget.initial[a.name]}};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Agregar combinaciones', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Marca los valores nuevos. Las combinaciones que ya existen no se duplican.', style: Theme.of(context).textTheme.bodySmall),
            for (final a in widget.attributes) ...[
              const SizedBox(height: PerchaSpace.lg),
              Text(a.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: PerchaSpace.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in a.values)
                    FilterChip(
                      label: Text(v),
                      selected: _sel[a.name]!.contains(v),
                      onSelected: (on) => setState(() => on ? _sel[a.name]!.add(v) : _sel[a.name]!.remove(v)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: PerchaSpace.xl),
            FilledButton(
              onPressed: _sel.values.any((s) => s.isEmpty) ? null : () => Navigator.pop(context, {for (final e in _sel.entries) e.key: e.value.toList()}),
              child: const Text('Crear combinaciones'),
            ),
          ],
        ),
      ),
    );
  }
}
