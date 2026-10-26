import '../../core/widgets/action_runner.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/forms/app_form.dart';
import '../../core/forms/validators.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/percha_widgets.dart';
import '../auth/application/session_controller.dart';
import '../lookup/lookup_api.dart';
import 'customers_api.dart';

/// Lista con búsqueda por nombre, documento o celular.
class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  Timer? _debounce;
  String _q = '';
  late Future<List<CustomerSummary>> _future = ref.read(customersApiProvider).search(null);

  void _search(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() {
          _q = v.trim();
          _future = ref.read(customersApiProvider).search(_q.isEmpty ? null : _q);
        }),);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(meProvider).can('customers.write');
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () async {
                final c = await showCustomerForm(context, ref);
                if (c != null && context.mounted) await context.push('/customers/${c.id}');
              },
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Nuevo'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(onChanged: _search, decoration: const InputDecoration(hintText: 'Nombre, DNI/RUC o celular', prefixIcon: Icon(Icons.search))),
        ),
        Expanded(
          child: FutureBuilder(
            future: _future,
            builder: (_, snap) {
              if (snap.hasError) return Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(snap.error!)));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              if (list.isEmpty) return Center(child: Text(_q.isEmpty ? 'Aún no hay clientes. Se crean solos al emitir boletas con DNI.' : 'Sin resultados', textAlign: TextAlign.center));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: PerchaSpace.sm),
                itemBuilder: (_, i) {
                  final c = list[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: PerchaColors.accentSoft, foregroundColor: PerchaColors.accentInk, child: Text(c.name.characters.first.toUpperCase())),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([c.docLabel, if (c.phone != null) c.phone!].where((x) => x.isNotEmpty).join(' · ')),
                      trailing: c.whatsappOptIn ? Icon(Icons.chat_outlined, size: 18, color: PerchaColors.success) : null,
                      onTap: () => context.push('/customers/${c.id}'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],),
    );
  }
}

/// Ficha: datos, preferencias (talla habitual), historial y permisos de contacto.
class CustomerPage extends ConsumerWidget {
  const CustomerPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final date = DateFormat("d MMM yyyy", 'es');
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (me.can('customers.write'))
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final c = ref.read(customerDetailProvider(id)).valueOrNull;
                if (c == null) return;
                await showCustomerForm(context, ref, existing: c);
                ref.invalidate(customerDetailProvider(id));
              },
            ),
        ],
      ),
      body: ref.watch(customerDetailProvider(id)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (c) {
              final s = c.summary;
              final text = Theme.of(context).textTheme;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Text(s.name, style: text.headlineSmall),
                  Text([s.docLabel, if (s.phone != null) s.phone!, if (c.email != null) c.email!].where((x) => x.isNotEmpty).join(' · '), style: text.bodySmall),
                  const SizedBox(height: PerchaSpace.lg),
                  Wrap(spacing: PerchaSpace.md, runSpacing: PerchaSpace.md, children: [
                    _Stat('Compras', '${c.purchases}'),
                    _Stat('Gastó', formatCents(c.spentCents)),
                    _Stat('Última visita', c.lastPurchaseAt == null ? '—' : date.format(c.lastPurchaseAt!)),
                    _Stat('Talla habitual', c.topSizes.isEmpty ? '—' : c.topSizes.join(', ')),
                    // Lo que hay que recordarle al cliente apenas llega.
                    if (c.creditBalanceCents > 0) _Stat('Saldo a favor', formatCents(c.creditBalanceCents)),
                    if (c.openLayaways > 0) _Stat('Apartados abiertos', '${c.openLayaways}'),
                  ],),
                  if (c.openLayaways > 0)
                    TextButton(onPressed: () => context.push('/layaways'), child: const Text('Ver apartados')),
                  if (c.birthday != null) ...[
                    const SizedBox(height: PerchaSpace.md),
                    Text('Cumpleaños: ${_birthday(c.birthday!)}', style: text.bodyMedium),
                  ],
                  if (c.notes != null) ...[const SizedBox(height: PerchaSpace.sm), Text(c.notes!, style: text.bodySmall)],
                  const SizedBox(height: PerchaSpace.lg),
                  Card(
                    child: SwitchListTile(
                      title: const Text('Acepta recibir WhatsApp de la tienda'),
                      subtitle: const Text('Solo con su permiso expreso. Queda registrado.'),
                      value: s.whatsappOptIn,
                      onChanged: me.can('customers.write')
                          ? (v) async {
                              await ref.read(customersApiProvider).update(id, {'whatsappOptIn': v});
                              ref.invalidate(customerDetailProvider(id));
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: PerchaSpace.xl),
                  Text('Compras', style: text.titleMedium),
                  const SizedBox(height: PerchaSpace.sm),
                  if (c.recentSales.isEmpty) const Text('Sin compras registradas'),
                  for (final sale in c.recentSales)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Ticket #${sale.number}'),
                      subtitle: Text(date.format(sale.at)),
                      trailing: Text(sale.voided ? 'Anulada' : formatCents(sale.totalCents), style: TextStyle(color: sale.voided ? PerchaColors.muted : null, fontWeight: FontWeight.w600)),
                      onTap: () => context.push('/sales/${sale.id}'),
                    ),
                  if (me.can('settings.manage')) ...[
                    const SizedBox(height: PerchaSpace.xl),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: PerchaColors.warn),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Eliminar datos del cliente'),
                            content: const Text('Se borran nombre, documento, celular y notas (derecho de cancelación). Sus compras se conservan sin datos personales. No se puede deshacer.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar datos')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await ref.read(customersApiProvider).anonymize(id);
                        if (context.mounted) context.pop();
                      },
                      child: const Text('Eliminar datos personales'),
                    ),
                  ],
                ],
              );
            },
          ),
    );
  }

  static String _birthday(String mmdd) {
    final p = mmdd.split('-');
    return DateFormat("d 'de' MMMM", 'es').format(DateTime(2000, int.parse(p[0]), int.parse(p[1])));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: PerchaType.title)),
            ],),
          ),
        ),
      );
}

