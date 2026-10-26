part of 'team_page.dart';

class _Members extends ConsumerWidget {
  const _Members();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final members = ref.watch(membersProvider);
    final catalog = ref.watch(rolesProvider).valueOrNull;
    final assignable = catalog?.role(me.role).assignable ?? const <String>[];
    return members.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      error: (e, _) => ErrorBanner(errorText(e)),
      data: (list) => Card(
        child: Column(
          children: [
            for (final (i, m) in list.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: m.id == me.membershipId ? PerchaColors.accentSoft : PerchaColors.surfaceAlt,
                  foregroundColor: m.id == me.membershipId ? PerchaColors.accentInk : PerchaColors.ink,
                  child: Text(m.name.characters.first.toUpperCase()),
                ),
                title: Text(m.id == me.membershipId ? '${m.name} (tú)' : m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([m.email, if (!m.hasPin) 'sin PIN', if (!m.active) 'desactivado'].join(' · ')),
                trailing: Pill(catalog?.label(m.role) ?? roleLabels[m.role] ?? m.role, dark: m.role == 'owner'),
                // El propio rol no se edita, y solo se gestiona a quien el rol actual puede asignar.
                onTap: m.id == me.membershipId || !assignable.contains(m.role) ? null : () => _edit(context, ref, m, assignable),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Member m, List<String> assignable) async {
    final me = ref.read(meProvider);
    final branches = await ref.read(_branchesProvider.future);
    if (!context.mounted) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MemberSheet(member: m, roles: assignable, branches: branches, fixedBranch: me.branchId),
    );
    if (changed == true) ref.invalidate(membersProvider);
  }
}

class _MemberSheet extends ConsumerStatefulWidget {
  const _MemberSheet({required this.member, required this.roles, required this.branches, this.fixedBranch});
  final Member member;
  final List<String> roles;
  final List<Branch> branches;
  final String? fixedBranch;

  @override
  ConsumerState<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends ConsumerState<_MemberSheet> with ActionRunner {
  late String _role = widget.member.role;
  late String? _branchId = widget.member.branchId;
  late bool _active = widget.member.active;
  late final _commission = TextEditingController(text: widget.member.commissionBp == null ? '' : (widget.member.commissionBp! / 100).toString().replaceAll(RegExp(r'\.0$'), ''));

  @override
  void dispose() {
    _commission.dispose();
    super.dispose();
  }

  /// "3" o "2.5" → puntos básicos; vacío = sin comisión.
  int? get _commissionBp {
    final t = _commission.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    return v == null ? null : (v * 100).round().clamp(0, 5000);
  }

  Future<void> _save() async {
    await runAction(() async {
        final m = widget.member;
        await ref.read(teamApiProvider).update(
              m.id,
              role: _role != m.role ? _role : null,
              branchId: _branchId != m.branchId ? _branchId : null,
              clearBranch: _branchId == null && m.branchId != null,
              active: _active != m.active ? _active : null,
              commissionBp: _commissionBp != m.commissionBp ? _commissionBp : null,
              clearCommission: _commissionBp == null && m.commissionBp != null,
            );
        if (mounted) Navigator.pop(context, true);
    });
  }

  Future<void> _setPin() async {
    final pin = await askPin(context, title: 'PIN de ${widget.member.name}');
    if (pin == null || !mounted) return;
    try {
      await ref.read(teamApiProvider).setPin(widget.member.id, pin);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
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
            Text(widget.member.name, style: Theme.of(context).textTheme.titleLarge),
            Text(widget.member.email, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: PerchaSpace.lg),
            if (error != null) ...[ErrorBanner(error!), const SizedBox(height: PerchaSpace.md)],
            _RoleAndBranch(
              roles: widget.roles,
              branches: widget.branches,
              fixedBranch: widget.fixedBranch,
              role: _role,
              branchId: _branchId,
              onRole: (r) => setState(() => _role = r),
              onBranch: (b) => setState(() => _branchId = b),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Acceso activo'),
              subtitle: const Text('Al desactivar, sus sesiones dejan de renovarse'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: PerchaSpace.sm),
            OutlinedButton(onPressed: _setPin, child: Text(widget.member.hasPin ? 'Cambiar PIN' : 'Asignar PIN')),
            const SizedBox(height: PerchaSpace.sm),
            TextField(
              controller: _commission,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Comisión (%)', hintText: 'Vacío = sin comisión', helperText: 'Sobre sus ventas netas sin IGV (Reportes → Comisiones)', suffixText: '%'),
            ),
            const SizedBox(height: PerchaSpace.md),
            BusyButton(label: 'Guardar', busy: busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _RoleAndBranch extends StatelessWidget {
  const _RoleAndBranch({
    required this.roles,
    required this.branches,
    required this.fixedBranch,
    required this.role,
    required this.branchId,
    required this.onRole,
    required this.onBranch,
  });

  final List<String> roles;
  final List<Branch> branches;
  final String? fixedBranch;
  final String role;
  final String? branchId;
  final ValueChanged<String> onRole;
  final ValueChanged<String?> onBranch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: role,
          decoration: const InputDecoration(labelText: 'Rol'),
          items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(roleLabels[r] ?? r))],
          onChanged: (v) {
            if (v != null) onRole(v);
          },
        ),
        const SizedBox(height: PerchaSpace.lg),
        DropdownButtonFormField<String?>(
          value: branchId,
          decoration: const InputDecoration(labelText: 'Sucursal'),
          items: [
            // Un encargado con sucursal fija solo asigna a la suya (la API lo exige).
            if (fixedBranch == null) const DropdownMenuItem(value: null, child: Text('Todas las sucursales')),
            for (final b in branches)
              if (fixedBranch == null || b.id == fixedBranch) DropdownMenuItem(value: b.id, child: Text(b.name)),
          ],
          onChanged: onBranch,
        ),
      ],
    );
  }
}
