part of 'pos_page.dart';

class _OpenCashPanel extends ConsumerStatefulWidget {
  const _OpenCashPanel({required this.branch});
  final Branch branch;

  @override
  ConsumerState<_OpenCashPanel> createState() => _OpenCashPanelState();
}

class _OpenCashPanelState extends ConsumerState<_OpenCashPanel> with ActionRunner {
  final _amount = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (busy || !submitForm(_form)) return;
    final cents = parseCents(_amount.text.isEmpty ? '0' : _amount.text)!;
    await runAction(() async {
        await ref.read(posApiProvider).openCash(widget.branch.id, cents);
        ref.invalidate(cashSessionProvider(widget.branch.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(PerchaSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Abre la caja', style: text.headlineMedium),
              const SizedBox(height: PerchaSpace.sm),
              Text('Indica con cuánto efectivo empiezas el turno.', style: text.bodyMedium?.copyWith(color: PerchaColors.muted)),
              const SizedBox(height: PerchaSpace.xl),
              if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.lg)],
              Form(
                key: _form,
                child: AppTextField(
                  controller: _amount,
                  label: 'Fondo de caja',
                  hint: '0.00',
                  kind: FieldKind.money,
                  helper: 'Déjalo vacío si empiezas sin sencillo',
                  validator: V.money(optional: true, maxCents: 10000000),
                  last: true,
                  onSubmitted: (_) => _open(),
                ),
              ),
              const SizedBox(height: PerchaSpace.xl),
              BusyButton(label: 'Abrir caja', busy: busy, onPressed: _open),
            ],
          ),
        ),
      ),
    );
  }
}