/// Alta o edición. Con DNI/RUC, la lupa completa el nombre (RENIEC/SUNAT).
Future<CustomerSummary?> showCustomerForm(BuildContext context, WidgetRef ref, {CustomerDetail? existing}) =>
    showDialog<CustomerSummary>(context: context, builder: (_) => _CustomerForm(existing: existing));

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.existing});
  final CustomerDetail? existing;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> with ActionRunner {
  final _form = GlobalKey<FormState>();
  late String _docType = widget.existing?.summary.docType ?? 'dni';
  late final _doc = TextEditingController(text: widget.existing?.summary.docNumber ?? '');
  late final _name = TextEditingController(text: widget.existing?.summary.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.summary.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _birthday = TextEditingController(text: widget.existing?.birthday ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late bool _optIn = widget.existing?.summary.whatsappOptIn ?? false;

  @override
  void dispose() {
    for (final c in [_doc, _name, _phone, _email, _birthday, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _lookup() async {
    try {
      final api = ref.read(lookupApiProvider);
      final r = _docType == 'ruc' ? await api.ruc(_doc.text.trim()) : await api.dni(_doc.text.trim());
      setState(() => _name.text = r.name);
    } catch (e) {
      setState(() => error = '${errorText(e)}. Puedes escribir el nombre a mano.');
    }
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (busy || !submitForm(_form)) return;
    final body = <String, Object?>{
      'docType': _opt(_doc) == null ? null : _docType,
      'docNumber': _opt(_doc),
      'name': _name.text.trim(),
      'phone': _opt(_phone),
      'email': _opt(_email),
      'birthday': _opt(_birthday),
      'notes': _opt(_notes),
      'whatsappOptIn': _optIn,
    };
    await runAction(() async {
      final api = ref.read(customersApiProvider);
      if (widget.existing != null) {
        await api.update(widget.existing!.summary.id, body);
        if (mounted) Navigator.pop(context, widget.existing!.summary);
      } else {
        final c = await api.create(body);
        if (mounted) Navigator.pop(context, c);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo cliente' : 'Editar cliente'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'dni', label: Text('DNI')), ButtonSegment(value: 'ruc', label: Text('RUC')), ButtonSegment(value: 'ce', label: Text('CE'))],
              selected: {_docType},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _docType = s.first),
            ),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(
              key: ValueKey(_docType),
              controller: _doc,
              label: 'Documento (opcional)',
              kind: _docType == 'dni' ? FieldKind.dni : _docType == 'ruc' ? FieldKind.ruc : FieldKind.upper,
              maxLength: _docType == 'ce' ? 12 : null,
              validator: (v) => (v ?? '').trim().isEmpty ? null : (_docType == 'dni' ? V.dni() : _docType == 'ruc' ? V.ruc() : V.minLength(8))(v),
              suffix: _docType == 'ce' ? null : IconButton(tooltip: 'Buscar', icon: const Icon(Icons.search), onPressed: _lookup),
            ),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: _name, label: 'Nombre', kind: FieldKind.name, validator: V.all([V.minLength(2, 'Ingresa el nombre'), V.maxLength(120)])),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: _phone, label: 'Celular (opcional)', kind: FieldKind.phone, validator: V.phone(optional: true)),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: _email, label: 'Correo (opcional)', kind: FieldKind.email, validator: (v) => (v ?? '').trim().isEmpty ? null : V.email()(v)),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(
              controller: _birthday,
              label: 'Cumpleaños (opcional)',
              hint: 'MM-DD, ej. 03-15',
              maxLength: 5,
              helper: 'Sin año: basta para saludar',
              validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$').hasMatch(v!.trim()) ? null : 'Formato MM-DD',
            ),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: _notes, label: 'Notas (opcional)', hint: 'Prefiere tonos neutros', maxLines: 2, validator: V.maxLength(500)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _optIn,
              onChanged: (v) => setState(() => _optIn = v ?? false),
              title: const Text('Acepta recibir WhatsApp de la tienda'),
              subtitle: const Text('Pregúntale y marca solo si dice que sí'),
            ),
          ],),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: busy ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

/// Selector rápido para el POS: buscar o crear, devuelve el cliente elegido.
Future<CustomerSummary?> pickCustomer(BuildContext context, WidgetRef ref) => showModalBottomSheet<CustomerSummary>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CustomerPicker(),
    );

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  Timer? _debounce;
  List<CustomerSummary> _results = const [];

  @override
  void initState() {
    super.initState();
    _find('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _find(String q) async {
    try {
      final r = await ref.read(customersApiProvider).search(q.trim().isEmpty ? null : q.trim());
      if (mounted) setState(() => _results = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Cliente de la venta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: PerchaSpace.sm),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Nombre, DNI o celular', prefixIcon: Icon(Icons.search)),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => _find(v));
              },
            ),
            Expanded(
              child: ListView(children: [
                for (final c in _results)
                  ListTile(
                    title: Text(c.name),
                    subtitle: Text([c.docLabel, if (c.phone != null) c.phone!].where((x) => x.isNotEmpty).join(' · ')),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Nuevo cliente'),
              onPressed: () async {
                final c = await showCustomerForm(context, ref);
                if (c != null && context.mounted) Navigator.pop(context, c);
              },
            ),
          ],),
        ),
      ),
    );
  }
}
