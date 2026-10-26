import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../onboarding/data/store_api.dart';
import '../data/einvoice_api.dart';

/// Configuración de boletas y facturas electrónicas (dueño/encargado) y seguimiento de
/// comprobantes con problemas.
class EInvoiceSettingsPage extends ConsumerStatefulWidget {
  const EInvoiceSettingsPage({super.key});

  @override
  ConsumerState<EInvoiceSettingsPage> createState() => _EInvoiceSettingsPageState();
}

class _SeriesCtrl {
  /// Por defecto cada sucursal recibe series distintas (B001, B002…): no pueden repetirse.
  _SeriesCtrl(this.branch, Map<String, dynamic>? s, int index)
      : boleta = TextEditingController(text: s?['boleta'] as String? ?? 'B${_n(index, 3)}'),
        factura = TextEditingController(text: s?['factura'] as String? ?? 'F${_n(index, 3)}'),
        ncBoleta = TextEditingController(text: s?['ncBoleta'] as String? ?? 'BC${_n(index, 2)}'),
        ncFactura = TextEditingController(text: s?['ncFactura'] as String? ?? 'FC${_n(index, 2)}'),
        guia = TextEditingController(text: s?['guia'] as String? ?? 'T${_n(index, 3)}');

  static String _n(int i, int width) => (i + 1).toString().padLeft(width, '0');
  final Branch branch;
  final TextEditingController boleta, factura, ncBoleta, ncFactura, guia;
  void dispose() {
    for (final c in [boleta, factura, ncBoleta, ncFactura, guia]) {
      c.dispose();
    }
  }
  Map<String, String> toJson() => {
        'branchId': branch.id,
        'boleta': boleta.text.trim().toUpperCase(),
        'factura': factura.text.trim().toUpperCase(),
        'ncBoleta': ncBoleta.text.trim().toUpperCase(),
        'ncFactura': ncFactura.text.trim().toUpperCase(),
        'guia': guia.text.trim().toUpperCase(),
      };
}

