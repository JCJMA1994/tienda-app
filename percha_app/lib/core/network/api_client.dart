import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../storage/token_storage.dart';
import 'api_error.dart';
import 'web_adapter.dart' if (dart.library.js_interop) 'web_adapter_web.dart';

/// Marca para endpoints públicos (login, registro...): no llevan token y un 401
/// significa "credenciales incorrectas", no "sesión vencida".
const kPublic = {'public': true};

/// Envoltura sobre Dio: un solo lugar que traduce errores a [ApiError].
/// Las capas de datos nunca ven un DioException.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStorage storage,
    required void Function() onSessionExpired,
    this.onPaymentRequired,
  }) : dio = Dio(_options(baseUrl)) {
    auth = AuthInterceptor(
      storage: storage,
      dio: dio,
      refreshDio: Dio(_options(baseUrl)),
      onSessionExpired: onSessionExpired,
    );
    dio.interceptors.add(auth);
    configureForWeb(dio);
    configureForWeb(auth.refreshDio);
  }

  final Dio dio;
  late final AuthInterceptor auth;

  /// 402: suscripción suspendida (SUBSCRIPTION_SUSPENDED) o límite del plan (PLAN_LIMIT).
  /// Se avisa en un solo lugar para no repetir el manejo en cada pantalla.
  final void Function(ApiError error)? onPaymentRequired;

  static BaseOptions _options(String baseUrl) => BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
        // Panel web: la API entrega el refresh token en una cookie HttpOnly, no en el JSON.
        headers: kIsWeb ? const {'X-Client': 'web'} : null,
      );

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => dio.get<dynamic>(path, queryParameters: _clean(query)));

  /// Con [idempotencyKey], la API aplica la operación una sola vez aunque se reintente (también
  /// cuando el interceptor reenvía la petición tras renovar la sesión: la cabecera viaja igual).
  Future<dynamic> post(String path, {Object? body, bool public = false, String? idempotencyKey}) => _run(
        () => dio.post<dynamic>(
          path,
          data: body ?? {},
          options: Options(extra: public ? kPublic : null, headers: idempotencyKey == null ? null : {'Idempotency-Key': idempotencyKey}),
        ),
      );

  Future<dynamic> patch(String path, {Object? body}) => _run(() => dio.patch<dynamic>(path, data: body));

  Future<dynamic> put(String path, {Object? body}) => _run(() => dio.put<dynamic>(path, data: body));

  Future<dynamic> delete(String path) => _run(() => dio.delete<dynamic>(path));

  /// Sube un archivo binario (p. ej. una foto) con su tipo de contenido.
  Future<dynamic> postBytes(String path, List<int> bytes, {required String contentType, Map<String, dynamic>? query}) => _run(
        () => dio.post<dynamic>(
          path,
          // Bytes en memoria (no un stream): si hay que renovar la sesión, el reintento puede reenviarlos.
          data: Uint8List.fromList(bytes),
          queryParameters: query,
          options: Options(contentType: contentType, headers: {Headers.contentLengthHeader: bytes.length}, sendTimeout: const Duration(seconds: 60)),
        ),
      );

  Future<dynamic> _run(Future<Response<dynamic>> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (e) {
      final error = ApiError.fromDio(e);
      if (error.status == 402) onPaymentRequired?.call(error);
      throw error;
    }
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) =>
      q == null ? null : (Map.of(q)..removeWhere((_, v) => v == null));
}

/// Adjunta el access token y, ante un 401, refresca UNA sola vez aunque fallen
/// varias peticiones a la vez.
///
/// Es un [QueuedInterceptor]: los errores se procesan en fila. Si cinco requests
/// vuelven con 401 al mismo tiempo, el primero refresca y los otros cuatro detectan
/// que el token ya cambió y solo reintentan. Esto importa porque la API ROTA el
/// refresh token: dos refresh en paralelo con el mismo token se leerían como robo y
/// cerrarían todas las sesiones del usuario.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.storage,
    required this.dio,
    required this.refreshDio,
    required this.onSessionExpired,
  });

  final TokenStorage storage;
  final Dio dio;
  final Dio refreshDio;
  final void Function() onSessionExpired;

  StoredTokens? _tokens;
  bool _loaded = false;

  Future<void> setTokens(StoredTokens? tokens) async {
    _tokens = tokens;
    _loaded = true;
    if (tokens == null) {
      await storage.clear();
    } else {
      await storage.save(tokens);
    }
  }

  Future<StoredTokens?> currentTokens() async {
    if (!_loaded) {
      _tokens = await storage.read();
      _loaded = true;
    }
    return _tokens;
  }

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['public'] != true) {
      final tokens = await currentTokens();
      if (tokens != null) options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    final shouldTry = err.response?.statusCode == 401 && req.extra['public'] != true && req.extra['retried'] != true;
    if (!shouldTry) return handler.next(err);

    final current = await currentTokens();
    if (current == null) return handler.next(err);

    final sentWith = req.headers['Authorization'];
    final alreadyRefreshed = sentWith != 'Bearer ${current.accessToken}';

    if (!alreadyRefreshed) {
      try {
        // Web: el refresh token va en la cookie (el JavaScript nunca lo ve).
        final res = await refreshDio.post<Map<String, dynamic>>('/auth/refresh', data: kIsWeb ? const {} : {'refreshToken': current.refreshToken});
        await setTokens(StoredTokens(
          accessToken: res.data!['accessToken'] as String,
          refreshToken: res.data!['refreshToken'] as String? ?? kCookieSession,
        ),);
      } on DioException {
        await setTokens(null);
        onSessionExpired();
        return handler.next(err);
      }
    }

    try {
      req.headers['Authorization'] = 'Bearer ${_tokens!.accessToken}';
      req.extra['retried'] = true;
      handler.resolve(await dio.fetch<dynamic>(req));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
