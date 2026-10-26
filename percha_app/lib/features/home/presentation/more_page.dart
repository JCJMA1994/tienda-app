import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/theme/theme_mode.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../../core/theme/tokens.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';

/// "Más": todo lo que no es diario, agrupado por tarea y filtrado por rol.
/// También concentra la cuenta (antes escondida en un menú del inicio).
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: PerchaColors.accentSoft,
                foregroundColor: PerchaColors.accentInk,
                child: Text(me.name.characters.first.toUpperCase()),
              ),
              title: Text(me.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${roleLabels[me.role] ?? me.role} · ${me.tenantName}'),
            ),
          ),
          for (final section in moreSections)
            if (section.items.any((d) => d.allowed(me))) ...[
              const SizedBox(height: PerchaSpace.lg),
              Text(section.title, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Card(
                child: Column(
                  children: [
                    for (final d in section.items.where((d) => d.allowed(me)))
                      ListTile(
                        leading: Icon(d.icon),
                        title: Text(d.label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(d.path),
                      ),
                  ],
                ),
              ),
            ],
          const SizedBox(height: PerchaSpace.lg),
          Text('Apariencia', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Oscuro')),
            ],
            selected: {ref.watch(themeModeProvider)},
            showSelectedIcon: false,
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: PerchaSpace.lg),
          Text('Seguridad', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('Cambiar contraseña'),
                  subtitle: const Text('Cierra tu sesión en los demás dispositivos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog<void>(context: context, builder: (_) => const _ChangePasswordDialog()),
                ),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Verificación en dos pasos'),
                  subtitle: Text(me.twoFactorEnabled ? 'Activada' : 'Recomendada para dueños'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/2fa'),
                ),
                ListTile(
                  leading: const Icon(Icons.devices_other_outlined),
                  title: const Text('Cerrar sesión en todos los dispositivos'),
                  subtitle: const Text('Úsalo si perdiste un teléfono o una tablet'),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Cerrar todas las sesiones'),
                        content: const Text('Se cerrará tu sesión en todos los dispositivos, incluido este.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar todas')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    await ref.read(sessionProvider.notifier).logoutEverywhere();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: PerchaSpace.xl),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: PerchaColors.warn),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('Tendrás que volver a ingresar tu correo y contraseña.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar sesión')),
                  ],
                ),
              );
              if (ok == true) await ref.read(sessionProvider.notifier).logout();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> with ActionRunner {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void dispose() {
    for (final c in [_current, _next, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !submitForm(_form)) return;
    await runAction(() async {
        // La API cierra las demás sesiones y entrega una nueva para este dispositivo.
        await ref.read(sessionProvider.notifier).changePassword(current: _current.text, next: _next.text);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña actualizada. Cerramos tus otras sesiones.')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
              AppTextField(controller: _current, label: 'Contraseña actual', kind: FieldKind.password, validator: V.required('Ingresa tu contraseña actual'), autofocus: true),
              const SizedBox(height: PerchaSpace.md),
              AppTextField(
                controller: _next,
                label: 'Nueva contraseña',
                kind: FieldKind.newPassword,
                helper: 'Mínimo 8 caracteres, con letras y números',
                validator: V.all([V.password(), (v) => v == _current.text ? 'Debe ser distinta a la actual' : null]),
              ),
              const SizedBox(height: PerchaSpace.md),
              AppTextField(
                controller: _repeat,
                label: 'Repite la nueva contraseña',
                kind: FieldKind.newPassword,
                validator: (v) => v == _next.text ? null : 'No coincide',
                last: true,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: busy ? null : _submit, child: const Text('Cambiar')),
      ],
    );
  }
}
