import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../application/session_controller.dart';

/// "¿Olvidaste tu contraseña?": siempre muestra el mismo mensaje (no revela qué correos existen).
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> with ActionRunner {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !submitForm(_form)) return;
    await runAction(() async {
        await ref.read(authApiProvider).forgotPassword(_email.text.trim());
        setState(() => _sent = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text('Recuperar contraseña', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: PerchaSpace.sm),
              Text(
                _sent
                    ? 'Si ${_email.text.trim()} tiene una cuenta, te llegará un enlace en unos minutos. Vence en 30 minutos. Revisa también la carpeta de spam.'
                    : 'Te enviaremos un enlace a tu correo para crear una nueva contraseña.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: PerchaSpace.xl),
              if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
              if (!_sent) ...[
                Form(
                  key: _form,
                  child: AppTextField(controller: _email, label: 'Correo', kind: FieldKind.email, validator: V.email(), autofocus: true, last: true, onSubmitted: (_) => _submit()),
                ),
                const SizedBox(height: PerchaSpace.xl),
                BusyButton(label: 'Enviar enlace', busy: busy, onPressed: _submit),
              ] else
                FilledButton(onPressed: () => context.go('/login'), child: const Text('Volver a ingresar')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Se abre desde el enlace del correo: /reset?token=…
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, required this.token});
  final String token;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> with ActionRunner {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !submitForm(_form)) return;
    await runAction(() async {
        await ref.read(authApiProvider).resetPassword(widget.token, _password.text);
        setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Align(alignment: Alignment.centerLeft, child: PerchaLogo()),
                const SizedBox(height: PerchaSpace.xl),
                Text(_done ? 'Contraseña actualizada' : 'Nueva contraseña', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: PerchaSpace.sm),
                Text(
                  _done ? 'Cerramos tu sesión en todos los dispositivos. Ingresa con tu nueva contraseña.' : 'Elige una contraseña que no uses en otros sitios.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PerchaSpace.xl),
                if (widget.token.isEmpty) const ErrorBanner('El enlace está incompleto. Ábrelo de nuevo desde el correo.'),
                if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
                if (!_done && widget.token.isNotEmpty) ...[
                  Form(
                    key: _form,
                    child: Column(children: [
                      AppTextField(controller: _password, label: 'Nueva contraseña', kind: FieldKind.newPassword, helper: 'Mínimo 8 caracteres, con letras y números', validator: V.password(), autofocus: true),
                      const SizedBox(height: PerchaSpace.md),
                      AppTextField(
                        controller: _repeat,
                        label: 'Repite la contraseña',
                        kind: FieldKind.newPassword,
                        validator: (v) => v == _password.text ? null : 'No coincide',
                        last: true,
                        onSubmitted: (_) => _submit(),
                      ),
                    ],),
                  ),
                  const SizedBox(height: PerchaSpace.xl),
                  BusyButton(label: 'Guardar contraseña', busy: busy, onPressed: _submit),
                ],
                if (_done) FilledButton(onPressed: () => context.go('/login'), child: const Text('Ingresar')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
