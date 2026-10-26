import 'package:flutter/foundation.dart';

/// Configuración por entorno vía --dart-define (nunca secretos en el binario).
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/v1
///   flutter build apk --dart-define=API_BASE_URL=https://api.system-failed-tech.com/v1
class Env {
  const Env._();

  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    // En Web o Desktop conectamos directo a localhost; en emulador Android a 10.0.2.2
    return kIsWeb ? 'http://localhost:3000/v1' : 'http://10.0.2.2:3000/v1';
  }

  /// Base de los enlaces de invitación que se comparten con el equipo.
  static const inviteBaseUrl = String.fromEnvironment(
    'INVITE_BASE_URL',
    defaultValue: 'https://app.system-failed-tech.com/invite',
  );

  /// Instrucciones para pagar la suscripción por Plin o transferencia (se verifica a mano).
  static const plinInstructions = String.fromEnvironment(
    'PLIN_INSTRUCTIONS',
    defaultValue: 'Plin al [TU NÚMERO] a nombre de [TU EMPRESA]. Envía la constancia a [TU CORREO O WHATSAPP].',
  );
}
