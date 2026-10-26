import '../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/forms/app_form.dart';
import '../../core/forms/dialogs.dart';
import '../../core/forms/validators.dart';
import '../../core/catalogs.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/percha_widgets.dart';
import '../auth/application/session_controller.dart';
import '../credits/credit_widgets.dart';
import '../onboarding/data/store_api.dart';
import '../printing/print_settings.dart';
import '../printing/ticket.dart';
import '../printing/ticket_pdf.dart';
import 'layaways_api.dart';


Future<String?> _pickMethod(BuildContext context, String title) => showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [for (final e in Labels.moneyMethods.entries) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value))],
      ),
    );

/// Constancia del apartado (para el cliente): prendas, abonado, saldo y fecha límite.
Future<void> printLayawayVoucher(WidgetRef ref, Layaway l) async {
  final store = ref.read(storeSettingsProvider).valueOrNull;
  final model = TicketModel(
    header: [(store?.name ?? '').toUpperCase()],
    title: 'APARTADO #${l.number}',
    meta: ['Cliente: ${l.customerName}', 'Recoger hasta: ${DateFormat('dd/MM/yyyy').format(l.expiresAt)}'],
    items: [for (final i in l.items) (left: '${i.quantity} x ${i.name}', right: formatCents(i.unitPriceCents * i.quantity), detail: i.options.isEmpty ? null : i.options)],
    totals: [
      (label: 'Total', value: formatCents(l.totalCents), strong: false),
      (label: 'Abonado', value: formatCents(l.paidCents), strong: false),
      (label: 'SALDO', value: formatCents(l.pendingCents), strong: true),
    ],
    payments: [for (final p in l.payments) (label: '${DateFormat('dd/MM').format(p.at)} ${Labels.paymentMethod(p.method)}', value: formatCents(p.amountCents))],
    footer: const ['Las prendas quedan separadas hasta la fecha indicada.', 'Este documento no es un comprobante de pago.'],
  );
  await Printing.layoutPdf(name: 'Apartado-${l.number}', onLayout: (_) => ticketPdf(model, paperMm: ref.read(printSettingsProvider).paperMm));
}

/// Apartar el ticket actual: adelanto (mín. 10 %), medio de pago y días.
Future<Layaway?> createLayawayFlow(
  BuildContext context,
  WidgetRef ref, {
  required String branchId,
  required String customerId,
  required int totalCents,
  required List<({String variantId, int quantity})> items,
}) async {
  final min = (totalCents * 0.10).ceil();
  final deposit = await promptMoney(
    context,
    title: 'Apartar · ${formatCents(totalCents)}',
    label: 'Adelanto',
    message: 'Mínimo 10 % (${formatCents(min)}). Las prendas quedan separadas y no se venden a otro cliente.',
    minCents: min,
    initialCents: (totalCents * 0.3).round(),
    confirm: 'Continuar',
  );
  if (deposit == null || !context.mounted) return null;
  if (deposit > totalCents) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El adelanto no puede superar el total: mejor regístralo como venta.')));
    return null;
  }
  final method = await _pickMethod(context, 'Adelanto de ${formatCents(deposit)}');
  if (method == null || !context.mounted) return null;
  final days = await promptInt(context, title: 'Plazo para recoger', label: 'Días', initial: 15, min: 1, max: 60, helper: 'Pasado el plazo te avisaremos', confirm: 'Apartar');
  if (days == null || !context.mounted) return null;
  try {
    final l = await ref.read(layawaysApiProvider).create(branchId: branchId, customerId: customerId, items: items, depositCents: deposit, method: method, days: days);
    if (context.mounted) await printLayawayVoucher(ref, l);
    return l;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    return null;
  }
}

class LayawaysPage extends ConsumerWidget {
  const LayawaysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('d MMM', 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Apartados')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(layawaysProvider),
        child: ref.watch(layawaysProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(padding: const EdgeInsets.all(20), children: [ErrorBanner(errorText(e))]),
              data: (list) => list.isEmpty
                  ? ListView(children: const [SizedBox(height: 120), Center(child: Text('Sin apartados. Se crean desde el POS con un cliente elegido.'))])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: PerchaSpace.sm),
                      itemBuilder: (_, i) {
                        final l = list[i];
                        return Card(
                          child: ListTile(
                            title: Text('#${l.number} · ${l.customerName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(l.status == 'open'
                                ? 'Saldo ${formatCents(l.pendingCents)} de ${formatCents(l.totalCents)} · hasta ${date.format(l.expiresAt)}'
                                : formatCents(l.totalCents)),
                            trailing: Pill(l.statusLabel, warn: l.expired),
                            onTap: () async {
                              await context.push('/layaways/${l.id}');
                              ref.invalidate(layawaysProvider);
                            },
                          ),
                        );
                      },
                    ),
            ),
      ),
    );
  }
}

class LayawayPage extends ConsumerStatefulWidget {
  const LayawayPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<LayawayPage> createState() => _LayawayPageState();
}

class _LayawayPageState extends ConsumerState<LayawayPage> with ActionRunner {

  Future<void> _run(Future<void> Function() action) async {
    await runAction(() async {
        await action();
        ref.invalidate(layawayProvider(widget.id));
    }, errorAsSnack: true);
  }

