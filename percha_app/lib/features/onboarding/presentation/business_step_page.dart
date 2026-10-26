import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../data/store_api.dart';
import 'onboarding_scaffold.dart';

class BusinessStepPage extends ConsumerStatefulWidget {
  const BusinessStepPage({super.key});

  @override
  ConsumerState<BusinessStepPage> createState() => _BusinessStepPageState();
}

class _BusinessStepPageState extends ConsumerState<BusinessStepPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ruc = TextEditingController();
  final _address = TextEditingController();
  String _currency = 'PEN';
  int _taxRateBp = 1800;
  bool _pricesIncludeTax = true;
  Branch? _branch;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(storeApiProvider);
      final store = await api.get();
      final branch = await ref.read(currentBranchProvider.future);
      _name.text = store.name;
      _ruc.text = store.ruc ?? '';
      _address.text = branch.address ?? '';
      setState(() {
        _currency = store.currency;
        _taxRateBp = store.taxRateBp;
        _pricesIncludeTax = store.pricesIncludeTax;
        _branch = branch;
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _ruc, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !submitForm(_form)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(storeApiProvider);
      await api.update({
        'name': _name.text.trim(),
        'ruc': _ruc.text.trim().isEmpty ? null : _ruc.text.trim(),
        'currency': _currency,
        'taxRateBp': _taxRateBp,
        'pricesIncludeTax': _pricesIncludeTax,
      });
      if (_branch != null && _address.text.trim().isNotEmpty) {
        await api.updateBranch(_branch!.id, {'address': _address.text.trim()});
      }
      ref.invalidate(storeSettingsProvider);
      if (mounted) context.go('/onboarding/attributes');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 1,
      title: 'Cuéntanos de tu negocio',
      subtitle: 'Esto aparece en tus comprobantes y reportes. Puedes cambiarlo luego.',
      onSkip: () {
        ref.read(sessionProvider.notifier).finishOnboarding();
        context.go('/home');
      },
      action: BusyButton(label: 'Continuar', busy: _saving, onPressed: _loading ? null : _save),
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: PerchaSpace.lg)],
                  AppTextField(
                    controller: _name,
                    label: 'Nombre comercial',
                    validator: V.all([V.minLength(2, 'Ingresa el nombre'), V.maxLength(80)]),
                    maxLength: 80,
                  ),
                  const SizedBox(height: PerchaSpace.lg),
                  AppTextField(
                    controller: _ruc,
                    label: 'RUC',
                    kind: FieldKind.ruc,
                    helper: 'Necesario para emitir comprobantes electrónicos',
                    validator: V.ruc(optional: true),
                  ),
                  const SizedBox(height: PerchaSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          decoration: const InputDecoration(labelText: 'Moneda'),
                          items: const [
                            DropdownMenuItem(value: 'PEN', child: Text('Soles (S/)')),
                            DropdownMenuItem(value: 'USD', child: Text('Dólares (US\$)')),
                          ],
                          onChanged: (v) => setState(() => _currency = v ?? 'PEN'),
                        ),
                      ),
                      const SizedBox(width: PerchaSpace.md),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _taxRateBp,
                          decoration: const InputDecoration(labelText: 'Impuesto'),
                          items: const [
                            DropdownMenuItem(value: 1800, child: Text('IGV 18%')),
                            DropdownMenuItem(value: 0, child: Text('Exonerado')),
                          ],
                          onChanged: (v) => setState(() => _taxRateBp = v ?? 1800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PerchaSpace.lg),
                  AppTextField(
                    controller: _address,
                    label: 'Dirección de tu tienda principal',
                    hint: 'Av., número, distrito',
                    validator: V.maxLength(200),
                    last: true,
                  ),
                  const SizedBox(height: PerchaSpace.lg),
                  Card(
                    child: CheckboxListTile(
                      value: _pricesIncludeTax,
                      onChanged: (v) => setState(() => _pricesIncludeTax = v ?? true),
                      title: const Text('Mis precios ya incluyen impuestos'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
