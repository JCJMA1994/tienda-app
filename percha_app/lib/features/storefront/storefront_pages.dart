import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/forms/app_form.dart';
import '../../core/forms/validators.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/action_runner.dart';
import '../../core/widgets/percha_widgets.dart';
import '../auth/application/session_controller.dart';
import '../layaways/layaways_pages.dart';
import '../onboarding/data/store_api.dart';
import 'storefront_api.dart';

final _branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) => ref.watch(storeApiProvider).branches());

/// Configurar el catálogo en línea y compartir su enlace.
class CatalogSettingsPage extends ConsumerStatefulWidget {
  const CatalogSettingsPage({super.key});

  @override
  ConsumerState<CatalogSettingsPage> createState() => _CatalogSettingsPageState();
}

class _CatalogSettingsPageState extends ConsumerState<CatalogSettingsPage> with ActionRunner {
  final _form = GlobalKey<FormState>();
  final _slug = TextEditingController();
  final _whatsapp = TextEditingController();
  final _description = TextEditingController();
  bool _enabled = false;
  String? _branchId;
  String? _url;
  int _published = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(storefrontApiProvider).settings().then((s) {
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled;
        _slug.text = s.slug ?? _suggestSlug(ref.read(meProvider).tenantName);
        _whatsapp.text = s.whatsapp ?? '';
        _description.text = s.description ?? '';
        _branchId = s.branchId;
        _url = s.url;
        _published = s.published;
        _loaded = true;
      });
    });
  }

  /// "Boutique Alma" → "boutique-alma".
  static String _suggestSlug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp('[áàä]'), 'a')
      .replaceAll(RegExp('[éèë]'), 'e')
      .replaceAll(RegExp('[íìï]'), 'i')
      .replaceAll(RegExp('[óòö]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  @override
  void dispose() {
    for (final c in [_slug, _whatsapp, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!submitForm(_form)) return;
    final s = await runAction(
      () => ref.read(storefrontApiProvider).save({
        'enabled': _enabled,
        'slug': _slug.text.trim(),
        'whatsapp': _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
        'branchId': _branchId,
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      }),
      success: 'Catálogo guardado',
    );
    if (s != null) setState(() => _url = s.url);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final branches = ref.watch(_branchesProvider).valueOrNull ?? const <Branch>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo en línea')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                children: [
                  Text('Un enlace con tus prendas, precios y tallas disponibles en tiempo real. Compártelo por WhatsApp o en tu Instagram: los clientes eligen y te llega el pedido.', style: text.bodySmall),
                  const SizedBox(height: PerchaSpace.md),
                  if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
                  Card(
                    child: SwitchListTile(
                      title: const Text('Catálogo visible', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('$_published producto${_published == 1 ? '' : 's'} publicado${_published == 1 ? '' : 's'} · se publican desde el detalle de cada producto'),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ),
                  const SizedBox(height: PerchaSpace.lg),
                  AppTextField(
                    controller: _slug,
                    label: 'Nombre del enlace',
                    hint: 'boutique-alma',
                    helper: 'Así se verá: …/c/${_slug.text.isEmpty ? 'tu-tienda' : _slug.text}',
                    maxLength: 40,
                    onChanged: (_) => setState(() {}),
                    validator: (v) => RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,38})[a-z0-9]$').hasMatch((v ?? '').trim()) ? null : 'De 3 a 40 minúsculas, números o guiones',
                  ),
                  const SizedBox(height: PerchaSpace.md),
                  AppTextField(
                    controller: _whatsapp,
                    label: 'WhatsApp para pedidos',
                    hint: '51987654321',
                    kind: FieldKind.integer,
                    maxLength: 15,
                    helper: 'Con código de país. El cliente podrá escribirte después de pedir.',
                    validator: (v) => (v ?? '').isEmpty || RegExp(r'^\d{8,15}$').hasMatch(v!) ? null : 'Ej. 51987654321',
                  ),
                  const SizedBox(height: PerchaSpace.md),
                  DropdownButtonFormField<String?>(
                    value: _branchId,
                    decoration: const InputDecoration(labelText: 'Stock que se muestra', helperText: 'Nunca se muestra la cantidad exacta: solo "Disponible", "Últimas unidades" o "Agotado"'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todas las sucursales')),
                      for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.name)),
                    ],
                    onChanged: (v) => setState(() => _branchId = v),
                  ),
                  const SizedBox(height: PerchaSpace.md),
                  AppTextField(controller: _description, label: 'Descripción (opcional)', hint: 'Ropa para el día a día · envíos a todo Lima', maxLines: 2, validator: V.maxLength(300), last: true),
                  if (_url != null && _enabled) ...[
                    const SizedBox(height: PerchaSpace.xl),
                    Text('Comparte tu catálogo', style: text.titleMedium),
                    const SizedBox(height: PerchaSpace.sm),
                    SelectableText(_url!, style: TextStyle(color: PerchaColors.accentInk, fontWeight: FontWeight.w600)),
                    const SizedBox(height: PerchaSpace.md),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(PerchaRadius.card)),
                        child: QrImageView(data: _url!, size: 160, backgroundColor: Colors.white),
                      ),
                    ),
                    const SizedBox(height: PerchaSpace.sm),
                    Text('Imprime el QR para tu vitrina o mostrador.', textAlign: TextAlign.center, style: text.bodySmall),
                    const SizedBox(height: PerchaSpace.md),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar'),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _url!));
                            snack('Enlace copiado');
                          },
                        ),
                      ),
                      const SizedBox(width: PerchaSpace.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('WhatsApp'),
                          onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent('Mira nuestras prendas y pide aquí: $_url')}'), mode: LaunchMode.externalApplication),
                        ),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: BusyButton(label: 'Guardar', busy: busy, onPressed: _loaded ? _save : null)),
      ),
    );
  }
}

