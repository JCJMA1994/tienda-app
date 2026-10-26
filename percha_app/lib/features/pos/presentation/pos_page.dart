import '../../../core/widgets/action_runner.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/dialogs.dart';
import '../../../core/forms/validators.dart';
import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../../core/widgets/thumb.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/data/store_api.dart';
import '../application/cart.dart';
import '../data/pos_api.dart';
import '../data/pos_models.dart';
import 'pin_dialog.dart';
import 'scanner_page.dart';
import 'ticket_panel.dart';
import '../../credits/credit_widgets.dart';
import '../../credits/credits_api.dart';
import '../../../core/barcodes.dart';
import '../../../core/network/api_error.dart';
import '../offline/offline_banner.dart';
import '../offline/offline_queue.dart';
import '../offline/pos_snapshot.dart';
import '../../printing/print_actions.dart';
import 'idle_lock.dart';
import 'variant_picker.dart';

part 'pos_app_bar.dart';
part 'pos_open_cash.dart';
part 'pos_catalog.dart';

/// Última caja conocida por sucursal (guardada en el equipo): si se cae el internet, incluso
/// tras reiniciar la app, el POS sigue abierto.
final cashSessionProvider = FutureProvider.autoDispose.family<CashSession?, String>((ref, branchId) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'percha.pos.cash.$branchId';
  try {
    final s = await ref.watch(posApiProvider).currentCash(branchId);
    s == null ? await prefs.remove(key) : await prefs.setString(key, jsonEncode(s.toJson()));
    return s;
  } on ApiError catch (e) {
    final saved = prefs.getString(key);
    if (e.isNetwork && saved != null) return CashSession.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    rethrow;
  }
});

/// Grilla: del servidor, o de la foto local si no hay conexión.
final productSearchProvider = FutureProvider.autoDispose.family<List<ProductSummary>, ({String branchId, String query})>(
  (ref, k) => withOfflineFallback(
    () => ref.watch(posApiProvider).products(search: k.query.isEmpty ? null : k.query, branchId: k.branchId),
    () => ref.read(posSnapshotProvider(k.branchId)).valueOrNull?.products(k.query),
  ),
);

/// Punto de venta. En tablet (≥ 900 px): catálogo a la izquierda y ticket a la derecha,
/// como en el mockup. En teléfono: catálogo y una barra inferior que abre el ticket.
class PosPage extends ConsumerWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(currentBranchProvider);
    final store = ref.watch(storeSettingsProvider);

    return switch ((branch, store)) {
      (AsyncData(value: final b), AsyncData(value: final s)) => _PosForBranch(branch: b, store: s),
      (AsyncError(:final error), _) || (_, AsyncError(:final error)) => Scaffold(
          appBar: AppBar(title: const Text('Vender')),
          body: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(errorText(error))),
        ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _PosForBranch extends ConsumerWidget {
  const _PosForBranch({required this.branch, required this.store});
  final Branch branch;
  final StoreSettings store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cash = ref.watch(cashSessionProvider(branch.id));
    return IdleLock(
      branchId: branch.id,
      child: Scaffold(
      appBar: _PosAppBar(branch: branch, cash: cash.valueOrNull),
      body: cash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(errorText(e))),
        data: (session) => session == null
            ? _OpenCashPanel(branch: branch)
            : LayoutBuilder(
                builder: (context, c) {
                  void refresh() => ref.invalidate(productSearchProvider);
                  if (c.maxWidth >= 900) {
                    return Row(
                      children: [
                        Expanded(child: Column(children: [OfflineBanner(branchId: branch.id), Expanded(child: _Catalog(branch: branch))])),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 400, child: TicketPanel(branch: branch, store: store, onSold: refresh)),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      OfflineBanner(branchId: branch.id),
                      Expanded(child: _Catalog(branch: branch)),
                      _TicketBar(branch: branch, store: store, onSold: refresh),
                    ],
                  );
                },
              ),
      ),
    ),
    );
  }
}

/// Teléfono: resumen fijo abajo; al tocarlo se abre el ticket completo.
class _TicketBar extends ConsumerWidget {
  const _TicketBar({required this.branch, required this.store, required this.onSold});
  final Branch branch;
  final StoreSettings store;
  final VoidCallback onSold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final total = cart.totals(taxRateBp: store.taxRateBp, pricesIncludeTax: store.pricesIncludeTax).total;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(PerchaSpace.lg),
        child: FilledButton(
          onPressed: cart.isEmpty
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (ctx) => SizedBox(
                      height: MediaQuery.of(ctx).size.height * 0.85,
                      child: TicketPanel(
                        branch: branch,
                        store: store,
                        onSold: () {
                          onSold();
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ),
                  ),
          child: Text(cart.isEmpty ? 'Ticket vacío' : 'Ver ticket · ${cart.units} prendas · ${formatCents(total)}'),
        ),
      ),
    );
  }
}
