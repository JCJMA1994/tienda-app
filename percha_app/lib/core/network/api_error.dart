import 'package:dio/dio.dart';

/// Error de la API normalizado. Los `code` coinciden con los de percha-api
/// (APPROVAL_REQUIRED, INSUFFICIENT_STOCK, CASH_CLOSED, PAYMENT_MISMATCH...).
class ApiError implements Exception {
  const ApiError({required this.status, required this.message, this.code, this.data = const {}});

  final int status;
  final String message;
  final String? code;
  final Map<String, dynamic> data;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  /// Errores de validación de zod: [{ path, message }].
  List<({String path, String message})> get issues {
    final raw = data['issues'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((i) => (path: '${i['path']}', message: '${i['message']}'))
        .toList();
  }

  factory ApiError.fromDio(DioException e) {
    final response = e.response;
    if (response == null) {
      return const ApiError(status: 0, message: 'Sin conexión con el servidor. Revisa tu internet.');
    }
    final body = response.data;
    final map = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final rawMessage = map['message'];
    final message = rawMessage is String
        ? rawMessage
        : rawMessage is List
            ? rawMessage.join(', ')
            : 'Ocurrió un error (${response.statusCode})';
    return ApiError(
      status: response.statusCode ?? 500,
      message: message,
      code: map['code'] as String?,
      data: map,
    );
  }

  @override
  String toString() => 'ApiError($status, $code, $message)';
}
