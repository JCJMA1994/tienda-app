import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Tema de Material construido desde los tokens del modo pedido. Los componentes estándar
/// (botones, campos, tarjetas, diálogos) toman sus colores de aquí, así que funcionan igual
/// en claro y oscuro sin tocar cada pantalla.
ThemeData buildPerchaTheme(Brightness brightness) {
  PerchaColors.use(brightness);
  final c = PerchaColors.palette;
  final base = ThemeData(useMaterial3: true, brightness: brightness);
  final body = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: c.ink, displayColor: c.ink);
  // Una sola familia (Inter / Inter Tight para títulos): más limpia que mezclar tipografías.
  TextStyle display(double size) => GoogleFonts.interTight(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.025 * size,
        color: c.ink,
        height: 1.15,
      );

  // Campos planos: fondo suave y borde fino; al enfocar, borde de tinta.
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(PerchaRadius.field),
    borderSide: BorderSide(color: c.border),
  );

  return base.copyWith(
    scaffoldBackgroundColor: c.ground,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accentInk,
      secondary: c.inverse,
      onSecondary: c.onInverse,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      surfaceContainerHighest: c.surfaceAlt,
      error: c.warn,
      onError: c.onAccent,
      errorContainer: c.warnSoft,
      onErrorContainer: c.warn,
      outline: c.borderStrong,
      outlineVariant: c.border,
      inverseSurface: c.inverse,
      onInverseSurface: c.onInverse,
      shadow: c.shadow,
    ),
    textTheme: body.copyWith(
      headlineLarge: display(30),
      headlineMedium: display(26),
      headlineSmall: display(22),
      titleLarge: display(18),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      bodySmall: body.bodySmall?.copyWith(fontSize: 13, color: c.muted),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(18),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(borderSide: BorderSide(color: c.ink, width: 1.5)),
      errorBorder: fieldBorder.copyWith(borderSide: BorderSide(color: c.warn)),
      focusedErrorBorder: fieldBorder.copyWith(borderSide: BorderSide(color: c.warn, width: 2)),
      labelStyle: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w500),
      hintStyle: TextStyle(color: c.muted),
      helperStyle: TextStyle(color: c.muted),
      errorStyle: TextStyle(color: c.warn, fontWeight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.surfaceAlt,
        disabledForegroundColor: c.muted,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PerchaRadius.field)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        foregroundColor: c.ink,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: c.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PerchaRadius.field)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accentInk)),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PerchaRadius.card), side: BorderSide(color: c.border)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(PerchaRadius.sheet))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PerchaRadius.dialog))),
    // Chips tipo píldora: seleccionado = tinta con texto claro (monocromo).
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.accent,
      checkmarkColor: c.onAccent,
      side: BorderSide(color: c.border),
      shape: const StadiumBorder(),
      labelStyle: WidgetStateTextStyle.resolveWith(
        (s) => TextStyle(color: s.contains(WidgetState.selected) ? c.onAccent : c.ink, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500),
      ),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onAccent : c.ink),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(PerchaRadius.field))),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
      elevation: 2,
      highlightElevation: 2,
      shape: const StadiumBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onAccent : c.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceAlt),
      trackOutlineColor: WidgetStatePropertyAll(c.borderStrong),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink, linearTrackColor: c.surfaceAlt),
    listTileTheme: ListTileThemeData(iconColor: c.inkSoft, titleTextStyle: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500)),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: c.surface, indicatorColor: c.surfaceAlt, selectedIconTheme: IconThemeData(color: c.ink), unselectedIconTheme: IconThemeData(color: c.muted)),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.inverse,
      contentTextStyle: TextStyle(color: c.onInverse),
      actionTextColor: c.onInverse,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PerchaRadius.field)),
    ),
    dividerTheme: DividerThemeData(color: c.border, space: 1),
  );
}
