import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../data/reports_api.dart';

/// Panel de reportes. Cada bloque carga por separado: si uno falla o tarda, los demás se ven.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  PeriodPreset _preset = PeriodPreset.month;
  int _deadDays = 60;

  @override
  Widget build(BuildContext context) {
    final period = _preset.resolve(DateTime.now());
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: RefreshIndicator(
        onRefresh: () async => ref
          ..invalidate(summaryProvider)
          ..invalidate(dailyProvider)
          ..invalidate(topProvider)
          ..invalidate(attributesRotationProvider)
          ..invalidate(deadStockProvider)
          ..invalidate(valuationProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            SegmentedButton<PeriodPreset>(
              segments: [for (final p in PeriodPreset.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_preset},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _preset = s.first),
            ),
            const SizedBox(height: PerchaSpace.lg),
            _SummaryGrid(period: period),
            if (_preset != PeriodPreset.today) ...[
              const SizedBox(height: PerchaSpace.xl),
              Text('Ventas por día', style: text.titleMedium),
              const SizedBox(height: PerchaSpace.sm),
              _DailyChart(period: period),
            ],
            const SizedBox(height: PerchaSpace.xl),
            Text('Más vendidos', style: text.titleMedium),
            const SizedBox(height: PerchaSpace.sm),
            _TopProducts(period: period),
            const SizedBox(height: PerchaSpace.xl),
            Text('Rotación por talla y color', style: text.titleMedium),
            const SizedBox(height: 4),
            Text('Porcentaje vendido sobre lo que hubo (vendidas + stock actual).', style: text.bodySmall),
            const SizedBox(height: PerchaSpace.sm),
            _Rotation(period: period),
            const SizedBox(height: PerchaSpace.xl),
            Row(
              children: [
                Expanded(child: Text('Stock sin rotar', style: text.titleMedium)),
                DropdownButton<int>(
                  value: _deadDays,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 días')),
                    DropdownMenuItem(value: 60, child: Text('60 días')),
                    DropdownMenuItem(value: 90, child: Text('90 días')),
                  ],
                  onChanged: (v) => setState(() => _deadDays = v ?? 60),
                ),
              ],
            ),
            _DeadStock(days: _deadDays),
            const SizedBox(height: PerchaSpace.xl),
            Text('Valor del inventario', style: text.titleMedium),
            const SizedBox(height: PerchaSpace.sm),
            const _ValuationCard(),
          ],
        ),
      ),
    );
  }
}

Widget _loading([double h = 120]) => SizedBox(height: h, child: const Center(child: CircularProgressIndicator()));

