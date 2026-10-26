part of 'transfers_pages.dart';

/// Detalle y recepción. Por defecto se asume que llegó todo; se ajusta lo que faltó.
class TransferDetailPage extends ConsumerStatefulWidget {
  const TransferDetailPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<TransferDetailPage> createState() => _TransferDetailPageState();
}

class _TransferDetailPageState extends ConsumerState<TransferDetailPage> with ActionRunner {
  final Map<String, int> _received = {};
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    await runAction(() async {
        await action();
        ref
          ..invalidate(transferProvider(widget.id))
          ..invalidate(transfersProvider);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }, errorAsSnack: true);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final branches = ref.watch(_branchesProvider).valueOrNull ?? const <Branch>[];
    final date = DateFormat("d 'de' MMMM, HH:mm", 'es');
    return Scaffold(
      appBar: AppBar(),
      body: ref.watch(transferProvider(widget.id)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (t) {
              final canAct = me.can('inventory.adjust') && t.status == 'in_transit';
              final canReceive = canAct && (me.branchId == null || me.branchId == t.toBranchId);
              final canCancel = canAct && (me.branchId == null || me.branchId == t.fromBranchId);
              final missing = t.items.fold(0, (a, i) => a + (i.sent - (_received[i.id] ?? i.sent)));
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Row(children: [
                    Expanded(child: Text('Transferencia #${t.number}', style: Theme.of(context).textTheme.headlineSmall)),
                    Pill(t.statusLabel, warn: t.status == 'in_transit'),
                  ]),
                  Text('${_branchName(branches, t.fromBranchId)} → ${_branchName(branches, t.toBranchId)}', style: Theme.of(context).textTheme.titleMedium),
                  Text('Enviada el ${date.format(t.sentAt)}', style: Theme.of(context).textTheme.bodySmall),
                  if (t.notes != null) Text(t.notes!, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: PerchaSpace.lg),
                  Card(
                    child: Column(children: [
                      for (final i in t.items)
                        ListTile(
                          title: Text(i.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(i.received == null
                              ? 'Enviadas ${i.sent}'
                              : i.missing! > 0
                                  ? 'Llegaron ${i.received} de ${i.sent} · faltaron ${i.missing}'
                                  : 'Llegaron ${i.received}'),
                          trailing: canReceive
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                    tooltip: 'Llegó una menos',
                                    icon: const Icon(Icons.remove),
                                    onPressed: (_received[i.id] ?? i.sent) > 0 ? () => setState(() => _received[i.id] = (_received[i.id] ?? i.sent) - 1) : null,
                                  ),
                                  Text('${_received[i.id] ?? i.sent}/${i.sent}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  IconButton(
                                    tooltip: 'Llegó una más',
                                    icon: const Icon(Icons.add),
                                    onPressed: (_received[i.id] ?? i.sent) < i.sent ? () => setState(() => _received[i.id] = (_received[i.id] ?? i.sent) + 1) : null,
                                  ),
                                ])
                              : (i.missing ?? 0) > 0
                                  ? Pill('Faltaron ${i.missing}', warn: true)
                                  : null,
                        ),
                    ]),
                  ),
                  for (final g in t.documents)
                    Card(
                      margin: const EdgeInsets.only(top: PerchaSpace.md),
                      child: ListTile(
                        leading: Icon(Icons.description_outlined, color: PerchaColors.accentInk),
                        title: Text('${g.kindLabel} ${g.code}'),
                        subtitle: Text(g.lastError ?? g.sunatDescription ?? 'Debe acompañar a la mercadería'),
                        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Pill(g.statusLabel, warn: g.status == 'rejected' || g.status == 'error'),
                          if (g.pdfUrl != null)
                            IconButton(tooltip: 'Ver o imprimir la guía', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => launchUrl(Uri.parse(g.pdfUrl!), mode: LaunchMode.externalApplication)),
                          if (g.canRetry)
                            IconButton(
                              tooltip: 'Reintentar envío',
                              icon: const Icon(Icons.refresh),
                              onPressed: () async {
                                await ref.read(einvoiceApiProvider).retry(g.id);
                                ref.invalidate(transferProvider(widget.id));
                              },
                            ),
                        ]),
                      ),
                    ),
                  if (t.receiveNotes != null) ...[const SizedBox(height: PerchaSpace.sm), Text('Nota al recibir: ${t.receiveNotes}', style: Theme.of(context).textTheme.bodySmall)],
                  if (canReceive) ...[
                    const SizedBox(height: PerchaSpace.lg),
                    TextField(controller: _notes, decoration: InputDecoration(labelText: missing > 0 ? 'Qué pasó con lo que faltó' : 'Nota (opcional)')),
                    const SizedBox(height: PerchaSpace.lg),
                    BusyButton(
                      label: missing > 0 ? 'Recibir (faltan $missing)' : 'Recibir todo',
                      busy: busy,
                      onPressed: () => _run(
                        () => ref.read(transferProvider(t.id).notifier).receive(_received, notes: _notes.text.trim()),
                        missing > 0 ? 'Recibida con $missing faltante(s); quedó registrado' : 'Mercadería recibida',
                      ),
                    ),
                  ],
                  if (canCancel) ...[
                    const SizedBox(height: PerchaSpace.sm),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: PerchaColors.warn),
                      onPressed: busy ? null : () => _run(() => ref.read(transferProvider(t.id).notifier).cancel(), 'Cancelada; el stock volvió al origen'),
                      child: const Text('Cancelar transferencia'),
                    ),
                  ],
                ],
              );
            },
          ),
    );
  }
}
