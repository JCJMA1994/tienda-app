part of 'pos_page.dart';

class _Catalog extends ConsumerStatefulWidget {
  const _Catalog({required this.branch});
  final Branch branch;

  @override
  ConsumerState<_Catalog> createState() => _CatalogState();
}

class _CatalogState extends ConsumerState<_Catalog> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  void _addToCart(SellableVariant v) => _toast(_add(v).message);

  /// Agrega al ticket y devuelve qué pasó (para el aviso o la cámara en modo continuo).
  ScanFeedback _add(SellableVariant v) {
    final name = '${v.productName} ${v.optionsLabel}'.trim();
    return switch (ref.read(cartProvider.notifier).add(v)) {
      AddResult.added || AddResult.incremented => (message: '+1 $name', ok: true),
      AddResult.outOfStock => (message: 'No hay más stock de $name', ok: false),
      AddResult.notSellable => (message: '${v.productName} no está a la venta', ok: false),
    };
  }

  /// Un código leído: prenda → al ticket; vale → se avisa que se usa al cobrar.
  Future<ScanFeedback> _onCode(String code) async {
    if (isCreditCode(code)) return (message: 'Es un vale: úsalo al cobrar (medio de pago "Vale")', ok: false);
    try {
      final hit = await lookupVariant(ref, code, widget.branch.id);
      return hit == null ? (message: 'No encontramos el código $code', ok: false) : _add(hit);
    } catch (e) {
      return (message: errorText(e), ok: false);
    }
  }

  /// Enter en el buscador: primero se intenta como código exacto (lectores USB/Bluetooth
  /// escriben el código y envían Enter); si no existe, queda como búsqueda por nombre.
  Future<void> _submit(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;
    if (isCreditCode(code)) {
      _toast('Es un vale: úsalo al cobrar (medio de pago "Vale")');
      _search.clear();
      return;
    }
    try {
      final hit = await lookupVariant(ref, code, widget.branch.id);
      if (!mounted) return;
      if (hit != null) {
        _addToCart(hit);
        _search.clear();
        setState(() => _query = '');
      } else {
        setState(() => _query = code);
      }
    } catch (e) {
      if (mounted) _toast(errorText(e));
    } finally {
      if (mounted) _focus.requestFocus(); // listo para el siguiente escaneo
    }
  }

  /// Cámara en modo continuo: se pasan varias prendas seguidas sin volver a abrirla.
  Future<void> _scan() async {
    await scanContinuous(context, title: 'Agregar al ticket', onCode: _onCode);
    if (mounted) _focus.requestFocus();
  }

  Future<void> _openProduct(ProductSummary p) async {
    final v = await pickVariant(context, productId: p.id, branchId: widget.branch.id);
    if (v != null) _addToCart(v);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(productSearchProvider((branchId: widget.branch.id, query: _query)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(PerchaSpace.xl, PerchaSpace.lg, PerchaSpace.xl, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Escanea o busca un producto',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onSubmitted: _submit,
                ),
              ),
              const SizedBox(width: PerchaSpace.sm),
              IconButton.outlined(
                tooltip: 'Escanear con la cámara',
                iconSize: 24,
                constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _scan,
              ),
            ],
          ),
          const SizedBox(height: PerchaSpace.lg),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorBanner(errorText(e)),
              data: (items) => items.isEmpty
                  ? Center(child: Text(_query.isEmpty ? 'Aún no hay productos' : 'Sin resultados para "$_query"'))
                  : GridView.builder(
                      padding: const EdgeInsets.only(bottom: PerchaSpace.xl),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisExtent: 120,
                        crossAxisSpacing: PerchaSpace.md,
                        mainAxisSpacing: PerchaSpace.md,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _ProductCard(product: items[i], onTap: () => _openProduct(items[i])),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});
  final ProductSummary product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final out = product.totalStock <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(PerchaSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // La foto ayuda a encontrar la prenda más rápido que el nombre.
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ProductThumb(url: product.imageUrl, size: 40),
                const SizedBox(width: PerchaSpace.sm),
                Expanded(child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Flexible: en tarjetas angostas, un precio largo no desborda la fila.
                  Flexible(child: Text(formatCents(product.priceCents), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                  out ? const Pill('Agotado', warn: true) : Text('${product.totalStock} unid.', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