class _SummaryGrid extends ConsumerWidget {
  const _SummaryGrid({required this.period});
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(summaryProvider(period)).when(
          loading: () => _loading(180),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (s) {
            final cards = <(String, String, String?)>[
              ('Ventas netas', formatCents(s.netSalesCents), '${s.tickets} ticket${s.tickets == 1 ? '' : 's'}'),
              ('Ticket promedio', formatCents(s.averageTicketCents), '${s.units} prendas'),
              if (s.grossMarginCents != null)
                ('Margen bruto', formatCents(s.grossMarginCents!), s.grossMarginPct == null ? null : '${s.grossMarginPct!.toStringAsFixed(1)}% sin IGV'),
              ('Descuentos', formatCents(s.discountsCents), [
                if (s.returns > 0) '${s.returns} devol.',
                if (s.voidedSales > 0) '${s.voidedSales} anul.',
              ].join(' · ')),
            ];
            return GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: PerchaSpace.md,
              mainAxisSpacing: PerchaSpace.md,
              childAspectRatio: 1.6,
              children: [for (final (label, value, sub) in cards) _Kpi(label: label, value: value, sub: sub)],
            );
          },
        );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Theme.of(context).textTheme.titleLarge)),
            if (sub != null && sub!.isNotEmpty) Text(sub!, style: TextStyle(fontSize: PerchaType.meta, color: PerchaColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Barras simples sin librería de gráficos: menos dependencias y control total del estilo.
class _DailyChart extends ConsumerWidget {
  const _DailyChart({required this.period});
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = DateFormat('d MMM', 'es');
    return ref.watch(dailyProvider(period)).when(
          loading: () => _loading(160),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (days) {
            final max = days.fold<int>(0, (a, d) => d.netSalesCents > a ? d.netSalesCents : a);
            final best = days.where((d) => d.netSalesCents == max && max > 0).firstOrNull;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 120,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final d in days)
                            Expanded(
                              child: Tooltip(
                                message: '${day.format(d.date)}: ${formatCents(d.netSalesCents)} · ${d.tickets} tickets',
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                                  child: Container(
                                    height: max == 0 ? 2 : (d.netSalesCents.clamp(0, max) / max * 116).clamp(2, 116).toDouble(),
                                    decoration: BoxDecoration(
                                      color: d == best ? PerchaColors.accent : PerchaColors.accent.withValues(alpha: 0.35),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(day.format(days.first.date), style: TextStyle(fontSize: PerchaType.caption, color: PerchaColors.muted)),
                        Text(day.format(days.last.date), style: TextStyle(fontSize: PerchaType.caption, color: PerchaColors.muted)),
                      ],
                    ),
                    if (best != null) ...[
                      const SizedBox(height: PerchaSpace.sm),
                      Text('Mejor día: ${day.format(best.date)} con ${formatCents(best.netSalesCents)}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            );
          },
        );
  }
}

class _TopProducts extends ConsumerWidget {
  const _TopProducts({required this.period});
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(topProvider(period)).when(
          loading: () => _loading(),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (items) => items.isEmpty
              ? const Text('Sin ventas en este período.')
              : Card(
                  child: Column(
                    children: [
                      for (final (i, t) in items.indexed)
                        ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: i < 3 ? PerchaColors.accentSoft : PerchaColors.surfaceAlt,
                            child: Text('${i + 1}', style: TextStyle(fontSize: PerchaType.meta, fontWeight: FontWeight.w700, color: i < 3 ? PerchaColors.accentInk : PerchaColors.ink)),
                          ),
                          title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text([
                            '${t.units} prendas',
                            if (t.grossMarginCents != null) 'margen ${formatCents(t.grossMarginCents!)}',
                          ].join(' · ')),
                          trailing: Text(formatCents(t.netSalesCents), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
        );
  }
}

class _Rotation extends ConsumerWidget {
  const _Rotation({required this.period});
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(attributesRotationProvider(period)).when(
          loading: () => _loading(),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (attrs) => attrs.isEmpty
              ? const Text('Aún no hay productos con atributos.')
              : Column(
                  children: [
                    for (final a in attrs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: PerchaSpace.md),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: PerchaSpace.sm),
                                for (final v in a.values)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 5),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 72, child: Text(v.value, overflow: TextOverflow.ellipsis)),
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: (v.sellThroughPct ?? 0) / 100,
                                              minHeight: 10,
                                              backgroundColor: PerchaColors.surfaceAlt,
                                              // Alto sell-through = se agota (reponer); bajo = sobra.
                                              color: (v.sellThroughPct ?? 0) >= 70 ? PerchaColors.warn : PerchaColors.accent,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 112,
                                          child: Text(
                                            '${v.sellThroughPct?.round() ?? 0}% · ${v.sold}/${v.sold + v.stock}',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(fontSize: PerchaType.meta, color: PerchaColors.inkSoft),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Text('Naranja: se agota (70% o más). Conviene reponer esas tallas o colores.', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
        );
  }
}

class _DeadStock extends ConsumerWidget {
  const _DeadStock({required this.days});
  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(deadStockProvider(days)).when(
          loading: () => _loading(),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (items) {
            if (items.isEmpty) return Text('Todo rotó en los últimos $days días.');
            final tied = items.fold<int>(0, (a, i) => a + (i.costValueCents ?? i.retailValueCents));
            final atCost = items.first.costValueCents != null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${items.length} variantes · ${formatCents(tied)} inmovilizados ${atCost ? 'a costo' : 'a precio de venta'}. Candidatas a promoción.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PerchaSpace.sm),
                Card(
                  child: Column(
                    children: [
                      for (final i in items.take(15))
                        ListTile(
                          title: Text([i.productName, if (i.options.isNotEmpty) i.options].join(' · '), style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text('${i.quantity} unid. · ${i.neverSold ? 'nunca vendida' : 'sin venta hace'} ${i.daysWithoutSale} días'),
                          trailing: Text(formatCents(i.costValueCents ?? i.retailValueCents)),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
  }
}

class _ValuationCard extends ConsumerWidget {
  const _ValuationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(valuationProvider).when(
          loading: () => _loading(),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (v) => Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _Mini('A precio de venta', formatCents(v.totalRetailValueCents))),
                      if (v.totalCostValueCents != null) Expanded(child: _Mini('A costo', formatCents(v.totalCostValueCents!))),
                    ],
                  ),
                  if (v.potentialMarginCents != null) ...[
                    const SizedBox(height: PerchaSpace.sm),
                    Text('Margen potencial si se vende todo: ${formatCents(v.potentialMarginCents!)} (sin IGV)', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const Divider(height: 24),
                  for (final c in v.categories)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(c.category)),
                          Text('${c.units} u.', style: TextStyle(color: PerchaColors.muted, fontSize: PerchaType.meta)),
                          SizedBox(
                            width: 110,
                            child: Text(formatCents(c.costValueCents ?? c.retailValueCents), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(label, style: Theme.of(context).textTheme.bodySmall), Text(value, style: Theme.of(context).textTheme.titleLarge)],
      );
}
