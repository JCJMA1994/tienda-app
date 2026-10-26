part of 'team_page.dart';

class _RoleMatrix extends ConsumerStatefulWidget {
  const _RoleMatrix();

  @override
  ConsumerState<_RoleMatrix> createState() => _RoleMatrixState();
}

class _RoleMatrixState extends ConsumerState<_RoleMatrix> {
  String _role = 'seller';

  static final _labels = {
    Access.yes: ('Sí', PerchaColors.accentSoft, PerchaColors.accentInk),
    Access.no: ('No', PerchaColors.surfaceAlt, PerchaColors.muted),
    Access.approval: ('Con aprobación', PerchaColors.warnSoft, PerchaColors.warn),
    Access.ownBranch: ('Su sucursal', PerchaColors.surfaceAlt, PerchaColors.ink),
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ref.watch(rolesProvider).when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (catalog) {
            final role = catalog.role(_role);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Permisos por rol', style: text.titleMedium),
                const SizedBox(height: PerchaSpace.sm),
                SegmentedButton<String>(
                  segments: [for (final r in catalog.roles) ButtonSegment(value: r.key, label: Text(r.label))],
                  selected: {_role},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _role = s.first),
                ),
                for (final group in catalog.byGroup.entries) ...[
                  const SizedBox(height: PerchaSpace.md),
                  Text(group.key, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Column(
                        children: [
                          for (final p in group.value)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(child: Text(p.label, style: const TextStyle(fontSize: PerchaType.small))),
                                  _AccessPill(_labels[role.access[p.key] ?? Access.no]!),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
  }
}

class _AccessPill extends StatelessWidget {
  const _AccessPill(this.style);
  final (String, Color, Color) style;

  @override
  Widget build(BuildContext context) {
    final (t, bg, fg) = style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(PerchaRadius.pill)),
      child: Text(t, style: TextStyle(color: fg, fontSize: PerchaType.meta, fontWeight: FontWeight.w600)),
    );
  }
}
