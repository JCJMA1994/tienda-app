import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/floating_nav.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';
import '../../notifications/notifications_api.dart';

/// Contenedor de las pestañas principales.
/// - Teléfono: barra inferior con ≤ 5 destinos según el rol.
/// - Tablet / web (≥ 900 px): riel lateral; desde 1200 px se extiende con etiquetas al lado.
/// Vender (POS) abre a pantalla completa para tener todo el espacio.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final dests = destinationsFor(me);
    final current = dests.indexWhere((d) => d.path != '/home' && location.startsWith(d.path));
    final index = current == -1 ? 0 : current;

    void go(int i) {
      final path = dests[i].path;
      path == '/pos' ? context.push(path) : context.go(path);
    }

    final width = MediaQuery.of(context).size.width;
    if (width >= 900) {
      final extended = width >= 1200;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: extended,
              selectedIndex: index,
              onDestinationSelected: go,
              labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              backgroundColor: PerchaColors.surface,
              indicatorColor: PerchaColors.accentSoft,
              leading: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: PerchaLogo(size: 32, showName: extended)),
              destinations: [
                for (final d in dests)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: child))),
          ],
        ),
      );
    }

    // Teléfono: barra flotante. El fondo de la barra es transparente para que se vea flotando
    // sobre la pantalla, y el contenido termina encima de ella (nada queda tapado).
    return Scaffold(
      body: child,
      backgroundColor: PerchaColors.ground,
      bottomNavigationBar: FloatingNavBar(
        destinations: dests,
        selected: index,
        onSelect: go,
        badges: {'/home': ref.watch(unreadProvider)},
      ),
    );
  }
}