class _EInvoiceSettingsPageState extends ConsumerState<EInvoiceSettingsPage> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _enabled = false;
  bool _hasToken = false;
  String _provider = 'nubefact';
  List<String> _providers = const ['nubefact'];
  final _legalName = TextEditingController();
  final _address = TextEditingController();
  final _apiUrl = TextEditingController();
  final _token = TextEditingController();
  List<_SeriesCtrl> _series = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_legalName, _address, _apiUrl, _token]) {
      c.dispose();
    }
    for (final s in _series) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(einvoiceApiProvider).settings();
      final branches = await ref.read(storeApiProvider).branches();
      final saved = (s['series'] as List<dynamic>).cast<Map<String, dynamic>>();
      setState(() {
        _enabled = s['enabled'] as bool;
        _hasToken = s['hasToken'] as bool;
        _providers = (s['providers'] as List<dynamic>).cast<String>();
        _provider = _providers.contains(s['provider']) ? s['provider'] as String : _providers.first;
        _legalName.text = s['legalName'] as String? ?? '';
        _address.text = s['fiscalAddress'] as String? ?? '';
        _apiUrl.text = s['apiUrl'] as String? ?? '';
        _series = [for (final (i, b) in branches.indexed) _SeriesCtrl(b, saved.where((x) => x['branchId'] == b.id).firstOrNull, i)];
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !submitForm(_form)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(einvoiceApiProvider).save({
        'enabled': _enabled,
        'provider': _provider,
        'legalName': _legalName.text.trim(),
        'fiscalAddress': _address.text.trim(),
        'apiUrl': _apiUrl.text.trim(),
        if (_token.text.trim().isNotEmpty) 'token': _token.text.trim(),
        'series': [for (final s in _series) s.toJson()],
      });
      _token.clear();
      ref.invalidate(einvoiceStatusProvider); // el POS empieza (o deja) de emitir
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuración guardada')));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Comprobantes electrónicos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              children: [
                Text('Boletas, facturas y notas de crédito se envían a SUNAT a través de tu OSE (por ejemplo, Nubefact).', style: text.bodySmall),
                const SizedBox(height: PerchaSpace.md),
                if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: PerchaSpace.md)],
                Card(
                  child: SwitchListTile(
                    title: const Text('Emitir comprobantes en cada venta', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Por defecto, boleta a "Clientes varios"; el vendedor puede elegir factura'),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                ),
                const SizedBox(height: PerchaSpace.lg),
                Text('Datos fiscales', style: text.titleMedium),
                const SizedBox(height: PerchaSpace.sm),
                AppTextField(controller: _legalName, label: 'Razón social (como en SUNAT)', kind: FieldKind.upper, validator: V.all([V.minLength(2, 'Ingresa la razón social'), V.maxLength(200)])),
                const SizedBox(height: PerchaSpace.md),
                AppTextField(controller: _address, label: 'Dirección fiscal', validator: V.all([V.minLength(5, 'Ingresa la dirección fiscal'), V.maxLength(300)])),
                const SizedBox(height: PerchaSpace.lg),
                Text('Conexión con el OSE', style: text.titleMedium),
                const SizedBox(height: PerchaSpace.sm),
                DropdownButtonFormField<String>(
                  value: _provider,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                  items: [for (final p in _providers) DropdownMenuItem(value: p, child: Text(p == 'nubefact' ? 'Nubefact' : p))],
                  onChanged: (v) => setState(() => _provider = v ?? _provider),
                ),
                const SizedBox(height: PerchaSpace.md),
                AppTextField(controller: _apiUrl, label: 'Ruta de la API', kind: FieldKind.url, helper: 'En Nubefact: tu cuenta → API (integración)', validator: V.url()),
                const SizedBox(height: PerchaSpace.md),
                AppTextField(
                  controller: _token,
                  label: 'Token',
                  kind: FieldKind.password,
                  // Nunca se muestra el guardado: solo se puede reemplazar.
                  helper: _hasToken ? 'Ya hay un token guardado (cifrado). Escribe uno nuevo solo para cambiarlo.' : 'Se guarda cifrado',
                  validator: (v) => !_hasToken && _enabled && (v ?? '').trim().length < 10 ? 'Pega el token de tu OSE' : null,
                ),
                const SizedBox(height: PerchaSpace.lg),
                Text('Series por sucursal', style: text.titleMedium),
                const SizedBox(height: 4),
                Text('4 caracteres. Las de boleta y su nota de crédito empiezan con B; las de factura, con F.', style: text.bodySmall),
                for (final s in _series)
                  Card(
                    margin: const EdgeInsets.only(top: PerchaSpace.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(s.branch.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: PerchaSpace.sm),
                          Row(children: [
                            Expanded(child: AppTextField(controller: s.boleta, label: 'Boleta', kind: FieldKind.upper, maxLength: 4, validator: V.serie('B'))),
                            const SizedBox(width: 8),
                            Expanded(child: AppTextField(controller: s.factura, label: 'Factura', kind: FieldKind.upper, maxLength: 4, validator: V.serie('F'))),
                          ]),
                          const SizedBox(height: PerchaSpace.sm),
                          Row(children: [
                            Expanded(child: AppTextField(controller: s.ncBoleta, label: 'NC boleta', kind: FieldKind.upper, maxLength: 4, validator: V.serie('B'))),
                            const SizedBox(width: 8),
                            Expanded(child: AppTextField(controller: s.ncFactura, label: 'NC factura', kind: FieldKind.upper, maxLength: 4, validator: V.serie('F'))),
                          ]),
                          const SizedBox(height: PerchaSpace.sm),
                          AppTextField(controller: s.guia, label: 'Guía de remisión (transferencias)', kind: FieldKind.upper, maxLength: 4, validator: V.serie('T')),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: PerchaSpace.xl),
                Text('Comprobantes que necesitan atención', style: text.titleMedium),
                const SizedBox(height: PerchaSpace.sm),
                const _ProblemDocs(),
              ],
            ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: BusyButton(label: 'Guardar', busy: _saving, onPressed: _loading ? null : _save),
        ),
      ),
    );
  }
}

class _ProblemDocs extends ConsumerWidget {
  const _ProblemDocs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(problemDocsProvider).when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (docs) => docs.isEmpty
              ? const Text('Todo enviado y aceptado.')
              : Card(
                  child: Column(
                    children: [
                      for (final d in docs)
                        ListTile(
                          title: Text('${d.kindLabel} ${d.code} · ${formatCents(d.totalCents)}'),
                          subtitle: Text(d.lastError ?? d.sunatDescription ?? d.statusLabel),
                          trailing: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Pill(d.statusLabel, warn: d.status != 'pending'),
                              if (d.canRetry)
                                IconButton(
                                  tooltip: 'Reintentar',
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () async {
                                    try {
                                      await ref.read(einvoiceApiProvider).retry(d.id);
                                    } catch (_) {}
                                    ref.invalidate(problemDocsProvider);
                                  },
                                ),
                            ],
                          ),
                          // Un rechazado se corrige anulando la venta (nota de crédito no aplica) y
                          // emitiendo de nuevo con los datos correctos.
                          onTap: d.saleId == null ? null : () => context.push('/sales/${d.saleId}'),
                        ),
                    ],
                  ),
                ),
        );
  }
}
