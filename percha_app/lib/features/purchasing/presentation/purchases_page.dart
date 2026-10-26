import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../data/purchasing_api.dart';
import 'suppliers_sheet.dart';

enum _Filter { pending, draft, done, all }

final _ordersProvider = FutureProvider.autoDispose<List<PoSummary>>((ref) => ref.watch(purchasingApiProvider).orders());

/// Órdenes de compra. Por defecto muestra lo que hay que recibir: es lo que el almacén
/// consulta cuando llega un proveedor.
class PurchasesPage extends ConsumerStatefulWidget {
  const PurchasesPage({super.key});

  @override
  ConsumerState<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends ConsumerState<PurchasesPage> {
  _Filter _filter = _Filter.pending;

  bool _matches(PoSummary o) => switch (_filter) {
        _Filter.pending => o.status.receivable,
        _Filter.draft => o.status == PoStatus.draft,
        _Filter.done => o.status == PoStatus.received || o.status == PoStatus.cancelled,
        _Filter.all => true,
      };

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final canWrite = me.can('purchasing.write');
    final date = DateFormat('d MMM', 'es');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras'),
        actions: [
          if (canWrite)
            IconButton(
              tooltip: 'Reposición sugerida',
              icon: const Icon(Icons.auto_graph),
              onPressed: () => context.push('/purchases/suggestions'),
            ),
          IconButton(
            tooltip: 'Proveedores',
            icon: const Icon(Icons.local_shipping_outlined),
            onPressed: () => showSuppliersSheet(context, canEdit: canWrite),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () async {
                final id = await context.push<String>('/purchases/new');
                ref.invalidate(_ordersProvider);
                if (id != null && context.mounted) await context.push('/purchases/$id');
                ref.invalidate(_ordersProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('Nueva orden'),
            )
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                for (final (f, label) in const [
                  (_Filter.pending, 'Por recibir'),
                  (_Filter.draft, 'Borradores'),
                  (_Filter.done, 'Cerradas'),
                  (_Filter.all, 'Todas'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: PerchaSpace.sm),
                    child: ChoiceChip(label: Text(label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ref.watch(_ordersProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
                  data: (all) {
                    final list = all.where(_matches).toList();
                    if (list.isEmpty) {
                      return Center(child: Text(_filter == _Filter.pending ? 'No hay mercadería por recibir' : 'Sin órdenes'));
                    }
                    return RefreshIndicator(
                      onRefresh: () async => ref.invalidate(_ordersProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: PerchaSpace.sm),
                        itemBuilder: (_, i) {
                          final o = list[i];
                          return Card(
                            child: ListTile(
                              title: Text('OC #${o.number} · ${o.supplierName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([
                                o.status.label,
                                if (o.expectedAt != null && o.status.receivable) 'llega ${date.format(o.expectedAt!)}',
                              ].join(' · '),),
                              trailing: Text(formatCents(o.totalCents), style: const TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () async {
                                await context.push('/purchases/${o.id}');
                                ref.invalidate(_ordersProvider);
                              },
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
