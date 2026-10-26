import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../billing/data/billing_api.dart';
import '../data/admin_api.dart';

const _statusLabels = {
  'trialing': 'Prueba',
  'active': 'Al día',
  'past_due': 'En gracia',
  'suspended': 'Solo lectura',
  'canceled': 'Cancelada',
};

/// Backoffice de Percha (solo superadmins). Pensado para usarse en la web (pantalla ancha),
/// pero funciona en el teléfono.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  String? _filter; // null = todas
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runBilling() async {
    try {
      final r = await ref.read(adminApiProvider).runBilling();
      ref
        ..invalidate(metricsProvider)
        ..invalidate(tenantsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ciclo: ${r['invoiced']} facturas, ${r['charged']} cobros, ${r['chargeFailed']} rechazos, ${r['suspended']} suspendidas'),
        ),);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backoffice'),
        actions: [TextButton.icon(onPressed: _runBilling, icon: const Icon(Icons.play_arrow), label: const Text('Correr facturación'))],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref
          ..invalidate(metricsProvider)
          ..invalidate(tenantsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            ref.watch(metricsProvider).when(
                  loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => ErrorBanner(errorText(e)),
                  data: (m) => Wrap(
                    spacing: PerchaSpace.md,
                    runSpacing: PerchaSpace.md,
                    children: [
                      _Metric('MRR', formatCents(m.mrrCents), 'activas + en gracia'),
                      _Metric('Tiendas', '${m.tenants}', '${m.active} al día · ${m.trialing} en prueba'),
                      _Metric('En riesgo', '${m.pastDue + m.suspended}', '${m.pastDue} en gracia · ${m.suspended} suspendidas', warn: m.pastDue + m.suspended > 0),
                      _Metric('Pruebas por vencer', '${m.trialsEnding7d}', 'en los próximos 7 días'),
                    ],
                  ),
                ),
            const SizedBox(height: PerchaSpace.xl),
            Row(
              children: [
                Expanded(child: Text('Tiendas', style: text.titleMedium)),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search), isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PerchaSpace.sm),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(label: const Text('Todas'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                for (final e in _statusLabels.entries)
                  ChoiceChip(label: Text(e.value), selected: _filter == e.key, onSelected: (_) => setState(() => _filter = e.key)),
              ],
            ),
            const SizedBox(height: PerchaSpace.md),
            ref.watch(tenantsProvider).when(
                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                  error: (e, _) => ErrorBanner(errorText(e)),
                  data: (all) {
                    final q = _search.text.trim().toLowerCase();
                    final list = all.where((t) => (_filter == null || t.status == _filter) && (q.isEmpty || t.name.toLowerCase().contains(q))).toList();
                    if (list.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Sin tiendas')));
                    return Card(
                      child: Column(
                        children: [
                          for (final t in list)
                            ListTile(
                              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([
                                t.planCode ?? 'sin plan',
                                '${t.products} productos',
                                '${t.members} usuarios',
                                if (t.owedCents > 0) 'debe ${formatCents(t.owedCents)}',
                              ].join(' · '),),
                              trailing: Wrap(
                                spacing: 6,
                                children: [
                                  if (t.blocked) const Pill('Bloqueada', warn: true),
                                  Pill(_statusLabels[t.status] ?? t.status, warn: t.status == 'past_due' || t.status == 'suspended'),
                                ],
                              ),
                              onTap: () => showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (_) => _TenantSheet(tenant: t),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.sub, {this.warn = false});
  final String label;
  final String value;
  final String sub;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Card(
        color: warn ? PerchaColors.warnSoft : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(sub, style: TextStyle(fontSize: PerchaType.meta, color: PerchaColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TenantSheet extends ConsumerWidget {
  const _TenantSheet({required this.tenant});
  final TenantRow tenant;

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
    try {
      await action();
      ref
        ..invalidate(tenantsProvider)
        ..invalidate(metricsProvider)
        ..invalidate(tenantInvoicesProvider(tenant.id));
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  Future<void> _markPaid(BuildContext context, WidgetRef ref, Invoice inv) async {
    final reference = TextEditingController();
    String method = 'plin';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Registrar pago · factura #${inv.number}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Solo después de verificar el dinero en la cuenta (${formatCents(inv.amountCents)}).'),
              const SizedBox(height: PerchaSpace.md),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Medio'),
                items: const [
                  DropdownMenuItem(value: 'plin', child: Text('Plin')),
                  DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
                  DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'other', child: Text('Otro')),
                ],
                onChanged: (v) => setState(() => method = v ?? 'plin'),
              ),
              const SizedBox(height: PerchaSpace.md),
              TextField(controller: reference, decoration: const InputDecoration(labelText: 'N.º de operación o referencia')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, reference.text.trim().length >= 3), child: const Text('Registrar')),
          ],
        ),
      ),
    );
    final ref0 = reference.text.trim();
    reference.dispose();
    if (ok != true || !context.mounted) return;
    await _act(context, ref, () => ref.read(adminApiProvider).markPaid(inv.id, method: method, reference: ref0), 'Pago registrado; la tienda quedó al día');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat("d MMM yyyy", 'es');
    final plans = ref.watch(plansProvider).valueOrNull ?? const <PlanInfo>[];
    final api = ref.read(adminApiProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(tenant.name, style: Theme.of(context).textTheme.titleLarge),
            Text([
              _statusLabels[tenant.status] ?? tenant.status,
              if (tenant.periodEnd != null) 'periodo hasta ${date.format(tenant.periodEnd!)}',
              tenant.lastSaleAt == null ? 'sin ventas' : 'última venta ${date.format(tenant.lastSaleAt!)}',
            ].join(' · '), style: Theme.of(context).textTheme.bodySmall,),
            const SizedBox(height: PerchaSpace.lg),
            Wrap(
              spacing: PerchaSpace.sm,
              runSpacing: PerchaSpace.sm,
              children: [
                OutlinedButton(
                  onPressed: () => _act(context, ref, () => api.update(tenant.id, extendDays: 7), '7 días de cortesía agregados'),
                  child: const Text('+7 días de cortesía'),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: tenant.blocked ? PerchaColors.accent : PerchaColors.warn),
                  onPressed: () => _act(
                    context,
                    ref,
                    () => api.update(tenant.id, status: tenant.blocked ? 'active' : 'suspended'),
                    tenant.blocked ? 'Tienda desbloqueada' : 'Tienda bloqueada',
                  ),
                  child: Text(tenant.blocked ? 'Desbloquear' : 'Bloqueo duro'),
                ),
              ],
            ),
            const SizedBox(height: PerchaSpace.lg),
            DropdownButtonFormField<String>(
              initialValue: plans.any((p) => p.code == tenant.planCode) ? tenant.planCode : null,
              decoration: const InputDecoration(labelText: 'Plan'),
              items: [for (final p in plans) DropdownMenuItem(value: p.code, child: Text('${p.name} · ${formatCents(p.priceCents)}'))],
              onChanged: (v) {
                if (v != null && v != tenant.planCode) _act(context, ref, () => api.update(tenant.id, planCode: v), 'Plan cambiado');
              },
            ),
            const SizedBox(height: PerchaSpace.xl),
            Text('Facturas', style: Theme.of(context).textTheme.titleMedium),
            ...ref.watch(tenantInvoicesProvider(tenant.id)).maybeWhen(
                  data: (list) => [
                    for (final inv in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('#${inv.number} · ${formatCents(inv.amountCents)}'),
                        subtitle: Text(inv.status == 'paid'
                            ? 'Pagada ${date.format(inv.paidAt!)}${inv.method == null ? '' : ' · ${inv.method}'}'
                            : 'Vence ${date.format(inv.dueAt)}',),
                        trailing: inv.status == 'open'
                            ? TextButton(onPressed: () => _markPaid(context, ref, inv), child: const Text('Registrar pago'))
                            : const Pill('Pagada'),
                      ),
                  ],
                  orElse: () => const [Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))],
                ),
          ],
        ),
      ),
    );
  }
}
