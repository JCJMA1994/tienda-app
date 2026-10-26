import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../application/session_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with ActionRunner {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !submitForm(_form)) return;
    await runAction(() async {
        // La navegación la hace el router al cambiar la sesión; aquí no se navega.
        await ref.read(sessionProvider.notifier).login(_email.text.trim(), _password.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final reason = session is SignedOut ? session.reason : null;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(alignment: Alignment.centerLeft, child: PerchaLogo()),
                      const SizedBox(height: PerchaSpace.xxl),
                      Text('Tu boutique, en orden.', style: text.headlineLarge),
                      const SizedBox(height: PerchaSpace.sm),
                      Text('Inventario, ventas y equipo en un solo lugar.', style: text.bodyMedium?.copyWith(color: PerchaColors.muted)),
                      const SizedBox(height: PerchaSpace.xxl),
                      if (error != null || reason != null) ...[
                        ErrorBanner(error ?? reason!),
                        const SizedBox(height: PerchaSpace.lg),
                      ],
                      AppTextField(
                        controller: _email,
                        label: 'Correo',
                        hint: 'tu@tienda.com',
                        kind: FieldKind.email,
                        validator: V.email(),
                      ),
                      const SizedBox(height: PerchaSpace.lg),
                      // En el login no se exigen reglas de fortaleza: solo que no esté vacío.
                      AppTextField(
                        controller: _password,
                        label: 'Contraseña',
                        kind: FieldKind.password,
                        validator: V.required('Ingresa tu contraseña'),
                        last: true,
                        onSubmitted: (_) => _submit(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: () => context.push('/forgot'), child: const Text('¿Olvidaste tu contraseña?')),
                      ),
                      const SizedBox(height: PerchaSpace.md),
                      BusyButton(label: 'Ingresar', busy: busy, onPressed: _submit),
                      const SizedBox(height: PerchaSpace.xxl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('¿Tienes una tienda nueva?', style: text.bodyMedium?.copyWith(color: PerchaColors.muted)),
                          TextButton(onPressed: () => context.go('/register'), child: const Text('Crear mi tienda')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
