import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';

Future<void> main() async {
  // En la web: rutas como /invite?token=… en lugar de /#/invite. Requiere que el hosting
  // reescriba toda ruta a index.html (ver docs/08-web.md). En móvil no tiene efecto.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  // Nombres de meses y días en español para DateFormat (kardex, invitaciones).
  await initializeDateFormatting('es');
  runApp(const ProviderScope(child: PerchaApp()));
}