/// Pedidos que llegan desde el catálogo (los nuevos primero).
class CatalogOrdersPage extends ConsumerWidget {
  const CatalogOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('d MMM, HH:mm', 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos del catálogo')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(catalogOrdersProvider),
        child: ref.watch(catalogOrdersProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(padding: const EdgeInsets.all(20), children: [ErrorBanner(errorText(e))]),
              data: (list) => list.isEmpty
                  ? ListView(children: const [SizedBox(height: 120), Center(child: Text('Aún no hay pedidos. Comparte tu catálogo desde Más → Catálogo en línea.', textAlign: TextAlign.center))])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: PerchaSpace.sm),
                      itemBuilder: (_, i) {
                        final o = list[i];
                        return Card(
                          child: ListTile(
                            title: Text('#${o.number} · ${o.customerName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${formatCents(o.totalCents)} · ${date.format(o.createdAt)}'),
                            trailing: Pill(o.statusLabel, warn: o.status == 'new'),
                            onTap: () async {
                              await context.push('/catalog/orders/${o.id}');
                              ref.invalidate(catalogOrdersProvider);
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

class CatalogOrderPage extends ConsumerStatefulWidget {
  const CatalogOrderPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<CatalogOrderPage> createState() => _CatalogOrderPageState();
}

class _CatalogOrderPageState extends ConsumerState<CatalogOrderPage> with ActionRunner {
  void _refresh() => ref
    ..invalidate(catalogOrderProvider(widget.id))
    ..invalidate(catalogOrdersProvider);

  Future<void> _status(String status, String done) async {
    await runAction(() => ref.read(storefrontApiProvider).setStatus(widget.id, status), success: done, errorAsSnack: true);
    _refresh();
  }

  /// Crea (o reutiliza) la ficha del cliente y abre el flujo de apartado con sus prendas.
  Future<void> _layaway(CatalogOrder o) async {
    final branch = await ref.read(currentBranchProvider.future);
    final customerId = await runAction(() => ref.read(storefrontApiProvider).linkCustomer(o.id), errorAsSnack: true);
    if (customerId == null || !mounted) return;
    final l = await createLayawayFlow(
      context,
      ref,
      branchId: branch.id,
      customerId: customerId,
      totalCents: o.totalCents,
      items: [for (final i in o.items) (variantId: i.variantId, quantity: i.quantity)],
    );
    if (l == null || !mounted) return;
    await ref.read(storefrontApiProvider).setStatus(o.id, 'completed');
    _refresh();
    snack('Apartado #${l.number} creado');
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(),
      body: ref.watch(catalogOrderProvider(widget.id)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (o) {
              final text = Theme.of(context).textTheme;
              final greeting = Uri.encodeComponent('Hola ${o.customerName.split(' ').first}, te escribimos por tu pedido #${o.number}.');
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Row(children: [Expanded(child: Text('Pedido #${o.number}', style: text.headlineSmall)), Pill(o.statusLabel, warn: o.status == 'new')]),
                  Text('${o.customerName} · +${o.customerPhone}', style: text.titleMedium),
                  if (o.note != null) ...[const SizedBox(height: PerchaSpace.sm), Text('"${o.note}"', style: text.bodyMedium)],
                  const SizedBox(height: PerchaSpace.lg),
                  Card(
                    child: Column(children: [
                      for (final i in o.items)
                        ListTile(
                          title: Text('${i.quantity} × ${i.name}'),
                          subtitle: i.options.isEmpty ? null : Text(i.options),
                          trailing: Text(formatCents(i.unitPriceCents * i.quantity)),
                        ),
                      ListTile(title: const Text('Total referencial', style: TextStyle(fontWeight: FontWeight.w600)), trailing: Text(formatCents(o.totalCents), style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                  ),
                  Text('El pedido no separa las prendas: confírmalo con el cliente y apártalo o véndelo.', style: text.bodySmall),
                  const SizedBox(height: PerchaSpace.xl),
                  FilledButton.icon(
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Escribir por WhatsApp'),
                    onPressed: () async {
                      await launchUrl(Uri.parse('https://wa.me/${o.customerPhone}?text=$greeting'), mode: LaunchMode.externalApplication);
                      if (o.status == 'new') await _status('contacted', 'Marcado como contactado');
                    },
                  ),
                  if (o.open && me.can('customers.write') && me.can('sales.create')) ...[
                    const SizedBox(height: PerchaSpace.sm),
                    OutlinedButton.icon(onPressed: busy ? null : () => _layaway(o), icon: const Icon(Icons.bookmark_add_outlined), label: const Text('Apartar estas prendas')),
                  ],
                  if (o.open) ...[
                    const SizedBox(height: PerchaSpace.sm),
                    OutlinedButton(onPressed: busy ? null : () => _status('completed', 'Pedido atendido'), child: const Text('Marcar como atendido')),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: PerchaColors.warn),
                      onPressed: busy ? null : () => _status('cancelled', 'Pedido cancelado'),
                      child: const Text('Cancelar pedido'),
                    ),
                  ],
                ],
              );
            },
          ),
    );
  }
}
