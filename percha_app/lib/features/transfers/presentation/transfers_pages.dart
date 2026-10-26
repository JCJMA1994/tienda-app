import '../../../core/widgets/action_runner.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../../catalog/data/catalog_api.dart';
import '../../onboarding/data/store_api.dart';
import '../../../core/forms/app_form.dart';
import '../../einvoice/data/einvoice_api.dart';
import '../data/transfers_api.dart';
import 'shipment_form.dart';

part 'transfer_new_page.dart';
part 'transfer_detail_page.dart';

final _branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) => ref.watch(storeApiProvider).branches());

String _branchName(List<Branch> branches, String id) => branches.where((b) => b.id == id).firstOrNull?.name ?? 'Sucursal';

/// Transferencias de la sucursal actual: lo que le llega (para recibir) y lo que envió.
class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends ConsumerState<TransfersPage> {
  bool _incoming = true;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final branch = ref.watch(currentBranchProvider).valueOrNull;
    final branches = ref.watch(_branchesProvider).valueOrNull ?? const <Branch>[];
    final date = DateFormat('d MMM, HH:mm', 'es');

    return Scaffold(
      appBar: AppBar(title: const Text('Transferencias')),
      floatingActionButton: me.can('inventory.adjust') && branches.length > 1
          ? FloatingActionButton.extended(
              onPressed: () async {
                final id = await context.push<String>('/transfers/new');
                ref.invalidate(transfersProvider);
                if (id != null && context.mounted) await context.push('/transfers/$id');
              },
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Enviar'),
            )
          : null,
      body: branch == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: SegmentedButton<bool>(
                    segments: const [ButtonSegment(value: true, label: Text('Me llegan')), ButtonSegment(value: false, label: Text('Envié'))],
                    selected: {_incoming},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _incoming = s.first),
                  ),
                ),
                if (branches.length < 2)
                  const Padding(padding: EdgeInsets.all(24), child: Text('Necesitas al menos dos sucursales para transferir mercadería.')),
                Expanded(
                  child: ref.watch(transfersProvider).when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
                        data: (all) {
                          final list = all.where((t) => _incoming ? t.toBranchId == branch.id : t.fromBranchId == branch.id).toList()
                            // Lo que está en tránsito primero: es lo que hay que atender.
                            ..sort((a, b) => (a.status == 'in_transit' ? 0 : 1).compareTo(b.status == 'in_transit' ? 0 : 1));
                          if (list.isEmpty) return Center(child: Text(_incoming ? 'No hay mercadería en camino' : 'Aún no enviaste transferencias'));
                          return RefreshIndicator(
                            onRefresh: () async => ref.invalidate(transfersProvider),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const SizedBox(height: PerchaSpace.sm),
                              itemBuilder: (_, i) {
                                final t = list[i];
                                final other = _incoming ? 'Desde ${_branchName(branches, t.fromBranchId)}' : 'Hacia ${_branchName(branches, t.toBranchId)}';
                                return Card(
                                  child: ListTile(
                                    title: Text('Transferencia #${t.number}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text('$other · ${date.format(t.sentAt)}'),
                                    trailing: Pill(t.statusLabel, warn: t.status == 'in_transit' && _incoming),
                                    onTap: () async {
                                      await context.push('/transfers/${t.id}');
                                      ref.invalidate(transfersProvider);
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

