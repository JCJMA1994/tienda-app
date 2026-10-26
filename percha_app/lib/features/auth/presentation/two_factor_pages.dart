import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/security/secure_screen.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../application/session_controller.dart';

/// Paso del login cuando la cuenta tiene verificación en dos pasos.
class TwoFactorPage extends ConsumerStatefulWidget {
  const TwoFactorPage({super.key});

  @override
  ConsumerState<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends ConsumerState<TwoFactorPage> with ActionRunner {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _recovery = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !submitForm(_form)) return;
    final v = _code.text.trim();
    // El router navega al cambiar la sesión; si falla, se limpia el código para reintentar.
    final ok = await runAction(() async {
      await ref.read(sessionProvider.notifier).verifyTwoFactor(code: _recovery ? null : v, recoveryCode: _recovery ? v : null);
      return true;
    });
    if (ok == null) _code.clear();
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
                Icon(Icons.verified_user_outlined, size: 40, color: PerchaColors.accentInk),
                const SizedBox(height: PerchaSpace.lg),
                Text('Verificación en dos pasos', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: PerchaSpace.sm),
                Text(
                  _recovery ? 'Ingresa uno de tus códigos de recuperación. Cada código sirve una sola vez.' : 'Abre tu app autenticadora e ingresa el código de 6 dígitos de Percha.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PerchaSpace.xl),
                if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
                Form(
                  key: _form,
                  child: AppTextField(
                    key: ValueKey(_recovery),
                    controller: _code,
                    label: _recovery ? 'Código de recuperación' : 'Código',
                    hint: _recovery ? 'XXXXX-XXXXX' : '123456',
                    kind: _recovery ? FieldKind.upper : FieldKind.integer,
                    maxLength: _recovery ? 11 : 6,
                    autofocus: true,
                    last: true,
                    onSubmitted: (_) => _submit(),
                    validator: _recovery ? V.minLength(10, 'Código incompleto') : (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : 'Son 6 dígitos',
                  ),
                ),
                const SizedBox(height: PerchaSpace.xl),
                BusyButton(label: 'Verificar', busy: busy, onPressed: _submit),
                const SizedBox(height: PerchaSpace.sm),
                TextButton(
                  onPressed: () => setState(() {
                    _recovery = !_recovery;
                    _code.clear();
                    error = null;
                  }),
                  child: Text(_recovery ? 'Usar la app autenticadora' : 'No tengo mi teléfono: usar código de recuperación'),
                ),
                TextButton(onPressed: () => ref.read(sessionProvider.notifier).cancelTenantChoice(), child: const Text('Cancelar')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Activar / desactivar la verificación en dos pasos (Más → Seguridad).
class TwoFactorSetupPage extends ConsumerStatefulWidget {
  const TwoFactorSetupPage({super.key});

  @override
  ConsumerState<TwoFactorSetupPage> createState() => _TwoFactorSetupPageState();
}

class _TwoFactorSetupPageState extends ConsumerState<TwoFactorSetupPage> with ActionRunner {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  ({String secret, String uri})? _setup;
  List<String>? _recovery;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    await runAction(action);
  }

  Future<void> _disable() async {
    final password = TextEditingController();
    final code = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar verificación en dos pasos'),
        content: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Tu cuenta quedará protegida solo con la contraseña.'),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: password, label: 'Contraseña', kind: FieldKind.password, validator: V.required('Ingresa tu contraseña')),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: code, label: 'Código de la app', kind: FieldKind.integer, maxLength: 6, validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : 'Son 6 dígitos', last: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => submitForm(key) ? Navigator.pop(ctx, true) : null, child: const Text('Desactivar')),
        ],
      ),
    );
    final p = password.text, c = code.text;
    password.dispose();
    code.dispose();
    if (ok != true) return;
    await _run(() async {
      await ref.read(authApiProvider).disableTwoFactor(password: p, code: c);
      await ref.read(sessionProvider.notifier).reloadMe();
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final text = Theme.of(context).textTheme;
    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('Verificación en dos pasos')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
            if (_recovery != null) ...[
              Text('Guarda tus códigos de recuperación', style: text.titleLarge),
              const SizedBox(height: PerchaSpace.sm),
              Text('Si pierdes el teléfono, cada código te deja entrar una vez. No volverás a verlos: guárdalos en un lugar seguro (no en una foto del celular).', style: text.bodySmall),
              const SizedBox(height: PerchaSpace.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [for (final c in _recovery!) SelectableText(c, style: const TextStyle(fontFamily: 'monospace', fontSize: PerchaType.title, fontWeight: FontWeight.w600))],
                  ),
                ),
              ),
              const SizedBox(height: PerchaSpace.md),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _recovery!.join('\n')));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Códigos copiados')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar códigos'),
              ),
              const SizedBox(height: PerchaSpace.md),
              FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Ya los guardé')),
            ] else if (me.twoFactorEnabled) ...[
              Card(
                child: ListTile(
                  leading: Icon(Icons.verified_user, color: PerchaColors.success),
                  title: const Text('Activada', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Al ingresar con tu contraseña te pediremos el código de tu app autenticadora.'),
                ),
              ),
              const SizedBox(height: PerchaSpace.lg),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: PerchaColors.warn),
                onPressed: busy ? null : _disable,
                child: const Text('Desactivar'),
              ),
            ] else if (_setup == null) ...[
              Text('Protege tu cuenta', style: text.titleLarge),
              const SizedBox(height: PerchaSpace.sm),
              Text(
                'Además de tu contraseña, te pediremos un código de 6 dígitos que genera una app en tu teléfono (Google Authenticator, Microsoft Authenticator, 1Password…). Recomendado para dueños: aunque alguien conozca tu contraseña, no podrá entrar.',
                style: text.bodySmall,
              ),
              const SizedBox(height: PerchaSpace.xl),
              BusyButton(label: 'Empezar', busy: busy, onPressed: () => _run(() async => _setup = await ref.read(authApiProvider).setupTwoFactor())),
            ] else ...[
              Text('1. Escanea el código con tu app autenticadora', style: text.titleMedium),
              const SizedBox(height: PerchaSpace.md),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  // El QR siempre sobre blanco: los lectores fallan con QR invertidos (modo oscuro).
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(PerchaRadius.card)),
                  child: QrImageView(data: _setup!.uri, size: 200, backgroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: PerchaSpace.md),
              Text('¿No puedes escanear? Ingresa esta clave a mano:', style: text.bodySmall),
              SelectableText(_setup!.secret, style: const TextStyle(fontFamily: 'monospace', fontSize: PerchaType.strong, fontWeight: FontWeight.w600)),
              const SizedBox(height: PerchaSpace.xl),
              Text('2. Ingresa el código que muestra la app', style: text.titleMedium),
              const SizedBox(height: PerchaSpace.md),
              Form(
                key: _form,
                child: AppTextField(
                  controller: _code,
                  label: 'Código de 6 dígitos',
                  kind: FieldKind.integer,
                  maxLength: 6,
                  validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : 'Son 6 dígitos',
                  last: true,
                ),
              ),
              const SizedBox(height: PerchaSpace.lg),
              BusyButton(
                label: 'Activar',
                busy: busy,
                onPressed: () {
                  if (!submitForm(_form)) return;
                  _run(() async {
                    _recovery = await ref.read(authApiProvider).enableTwoFactor(_code.text);
                    await ref.read(sessionProvider.notifier).reloadMe();
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
