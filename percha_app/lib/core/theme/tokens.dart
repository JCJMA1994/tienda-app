import 'package:flutter/material.dart';

/// Tokens SEMÁNTICOS de color: se nombran por su función ("superficie", "texto atenuado"),
/// no por su tono. Cada modo (claro / oscuro) define su propio valor para cada token.
///
/// Contrastes verificados para WCAG AA:
/// - texto (`ink`, `inkSoft`, `muted`) sobre `surface` y `ground`: ≥ 4.5:1
/// - `onAccent` sobre `accent` y `onInverse` sobre `inverse`: ≥ 4.5:1
/// - `accentInk` y `warn` (texto) sobre su fondo suave: ≥ 4.5:1
@immutable
class PerchaPalette {
  const PerchaPalette({
    required this.brightness,
    required this.ground,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceGlass,
    required this.border,
    required this.borderStrong,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentInk,
    required this.accentSoft,
    required this.warn,
    required this.warnSoft,
    required this.success,
    required this.inverse,
    required this.onInverse,
    required this.shadow,
  });

  final Brightness brightness;

  /// Fondo de pantalla.
  final Color ground;

  /// Tarjetas, campos, barras.
  final Color surface;
  final Color surfaceAlt;

  /// Superficie translúcida de la barra flotante (con desenfoque detrás).
  final Color surfaceGlass;
  final Color border;
  final Color borderStrong;

  /// Texto principal, secundario y atenuado.
  final Color ink;
  final Color inkSoft;
  final Color muted;

  /// Marca: relleno de acciones principales y el texto que va encima.
  final Color accent;
  final Color onAccent;

  /// Acento como TEXTO o ícono sobre superficies, y su fondo suave.
  final Color accentInk;
  final Color accentSoft;

  /// Alertas (stock bajo, pagos pendientes). Naranja: se distingue del acento también en luminosidad.
  final Color warn;
  final Color warnSoft;
  final Color success;

  /// Tarjetas de alto énfasis (contraste invertido) y su texto.
  final Color inverse;
  final Color onInverse;
  final Color shadow;

  /// Dirección visual: minimalista y cálida, como una tienda de diseño.
  ///  - Neutros "piedra" (ligeramente cálidos), no grises fríos: la ropa y las fotos resaltan.
  ///  - Acción principal en negro tinta (claro) / blanco hueso (oscuro): monocromo y sobrio.
  ///  - UN solo color de marca, índigo "iris", y solo para destacar (enlaces, selección,
  ///    promociones, estado "disponible"). Nunca para fondos grandes.
  ///  - Bordes finos en lugar de sombras; superficies planas.
  /// Todo par texto/fondo cumple WCAG AA (probado en test/design_tokens_test.dart).
  static const light = PerchaPalette(
    brightness: Brightness.light,
    ground: Color(0xFFF7F6F4),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F0EE),
    surfaceGlass: Color(0xE6FFFFFF),
    border: Color(0xFFE7E4E0),
    borderStrong: Color(0xFFD6D2CC),
    ink: Color(0xFF171514),
    inkSoft: Color(0xFF3D3935),
    muted: Color(0xFF6B6560),
    accent: Color(0xFF171514),
    onAccent: Color(0xFFFFFFFF),
    accentInk: Color(0xFF4B3FD1),
    accentSoft: Color(0xFFEFEEFB),
    warn: Color(0xFFB93815),
    warnSoft: Color(0xFFFDF1EC),
    success: Color(0xFF157F3C),
    inverse: Color(0xFF171514),
    onInverse: Color(0xFFFFFFFF),
    shadow: Color(0x14171514),
  );

  static const dark = PerchaPalette(
    brightness: Brightness.dark,
    ground: Color(0xFF0D0C0B),
    surface: Color(0xFF161514),
    surfaceAlt: Color(0xFF201E1C),
    surfaceGlass: Color(0xD91A1917),
    border: Color(0xFF2B2826),
    borderStrong: Color(0xFF3B3734),
    ink: Color(0xFFF5F4F2),
    inkSoft: Color(0xFFD3CFCA),
    muted: Color(0xFFA39D96),
    accent: Color(0xFFF5F4F2),
    onAccent: Color(0xFF0D0C0B),
    accentInk: Color(0xFFB3ABFF),
    accentSoft: Color(0xFF25223A),
    warn: Color(0xFFFF9B6B),
    warnSoft: Color(0xFF2C1810),
    success: Color(0xFF5FD68B),
    inverse: Color(0xFF2A2725),
    onInverse: Color(0xFFFFFFFF),
    shadow: Color(0x66000000),
  );
}

abstract final class PerchaColors {
  static PerchaPalette _p = PerchaPalette.light;
  static PerchaPalette get palette => _p;
  static void use(Brightness b) => _p = b == Brightness.dark ? PerchaPalette.dark : PerchaPalette.light;

  static Color get ground => _p.ground;
  static Color get surface => _p.surface;
  static Color get surfaceAlt => _p.surfaceAlt;
  static Color get surfaceGlass => _p.surfaceGlass;
  static Color get border => _p.border;
  static Color get borderStrong => _p.borderStrong;
  static Color get ink => _p.ink;
  static Color get inkSoft => _p.inkSoft;
  static Color get muted => _p.muted;
  static Color get accent => _p.accent;
  static Color get onAccent => _p.onAccent;
  static Color get accentInk => _p.accentInk;
  static Color get accentSoft => _p.accentSoft;
  static Color get warn => _p.warn;
  static Color get warnSoft => _p.warnSoft;
  static Color get success => _p.success;
  static Color get inverse => _p.inverse;
  static Color get onInverse => _p.onInverse;
  static Color get shadow => _p.shadow;
}

/// Escala tipográfica (puntos lógicos; el sistema aplica el tamaño de letra del usuario).
/// Toda la app usa estos pasos: así una pantalla nueva no inventa tamaños.
abstract final class PerchaType {
  /// Notas mínimas: saldo en el kardex, ejes de gráficos, leyendas.
  static const double caption = 11;

  /// Metadatos: etiquetas, pills, stock bajo una tarjeta.
  static const double meta = 12;

  /// Texto secundario (= bodySmall del tema).
  static const double small = 13;

  /// Texto de lista o tabla.
  static const double body = 14;

  /// Texto destacado, nombres, botones (= bodyMedium / titleMedium del tema).
  static const double strong = 15;

  /// Títulos de tarjetas y cifras.
  static const double title = 16;

  /// Totales.
  static const double amount = 18;

  /// Códigos para leer en voz alta (vales, recuperación).
  static const double code = 20;

  /// Cifras grandes y PIN.
  static const double display = 28;
}

abstract final class PerchaSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class PerchaRadius {
  static const field = 12.0;
  static const card = 16.0;
  static const sheet = 24.0;
  static const dialog = 20.0;
  static const pill = 999.0;
}

/// Movimiento: corto y con desaceleración (se siente rápido sin ser brusco).
abstract final class PerchaMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;
}

/// Mínimo táctil: 48 px (en el POS se trabaja rápido y de pie).
const kTouchTarget = 48.0;

/// Espacio que deja libre la barra flotante al final de las listas.
const kFloatingNavClearance = 104.0;
