import 'package:flutter/material.dart';

import 'network/api_error.dart';

/// Mensajes globales (fuera de cualquier pantalla), p. ej. avisos de facturación.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showPaymentRequired(ApiError e, VoidCallback openBilling) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: e.code == 'PLAN_LIMIT' ? 'Mejorar plan' : 'Ver facturación', onPressed: openBilling),
      ),
    );
}
