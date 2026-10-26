import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/percha_widgets.dart';
import '../onboarding/data/store_api.dart';
import '../printing/print_actions.dart';
import 'cash_api.dart';

final _sessionsProvider = FutureProvider.autoDispose.family<List<CashSessionRow>, String>((ref, branchId) => ref.watch(cashApiProvider).list(branchId));

/// Cierres de caja de la sucursal, para revisar o reimprimir.
class CashSessionsPage extends ConsumerWidget {
  const CashSessionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(currentBranchProvider).valueOrNull;
    final date = DateFormat("EEE d MMM · HH:mm", 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Cierres de caja')),
      body: branch == null
          ? const Center(child: CircularProgressIndicator())
          : ref.watch(_sessionsProvider(branch.id)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
                data: (list) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: PerchaSpace.sm),
                  itemBuilder: (_, i) {
                    final s = list[i];
                    final diff = s.differenceCents;
                    return Card(
                      child: ListTile(
                        title: Text(date.format(s.openedAt)),
                        subtitle: Text(s.status == 'open'
                            ? 'Abierta'
                            : diff == null || diff == 0
                                ? 'Cerrada · cuadró'
                                : 'Cerrada · ${diff > 0 ? 'sobrante' : 'faltante'} ${formatCents(diff.abs())}',),
                        trailing: IconButton(
                          tooltip: s.status == 'open' ? 'Imprimir corte parcial' : 'Reimprimir cierre',
                          icon: const Icon(Icons.print_outlined),
                          onPressed: () => printCashReport(context, ref, s.id),
                        ),
                        leading: Icon(diff != null && diff != 0 ? Icons.error_outline : Icons.point_of_sale_outlined, color: diff != null && diff != 0 ? PerchaColors.warn : PerchaColors.muted),
                      ),
                    );
                  },
                ),
              ),
    );
  }
}
