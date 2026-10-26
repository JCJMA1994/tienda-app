part of 'team_page.dart';

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.roles, required this.branches, this.fixedBranch});
  final List<String> roles;
  final List<Branch> branches;
  final String? fixedBranch;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> with ActionRunner {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  late String _role = widget.roles.contains('seller') ? 'seller' : widget.roles.first;
  late String? _branchId = widget.fixedBranch ?? widget.branches.where((b) => b.isDefault).firstOrNull?.id;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (busy || !submitForm(_form)) return;
    await runAction(() async {
        final token = await ref.read(teamApiProvider).invite(email: _email.text.trim(), role: _role, branchId: _branchId);
        if (mounted) Navigator.pop(context, '${Env.inviteBaseUrl}?token=$token');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Invitar al equipo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: PerchaSpace.lg),
            if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
            Form(
              key: _form,
              child: AppTextField(controller: _email, label: 'Correo de la persona', kind: FieldKind.email, autofocus: true, validator: V.email()),
            ),
            const SizedBox(height: PerchaSpace.lg),
            _RoleAndBranch(
              roles: widget.roles,
              branches: widget.branches,
              fixedBranch: widget.fixedBranch,
              role: _role,
              branchId: _branchId,
              onRole: (r) => setState(() => _role = r),
              onBranch: (b) => setState(() => _branchId = b),
            ),
            const SizedBox(height: PerchaSpace.lg),
            BusyButton(label: 'Crear invitación', busy: busy, onPressed: _send),
          ],
        ),
      ),
    );
  }
}

class _PendingInvitations extends ConsumerWidget {
  const _PendingInvitations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(invitationsProvider).valueOrNull ?? const [];
    final pending = list.where((i) => i.expiresAt.isAfter(DateTime.now())).toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: PerchaSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Invitaciones pendientes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: PerchaSpace.sm),
          for (final i in pending)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(i.email),
              subtitle: Text(roleLabels[i.role] ?? i.role),
              trailing: TextButton(
                onPressed: () async {
                  await ref.read(teamApiProvider).revoke(i.id);
                  ref.invalidate(invitationsProvider);
                },
                child: const Text('Revocar'),
              ),
            ),
        ],
      ),
    );
  }
}