  Future<void> _pay(Layaway l) async {
    final amount = await promptMoney(context, title: 'Abono', label: 'Monto', initialCents: l.pendingCents, helper: 'Saldo: ${formatCents(l.pendingCents)}', allowZero: false, confirm: 'Continuar');
    if (amount == null || !mounted) return;
    if (amount > l.pendingCents) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El abono supera el saldo')));
      return;
    }
    final method = await _pickMethod(context, 'Abono de ${formatCents(amount)}');
    if (method == null) return;
    await _run(() async {
      final updated = await ref.read(layawayProvider(l.id).notifier).pay(amount, method);
      if (mounted) await printLayawayVoucher(ref, updated);
    });
  }

  Future<void> _deliver(Layaway l) async {
    String method = 'cash';
    if (l.pendingCents > 0) {
      final m = await _pickMethod(context, 'Cobrar el saldo: ${formatCents(l.pendingCents)}');
      if (m == null) return;
      method = m;
    }
    await _run(() async {
      final saleId = await ref.read(layawayProvider(l.id).notifier).deliver(method: method);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entregado: la venta quedó registrada')));
        context.push('/sales/$saleId');
      }
    });
  }

  Future<void> _cancel(Layaway l) async {
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    String refund = 'store_credit';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Cancelar apartado'),
          content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Las prendas vuelven a estar disponibles. Abonado: ${formatCents(l.paidCents)}.'),
              const SizedBox(height: PerchaSpace.md),
              if (l.paidCents > 0)
                for (final (value, label) in const [('store_credit', 'Dejarlo como saldo a favor (vale)'), ('cash', 'Devolver en efectivo'), ('none', 'No devolver (política de la tienda)')])
                  RadioListTile<String>(contentPadding: EdgeInsets.zero, value: value, groupValue: refund, onChanged: (v) => setState(() => refund = v!), title: Text(label)),
              AppTextField(controller: reason, label: 'Motivo', validator: V.minLength(3, 'Indica el motivo'), last: true),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
            FilledButton(onPressed: () => submitForm(form) ? Navigator.pop(ctx, true) : null, child: const Text('Cancelar apartado')),
          ],
        ),
      ),
    );
    final why = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    await _run(() async {
      final r = await ref.read(layawayProvider(l.id).notifier).cancel(reason: why, refund: refund);
      if (r.creditCode != null && mounted) await showCreditIssued(context, ref, code: r.creditCode!, amountCents: r.creditCents);
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final date = DateFormat("d 'de' MMMM", 'es');
    return Scaffold(
      appBar: AppBar(actions: [
        if (ref.watch(layawayProvider(widget.id)).hasValue)
          IconButton(tooltip: 'Imprimir constancia', icon: const Icon(Icons.print_outlined), onPressed: () => printLayawayVoucher(ref, ref.read(layawayProvider(widget.id)).value!)),
      ]),
      body: ref.watch(layawayProvider(widget.id)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (l) {
              final open = l.status == 'open';
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Row(children: [
                    Expanded(child: Text('Apartado #${l.number}', style: Theme.of(context).textTheme.headlineSmall)),
                    Pill(l.statusLabel, warn: l.expired),
                  ]),
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    onPressed: () => context.push('/customers/${l.customerId}'),
                    child: Text(l.customerName),
                  ),
                  if (open) Text('${l.expired ? 'Venció' : 'Recoger hasta'} el ${date.format(l.expiresAt)}', style: TextStyle(color: l.expired ? PerchaColors.warn : null)),
                  const SizedBox(height: PerchaSpace.lg),
                  Card(
                    child: Column(children: [
                      for (final i in l.items)
                        ListTile(
                          title: Text('${i.quantity} × ${i.name}'),
                          subtitle: i.options.isEmpty ? null : Text(i.options),
                          trailing: Text(formatCents(i.unitPriceCents * i.quantity)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: PerchaSpace.md),
                  Wrap(spacing: PerchaSpace.md, runSpacing: PerchaSpace.md, children: [
                    _Amount('Total', l.totalCents),
                    _Amount('Abonado', l.paidCents),
                    _Amount('Saldo', l.pendingCents, strong: true),
                  ]),
                  const SizedBox(height: PerchaSpace.lg),
                  Text('Abonos', style: Theme.of(context).textTheme.titleMedium),
                  for (final p in l.payments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(Labels.paymentMethod(p.method)),
                      subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(p.at)),
                      trailing: Text(formatCents(p.amountCents)),
                    ),
                  if (open && me.can('sales.create')) ...[
                    const SizedBox(height: PerchaSpace.xl),
                    if (l.pendingCents > 0) OutlinedButton.icon(onPressed: busy ? null : () => _pay(l), icon: const Icon(Icons.add_card), label: const Text('Registrar abono')),
                    const SizedBox(height: PerchaSpace.sm),
                    BusyButton(
                      label: l.pendingCents > 0 ? 'Cobrar saldo y entregar' : 'Entregar',
                      busy: busy,
                      onPressed: () => _deliver(l),
                    ),
                  ],
                  if (open && me.can('sales.return')) ...[
                    const SizedBox(height: PerchaSpace.sm),
                    TextButton(style: TextButton.styleFrom(foregroundColor: PerchaColors.warn), onPressed: busy ? null : () => _cancel(l), child: const Text('Cancelar apartado')),
                  ],
                  if (l.saleId != null)
                    TextButton(onPressed: () => context.push('/sales/${l.saleId}'), child: const Text('Ver la venta')),
                ],
              );
            },
          ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.cents, {this.strong = false});
  final String label;
  final int cents;
  final bool strong;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 110,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(formatCents(cents), style: TextStyle(fontWeight: FontWeight.w600, fontSize: strong ? PerchaType.amount : PerchaType.strong)),
        ]),
      );
}
