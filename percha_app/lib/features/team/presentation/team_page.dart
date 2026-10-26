import '../../../core/widgets/action_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../onboarding/data/store_api.dart';
import '../../pos/presentation/pin_dialog.dart';
import '../data/roles_api.dart';
import '../data/team_api.dart';

part 'team_members.dart';
part 'team_invite.dart';
part 'team_roles.dart';

final _branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) => ref.watch(storeApiProvider).branches());

/// Todos ven "Mi PIN". Quien tiene team.manage ve además el equipo, invitaciones y la matriz.
class TeamPage extends ConsumerWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final manage = me.can('team.manage');
    return Scaffold(
      appBar: AppBar(title: const Text('Equipo')),
      floatingActionButton: manage
          ? FloatingActionButton.extended(onPressed: () => _invite(context, ref), icon: const Icon(Icons.person_add_alt), label: const Text('Invitar'))
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref
          ..invalidate(membersProvider)
          ..invalidate(invitationsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
          children: [
            _MyPinCard(me: me),
            if (manage) ...[
              const SizedBox(height: PerchaSpace.xl),
              const _Members(),
              const _PendingInvitations(),
              const SizedBox(height: PerchaSpace.xl),
              const _RoleMatrix(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final me = ref.read(meProvider);
    final branches = await ref.read(_branchesProvider.future);
    final catalog = await ref.read(rolesProvider.future);
    if (!context.mounted) return;
    final link = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InviteSheet(roles: catalog.role(me.role).assignable, branches: branches, fixedBranch: me.branchId),
    );
    if (link == null || !context.mounted) return;
    ref.invalidate(invitationsProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invitación creada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Envía este enlace por WhatsApp o correo. Solo se muestra una vez y vence en 72 horas.'),
            const SizedBox(height: PerchaSpace.md),
            SelectableText(link, style: const TextStyle(fontSize: PerchaType.small)),
          ],
        ),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace copiado')));
            },
            label: const Text('Copiar enlace'),
          ),
        ],
      ),
    );
  }
}

class _MyPinCard extends ConsumerWidget {
  const _MyPinCard({required this.me});
  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: const Text('Mi PIN', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Para cambiar de vendedor en el POS y aprobar operaciones'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final pin = await askPin(context, title: 'Nuevo PIN', message: '4 a 6 dígitos. No uses tu fecha de nacimiento.');
          if (pin == null || !context.mounted) return;
          try {
            await ref.read(teamApiProvider).setPin(me.membershipId, pin);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN actualizado')));
          } catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
          }
        },
      ),
    );
  }
}

