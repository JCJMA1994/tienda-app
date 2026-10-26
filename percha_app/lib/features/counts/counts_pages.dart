import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/forms/dialogs.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/action_runner.dart';
import '../../core/widgets/percha_widgets.dart';
import '../auth/application/session_controller.dart';
import '../onboarding/data/store_api.dart';
import '../pos/offline/pos_snapshot.dart';
import '../pos/presentation/scanner_page.dart';
import 'counts_api.dart';

/// Conteos de inventario de la sucursal.
class CountsPage extends ConsumerStatefulWidget {
  const CountsPage({super.key});

  @override
  ConsumerState<CountsPage> createState() => _CountsPageState();
}

class _CountsPageState extends ConsumerState<CountsPage> with ActionRunner {
  Future<void> _start(String branchId) async {
    final c = await runAction(() => ref.read(countsApiProvider).start(branchId), errorAsSnack: true);
    if (c == null || !mounted) return;
    await context.push('/stock-counts/${c.id}');
    ref.invalidate(countsProvider(branchId));
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(currentBranchProvider).valueOrNull;
    final date = DateFormat('d MMM yyyy', 'es');
    if (branch == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Conteo de inventario')),
      floatingActionButton: FloatingActionButton.extended(onPressed: busy ? null : () => _start(branch.id), icon: const Icon(Icons.fact_check_outlined), label: const Text('Nuevo conteo')),
      body: ref.watch(countsProvider(branch.id)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (list) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
              children: [
                Text('Escanea prenda por prenda; al final se ajusta el stock con las diferencias. Puedes contar con la tienda abierta: lo que se venda después de contar una prenda no cuenta como faltante.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: PerchaSpace.md),
                for (final c in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: PerchaSpace.sm),
                    child: ListTile(
                      title: Text('Conteo #${c.number}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([date.format(c.createdAt), if (c.note != null) c.note!].join(' · ')),
                      trailing: Pill(c.statusLabel, warn: c.open),
                      onTap: () async {
                        await context.push('/stock-counts/${c.id}');
                        ref.invalidate(countsProvider(branch.id));
                      },
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}

class CountPage extends ConsumerStatefulWidget {
  const CountPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<CountPage> createState() => _CountPageState();
}

class _CountPageState extends ConsumerState<CountPage> with ActionRunner {
  final _code = TextEditingController();
  final _focus = FocusNode();
  StockCount? _count;
  String? _last;

  @override
  void initState() {
    super.initState();
    ref.read(countsApiProvider).get(widget.id).then((c) {
      if (mounted) setState(() => _count = c);
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Una lectura (lector USB o cámara continua): suma 1 a esa prenda.
  Future<ScanFeedback> _countCode(String code) async {
    final branch = await ref.read(currentBranchProvider.future);
    try {
      final v = await lookupVariant(ref, code, branch.id);
      if (v == null) return (message: 'No encontramos el código $code', ok: false);
      final c = await ref.read(countsApiProvider).add(widget.id, v.id);
      final name = '${v.productName} ${v.optionsLabel}'.trim();
      final n = c.items.where((i) => i.variantId == v.id).firstOrNull?.counted ?? 0;
      if (mounted) setState(() {
        _count = c;
        _last = name;
      });
      return (message: '+1 $name (van $n)', ok: true);
    } catch (e) {
      return (message: errorText(e), ok: false);
    }
  }

  /// Lector USB o cámara: cada lectura suma 1 a esa prenda.
  Future<void> _scan(String raw) async {
    final code = raw.trim();
    _code.clear();
    if (code.isEmpty) return;
    final branch = await ref.read(currentBranchProvider.future);
    final v = await runAction(() => lookupVariant(ref, code, branch.id), errorAsSnack: true);
    if (!mounted) return;
    if (v == null) {
      HapticFeedback.heavyImpact();
      snack('No encontramos el código $code');
    } else {
      final c = await runAction(() => ref.read(countsApiProvider).add(widget.id, v.id), errorAsSnack: true);
      if (c != null && mounted) {
        HapticFeedback.selectionClick();
        setState(() {
          _count = c;
          _last = '${v.productName} ${v.optionsLabel}'.trim();
        });
      }
    }
    _focus.requestFocus();
  }

  Future<void> _edit(CountItem i) async {
    final q = await promptInt(context, title: '${i.productName} ${i.optionsLabel}'.trim(), label: 'Cantidad contada', initial: i.counted, min: 0, max: 10000);
    if (q == null || !mounted) return;
    final c = await runAction(() => q == 0 ? ref.read(countsApiProvider).remove(widget.id, i.variantId) : ref.read(countsApiProvider).set(widget.id, i.variantId, q), errorAsSnack: true);
    if (c != null && mounted) setState(() => _count = c);
  }

  Future<void> _apply(StockCount c) async {
    var zero = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Aplicar conteo #${c.number}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Se ajustará el stock: faltan ${c.missing} y sobran ${c.extra} unidad(es). Queda registrado en el kardex.'),
            const SizedBox(height: PerchaSpace.md),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: zero,
              onChanged: (v) => set(() => zero = v ?? false),
              title: const Text('Fue un conteo COMPLETO de la sucursal'),
              subtitle: const Text('Las prendas con stock que no se contaron quedarán en 0'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final r = await runAction(() => ref.read(countsApiProvider).apply(c.id, zeroUncounted: zero), errorAsSnack: true);
    if (r == null || !mounted) return;
    snack('Stock ajustado: ${r['adjusted']} prenda(s) con diferencia');
    setState(() => _count = StockCount.fromJson(r));
  }

  @override
  Widget build(BuildContext context) {
    final c = _count;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Conteo' : 'Conteo #${c.number}'),
        actions: [
          if (c != null && c.open)
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (_) async {
                await runAction(() => ref.read(countsApiProvider).cancel(c.id), errorAsSnack: true);
                if (mounted) context.pop();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancelar conteo (sin ajustar)'))],
            ),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (c.open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        focusNode: _focus,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(prefixIcon: const Icon(Icons.qr_code_scanner), hintText: 'Escanea o escribe el código', helperText: _last == null ? null : '+1 $_last'),
                        onSubmitted: _scan,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Escanear con la cámara',
                      icon: const Icon(Icons.photo_camera_outlined),
                      // Cámara continua: se pasan muchas prendas seguidas sin volver a abrirla.
                      onPressed: () => scanContinuous(context, title: 'Contando', onCode: _countCode),
                    ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Expanded(child: Text('${c.counted} contadas · ${c.items.length} variantes', style: text.bodySmall)),
                  if (c.missing > 0) Pill('Faltan ${c.missing}', warn: true),
                  const SizedBox(width: 6),
                  if (c.extra > 0) Pill('Sobran ${c.extra}'),
                ]),
              ),
              const SizedBox(height: PerchaSpace.sm),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: c.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, k) {
                    final i = c.items[k];
                    final d = i.difference;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(i.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${i.optionsLabel.isEmpty ? i.sku : i.optionsLabel} · sistema ${i.stockAtFirstScan}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (d != 0) Text(d > 0 ? '+$d' : '$d', style: TextStyle(color: d < 0 ? PerchaColors.warn : PerchaColors.accentInk, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 12),
                        Text('${i.counted}', style: const TextStyle(fontSize: PerchaType.title, fontWeight: FontWeight.w700)),
                      ]),
                      onTap: c.open ? () => _edit(i) : null,
                    );
                  },
                ),
              ),
            ]),
      bottomNavigationBar: c != null && c.open
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: BusyButton(label: 'Terminar y ajustar stock', busy: busy, onPressed: c.items.isEmpty ? null : () => _apply(c)),
              ),
            )
          : null,
    );
  }
}
