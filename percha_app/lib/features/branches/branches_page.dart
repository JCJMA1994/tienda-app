import '../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/forms/app_form.dart';
import '../../core/forms/validators.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/percha_widgets.dart';
import '../onboarding/data/store_api.dart';

final _branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) => ref.watch(storeApiProvider).branches());

/// Sucursales: nombre, dirección y ubigeo (la guía de remisión los necesita como punto de
/// partida y de llegada).
class BranchesPage extends ConsumerWidget {
  const BranchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sucursales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (await showDialog<bool>(context: context, builder: (_) => const _BranchDialog()) == true) ref.invalidate(_branchesProvider);
        },
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nueva'),
      ),
      body: ref.watch(_branchesProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
            data: (list) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
              children: [
                Text('La dirección y el ubigeo se imprimen en las guías de remisión de las transferencias.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: PerchaSpace.md),
                for (final b in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: PerchaSpace.sm),
                    child: ListTile(
                      title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([b.address ?? 'Sin dirección', if (b.ubigeo != null) 'Ubigeo ${b.ubigeo}'].join(' · ')),
                      trailing: b.address == null || b.ubigeo == null ? const Pill('Completar', warn: true) : null,
                      onTap: () async {
                        if (await showDialog<bool>(context: context, builder: (_) => _BranchDialog(branch: b)) == true) ref.invalidate(_branchesProvider);
                      },
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}

class _BranchDialog extends ConsumerStatefulWidget {
  const _BranchDialog({this.branch});
  final Branch? branch;

  @override
  ConsumerState<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends ConsumerState<_BranchDialog> with ActionRunner {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.branch?.name ?? '');
  late final _address = TextEditingController(text: widget.branch?.address ?? '');
  late final _ubigeo = TextEditingController(text: widget.branch?.ubigeo ?? '');

  @override
  void dispose() {
    for (final c in [_name, _address, _ubigeo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (busy || !submitForm(_form)) return;
    final body = {
      'name': _name.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'ubigeo': _ubigeo.text.trim().isEmpty ? null : _ubigeo.text.trim(),
    };
    await runAction(() async {
      final api = ref.read(storeApiProvider);
      widget.branch == null ? await api.createBranch(body) : await api.updateBranch(widget.branch!.id, body);
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.branch == null ? 'Nueva sucursal' : 'Editar sucursal'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
            AppTextField(controller: _name, label: 'Nombre', validator: V.all([V.minLength(2, 'Ingresa el nombre'), V.maxLength(80)])),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: _address, label: 'Dirección', hint: 'Av., número, distrito', validator: V.maxLength(200)),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(
              controller: _ubigeo,
              label: 'Ubigeo (6 dígitos)',
              hint: '150122',
              kind: FieldKind.integer,
              maxLength: 6,
              helper: 'Código INEI del distrito (p. ej. 150122 Miraflores, 150140 Santiago de Surco)',
              validator: (v) => (v ?? '').isEmpty || RegExp(r'^\d{6}$').hasMatch(v!) ? null : 'Son 6 dígitos',
              last: true,
              onSubmitted: (_) => _save(),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: busy ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}
