import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../application/session_controller.dart';

/// Se abre desde el enlace de invitación (…/invite?token=…).
/// Si la persona ya tiene cuenta en Percha (p. ej. trabaja en otra tienda), usa su contraseña
/// actual y puede dejar el nombre vacío.
class AcceptInvitationPage extends ConsumerStatefulWidget {
  const AcceptInvitationPage({super.key, required this.token});
  final String token;

  @override
  ConsumerState<AcceptInvitationPage> createState() => _AcceptInvitationPageState();
}

class _AcceptInvitationPageState extends ConsumerState<AcceptInvitationPage> with ActionRunner {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !submitForm(_form)) return;
    await runAction(() async {
        await ref.read(sessionProvider.notifier).acceptInvitation(
              token: widget.token,
              name: _name.text.trim(),
              password: _password.text,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: PerchaLogo()),
                  const SizedBox(height: PerchaSpace.xxl),
                  Text('Te invitaron a un equipo', style: text.headlineMedium),
                  const SizedBox(height: PerchaSpace.sm),
                  Text('Crea tu contraseña para entrar. Si ya usas Percha, ingresa tu contraseña actual.',
                      style: text.bodyMedium?.copyWith(color: PerchaColors.muted),),
                  const SizedBox(height: PerchaSpace.xl),
                  if (widget.token.isEmpty) const ErrorBanner('El enlace está incompleto. Pide uno nuevo.'),
                  if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.lg)],
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        AppTextField(
                          controller: _name,
                          label: 'Tu nombre',
                          kind: FieldKind.name,
                          helper: 'Déjalo vacío si ya tienes cuenta',
                          validator: V.maxLength(80),
                        ),
                        const SizedBox(height: PerchaSpace.lg),
                        // Puede ser la contraseña actual (ya usa Percha) o una nueva: se exige el mínimo de la API.
                        AppTextField(
                          controller: _password,
                          label: 'Contraseña',
                          kind: FieldKind.newPassword,
                          validator: V.all([V.minLength(8, 'Mínimo 8 caracteres'), V.maxLength(128)]),
                          last: true,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PerchaSpace.xl),
                  BusyButton(label: 'Unirme', busy: busy, onPressed: widget.token.isEmpty ? null : _submit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
