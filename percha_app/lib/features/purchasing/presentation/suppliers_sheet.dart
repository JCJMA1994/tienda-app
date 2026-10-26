import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../lookup/lookup_api.dart';
import '../data/purchasing_api.dart';

Future<void> showSuppliersSheet(BuildContext context, {required bool canEdit}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SuppliersSheet(canEdit: canEdit),
    );

/// Crea o edita un proveedor. Devuelve el proveedor guardado.
Future<Supplier?> editSupplier(BuildContext context, WidgetRef ref, {Supplier? supplier}) async {
  final data = await showDialog<Map<String, Object?>>(context: context, builder: (_) => _SupplierDialog(supplier: supplier));
  if (data == null) return null;
  try {
    final saved = await ref.read(purchasingApiProvider).saveSupplier(id: supplier?.id, data: data);
    ref.invalidate(suppliersProvider);
    return saved;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    return null;
  }
}

class _SuppliersSheet extends ConsumerWidget {
  const _SuppliersSheet({required this.canEdit});
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Proveedores', style: Theme.of(context).textTheme.titleLarge)),
                  if (canEdit) TextButton.icon(onPressed: () => editSupplier(context, ref), icon: const Icon(Icons.add), label: const Text('Nuevo')),
                ],
              ),
            ),
            Expanded(
              child: ref.watch(suppliersProvider).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
                    data: (list) => list.isEmpty
                        ? const Center(child: Text('Aún no hay proveedores'))
                        : ListView(
                            children: [
                              for (final s in list)
                                ListTile(
                                  title: Text(s.name, style: TextStyle(fontWeight: FontWeight.w600, color: s.active ? null : PerchaColors.muted)),
                                  subtitle: Text([if (s.ruc != null) 'RUC ${s.ruc}', if (s.contactName != null) s.contactName!, if (s.phone != null) s.phone!].join(' · ')),
                                  trailing: s.active ? null : const Pill('Inactivo'),
                                  onTap: canEdit ? () => editSupplier(context, ref, supplier: s) : null,
                                ),
                            ],
                          ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierDialog extends ConsumerStatefulWidget {
  const _SupplierDialog({this.supplier});
  final Supplier? supplier;

  @override
  ConsumerState<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends ConsumerState<_SupplierDialog> {
  late final _name = TextEditingController(text: widget.supplier?.name);
  late final _ruc = TextEditingController(text: widget.supplier?.ruc);
  late final _contact = TextEditingController(text: widget.supplier?.contactName);
  late final _phone = TextEditingController(text: widget.supplier?.phone);
  late bool _active = widget.supplier?.active ?? true;
  final _form = GlobalKey<FormState>();
  String? _error;
  String? _warning;

  Future<void> _lookupRuc() async {
    setState(() {
      _error = null;
      _warning = null;
    });
    try {
      final r = await ref.read(lookupApiProvider).ruc(_ruc.text.trim());
      setState(() {
        _name.text = r.name;
        _warning = r.warnings.isEmpty ? null : r.warnings.join(' · ');
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _ruc, _contact, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    if (!submitForm(_form)) return;
    final ruc = _opt(_ruc);
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'ruc': ruc,
      'contactName': _opt(_contact),
      'phone': _opt(_phone),
      if (widget.supplier != null) 'active': _active,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.supplier == null ? 'Nuevo proveedor' : 'Editar proveedor'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: PerchaSpace.md)],
            AppTextField(controller: _name, label: 'Nombre o razón social', autofocus: true, validator: V.all([V.minLength(2, 'Ingresa el nombre'), V.maxLength(120)])),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(
              controller: _ruc,
              label: 'RUC (opcional)',
              kind: FieldKind.ruc,
              validator: V.ruc(optional: true),
              onSubmitted: (_) => _lookupRuc(),
              suffix: IconButton(tooltip: 'Buscar en SUNAT', icon: const Icon(Icons.search), onPressed: _lookupRuc),
            ),
            if (_warning != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Atención: $_warning', style: TextStyle(color: PerchaColors.warn))),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: _contact, label: 'Contacto (opcional)', kind: FieldKind.name, validator: V.maxLength(80)),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: _phone, label: 'Celular (opcional)', kind: FieldKind.phone, validator: V.phone(optional: true), last: true, onSubmitted: (_) => _save()),
            if (widget.supplier != null)
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: _active, onChanged: (v) => setState(() => _active = v)),
          ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
