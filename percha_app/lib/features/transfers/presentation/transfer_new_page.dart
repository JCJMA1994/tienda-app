part of 'transfers_pages.dart';

/// Enviar mercadería desde la sucursal actual a otra.
class NewTransferPage extends ConsumerStatefulWidget {
  const NewTransferPage({super.key});

  @override
  ConsumerState<NewTransferPage> createState() => _NewTransferPageState();
}

class _NewTransferPageState extends ConsumerState<NewTransferPage> with ActionRunner {
  String? _to;
  final Map<String, ({String label, int qty, int max})> _items = {};
  final _notes = TextEditingController();
  final _shipment = ShipmentController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _notes.dispose();
    _shipment.dispose();
    super.dispose();
  }

  bool get _needsGuide => ref.read(einvoiceStatusProvider).valueOrNull?.enabled ?? false;

  Future<void> _add(Branch from) async {
    final picked = await showModalBottomSheet<Map<String, ({String label, int qty, int max})>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickSheet(branchId: from.id),
    );
    if (picked != null) setState(() => _items.addAll(picked));
  }

  Future<void> _send(Branch from) async {
    if (_to == null) return setState(() => error = 'Elige la sucursal destino');
    if (_items.isEmpty) return setState(() => error = 'Agrega al menos una prenda');
    if (_needsGuide && !submitForm(_form)) return;
    final t = await runAction(
      () => ref.read(transfersApiProvider).send(
            from: from.id,
            to: _to!,
            items: {for (final e in _items.entries) e.key: e.value.qty},
            notes: _notes.text.trim(),
            shipment: _needsGuide ? _shipment.toJson() : null,
          ),
    );
    if (t == null || !mounted) {
      // Si falta configurar algo para la guía, se indica dónde hacerlo.
      if (mounted && error != null && RegExp('ubigeo|RUC|serie', caseSensitive: false).hasMatch(error!)) {
        setState(() => error = '$error. Revisa Más → Sucursales, Datos del negocio o Comprobantes electrónicos.');
      }
      return;
    }
    final guide = t.documents.where((d) => d.kind == 'guia_remitente').firstOrNull;
    if (guide != null) snack('Guía ${guide.code}: ${guide.statusLabel.toLowerCase()}. Llévala impresa con la mercadería.');
    context.pop(t.id);
  }

  @override
  Widget build(BuildContext context) {
    final from = ref.watch(currentBranchProvider).valueOrNull;
    final branches = ref.watch(_branchesProvider).valueOrNull ?? const <Branch>[];
    final units = _items.values.fold(0, (a, i) => a + i.qty);
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar mercadería')),
      body: from == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              children: [
                if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
                Text('Desde: ${from.name}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: PerchaSpace.md),
                DropdownButtonFormField<String>(
                  value: _to,
                  decoration: const InputDecoration(labelText: 'Hacia'),
                  items: [for (final b in branches.where((b) => b.id != from.id)) DropdownMenuItem(value: b.id, child: Text(b.name))],
                  onChanged: (v) => setState(() => _to = v),
                ),
                const SizedBox(height: PerchaSpace.md),
                TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ej. reposición del fin de semana')),
                if (ref.watch(einvoiceStatusProvider).valueOrNull?.enabled ?? false) ...[
                  const SizedBox(height: PerchaSpace.lg),
                  Form(key: _form, child: ShipmentForm(controller: _shipment, units: units)),
                ],
                const SizedBox(height: PerchaSpace.xl),
                Row(children: [
                  Expanded(child: Text('Prendas · $units unid.', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton.icon(onPressed: () => _add(from), icon: const Icon(Icons.add), label: const Text('Agregar')),
                ]),
                for (final e in _items.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.value.label),
                    subtitle: Text('Hay ${e.value.max} en ${from.name}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Menos',
                        icon: const Icon(Icons.remove),
                        onPressed: () => setState(() {
                          if (e.value.qty <= 1) {
                            _items.remove(e.key);
                          } else {
                            _items[e.key] = (label: e.value.label, qty: e.value.qty - 1, max: e.value.max);
                          }
                        }),
                      ),
                      Text('${e.value.qty}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      IconButton(
                        tooltip: 'Más',
                        icon: const Icon(Icons.add),
                        onPressed: e.value.qty >= e.value.max ? null : () => setState(() => _items[e.key] = (label: e.value.label, qty: e.value.qty + 1, max: e.value.max)),
                      ),
                    ]),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: BusyButton(label: 'Enviar $units prendas', busy: busy, onPressed: from == null || units == 0 ? null : () => _send(from)),
        ),
      ),
    );
  }
}

/// Buscar un producto y elegir cuántas de cada variante enviar (con tope en el stock del origen).
class _PickSheet extends ConsumerStatefulWidget {
  const _PickSheet({required this.branchId});
  final String branchId;

  @override
  ConsumerState<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends ConsumerState<_PickSheet> {
  Timer? _debounce;
  List<ProductListItem> _results = const [];
  Product? _product;
  final Map<String, TextEditingController> _qty = {};

  @override
  void initState() {
    super.initState();
    _find('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _find(String q) async {
    final page = await ref.read(catalogApiProvider).products(search: q.trim().isEmpty ? null : q.trim(), branchId: widget.branchId);
    if (mounted) setState(() => _results = page.items.where((p) => p.totalStock > 0).toList());
  }

  void _done() {
    final p = _product!;
    final out = <String, ({String label, int qty, int max})>{};
    for (final v in p.variants) {
      final max = v.stockIn(widget.branchId).quantity;
      final q = (int.tryParse(_qty[v.id]?.text ?? '') ?? 0).clamp(0, max);
      if (q > 0) out[v.id] = (label: [p.name, if (v.options.isNotEmpty) v.options.values.join(' · ')].join(' · '), qty: q, max: max);
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
          child: p == null
              ? Column(children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Buscar producto con stock', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () => _find(v));
                    },
                  ),
                  Expanded(
                    child: ListView(children: [
                      for (final r in _results)
                        ListTile(
                          title: Text(r.name),
                          subtitle: Text('${r.totalStock} en esta sucursal'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final full = await ref.read(catalogApiProvider).product(r.id);
                            if (mounted) setState(() => _product = full);
                          },
                        ),
                    ]),
                  ),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    IconButton(tooltip: 'Otro producto', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _product = null)),
                    Expanded(child: Text(p.name, style: Theme.of(context).textTheme.titleLarge)),
                  ]),
                  Expanded(
                    child: ListView(children: [
                      for (final v in p.variants.where((v) => v.stockIn(widget.branchId).quantity > 0))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Expanded(child: Text('${v.options.isEmpty ? 'Única' : v.options.values.join(' · ')} · hay ${v.stockIn(widget.branchId).quantity}')),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _qty.putIfAbsent(v.id, TextEditingController.new),
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(hintText: '0', isDense: true),
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                  FilledButton(onPressed: _done, child: const Text('Agregar')),
                ]),
        ),
      ),
    );
  }
}
