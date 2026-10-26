import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/feedback.dart';
import '../../../core/router/app_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_api.dart';
import '../data/auth_models.dart';

// ---------------------------------------------------------------- infraestructura

final tokenStorageProvider = Provider<TokenStorage>((_) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: Env.apiBaseUrl,
    storage: ref.watch(tokenStorageProvider),
    // Se lee en diferido para no crear un ciclo de dependencias entre providers.
    onSessionExpired: () => ref.read(sessionProvider.notifier).expired(),
    onPaymentRequired: (e) => showPaymentRequired(e, () => ref.read(routerProvider).push('/billing')),
  );
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));

// ---------------------------------------------------------------- estado de sesión

sealed class SessionState {
  const SessionState();
}

/// Arrancando: leyendo tokens guardados y validándolos con /auth/me.
class SessionRestoring extends SessionState {
  const SessionRestoring();
}

class SignedOut extends SessionState {
  const SignedOut({this.reason});

  /// Mensaje para el login cuando la sesión terminó sola (p. ej. expiró).
  final String? reason;
}

/// La contraseña es correcta pero el usuario pertenece a varias tiendas.
class ChoosingTenant extends SessionState {
  const ChoosingTenant({required this.email, required this.password, required this.tenants, this.challenge});
  final String email;
  final String password;
  final List<TenantOption> tenants;

  /// Con 2FA ya verificado, se elige la tienda con este desafío (sin repetir el código).
  final String? challenge;
}

/// La contraseña es correcta y la cuenta tiene verificación en dos pasos: falta el código.
class AwaitingTwoFactor extends SessionState {
  const AwaitingTwoFactor({required this.challenge, this.email = '', this.isNewStore = false});
  final String challenge;
  final String email;
  final bool isNewStore;
}

class SignedIn extends SessionState {
  const SignedIn(this.me, {this.isNewStore = false});
  final Me me;

  /// Recién registrada: el router la lleva al onboarding.
  final bool isNewStore;
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Única fuente de verdad sobre "¿hay alguien conectado y quién es?".
/// El router escucha este estado para decidir a qué pantalla ir.
class SessionController extends Notifier<SessionState> {
  AuthApi get _api => ref.read(authApiProvider);
  AuthInterceptor get _auth => ref.read(apiClientProvider).auth;

  @override
  SessionState build() {
    unawaited(_restore());
    return const SessionRestoring();
  }

  Future<void> _restore() async {
    final tokens = await _auth.currentTokens();
    if (tokens == null) {
      state = const SignedOut();
      return;
    }
    try {
      // Si el access token venció, el interceptor refresca solo antes de responder.
      state = SignedIn(await _api.me());
    } on ApiError catch (e) {
      // Sin red al abrir la app no cerramos la sesión: se reintenta al volver la conexión.
      if (e.isNetwork) {
        state = const SignedOut(reason: 'No pudimos conectar con el servidor.');
        return;
      }
      await _auth.setTokens(null);
      state = const SignedOut();
    }
  }

  Future<void> login(String email, String password, {String? tenantId}) async {
    await _apply(await _api.login(email: email, password: password, tenantId: tenantId), email: email, password: password);
  }

  /// Aplica el resultado de cualquier paso de acceso.
  Future<void> _apply(LoginResult result, {String email = '', String password = '', bool isNewStore = false}) async {
    switch (result) {
      case LoginNeedsTwoFactor(:final challenge):
        state = AwaitingTwoFactor(challenge: challenge, email: email, isNewStore: isNewStore);
      case LoginNeedsTenant(:final tenants, :final challenge):
        state = ChoosingTenant(email: email, password: password, tenants: tenants, challenge: challenge);
      case LoginOk(:final tokens):
        await _auth.setTokens(tokens);
        state = SignedIn(await _api.me(), isNewStore: isNewStore);
    }
  }

  Future<void> verifyTwoFactor({String? code, String? recoveryCode}) async {
    final s = state;
    if (s is! AwaitingTwoFactor) return;
    await _apply(await _api.verifyTwoFactor(challenge: s.challenge, code: code, recoveryCode: recoveryCode), email: s.email, isNewStore: s.isNewStore);
  }

  Future<void> chooseTenant(String tenantId) async {
    final s = state;
    if (s is! ChoosingTenant) return;
    if (s.challenge != null) {
      await _apply(await _api.verifyTwoFactor(challenge: s.challenge!, tenantId: tenantId), email: s.email);
    } else {
      await login(s.email, s.password, tenantId: tenantId);
    }
  }

  Future<void> register({
    required String storeName,
    required String ownerName,
    required String email,
    required String password,
  }) async {
    await _apply(await _api.register(storeName: storeName, ownerName: ownerName, email: email, password: password), email: email, isNewStore: true);
  }

  /// Acepta una invitación: crea la cuenta (o usa la existente) y entra a la tienda.
  Future<void> acceptInvitation({required String token, String? name, required String password}) async {
    await _apply(await _api.acceptInvitation(token: token, name: name, password: password));
  }

  /// Cambio de vendedor en el POS. Solo reemplaza la sesión si el PIN es válido.
  Future<Me> switchByPin({required String branchId, required String pin}) async {
    final previous = await _auth.currentTokens();
    final tokens = await _api.switchByPin(branchId: branchId, pin: pin);
    await _auth.setTokens(tokens);
    final me = await _api.me();
    state = SignedIn(me);
    // La sesión anterior queda revocada: la tablet no acumula sesiones abiertas.
    if (previous != null) unawaited(_api.logout(previous.refreshToken).catchError((_) {}));
    return me;
  }

  void finishOnboarding() {
    final s = state;
    if (s is SignedIn) state = SignedIn(s.me);
  }

  Future<void> logout() async {
    final tokens = await _auth.currentTokens();
    await _auth.setTokens(null);
    state = const SignedOut();
    if (tokens != null) {
      try {
        await _api.logout(tokens.refreshToken);
      } on ApiError {
        // Ya se borró localmente; si el servidor no responde, el token expira solo.
      }
    }
  }

  /// El interceptor no pudo refrescar: el refresh venció o fue revocado.
  void expired() {
    if (state is SignedIn) state = const SignedOut(reason: 'Tu sesión terminó. Vuelve a ingresar.');
  }

  void cancelTenantChoice() => state = const SignedOut();

  /// Cambia la contraseña y guarda la sesión nueva (las demás quedan cerradas).
  Future<void> changePassword({required String current, required String next}) async {
    await _auth.setTokens(await _api.changePassword(current: current, next: next));
  }

  /// Cierra la sesión en todos los dispositivos, incluido este.
  Future<void> logoutEverywhere() async {
    try {
      await _api.logoutEverywhere();
    } catch (_) {}
    await logout();
  }

  /// Recarga los datos del usuario (p. ej. tras activar 2FA).
  Future<void> reloadMe() async {
    if (state is SignedIn) state = SignedIn(await _api.me());
  }
}

/// Atajo para pantallas que solo existen con sesión iniciada.
final meProvider = Provider<Me>((ref) {
  final s = ref.watch(sessionProvider);
  if (s is SignedIn) return s.me;
  throw StateError('meProvider usado sin sesión');
});
