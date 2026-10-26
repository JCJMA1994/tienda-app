import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'nav.dart';

/// Barra de navegación flotante: cápsula translúcida con desenfoque, separada de los bordes.
///
/// Decisiones de UX:
/// - **Píldora que se expande** en el destino activo (ícono + etiqueta); los demás, solo ícono
///   con etiqueta para lectores de pantalla. Menos ruido visual, el contexto queda claro.
/// - **"Vender" como botón central elevado**: la acción principal se alcanza con el pulgar y
///   se distingue sin depender del color (tamaño y forma).
/// - Respuesta háptica suave al cambiar de pestaña; objetivos táctiles ≥ 48 px.
/// - El contenido NO queda debajo de la barra (no se usa extendBody): nada se tapa.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.destinations, required this.selected, required this.onSelect, this.badges = const {}});
  final List<NavDest> destinations;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Contador por ruta (p. ej. notificaciones sin leer en "Más").
  final Map<String, int> badges;

  @override
  Widget build(BuildContext context) {
    final c = PerchaColors.palette;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: 72,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PerchaRadius.pill),
                boxShadow: [BoxShadow(color: c.shadow, blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PerchaRadius.pill),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surfaceGlass,
                      borderRadius: BorderRadius.circular(PerchaRadius.pill),
                      border: Border.all(color: c.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          Expanded(
                            child: destinations[i].path == '/pos'
                                ? const SizedBox() // espacio para el botón central
                                : _Item(
                                    dest: destinations[i],
                                    active: i == selected,
                                    badge: badges[destinations[i].path] ?? 0,
                                    onTap: () => _select(i),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < destinations.length; i++)
              if (destinations[i].path == '/pos')
                Positioned(
                  top: -14,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment(_centerOf(i), 0),
                    child: _CenterButton(dest: destinations[i], onTap: () => _select(i)),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Posición horizontal (-1..1) del destino i dentro de la barra.
  double _centerOf(int i) => destinations.length == 1 ? 0 : -1 + (2 * i + 1) / destinations.length;

  void _select(int i) {
    HapticFeedback.selectionClick();
    onSelect(i);
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.dest, required this.active, required this.badge, required this.onTap});
  final NavDest dest;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PerchaColors.palette;
    return Semantics(
      button: true,
      selected: active,
      label: badge > 0 ? '${dest.label}, $badge sin leer' : dest.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Center(
          child: AnimatedContainer(
            duration: PerchaMotion.normal,
            curve: PerchaMotion.curve,
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: active ? 14 : 10),
            decoration: BoxDecoration(color: active ? c.surfaceAlt : Colors.transparent, borderRadius: BorderRadius.circular(PerchaRadius.pill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text(badge > 99 ? '99+' : '$badge'),
                  backgroundColor: c.warn,
                  textColor: c.onAccent,
                  child: Icon(active ? dest.selectedIcon : dest.icon, color: active ? c.ink : c.muted, size: 24),
                ),
                AnimatedSize(
                  duration: PerchaMotion.normal,
                  curve: PerchaMotion.curve,
                  child: active
                      ? Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(dest.label, maxLines: 1, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: PerchaType.small)),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.dest, required this.onTap});
  final NavDest dest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PerchaColors.palette;
    return Semantics(
      button: true,
      label: dest.label,
      excludeSemantics: true,
      child: Material(
        color: c.accent,
        shape: CircleBorder(side: BorderSide(color: c.ground, width: 4)),
        elevation: 6,
        shadowColor: c.shadow,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 60, height: 60, child: Icon(dest.selectedIcon, color: c.onAccent, size: 28)),
        ),
      ),
    );
  }
}
