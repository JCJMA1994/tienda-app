import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/core/theme/tokens.dart';
import 'package:percha_app/features/notifications/notifications_api.dart';

/// Contraste WCAG 2.x entre dos colores opacos.
double contrast(Color a, Color b) {
  double ch(double c) => c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  double lum(Color c) => 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  final la = lum(a), lb = lum(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  for (final p in [PerchaPalette.light, PerchaPalette.dark]) {
    test('tokens ${p.brightness.name}: todo texto cumple WCAG AA (≥ 4.5:1)', () {
      final pairs = {
        'ink/surface': (p.ink, p.surface),
        'inkSoft/surface': (p.inkSoft, p.surface),
        'muted/surface': (p.muted, p.surface),
        'muted/ground': (p.muted, p.ground),
        'muted/surfaceAlt': (p.muted, p.surfaceAlt),
        'onAccent/accent': (p.onAccent, p.accent),
        'accentInk/accentSoft': (p.accentInk, p.accentSoft),
        'accentInk/surface': (p.accentInk, p.surface),
        'accentInk/ground': (p.accentInk, p.ground),
        'ink/ground': (p.ink, p.ground),
        'success/surface': (p.success, p.surface),
        'warn/warnSoft': (p.warn, p.warnSoft),
        'warn/surface': (p.warn, p.surface),
        'onInverse/inverse': (p.onInverse, p.inverse),
      };
      for (final e in pairs.entries) {
        expect(contrast(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5), reason: e.key);
      }
    });
  }

  test('dirección minimalista: acción principal monocroma y fondos planos', () {
    // Claro: tinta sobre hueso; oscuro: hueso sobre tinta. El color de marca no es la acción.
    expect(PerchaPalette.light.accent, PerchaPalette.light.ink);
    expect(PerchaPalette.dark.accent, PerchaPalette.dark.ink);
    expect(PerchaPalette.light.accentInk, isNot(PerchaPalette.light.accent));
  });

  test('las notificaciones solo navegan a rutas internas', () {
    AppNotification n(String? link) => AppNotification(id: '1', type: 't', title: 't', body: 'b', createdAt: DateTime(2026), link: link);
    expect(n('/transfers/abc').safeLink, '/transfers/abc');
    expect(n('https://evil.example').safeLink, isNull);
    expect(n('//evil.example').safeLink, isNull);
    expect(n(null).safeLink, isNull);
  });
}
