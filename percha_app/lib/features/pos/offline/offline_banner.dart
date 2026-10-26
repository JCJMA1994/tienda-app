import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import 'offline_queue.dart';
import 'pos_snapshot.dart';

/// Aviso en el POS cuando hay ventas guardadas sin conexión. Mantiene viva la foto local
/// (y la refresca cada 10 min) para que el POS pueda vender si se cae el internet.
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key, required this.branchId});
  final String branchId;

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  Timer? _refresh;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(minutes: 10), (_) => ref.read(posSnapshotProvider(widget.branchId).notifier).refresh());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final done = await ref.read(offlineQueueProvider.notifier).sync();
    if (done > 0) await ref.read(posSnapshotProvider(widget.branchId).notifier).refresh();
    if (!mounted) return;
    setState(() => _syncing = false);
    final left = ref.read(offlineQueueProvider).length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(done > 0 ? '$done venta${done == 1 ? '' : 's'} sincronizada${done == 1 ? '' : 's'}${left > 0 ? ' · quedan $left' : ''}' : 'Aún sin conexión: se reintentará sola'),
    ),);
  }

  void _review(List<PendingSale> failed) {
    final date = DateFormat('d MMM HH:mm', 'es');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text('Ventas que la tienda debe revisar', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('El servidor no las aceptó. La prenda ya salió: corrige lo indicado y reintenta, o regístrala manualmente.', style: Theme.of(ctx).textTheme.bodySmall),
            for (final p in failed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${formatCents(p.totalCents)} · ${date.format(p.createdAt)}'),
                subtitle: Text(p.error ?? ''),
                trailing: Wrap(children: [
                  IconButton(
                    tooltip: 'Reintentar',
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(offlineQueueProvider.notifier).retry(p.key);
                    },
                  ),
                  IconButton(
                    tooltip: 'Descartar',
                    icon: Icon(Icons.delete_outline, color: PerchaColors.warn),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          title: const Text('¿Descartar esta venta?'),
                          content: const Text('No se registrará nunca. Hazlo solo si ya la registraste de otra forma.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Volver')),
                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Descartar')),
                          ],
                        ),
                      );
                      if (ok == true && ctx.mounted) {
                        Navigator.pop(ctx);
                        await ref.read(offlineQueueProvider.notifier).discard(p.key);
                      }
                    },
                  ),
                ],),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(posSnapshotProvider(widget.branchId)); // mantiene la foto cargada
    final queue = ref.watch(offlineQueueProvider);
    if (queue.isEmpty) return const SizedBox.shrink();
    final failed = queue.where((p) => p.error != null).toList();
    final pending = queue.length - failed.length;
    final c = PerchaColors.palette;
    return Material(
      color: c.warnSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(Icons.cloud_off_outlined, color: c.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                if (pending > 0) '$pending venta${pending == 1 ? '' : 's'} sin sincronizar',
                if (failed.isNotEmpty) '${failed.length} por revisar',
              ].join(' · '),
              style: TextStyle(color: c.warn, fontWeight: FontWeight.w600),
            ),
          ),
          if (failed.isNotEmpty) TextButton(onPressed: () => _review(failed), child: const Text('Revisar')),
          if (pending > 0)
            TextButton(
              onPressed: _syncing ? null : _sync,
              child: _syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sincronizar'),
            ),
        ],),
      ),
    );
  }
}
