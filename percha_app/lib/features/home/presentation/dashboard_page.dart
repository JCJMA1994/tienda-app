import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../../core/money.dart';
import '../../billing/data/billing_api.dart';
import '../../notifications/notifications_api.dart';
import '../../onboarding/data/store_api.dart';
import '../../reports/data/reports_api.dart';
import '../data/dashboard_api.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final branch = ref.watch(currentBranchProvider).valueOrNull;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(onboardingProvider)
              ..invalidate(lowStockProvider)
              ..invalidate(summaryProvider)
              ..invalidate(billingOverviewProvider);
            await ref.read(unreadProvider.notifier).refresh();
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(branch?.name ?? me.tenantName, style: text.bodySmall),
                        Text('Hola, ${me.firstName}', style: text.headlineSmall),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notificaciones',
                    onPressed: () => context.push('/notifications'),
                    icon: Badge(
                      isLabelVisible: ref.watch(unreadProvider) > 0,
                      label: Text('${ref.watch(unreadProvider)}'),
                      backgroundColor: PerchaColors.warn,
                      textColor: PerchaColors.onAccent,
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cuenta y más opciones',
                    icon: const Icon(Icons.account_circle_outlined),
                    onPressed: () => context.go('/more'),
                  ),
                ],
              ),
              const SizedBox(height: PerchaSpace.lg),
              const _BillingBanner(),
              if (me.can('settings.manage')) const _OnboardingCard(),
              if (me.can('reports.read')) const _TodayCard(),
              _QuickActions(me: me),
              const SizedBox(height: PerchaSpace.lg),
              if (me.can('inventory.read')) const _LowStockCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingCard extends ConsumerWidget {
  const _OnboardingCard();

  static const _routes = {'business': '/onboarding/business', 'attributes': '/onboarding/attributes'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(onboardingProvider).valueOrNull;
    if (progress == null || !progress.visible) return const SizedBox.shrink();
    final next = progress.next;
    final route = _routes[next?.key];

    return Padding(
      padding: const EdgeInsets.only(bottom: PerchaSpace.lg),
      child: Container(
        padding: const EdgeInsets.all(PerchaSpace.lg),
        decoration: BoxDecoration(color: PerchaColors.inverse, borderRadius: BorderRadius.circular(PerchaRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Configura tu tienda', style: TextStyle(color: PerchaColors.onInverse, fontWeight: FontWeight.w600, fontSize: PerchaType.strong)),
                Text('${progress.completed} de ${progress.total}', style: TextStyle(color: PerchaColors.onInverse.withValues(alpha: 0.75), fontSize: PerchaType.small)),
              ],
            ),
            const SizedBox(height: PerchaSpace.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.completed / progress.total,
                minHeight: 6,
                backgroundColor: PerchaColors.onInverse.withValues(alpha: 0.2),
                color: PerchaColors.onInverse,
              ),
            ),
            if (next != null) ...[
              const SizedBox(height: PerchaSpace.sm),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: PerchaColors.onInverse, alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
                // Catálogo, equipo y primera venta se completan usando la app; los dos primeros tienen asistente.
                onPressed: route == null ? null : () => context.go(route),
                child: Text('Siguiente: ${next.label}${route == null ? '' : ' →'}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Aviso de facturación (prueba por vencer, pago pendiente, solo lectura). Solo aparece si importa.
class _BillingBanner extends ConsumerWidget {
  const _BillingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(billingOverviewProvider).valueOrNull;
    if (o == null || !o.needsAttention) return const SizedBox.shrink();
    final text = switch (o.status) {
      'trialing' => 'Tu prueba termina en ${o.trialDaysLeft} días. Elige cómo pagar para no interrumpir tu tienda.',
      'past_due' => 'Tienes un pago pendiente. Paga antes de que la tienda quede en solo lectura.',
      'suspended' => 'Tienda en solo lectura por falta de pago. Tus datos están a salvo.',
      'canceled' => 'Tu suscripción terminó. Reactívala para seguir vendiendo.',
      _ => 'Tu suscripción termina al final del periodo.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: PerchaSpace.lg),
      child: Material(
        color: o.status == 'trialing' ? PerchaColors.accentSoft : PerchaColors.warnSoft,
        borderRadius: BorderRadius.circular(PerchaRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(PerchaRadius.card),
          onTap: () => context.push('/billing'),
          child: Padding(
            padding: const EdgeInsets.all(PerchaSpace.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: o.status == 'trialing' ? PerchaColors.accentInk : PerchaColors.warn,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ventas de hoy (zona horaria de la tienda) con acceso a los reportes completos.
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = PeriodPreset.today.resolve(DateTime.now());
    final s = ref.watch(summaryProvider(today)).valueOrNull;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: PerchaSpace.lg),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/reports'),
          child: Padding(
            padding: const EdgeInsets.all(PerchaSpace.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ventas de hoy', style: text.bodySmall),
                      Text(s == null ? '—' : formatCents(s.netSalesCents), style: text.headlineSmall),
                      if (s != null)
                        Text(
                          [
                            '${s.tickets} ticket${s.tickets == 1 ? '' : 's'}',
                            '${s.units} prendas',
                            if (s.grossMarginPct != null) 'margen ${s.grossMarginPct!.toStringAsFixed(0)}%',
                          ].join(' · '),
                          style: text.bodySmall,
                        ),
                    ],
                  ),
                ),
                Text('Reportes', style: TextStyle(color: PerchaColors.accentInk, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: PerchaColors.accentInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Accesos rápidos: las 2–4 tareas más frecuentes del rol, como tarjetas grandes y tocables.
/// El resto vive en la barra o en "Más" (antes había una pila de botones sin jerarquía).
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.me});
  final Me me;

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (me.can('sales.create')) (Icons.point_of_sale, 'Nueva venta', '/pos', true),
      if (me.can('purchasing.receive')) (Icons.inventory_2_outlined, 'Recibir mercadería', '/purchases', false),
      if (me.can('inventory.adjust')) (Icons.swap_horiz, 'Transferir', '/transfers', false),
      if (me.can('reports.read')) (Icons.insights_outlined, 'Reportes', '/reports', false),
      if (me.can('sales.read') && !me.can('reports.read')) (Icons.receipt_long_outlined, 'Ventas del día', '/sales', false),
    ].take(4).toList();
    if (actions.isEmpty) return const SizedBox.shrink();

    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: PerchaSpace.md,
      crossAxisSpacing: PerchaSpace.md,
      childAspectRatio: 1.9,
      children: [
        for (final (icon, label, path, primary) in actions)
          Material(
            color: primary ? PerchaColors.accent : PerchaColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PerchaRadius.card),
              side: primary ? BorderSide.none : BorderSide(color: PerchaColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(PerchaRadius.card),
              onTap: () => context.push(path),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: primary ? PerchaColors.onAccent : PerchaColors.accentInk),
                    Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: primary ? PerchaColors.onAccent : PerchaColors.ink)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LowStockCard extends ConsumerWidget {
  const _LowStockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(lowStockProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Stock bajo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: PerchaSpace.sm),
            items.when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => ErrorBanner(errorText(e)),
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Todo en orden por ahora.'))
                  : Column(
                      children: [
                        for (final i in list.take(5))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(i.productName, style: const TextStyle(fontWeight: FontWeight.w500)),
                            subtitle: Text(i.options),
                            trailing: Pill(i.quantity <= 0 ? 'Agotado' : '${i.quantity} unid.', warn: true),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
