import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// En web el refresh token vive en una cookie HttpOnly: en la app queda solo esta marca.
const kCookieSession = 'cookie';

class StoredTokens {
  const StoredTokens({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;
}

/// Tokens en Keychain (iOS) / Keystore (Android). SharedPreferences no es seguro para esto.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;
  static const _access = 'percha.access';
  static const _refresh = 'percha.refresh';

  /// Web: el access token (15 min) solo en memoria; el refresh, en la cookie HttpOnly. Se
  /// guarda únicamente una marca "hay sesión" para intentar recuperarla al recargar la página.
  static const _webFlag = 'percha.web.session';
  String? _webAccess;

  Future<StoredTokens?> read() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_webFlag) != true) return null;
      // Sin access token: la primera petición da 401 y el interceptor renueva con la cookie.
      return StoredTokens(accessToken: _webAccess ?? '', refreshToken: kCookieSession);
    }
    final access = await _storage.read(key: _access);
    final refresh = await _storage.read(key: _refresh);
    if (access == null || refresh == null) return null;
    return StoredTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> save(StoredTokens tokens) async {
    if (kIsWeb) {
      _webAccess = tokens.accessToken;
      await (await SharedPreferences.getInstance()).setBool(_webFlag, true);
      return;
    }
    await _storage.write(key: _access, value: tokens.accessToken);
    await _storage.write(key: _refresh, value: tokens.refreshToken);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      _webAccess = null;
      await (await SharedPreferences.getInstance()).remove(_webFlag);
      return;
    }
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
  }
}
