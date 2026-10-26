import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../application/session_controller.dart';
import '../data/auth_models.dart';

/// Quien trabaja en varias tiendas elige a cuál entrar.
class TenantPickerPage extends ConsumerStatefulWidget {
  const TenantPickerPage({super.key});

  @override
  ConsumerState<TenantPickerPage> createState() => _TenantPickerPageState();
}

class _TenantPickerPageState extends ConsumerState<TenantPickerPage> {
  String? _loading;
  String? _error;

  Future<void> _pick(String tenantId) async {
    setState(() {
      _loading = tenantId;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).chooseTenant(tenantId);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final tenants = s is ChoosingTenant ? s.tenants : const <TenantOption>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elige tu tienda'),
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => ref.read(sessionProvider.notifier).cancelTenantChoice(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(PerchaSpace.xl),
        children: [
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: PerchaSpace.lg)],
          for (final t in tenants)
            Padding(
              padding: const EdgeInsets.only(bottom: PerchaSpace.md),
              child: Card(
                child: ListTile(
                  minVerticalPadding: 14,
                  title: Text(t.name, style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text(roleLabels[t.role] ?? t.role),
                  trailing: _loading == t.tenantId
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _loading == null ? () => _pick(t.tenantId) : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
