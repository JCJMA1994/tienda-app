import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/forms/dialogs.dart';
import '../../../core/forms/validators.dart';
import '../../../core/forms/app_form.dart';
import '../../../core/money.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../../pos/data/pos_api.dart';
import '../../pos/presentation/scanner_page.dart';
import '../application/drafts.dart';
import '../data/purchasing_api.dart';

class PoDetailPage extends ConsumerWidget {
  const PoDetailPage({super.key, required this.orderId});
  final String orderId;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
    try {
      await action();
      ref
        ..invalidate(poDetailProvider(orderId))
        ..invalidate(poReceiptsProvider(orderId));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, continuar')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final api = ref.read(purchasingApiProvider);
    final date = DateFormat("d 'de' MMMM", 'es');
    final dateTime = DateFormat("d MMM, HH:mm", 'es');

    return Scaffold(
      appBar: AppBar(),
      body: ref.watch(poDetailProvider(orderId)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (o) {
              final text = Theme.of(context).textTheme;
              final canWrite = me.can('purchasing.write');
              final supplier = ref.watch(suppliersProvider).valueOrNull?.where((s) => s.id == o.supplierId).firstOrNull;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('OC #${o.number}', style: text.headlineSmall)),
                      Pill(o.status.label, warn: o.status == PoStatus.partial, dark: o.status == PoStatus.received),
                    ],
                  ),
                  if (supplier != null) Text(supplier.name, style: text.titleMedium),
                  if (o.expectedAt != null) Text('Llegada estimada: ${date.format(o.expectedAt!)}', style: text.bodySmall),
                  if (o.notes != null) ...[const SizedBox(height: 4), Text(o.notes!, style: text.bodySmall)],
                  const SizedBox(height: PerchaSpace.lg),
                  if (o.status.receivable) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: o.unitsReceived / o.unitsOrdered, minHeight: 6, color: PerchaColors.accent, backgroundColor: PerchaColors.border),
                    ),
                    const SizedBox(height: 4),
                    Text('${o.unitsReceived} de ${o.unitsOrdered} unidades recibidas', style: text.bodySmall),
                    const SizedBox(height: PerchaSpace.lg),
                  ],
                  Card(
                    child: Column(
                      children: [
                        for (final l in o.lines)
                          ListTile(
                            title: Text([l.productName, if (l.optionsLabel.isNotEmpty) l.optionsLabel].join(' · '), style: const TextStyle(fontWeight: FontWeight.w500)),
                            subtitle: Text('${l.ordered} × ${formatCents(l.unitCostCents)}'),
                            trailing: l.pending == 0
                                ? const Pill('Completa')
                                : o.status.receivable
                                    ? Pill('Faltan ${l.pending}', warn: true)
                                    : Text('${l.ordered} u.'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PerchaSpace.md),
                  Align(alignment: Alignment.centerRight, child: Text('Total ${formatCents(o.totalCents)}', style: text.titleLarge)),
                  const SizedBox(height: PerchaSpace.xl),
                  if (o.status.receivable && me.can('purchasing.receive'))
                    FilledButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined),
                      onPressed: () => context.push('/purchases/${o.id}/receive'),
                      label: const Text('Recibir mercadería'),
                    ),
                  if (o.status == PoStatus.draft && canWrite) ...[
                    FilledButton(
                      onPressed: () async {
                        if (await _confirm(context, 'Confirmar pedido', 'La orden quedará como pedida y ya no se podrá editar.') && context.mounted) {
                          await _run(context, ref, () => api.confirm(o.id), 'Pedido confirmado');
                        }
                      },
                      child: const Text('Confirmar pedido'),
                    ),
                    const SizedBox(height: PerchaSpace.sm),
                    OutlinedButton(
                      onPressed: () async {
                        await context.push('/purchases/${o.id}/edit');
                        ref.invalidate(poDetailProvider(orderId));
                      },
                      child: const Text('Editar borrador'),
                    ),
                  ],
                  // Solo se cancela si aún no se recibió nada (la API lo valida igual).
                  if ((o.status == PoStatus.draft || o.status == PoStatus.ordered) && canWrite) ...[
                    const SizedBox(height: PerchaSpace.sm),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: PerchaColors.warn),
                      onPressed: () async {
                        if (await _confirm(context, 'Cancelar orden', 'La orden quedará cancelada.') && context.mounted) {
                          await _run(context, ref, () => api.cancel(o.id), 'Orden cancelada');
                        }
                      },
                      child: const Text('Cancelar orden'),
                    ),
                  ],
                  if (o.unitsReceived > 0) ...[
                    const SizedBox(height: PerchaSpace.xl),
                    Text('Recepciones', style: text.titleMedium),
                    ...ref.watch(poReceiptsProvider(o.id)).maybeWhen(
                          data: (rs) => [
                            for (final r in rs)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Recepción #${r.number}'),
                                subtitle: Text(dateTime.format(r.createdAt)),
                                trailing: Text('+${r.units} u.', style: TextStyle(fontWeight: FontWeight.w600, color: PerchaColors.accent)),
                              ),
                          ],
                          orElse: () => const [SizedBox.shrink()],
                        ),
                  ],
                ],
              );
            },
          ),
    );
  }
}

