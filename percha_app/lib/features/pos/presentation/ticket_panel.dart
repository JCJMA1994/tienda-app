import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/dialogs.dart';
import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/application/session_controller.dart';
import '../../einvoice/domain/customer_rules.dart';
import '../../einvoice/data/einvoice_api.dart';
import '../../einvoice/presentation/document_sheet.dart';
import '../../credits/credit_widgets.dart';
import '../../layaways/layaways_pages.dart';
import '../../customers/customers_api.dart';
import '../../customers/customers_pages.dart';
import '../../messaging/whatsapp_pages.dart';
import '../../printing/print_actions.dart';
import '../../printing/print_settings.dart';
import '../../onboarding/data/store_api.dart';
import '../application/cart.dart';
import '../domain/checkout.dart';
import '../domain/promotions.dart';
import '../application/checkout_controller.dart';
import '../offline/pos_snapshot.dart';
import '../data/pos_models.dart';
import 'pin_dialog.dart';

/// Ticket en curso: líneas, descuento, total, método de pago y "Cobrar".
class TicketPanel extends ConsumerStatefulWidget {
  const TicketPanel({super.key, required this.branch, required this.store, this.onSold});
  final Branch branch;
  final StoreSettings store;
  final VoidCallback? onSold;

  @override
  ConsumerState<TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends ConsumerState<TicketPanel> {
  PaymentMethod _method = PaymentMethod.cash;
  DocumentChoice _document = const DocumentChoice();
  CustomerSummary? _customer;

  /// Promociones del ticket, con la foto local (las mismas reglas que el servidor).
  ({List<PromoLineResult> lines, int totalCents}) _promos(Cart cart) {
    final snap = ref.read(posSnapshotProvider(widget.branch.id)).valueOrNull;
    final items = [for (final l in cart.lines) (variantId: l.variant.id, quantity: l.quantity, unitPriceCents: l.variant.priceCents)];
    return snap?.promosFor(items) ?? (lines: [for (final _ in items) (discountCents: 0, promotionId: null)], totalCents: 0);
  }

  ({int total, int tax}) _totals(Cart cart) =>
      cart.totals(taxRateBp: widget.store.taxRateBp, pricesIncludeTax: widget.store.pricesIncludeTax, promoCents: _promos(cart).totalCents);

  Future<void> _editDiscount(Cart cart) async {
    final value = await promptMoney(
      context,
      title: 'Descuento',
      label: 'Monto del descuento',
      initialCents: cart.discountCents == 0 ? null : cart.discountCents,
      helper: 'Más de ${widget.store.discountLimitBp ~/ 100}% requiere PIN de supervisor. 0 lo quita.',
    );
    if (value != null) ref.read(cartProvider.notifier).setDiscount(value);
  }

  /// El caso de uso vive en CheckoutController; aquí solo se ponen los diálogos y se reacciona
  /// al resultado.
  Future<void> _checkout() async {
    final cart = ref.read(cartProvider);
    final me = ref.read(meProvider);
    final total = _totals(cart).total;
    final anonLimit = ref.read(einvoiceStatusProvider).valueOrNull?.anonLimitCents ?? 70000;

    final outcome = await ref.read(checkoutProvider.notifier).checkout(
          CheckoutRequest(
            branchId: widget.branch.id,
            items: cart.toItems(),
            discountCents: cart.manualDiscountAfter(_promos(cart).totalCents),
            totalCents: total,
            method: _method,
            document: _document,
            customerId: _customer?.id,
            needsDiscountApproval: cart.needsDiscountApproval(widget.store.discountLimitBp, promoCents: _promos(cart).totalCents) && !me.can('sales.discount_over_limit'),
          ),
          CheckoutPrompts(
            fixDocument: (problem) async {
              final fixed = await pickDocument(context, current: _document, totalCents: total, anonLimitCents: anonLimit, error: problem);
              if (fixed != null && mounted) setState(() => _document = fixed);
              return fixed;
            },
            askCredit: (t) => askCreditCode(context, totalCents: t),
            askRestMethod: (rest) => showDialog<PaymentMethod>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: Text('Resto: ${formatCents(rest)}'),
                children: [
                  for (final m in PaymentMethod.values.where((m) => m != PaymentMethod.storeCredit))
                    SimpleDialogOption(onPressed: () => Navigator.pop(ctx, m), child: Text(m.label)),
                ],
              ),
            ),
            askCashReceived: _askCashReceived,
            askApproval: (reason) => askPinForApproval(context, reason),
            confirmTotal: (shown, server) async =>
                await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('El total cambió'),
                    content: Text('El total correcto es ${formatCents(server)} (antes se mostraba ${formatCents(shown)}). Puede ser una promoción que empezó o terminó, o un precio actualizado.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Cobrar ${formatCents(server)}')),
                    ],
                  ),
                ) ??
                false,
          ),
        );
    if (!mounted) return;
    switch (outcome) {
      case CheckoutCancelled():
        return;
      case CheckoutFailed(:final message):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      case CheckoutQueued(:final totalCents):
        ref.read(cartProvider.notifier).clear();
        setState(() {
          _document = const DocumentChoice();
          _customer = null;
        });
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.cloud_off_outlined, color: PerchaColors.warn, size: 40),
            title: Text('Venta guardada · ${formatCents(totalCents)}'),
            content: const Text('No hay conexión. La venta quedó guardada en este equipo y se enviará sola apenas vuelva el internet (con su comprobante). Puedes seguir vendiendo.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nueva venta'))],
          ),
        );
        if (mounted) widget.onSold?.call();
      case CheckoutDone(:final receipt):
        ref.read(cartProvider.notifier).clear();
        setState(() {
          _document = const DocumentChoice();
          _customer = null;
        });
        if (ref.read(printSettingsProvider).autoPrint) unawaited(printTicket(context, ref, receipt.id, changeCents: receipt.changeCents));
        await _showReceipt(receipt);
        // Después del recibo: en teléfono onSold cierra la hoja que contiene este panel.
        if (mounted) widget.onSold?.call();
    }
  }


  Future<String?> askPinForApproval(BuildContext context, String message) =>
      askPin(context, title: 'Aprobación de supervisor', message: message);

  Future<int?> _askCashReceived(int total) async {
    // Sugerencias: exacto y los billetes siguientes (S/ 50, 100, 200).
    final suggestions = cashSuggestions(total);
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Total ${formatCents(total)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('¿Con cuánto paga?'),
            const SizedBox(height: PerchaSpace.md),
            Wrap(
              spacing: PerchaSpace.sm,
              runSpacing: PerchaSpace.sm,
              children: [
                for (final s in suggestions)
                  ActionChip(label: Text(s == total ? 'Exacto' : formatCents(s)), onPressed: () => Navigator.pop(ctx, s)),
                ActionChip(label: const Text('Otro monto'), onPressed: () => Navigator.pop(ctx, -1)),
              ],
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
      ),
    );
    if (picked != -1 || !mounted) return picked;
    return promptMoney(context, title: 'Efectivo recibido', label: '¿Con cuánto paga?', minCents: total, confirm: 'Continuar');
  }

  Future<void> _showReceipt(SaleReceipt r) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.check_circle_outline, color: PerchaColors.success, size: 40),
        title: Text('Venta #${r.number}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatCents(r.totalCents), style: Theme.of(ctx).textTheme.headlineMedium),
            Text('Incluye IGV ${formatCents(r.taxCents)}', style: Theme.of(ctx).textTheme.bodySmall),
            if (r.changeCents > 0) ...[
              const SizedBox(height: PerchaSpace.lg),
              Text('Vuelto: ${formatCents(r.changeCents)}', style: Theme.of(ctx).textTheme.titleLarge),
            ],
            for (final d in r.documents) ...[
              const SizedBox(height: PerchaSpace.md),
              // La venta ya está registrada aunque el OSE no haya respondido: se reenvía solo.
              Text('${d.kindLabel} ${d.code} · ${d.statusLabel}', style: TextStyle(color: d.status == 'accepted' ? PerchaColors.accentInk : PerchaColors.warn)),
            ],
          ],
        ),
        actions: [
          for (final d in r.documents.where((d) => d.pdfUrl != null))
            TextButton(onPressed: () => launchUrl(Uri.parse(d.pdfUrl!), mode: LaunchMode.externalApplication), child: const Text('Ver PDF')),
          TextButton.icon(onPressed: () => printTicket(ctx, ref, r.id, changeCents: r.changeCents), icon: const Icon(Icons.print_outlined), label: const Text('Imprimir')),
          if (ref.read(whatsappEnabledProvider).valueOrNull ?? false)
            TextButton.icon(onPressed: () => sendReceiptByWhatsApp(ctx, ref, r.id), icon: const Icon(Icons.chat_outlined), label: const Text('WhatsApp')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nueva venta')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final snap = ref.watch(posSnapshotProvider(widget.branch.id)).valueOrNull;
    final promos = _promos(cart);
    final totals = _totals(cart);
    final text = Theme.of(context).textTheme;

    return Container(
      color: PerchaColors.surface,
      padding: const EdgeInsets.all(PerchaSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ticket actual', style: text.titleLarge),
          const SizedBox(height: PerchaSpace.md),
          Expanded(
            child: cart.isEmpty
                ? Center(child: Text('Escanea o elige una prenda', style: text.bodyMedium?.copyWith(color: PerchaColors.muted)))
                : ListView.separated(
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) => _LineTile(
                      line: cart.lines[i],
                      promoLabel: snap?.promoName(promos.lines[i].promotionId),
                      promoCents: promos.lines[i].discountCents,
                    ),
                  ),
          ),
          const Divider(),
          const SizedBox(height: PerchaSpace.sm),
          _Row('Subtotal', formatCents(cart.subtotalCents)),
          if (promos.totalCents > 0) _Row('Promociones', '− ${formatCents(promos.totalCents)}'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Descuento'),
              TextButton(
                onPressed: cart.isEmpty ? null : () => _editDiscount(cart),
                child: Text(cart.manualDiscountAfter(promos.totalCents) == 0 ? 'Aplicar' : '− ${formatCents(cart.manualDiscountAfter(promos.totalCents))}'),
              ),
            ],
          ),
          _Row(widget.store.pricesIncludeTax ? 'Incluye IGV' : 'IGV', formatCents(totals.tax), small: true),
          const SizedBox(height: PerchaSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [Text('Total', style: text.titleMedium), Text(formatCents(totals.total), style: text.headlineMedium)],
          ),
          if (ref.watch(meProvider).can('customers.read')) ...[
            const SizedBox(height: PerchaSpace.sm),
            OutlinedButton.icon(
              icon: Icon(_customer == null ? Icons.person_add_alt : Icons.person),
              label: Text(_customer?.name ?? 'Agregar cliente (opcional)', overflow: TextOverflow.ellipsis),
              onPressed: () async {
                final c = await pickCustomer(context, ref);
                if (c == null) return;
                setState(() {
                  _customer = c;
                  // Si tiene documento, se ofrece en el comprobante (el vendedor lo puede cambiar).
                  if (c.docNumber != null && _document.type == DocType.none && !_document.factura) {
                    _document = DocumentChoice(
                      factura: false,
                      type: switch (c.docType) { 'ruc' => DocType.ruc, 'ce' => DocType.ce, _ => DocType.dni },
                      number: c.docNumber!,
                      name: c.name,
                    );
                  }
                });
              },
            ),
          ],
          if (ref.watch(einvoiceStatusProvider).valueOrNull?.enabled ?? false) ...[
            const SizedBox(height: PerchaSpace.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(_document.summary, overflow: TextOverflow.ellipsis),
              onPressed: cart.isEmpty
                  ? null
                  : () async {
                      final status = ref.read(einvoiceStatusProvider).valueOrNull!;
                      final picked = await pickDocument(context, current: _document, totalCents: totals.total, anonLimitCents: status.anonLimitCents);
                      if (picked != null) setState(() => _document = picked);
                    },
            ),
          ],
          const SizedBox(height: PerchaSpace.lg),
          SegmentedButton<PaymentMethod>(
            segments: [for (final m in PaymentMethod.values) ButtonSegment(value: m, label: Text(m.label))],
            selected: {_method},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: PerchaSpace.md),
          // Apartar: requiere cliente (hay que saber a quién se le separa).
          if (!cart.isEmpty && ref.watch(meProvider).can('customers.read')) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(_customer == null ? 'Apartar (elige un cliente)' : 'Apartar para ${_customer!.name.split(' ').first}'),
              onPressed: ref.watch(checkoutProvider)
                  ? null
                  : () async {
                      var customer = _customer;
                      customer ??= await pickCustomer(context, ref);
                      if (customer == null || !context.mounted) return;
                      setState(() => _customer = customer);
                      final l = await createLayawayFlow(
                        context,
                        ref,
                        branchId: widget.branch.id,
                        customerId: customer.id,
                        totalCents: totals.total,
                        items: cart.toItems(),
                      );
                      if (l == null || !mounted || !context.mounted) return;
                      ref.read(cartProvider.notifier).clear();
                      setState(() => _customer = null);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Apartado #${l.number}: saldo ${formatCents(l.pendingCents)}')));
                    },
            ),
            const SizedBox(height: PerchaSpace.sm),
          ],
          SizedBox(
            height: 60,
            child: BusyButton(
              label: cart.isEmpty ? 'Cobrar' : 'Cobrar ${formatCents(totals.total)}',
              busy: ref.watch(checkoutProvider),
              onPressed: cart.isEmpty ? null : _checkout,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.small = false});
  final String label;
  final String value;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = small ? Theme.of(context).textTheme.bodySmall : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text(value, style: style)]),
    );
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({required this.line, this.promoLabel, this.promoCents = 0});
  final CartLine line;

  /// Promoción aplicada a la línea (nombre y cuánto descuenta).
  final String? promoLabel;
  final int promoCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartProvider.notifier);
    final v = line.variant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PerchaSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(v.optionsLabel.isEmpty ? v.sku : v.optionsLabel, style: Theme.of(context).textTheme.bodySmall),
                if (promoLabel != null && promoCents > 0)
                  Text('$promoLabel · − ${formatCents(promoCents)}', style: TextStyle(color: PerchaColors.accentInk, fontSize: PerchaType.meta, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'Quitar uno',
            icon: const Icon(Icons.remove, size: 18),
            onPressed: () => cart.setQuantity(v.id, line.quantity - 1),
          ),
          SizedBox(width: 28, child: Text('${line.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton.outlined(
            tooltip: 'Agregar uno',
            icon: const Icon(Icons.add, size: 18),
            onPressed: v.stock != null && line.quantity >= v.stock! ? null : () => cart.setQuantity(v.id, line.quantity + 1),
          ),
          SizedBox(width: 88, child: Text(formatCents(line.totalCents), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
