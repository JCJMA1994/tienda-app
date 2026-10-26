import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../../core/widgets/thumb.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/data/store_api.dart';
import '../data/catalog_api.dart';

/// Productos con stock en la sucursal actual. Búsqueda con espera (debounce) para no
/// disparar una petición por cada letra, y paginado con "Cargar más".
class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  final List<ProductListItem> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _lowOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _items.clear();
    _page = 0;
    _hasMore = true;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branch = await ref.read(currentBranchProvider.future);
      final query = _search.text.trim();
      final page = await ref.read(catalogApiProvider).products(
            search: query.isEmpty ? null : query,
            branchId: branch.id,
            page: _page + 1,
          );
      if (!mounted || query != _search.text.trim()) return; // llegó tarde: el usuario ya escribió otra cosa
      setState(() {
        _items.addAll(page.items);
        _page = page.page;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final visible = _lowOnly ? _items.where((p) => p.lowVariants > 0).toList() : _items;
    final lowCount = _items.where((p) => p.lowVariants > 0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        actions: [
          if (me.can('catalog.write'))
            IconButton(
              tooltip: 'Importar desde Excel',
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: () async {
                await context.push('/products/import');
                await _reload();
              },
            ),
        ],
      ),
      floatingActionButton: me.can('catalog.write')
          ? FloatingActionButton.extended(
              onPressed: () async {
                final id = await context.push<String>('/products/new');
                if (id != null && context.mounted) {
                  await _reload();
                  if (context.mounted) await context.push('/products/$id');
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              sliver: SliverList.list(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(hintText: 'Buscar por nombre, SKU o código', prefixIcon: Icon(Icons.search)),
                  ),
                  const SizedBox(height: PerchaSpace.md),
                  Wrap(
                    spacing: PerchaSpace.sm,
                    children: [
                      ChoiceChip(label: const Text('Todos'), selected: !_lowOnly, onSelected: (_) => setState(() => _lowOnly = false)),
                      ChoiceChip(
                        label: Text('Stock bajo${lowCount > 0 ? ' · $lowCount' : ''}'),
                        selected: _lowOnly,
                        selectedColor: PerchaColors.warnSoft,
                        onSelected: (_) => setState(() => _lowOnly = true),
                      ),
                    ],
                  ),
                  if (_error != null) ...[const SizedBox(height: PerchaSpace.md), ErrorBanner(_error!)],
                ],
              ),
            ),
            if (visible.isEmpty && !_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _search.text.isNotEmpty ? 'Sin resultados' : 'Aún no hay productos. Crea uno o importa tu catálogo.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                sliver: SliverList.separated(
                  itemCount: visible.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: PerchaSpace.sm),
                  itemBuilder: (_, i) {
                    if (i == visible.length) {
                      if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                      if (_hasMore && !_lowOnly) return OutlinedButton(onPressed: _loadMore, child: const Text('Cargar más'));
                      return const SizedBox.shrink();
                    }
                    final p = visible[i];
                    return _ProductTile(
                      product: p,
                      onTap: () async {
                        await context.push('/products/${p.id}');
                        await _reload(); // el stock pudo cambiar con un ajuste
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final ProductListItem product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final low = product.lowVariants > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ProductThumb(url: product.imageUrl),
              const SizedBox(width: PerchaSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: PerchaType.strong)),
                    const SizedBox(height: 2),
                    Text(
                      '${product.variantCount} variante${product.variantCount == 1 ? '' : 's'} · ${product.skuBase}${product.active ? '' : ' · Inactivo'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatCents(product.priceCents), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    low ? '${product.lowVariants} variante${product.lowVariants == 1 ? '' : 's'} baja${product.lowVariants == 1 ? '' : 's'}' : '${product.totalStock} en stock',
                    style: TextStyle(fontSize: PerchaType.meta, fontWeight: FontWeight.w500, color: low ? PerchaColors.warn : PerchaColors.inkSoft),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
