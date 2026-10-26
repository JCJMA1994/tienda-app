part of 'pos_page.dart';

class _PosAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _PosAppBar({required this.branch, required this.cash});
  final Branch branch;
  final CashSession? cash;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  Future<void> _switchSeller(BuildContext context, WidgetRef ref) async {
    if (ref.read(cartProvider).lines.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Termina o vacía el ticket antes de cambiar de vendedor.')));
      return;
    }
    final pin = await askPin(context, title: 'Cambiar de vendedor', message: 'Ingresa tu PIN');
    if (pin == null || !context.mounted) return;
    try {
      final me = await ref.read(sessionProvider.notifier).switchByPin(branchId: branch.id, pin: pin);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hola, ${me.firstName}')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  /// Gift card: el dinero entra a caja ahora; la boleta se emite cuando se canjea.
  Future<void> _sellGiftCard(BuildContext context, WidgetRef ref) async {
    final amount = await promptMoney(context, title: 'Vender gift card', label: 'Monto', message: 'Entre S/ 10 y S/ 5,000. Vale por 1 año.', minCents: 1000, allowZero: false, confirm: 'Continuar');
    if (amount == null || !context.mounted) return;
    final method = await showDialog<PaymentMethod>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Cobrar ${formatCents(amount)}'),
        children: [
          for (final m in PaymentMethod.values.where((m) => m != PaymentMethod.storeCredit))
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, m), child: Text(m.label)),
        ],
      ),
    );
    if (method == null || !context.mounted) return;
    try {
      final c = await ref.read(creditsApiProvider).sellGiftCard(branchId: branch.id, amountCents: amount, method: method.api);
      if (context.mounted) await showCreditIssued(context, ref, code: c.code!, amountCents: c.balanceCents, expiresAt: c.expiresAt, title: 'Gift card');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  Future<void> _closeCash(BuildContext context, WidgetRef ref) async {
    final session = cash;
    if (session == null) return;
    // Las ventas sin conexión aún no están en el sistema: si se cierra ahora, su efectivo
    // aparecería como sobrante hoy y faltante en la próxima caja.
    final queue = ref.read(offlineQueueProvider.notifier);
    if (queue.pendingFor(branch.id) > 0) {
      await queue.sync();
      if (!context.mounted) return;
      final left = queue.pendingFor(branch.id);
      if (left > 0) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Primero sincroniza las ventas'),
            content: Text('Hay $left venta${left == 1 ? '' : 's'} hecha${left == 1 ? '' : 's'} sin conexión. Su efectivo está en esta caja: ciérrala cuando vuelva el internet y se envíen.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
        return;
      }
    }
    // A propósito NO se muestra el esperado: así el conteo es honesto.
    final counted = await promptMoney(
      context,
      title: 'Cerrar caja',
      label: 'Efectivo contado',
      message: 'Cuenta el efectivo de la caja e ingrésalo. Luego verás si cuadra.',
      confirm: 'Cerrar caja',
    );
    if (counted == null || !context.mounted) return;
    try {
      final res = await ref.read(posApiProvider).closeCash(session.id, counted);
      final diff = res['differenceCents'] as int;
      ref.invalidate(cashSessionProvider(branch.id));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Caja cerrada'),
          content: Text(
            'Esperado: ${formatCents(res['expectedCashCents'] as int)}\n'
            'Contado: ${formatCents(counted)}\n'
            '${diff == 0 ? 'Cuadra exacto.' : 'Diferencia: ${formatCents(diff)}'}',
          ),
          actions: [
            TextButton.icon(
              onPressed: () => printCashReport(ctx, ref, session.id),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir cierre'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return AppBar(
      toolbarHeight: 64,
      backgroundColor: PerchaColors.surface,
      leading: IconButton(tooltip: 'Volver al inicio', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
      titleSpacing: 0,
      title: Wrap(
        spacing: PerchaSpace.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(branch.name),
          if (cash != null) const Pill('Caja abierta'),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: PerchaSpace.sm),
          child: Center(child: Text(me.firstName, style: const TextStyle(fontWeight: FontWeight.w600))),
        ),
        TextButton(onPressed: () => _switchSeller(context, ref), child: const Text('Cambiar (PIN)')),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          onSelected: (v) {
            if (v == 'sales') context.push('/sales');
            if (v == 'layaways') context.push('/layaways');
            if (v == 'gift') _sellGiftCard(context, ref);
            if (v == 'close') _closeCash(context, ref);
            if (v == 'partial' && cash != null) printCashReport(context, ref, cash!.id);
            if (v == 'history') context.push('/cash-sessions');
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'sales', child: Text('Ventas, devoluciones y cambios')),
            const PopupMenuItem(value: 'layaways', child: Text('Apartados')),
            PopupMenuItem(value: 'gift', enabled: cash != null, child: const Text('Vender gift card')),
            PopupMenuItem(value: 'partial', enabled: cash != null, child: const Text('Imprimir corte parcial')),
            PopupMenuItem(value: 'close', enabled: cash != null, child: const Text('Cerrar caja')),
            const PopupMenuItem(value: 'history', child: Text('Cierres anteriores')),
          ],
        ),
      ],
    );
  }
}
