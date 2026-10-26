import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../data/store_api.dart';
import 'onboarding_scaffold.dart';

class _AttrDraft {
  _AttrDraft(this.name, this.values, {this.existing = false}) : enabled = true;
  String name;
  final List<String> values;
  bool enabled;

  /// Ya existe en la API: no se vuelve a crear (el paso se puede repetir sin duplicar).
  final bool existing;
}

class AttributesStepPage extends ConsumerStatefulWidget {
  const AttributesStepPage({super.key});

  @override
  ConsumerState<AttributesStepPage> createState() => _AttributesStepPageState();
}

class _AttributesStepPageState extends ConsumerState<AttributesStepPage> {
  // Valores sugeridos para una boutique; el dueño los edita.
  final List<_AttrDraft> _attrs = [
    _AttrDraft('Talla', ['XS', 'S', 'M', 'L', 'XL']),
    _AttrDraft('Color', ['Negro', 'Blanco', 'Beige', 'Azul']),
  ];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final existing = await ref.read(storeApiProvider).attributes();
      if (existing.isNotEmpty) {
        _attrs
          ..clear()
          ..addAll(existing.map((a) => _AttrDraft(
                a['name'] as String,
                (a['values'] as List<dynamic>).map((v) => (v as Map<String, dynamic>)['value'] as String).toList(),
                existing: true,
              ),),);
      }
    } catch (e) {
      _error = errorText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _ask(String title, String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Agregar')),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _addValue(_AttrDraft attr) async {
    final v = await _ask('Nuevo valor de ${attr.name}', 'Valor');
    if (v == null || v.isEmpty) return;
    if (attr.values.any((x) => x.toLowerCase() == v.toLowerCase())) return;
    setState(() => attr.values.add(v));
  }

  Future<void> _addAttribute() async {
    final name = await _ask('Otro atributo', 'Ej. Material, Largo, Horma');
    if (name == null || name.isEmpty) return;
    setState(() => _attrs.add(_AttrDraft(name, [])));
    await _addValue(_attrs.last);
  }

  Future<void> _save() async {
    final toCreate = _attrs.where((a) => a.enabled && !a.existing).toList();
    if (toCreate.any((a) => a.values.isEmpty)) {
      setState(() => _error = 'Cada atributo activo necesita al menos un valor');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(storeApiProvider);
      for (final (i, a) in toCreate.indexed) {
        await api.createAttribute(name: a.name, position: i, values: a.values);
      }
      ref.read(sessionProvider.notifier).finishOnboarding();
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 2,
      title: '¿Cómo varían tus productos?',
      subtitle: 'Cada combinación tendrá su propio stock y código de barras.',
      onBack: () => context.go('/onboarding/business'),
      onSkip: () {
        ref.read(sessionProvider.notifier).finishOnboarding();
        context.go('/home');
      },
      action: BusyButton(label: 'Continuar', busy: _saving, onPressed: _loading ? null : _save),
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: PerchaSpace.lg)],
                for (final a in _attrs) ...[
                  _AttributeCard(
                    attr: a,
                    onToggle: a.existing ? null : (v) => setState(() => a.enabled = v),
                    onRemoveValue: a.existing ? null : (v) => setState(() => a.values.remove(v)),
                    onAddValue: a.existing ? null : () => _addValue(a),
                  ),
                  const SizedBox(height: PerchaSpace.md),
                ],
                OutlinedButton(onPressed: _addAttribute, child: const Text('+ Otro atributo (material, largo, horma…)')),
              ],
            ),
    );
  }
}

class _AttributeCard extends StatelessWidget {
  const _AttributeCard({required this.attr, this.onToggle, this.onRemoveValue, this.onAddValue});
  final _AttrDraft attr;
  final ValueChanged<bool>? onToggle;
  final ValueChanged<String>? onRemoveValue;
  final VoidCallback? onAddValue;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(PerchaSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(attr.name, style: Theme.of(context).textTheme.titleMedium)),
                if (attr.existing)
                  const Pill('Configurado')
                else
                  Switch(value: attr.enabled, onChanged: onToggle),
              ],
            ),
            if (attr.enabled) ...[
              const SizedBox(height: PerchaSpace.md),
              Wrap(
                spacing: PerchaSpace.sm,
                runSpacing: PerchaSpace.sm,
                children: [
                  for (final v in attr.values)
                    InputChip(
                      label: Text(v),
                      backgroundColor: PerchaColors.accentSoft,
                      labelStyle: TextStyle(color: PerchaColors.accentInk, fontWeight: FontWeight.w500),
                      side: BorderSide.none,
                      onDeleted: onRemoveValue == null ? null : () => onRemoveValue!(v),
                      deleteButtonTooltipMessage: 'Quitar $v',
                    ),
                  if (onAddValue != null) ActionChip(label: const Text('+ Agregar'), onPressed: onAddValue),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