/// Recibir mercadería: se cuenta al desempacar escaneando cada prenda (o con "Recibir todo").
/// Lo no recibido queda pendiente y la orden pasa a "Recepción parcial".
class ReceivePage extends ConsumerStatefulWidget {
  const ReceivePage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends ConsumerState<ReceivePage> with ActionRunner {
  ReceiveDraft? _draft;
  SupplierInvoice? _invoice;
  final _code = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  Future<void> _scan(String code, PurchaseOrder o) async {
    if (code.trim().isEmpty) return;
    try {
      final v = await ref.read(posApiProvider).lookup(code.trim(), o.branchId);
      if (!mounted) return;
      if (v == null) return _toast('Código no encontrado');
      final (next, result) = _draft!.scan(v.id);
      setState(() => _draft = next);
      _toast(switch (result) {
        ScanResult.counted => '${v.productName} ${v.optionsLabel} contada · ${next.units} en total',
        ScanResult.alreadyComplete => '${v.productName} ${v.optionsLabel} ya está completa',
        ScanResult.notInOrder => '${v.productName} ${v.optionsLabel} no está en esta orden',
      });
    } catch (e) {
      if (mounted) _toast(errorText(e));
    } finally {
      if (mounted) {
        _code.clear();
        _focus.requestFocus(); // listo para la siguiente prenda
      }
    }
  }

  Future<void> _editCost(PoLine line) async {
    final current = _draft!.costs[line.id] ?? line.unitCostCents;
    final v = await promptMoney(
      context,
      title: 'Costo de la factura',
      label: 'Costo por unidad',
      initialCents: current,
      helper: 'En la orden: ${formatCents(line.unitCostCents)}',
      confirm: 'Guardar',
    );
    if (v != null) setState(() => _draft = _draft!.setCost(line, v));
  }

  Future<void> _submit() async {
    final d = _draft!;
    if (!d.completesOrder) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recepción parcial'),
          content: const Text('Faltan prendas por llegar. Lo no recibido quedará pendiente en la orden.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir contando')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar lo recibido')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await runAction(() async {
        final r = await ref.read(purchasingApiProvider).receive(d.order.id, d.toItems(), invoice: _invoice);
        final status = r.status;
        ref
          ..invalidate(poDetailProvider(d.order.id))
          ..invalidate(poReceiptsProvider(d.order.id));
        if (!mounted) return;
        final inv = switch (r.invoiceStatus) { 'valid' => ' Factura validada en SUNAT.', 'unverified' => ' La factura no se pudo verificar ahora.', _ => '' };
        _toast('${status == 'received' ? 'Orden recibida completa. El stock ya está disponible.' : 'Recepción parcial registrada.'}$inv');
        context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(poDetailProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Recibir mercadería')),
      body: order.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
        data: (o) {
          final d = _draft ??= ReceiveDraft(order: o);
          final showCosts = ref.watch(meProvider).can('costs.read');
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            children: [
              Text('OC #${o.number}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: PerchaSpace.md),
              Card(
                child: ListTile(
                  leading: Icon(_invoice == null ? Icons.receipt_long_outlined : Icons.fact_check_outlined, color: PerchaColors.accentInk),
                  title: Text(_invoice == null ? 'Factura del proveedor (opcional)' : 'Factura ${_invoice!.label}'),
                  subtitle: Text(_invoice == null ? 'Se valida en SUNAT al registrar: una factura anulada no se acepta' : 'Se validará en SUNAT al registrar'),
                  trailing: _invoice == null
                      ? const Icon(Icons.add)
                      : IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => setState(() => _invoice = null)),
                  onTap: () async {
                    final inv = await showDialog<SupplierInvoice>(context: context, builder: (_) => _InvoiceDialog(initial: _invoice));
                    if (inv != null) setState(() => _invoice = inv);
                  },
                ),
              ),
              const SizedBox(height: PerchaSpace.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      focusNode: _focus,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Escanea cada prenda al desempacar', prefixIcon: Icon(Icons.qr_code)),
                      onSubmitted: (v) => _scan(v, o),
                    ),
                  ),
                  const SizedBox(width: PerchaSpace.sm),
                  IconButton.outlined(
                    tooltip: 'Escanear con la cámara',
                    constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
                      if (code != null) await _scan(code, o);
                    },
                  ),
                ],
              ),
              const SizedBox(height: PerchaSpace.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => setState(() => _draft = d.all()), child: const Text('Recibir todo lo pendiente')),
              ),
              Card(
                child: Column(
                  children: [
                    for (final l in d.pendingLines)
                      ListTile(
                        title: Text([l.productName, if (l.optionsLabel.isNotEmpty) l.optionsLabel].join(' · '), style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text([
                          'Pendiente ${l.pending}',
                          if (showCosts) 'costo ${formatCents(d.costs[l.id] ?? l.unitCostCents)}${d.costs.containsKey(l.id) ? ' (editado)' : ''}',
                        ].join(' · ')),
                        onLongPress: showCosts ? () => _editCost(l) : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Menos',
                              icon: const Icon(Icons.remove),
                              onPressed: (d.counts[l.id] ?? 0) > 0 ? () => setState(() => _draft = d.set(l, (d.counts[l.id] ?? 0) - 1)) : null,
                            ),
                            Text('${d.counts[l.id] ?? 0}/${l.pending}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            IconButton(
                              tooltip: 'Más',
                              icon: const Icon(Icons.add),
                              onPressed: (d.counts[l.id] ?? 0) < l.pending ? () => setState(() => _draft = d.set(l, (d.counts[l.id] ?? 0) + 1)) : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (showCosts) ...[
                const SizedBox(height: PerchaSpace.sm),
                Text('Mantén presionada una línea si la factura trae otro costo: se usa para el costo promedio.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (error != null) ...[const SizedBox(height: PerchaSpace.lg), ErrorBanner(error!)],
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: BusyButton(
            label: _draft == null || _draft!.isEmpty ? 'Cuenta las prendas recibidas' : 'Registrar ${_draft!.units} unidades',
            busy: busy,
            onPressed: _draft == null || _draft!.isEmpty ? null : _submit,
          ),
        ),
      ),
    );
  }
}

class _InvoiceDialog extends StatefulWidget {
  const _InvoiceDialog({this.initial});
  final SupplierInvoice? initial;

  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  final _form = GlobalKey<FormState>();
  late final _serie = TextEditingController(text: widget.initial?.serie ?? '');
  late final _numero = TextEditingController(text: widget.initial?.numero.toString() ?? '');
  late final _total = TextEditingController(text: widget.initial?.totalCents == null ? '' : (widget.initial!.totalCents! / 100).toStringAsFixed(2));
  late DateTime _date = widget.initial?.date ?? DateTime.now();

  @override
  void dispose() {
    for (final c in [_serie, _numero, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Factura del proveedor'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: AppTextField(
                  controller: _serie,
                  label: 'Serie',
                  hint: 'F001',
                  kind: FieldKind.upper,
                  maxLength: 4,
                  autofocus: true,
                  validator: (v) => RegExp(r'^[A-Z0-9]{1,4}$').hasMatch((v ?? '').trim().toUpperCase()) ? null : 'Ej. F001',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: AppTextField(controller: _numero, label: 'Número', kind: FieldKind.integer, maxLength: 8, validator: V.intRange(min: 1, max: 99999999))),
            ]),
            const SizedBox(height: PerchaSpace.md),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text('Emitida el ${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
              onPressed: () async {
                final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(DateTime.now().year - 2), lastDate: DateTime.now());
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: _total, label: 'Importe total (opcional)', kind: FieldKind.money, validator: V.money(optional: true), last: true),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!submitForm(_form)) return;
            Navigator.pop(
              context,
              SupplierInvoice(serie: _serie.text.trim().toUpperCase(), numero: int.parse(_numero.text), date: _date, totalCents: _total.text.trim().isEmpty ? null : parseCents(_total.text)),
            );
          },
          child: const Text('Listo'),
        ),
      ],
    );
  }
}
