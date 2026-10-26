import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error.dart';
import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../application/session_controller.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> with ActionRunner {
  final _form = GlobalKey<FormState>();
  final _store = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    for (final c in [_store, _name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !submitForm(_form)) return;
    await runAction(() async {
        await ref.read(sessionProvider.notifier).register(
              storeName: _store.text.trim(),
              ownerName: _name.text.trim(),
              email: _email.text.trim(),
              password: _password.text,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Volver', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/login')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Crea tu tienda', style: text.headlineMedium),
                    const SizedBox(height: PerchaSpace.sm),
                    Text('Empiezas como dueño. Luego invitas a tu equipo.', style: text.bodyMedium?.copyWith(color: PerchaColors.muted)),
                    const SizedBox(height: PerchaSpace.xl),
                    if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.lg)],
                    AppTextField(
                      controller: _store,
                      label: 'Nombre de la tienda',
                      hint: 'Ej. Boutique Alma',
                      validator: V.all([V.minLength(2, 'Ingresa el nombre de la tienda'), V.maxLength(80)]),
                      maxLength: 80,
                    ),
                    const SizedBox(height: PerchaSpace.lg),
                    AppTextField(
                      controller: _name,
                      label: 'Tu nombre',
                      kind: FieldKind.name,
                      validator: V.all([V.minLength(2, 'Ingresa tu nombre'), V.maxLength(80)]),
                    ),
                    const SizedBox(height: PerchaSpace.lg),
                    AppTextField(controller: _email, label: 'Correo', kind: FieldKind.email, validator: V.email()),
                    const SizedBox(height: PerchaSpace.lg),
                    AppTextField(
                      controller: _password,
                      label: 'Contraseña',
                      kind: FieldKind.newPassword,
                      helper: 'Mínimo 8 caracteres, con letras y números',
                      validator: V.password(),
                      last: true,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: PerchaSpace.xl),
                    BusyButton(label: 'Crear tienda', busy: busy, onPressed: _submit),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
