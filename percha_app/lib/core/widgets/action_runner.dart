import 'package:flutter/material.dart';

import 'percha_widgets.dart';

/// Una sola forma de ejecutar acciones desde una pantalla: marca "ocupado" (evita doble toque),
/// convierte el error en un mensaje legible y opcionalmente avisa el éxito.
///
/// Reemplaza el bloque `setState(busy) → try → catch(error) → finally` que se repetía en
/// muchas pantallas.
mixin ActionRunner<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  /// Ejecuta [action]. Devuelve su resultado, o null si falló o ya había otra en curso.
  /// Con [errorAsSnack] el error se muestra como aviso en lugar de en la pantalla.
  /// Con [describeError] se traduce un error conocido a un mensaje propio de la pantalla.
  Future<R?> runAction<R>(Future<R> Function() action, {String? success, bool errorAsSnack = false, String Function(Object error)? describeError}) async {
    if (busy) return null;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await action();
      if (success != null && mounted) snack(success);
      return result;
    } catch (e) {
      if (!mounted) return null;
      final message = describeError?.call(e) ?? errorText(e);
      errorAsSnack ? snack(message) : setState(() => error = message);
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
