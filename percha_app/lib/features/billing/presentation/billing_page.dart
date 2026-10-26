import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../data/billing_api.dart';

/// Facturación de la tienda. Todos ven el estado; solo quien tiene billing.manage paga,
/// cambia el plan o cancela.
class BillingPage extends ConsumerStatefulWidget {
  const BillingPage({super.key});

  @override
  ConsumerState<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends ConsumerState<BillingPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver del checkout, el webhook ya pudo acreditar el pago: se recarga el estado.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(billingOverviewProvider);
  }

  Future<void> _pay(Invoice inv, BillingOverview o) async {
    final option = await showModalBottomSheet<PayOption?>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PayOptionsSheet(invoice: inv, options: payOptions(o.providers)),
    );
    if (option == null || !mounted) return;
    try {
      final url = await ref.read(billingApiProvider).pay(inv.id, option);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack('No se pudo abrir el pago. Intenta de nuevo.');
    } catch (e) {
      if (mounted) _snack(errorText(e));
    }
  }

  Future<void> _setupCard() async {
    try {
      final url = await ref.read(billingApiProvider).cardSetupLink();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) _snack(errorText(e));
    }
  }

  Future<void> _changePlan(PlanInfo plan, BillingOverview o) async {
    final up = plan.priceCents > o.plan.priceCents;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cambiar a ${plan.name}'),
        content: Text(up
            ? 'Los nuevos límites aplican desde ahora. El nuevo precio (${formatCents(plan.priceCents)} al mes) se cobra desde la próxima factura.'
            : 'El nuevo precio aplica desde la próxima factura. Solo se puede si tu uso actual cabe en el plan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cambiar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(billingApiProvider).changePlan(plan.code);
      ref.invalidate(billingOverviewProvider);
      _snack('Plan actualizado a ${plan.name}');
    } catch (e) {
      _snack(errorText(e));
    }
  }

  Future<void> _toggleCancel(BillingOverview o) async {
    final api = ref.read(billingApiProvider);
    try {
      if (o.cancelAtPeriodEnd) {
        await api.resume();
      } else {
        await api.cancel();
      }
      ref.invalidate(billingOverviewProvider);
    } catch (e) {
      _snack(errorText(e));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final canManage = me.can('billing.manage');
    final date = DateFormat("d 'de' MMMM", 'es');
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Plan y facturación')),
      body: ref.watch(billingOverviewProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (o) => RefreshIndicator(
              onRefresh: () async => ref.invalidate(billingOverviewProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  _StatusCard(overview: o, date: date),
                  const SizedBox(height: PerchaSpace.lg),
                  if (o.openInvoices.isNotEmpty) ...[
                    Text('Por pagar', style: text.titleMedium),
                    const SizedBox(height: PerchaSpace.sm),
                    for (final inv in o.openInvoices)
                      Card(
                        child: ListTile(
                          title: Text('Factura #${inv.number} · ${formatCents(inv.amountCents)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Venció el ${date.format(inv.dueAt)}'),
                          trailing: canManage ? FilledButton(onPressed: () => _pay(inv, o), child: const Text('Pagar')) : null,
                        ),
                      ),
                    if (!canManage) Text('Solo el dueño puede pagar. Avísale para evitar el bloqueo.', style: text.bodySmall),
                    const SizedBox(height: PerchaSpace.lg),
                  ],
                  Text('Tu plan: ${o.plan.name} · ${formatCents(o.plan.priceCents)}/mes', style: text.titleMedium),
                  const SizedBox(height: PerchaSpace.sm),
                  _Usage(label: 'Sucursales', used: o.usage.branches, limit: o.plan.limits.branches),
                  _Usage(label: 'Usuarios', used: o.usage.members, limit: o.plan.limits.members),
                  _Usage(label: 'Productos', used: o.usage.products, limit: o.plan.limits.products),
                  if (canManage && o.status != 'canceled') ...[
                    const SizedBox(height: PerchaSpace.lg),
                    Card(
                      child: ListTile(
                        leading: Icon(o.autopay ? Icons.credit_card : Icons.credit_card_off_outlined),
                        title: Text(o.autopay ? 'Cobro automático activo' : 'Activar cobro automático'),
                        subtitle: Text(o.autopay
                            ? 'Cada mes se cobra a tu tarjeta. Puedes cambiarla cuando quieras.'
                            : 'Registra una tarjeta y olvídate de pagar cada mes (Yape no lo permite).'),
                        trailing: TextButton(onPressed: _setupCard, child: Text(o.autopay ? 'Cambiar' : 'Registrar')),
                      ),
                    ),
                  ],
                  if (canManage) ...[
                    const SizedBox(height: PerchaSpace.xl),
                    Text('Planes', style: text.titleMedium),
                    const SizedBox(height: PerchaSpace.sm),
                    ...ref.watch(plansProvider).maybeWhen(
                          data: (plans) => [
                            for (final p in plans)
                              Card(
                                child: ListTile(
                                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text([
                                    _limit(p.limits.branches, 'sucursal', 'sucursales'),
                                    _limit(p.limits.members, 'usuario', 'usuarios'),
                                    _limit(p.limits.products, 'producto', 'productos'),
                                  ].join(' · ')),
                                  trailing: p.code == o.plan.code
                                      ? const Pill('Actual', dark: true)
                                      : TextButton(onPressed: () => _changePlan(p, o), child: Text('${formatCents(p.priceCents)}/mes')),
                                ),
                              ),
                          ],
                          orElse: () => const [SizedBox.shrink()],
                        ),
                    const SizedBox(height: PerchaSpace.lg),
                    if (o.status != 'canceled')
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: o.cancelAtPeriodEnd ? PerchaColors.accent : PerchaColors.warn),
                        onPressed: () => _toggleCancel(o),
                        child: Text(o.cancelAtPeriodEnd ? 'Mantener mi suscripción' : 'Cancelar al final del periodo'),
                      ),
                  ],
                  if (o.history.where((i) => i.status == 'paid').isNotEmpty) ...[
                    const SizedBox(height: PerchaSpace.xl),
                    Text('Pagos', style: text.titleMedium),
                    for (final i in o.history.where((i) => i.status == 'paid'))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Factura #${i.number}'),
                        subtitle: Text('${date.format(i.paidAt!)}${i.method == null ? '' : ' · ${i.method}'}'),
                        trailing: Text(formatCents(i.amountCents)),
                      ),
                  ],
                ],
              ),
            ),
          ),
    );
  }

  String _limit(int? n, String one, String many) => n == null ? '$many ilimitados' : '$n ${n == 1 ? one : many}';
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.overview, required this.date});
  final BillingOverview overview;
  final DateFormat date;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final (title, body, warn) = switch (o.status) {
      'trialing' => ('Periodo de prueba', 'Te quedan ${o.trialDaysLeft} días (hasta el ${date.format(o.trialEndsAt!)}). Luego se emite tu primera factura.', false),
      'active' => (
          'Al día',
          o.cancelAtPeriodEnd
              ? 'Tu suscripción termina el ${date.format(o.currentPeriodEnd!)}. Después quedará en solo lectura.'
              : 'Próxima factura el ${date.format(o.currentPeriodEnd!)}${o.autopay ? ', se cobra sola a tu tarjeta' : ''}.',
          o.cancelAtPeriodEnd,
        ),
      'past_due' => ('Pago pendiente', 'Todo sigue funcionando hasta el ${date.format(o.graceEndsAt!)}. Después la tienda queda en solo lectura.', true),
      'suspended' => ('Tienda en solo lectura', 'Puedes ver tus datos, pero no registrar ventas ni cambios hasta pagar. No se perdió nada.', true),
      _ => ('Suscripción terminada', 'Tus datos siguen guardados. Paga una factura o contáctanos para reactivarla.', true),
    };
    return Container(
      padding: const EdgeInsets.all(PerchaSpace.lg),
      decoration: BoxDecoration(
        color: warn ? PerchaColors.warnSoft : PerchaColors.accentSoft,
        borderRadius: BorderRadius.circular(PerchaRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: PerchaType.title, color: warn ? PerchaColors.warn : PerchaColors.accentInk)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: warn ? PerchaColors.warn : PerchaColors.accentInk)),
        ],
      ),
    );
  }
}

class _Usage extends StatelessWidget {
  const _Usage({required this.label, required this.used, required this.limit});
  final String label;
  final int used;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final ratio = limit == null || limit == 0 ? 0.0 : (used / limit!).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: limit == null ? 0 : ratio,
                minHeight: 8,
                backgroundColor: PerchaColors.surfaceAlt,
                color: ratio >= 0.9 ? PerchaColors.warn : PerchaColors.accent,
              ),
            ),
          ),
          SizedBox(width: 88, child: Text(limit == null ? '$used / ∞' : '$used / $limit', textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _PayOptionsSheet extends StatelessWidget {
  const _PayOptionsSheet({required this.invoice, required this.options});
  final Invoice invoice;
  final List<PayOption> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pagar ${formatCents(invoice.amountCents)}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: PerchaSpace.md),
            for (final o in options)
              Card(
                child: ListTile(
                  title: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(o.detail),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => Navigator.pop(context, o),
                ),
              ),
            // Plin no tiene cobro por API: se paga directo y el equipo de Percha lo verifica.
            Card(
              child: ExpansionTile(
                title: const Text('Plin o transferencia', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Se activa cuando verificamos tu pago'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [SelectableText('${Env.plinInstructions}\nIndica la factura #${invoice.number}.')],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
