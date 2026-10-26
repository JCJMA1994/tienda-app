import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/percha_widgets.dart';
import 'notifications_api.dart';

const _icons = {
  'transfer.incoming': Icons.local_shipping_outlined,
  'stock.low': Icons.inventory_2_outlined,
  'einvoice.rejected': Icons.description_outlined,
  'billing.past_due': Icons.workspace_premium_outlined,
  'billing.suspended': Icons.lock_outline,
  'team.joined': Icons.person_add_alt,
  'catalog.order': Icons.shopping_basket_outlined,
  'layaway.expired': Icons.bookmark_border,
};

/// Bandeja de avisos: agrupada por día, las no leídas resaltadas, y cada aviso lleva a donde
/// hay que actuar.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    if (!n.read) {
      try {
        await ref.read(notificationsApiProvider).read(n.id);
      } catch (_) {}
      ref.invalidate(notificationsProvider);
      await ref.read(unreadProvider.notifier).refresh();
    }
    final link = n.safeLink;
    if (link != null && context.mounted) await context.push(link);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    String group(DateTime d) {
      final days = DateTime(today.year, today.month, today.day).difference(DateTime(d.year, d.month, d.day)).inDays;
      return days == 0 ? 'Hoy' : days == 1 ? 'Ayer' : DateFormat("d 'de' MMMM", 'es').format(d);
    }

    final time = DateFormat('HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationsApiProvider).readAll();
              ref.invalidate(notificationsProvider);
              await ref.read(unreadProvider.notifier).refresh();
            },
            child: const Text('Marcar todo como leído'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: ref.watch(notificationsProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(padding: const EdgeInsets.all(20), children: [ErrorBanner(errorText(e))]),
              data: (items) {
                if (items.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 120),
                    Icon(Icons.notifications_none, size: 48, color: PerchaColors.muted),
                    const SizedBox(height: 12),
                    Center(child: Text('Estás al día', style: Theme.of(context).textTheme.titleMedium)),
                  ],);
                }
                final groups = <String, List<AppNotification>>{};
                for (final n in items) {
                  groups.putIfAbsent(group(n.createdAt), () => []).add(n);
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                    for (final g in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Text(g.key, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      Card(
                        child: Column(
                          children: [
                            for (final n in g.value)
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: n.read ? PerchaColors.surfaceAlt : PerchaColors.accentSoft,
                                  foregroundColor: n.read ? PerchaColors.muted : PerchaColors.accentInk,
                                  child: Icon(_icons[n.type] ?? Icons.notifications_outlined, size: 20),
                                ),
                                title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w400 : FontWeight.w600)),
                                subtitle: Text(n.body),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(time.format(n.createdAt), style: Theme.of(context).textTheme.bodySmall),
                                    if (!n.read)
                                      Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(color: PerchaColors.accentInk, shape: BoxShape.circle),
                                      ),
                                  ],
                                ),
                                onTap: () => _open(context, ref, n),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
      ),
    );
  }
}
