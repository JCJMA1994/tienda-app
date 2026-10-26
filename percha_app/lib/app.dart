import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/feedback.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';

class PerchaApp extends ConsumerStatefulWidget {
  const PerchaApp({super.key});

  @override
  ConsumerState<PerchaApp> createState() => _PerchaAppState();
}

class _PerchaAppState extends ConsumerState<PerchaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// En modo "sistema", sigue el cambio del teléfono (p. ej. oscuro automático de noche).
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final brightness = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platform,
    };
    // Se construye SOLO el tema activo: los tokens (PerchaColors) apuntan a ese modo.
    final theme = buildPerchaTheme(brightness);

    return MaterialApp.router(
      title: 'Percha',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: theme,
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Al cambiar de modo se vuelven a pintar TODAS las pantallas con los tokens nuevos, sin
      // perder su estado (ticket a medio cobrar, diálogos abiertos, formularios llenos).
      builder: (context, child) => _RepaintOnBrightness(brightness: brightness, child: child ?? const SizedBox()),
    );
  }
}

/// Antes se usaba una clave por modo, que REINICIABA todo el árbol: si el teléfono pasaba a
/// oscuro de noche en medio de un cobro, se cerraban los diálogos y se perdía el ticket.
/// Ahora se marcan los widgets para volver a pintarse (incluidos los `const`, que leen los
/// tokens estáticos) y el estado se conserva.
class _RepaintOnBrightness extends StatefulWidget {
  const _RepaintOnBrightness({required this.brightness, required this.child});
  final Brightness brightness;
  final Widget child;

  @override
  State<_RepaintOnBrightness> createState() => _RepaintOnBrightnessState();
}

class _RepaintOnBrightnessState extends State<_RepaintOnBrightness> {
  @override
  void didUpdateWidget(covariant _RepaintOnBrightness old) {
    super.didUpdateWidget(old);
    if (old.brightness == widget.brightness) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      (context as Element).visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
