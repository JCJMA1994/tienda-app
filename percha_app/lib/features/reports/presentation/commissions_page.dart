import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../data/commissions_api.dart';

/// Comisiones del mes (o del anterior): ventas netas de devoluciones, sin IGV.
class CommissionsPage extends ConsumerStatefulWidget {
  const CommissionsPage({super.key});

  @override
  ConsumerState<CommissionsPage> createState() => _CommissionsPageState();
}

class _CommissionsPageState extends ConsumerState<CommissionsPage> {
  int _monthsBack = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - _monthsBack, 1);
    final last = _monthsBack == 0 ? now : DateTime(first.year, first.month + 1, 0);
    final fmt = DateFormat('yyyy-MM-dd');
    final range = (from: fmt.format(first), to: fmt.format(last));
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Comisiones')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 0, label: Text('Este mes')), ButtonSegment(value: 1, label: Text('Mes anterior'))],
            selected: {_monthsBack},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _monthsBack = s.first),
          ),
          const SizedBox(height: PerchaSpace.sm),
          Text('Sobre ventas netas sin IGV. Las devoluciones restan a quien hizo la venta, el mes en que ocurren. El porcentaje de cada persona se define en Equipo.', style: text.bodySmall),
          const SizedBox(height: PerchaSpace.md),
          ...ref.watch(commissionsProvider(range)).when(
                loading: () => const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
                error: (e, _) => [ErrorBanner(errorText(e))],
                data: (d) => [
                  if (d.sellers.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('Sin ventas en el período.', textAlign: TextAlign.center)),
                  for (final s in d.sellers)
                    Card(
                      margin: const EdgeInsets.only(bottom: PerchaSpace.sm),
                      child: ListTile(
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          '${s.tickets} venta${s.tickets == 1 ? '' : 's'}',
                          if (s.returns > 0) '${s.returns} devolución${s.returns == 1 ? '' : 'es'}',
                          'neto ${formatCents(s.netCents)} (${formatCents(s.netExTaxCents)} sin IGV)',
                        ].join(' · ')),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(s.commissionBp == null ? '—' : formatCents(s.commissionCents), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: PerchaType.title)),
                          Text(s.commissionBp == null ? 'sin comisión' : '${(s.commissionBp! / 100).toStringAsFixed(s.commissionBp! % 100 == 0 ? 0 : 1)} %', style: text.bodySmall),
                        ]),
                      ),
                    ),
                  if (d.sellers.isNotEmpty) ...[
                    const Divider(),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Total a pagar', style: text.titleMedium), Text(formatCents(d.totalCents), style: text.titleLarge)]),
                  ],
                ],
              ),
        ],
      ),
    );
  }
}
