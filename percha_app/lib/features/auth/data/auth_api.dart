import '../../../core/network/api_client.dart';
import '../../../core/storage/token_storage.dart';
import 'auth_models.dart';

class AuthApi {
  const AuthApi(this._api);
  final ApiClient _api;

  Future<LoginResult> register({
    required String storeName,
    required String ownerName,
    required String email,
    required String password,
  }) async {
    final res = await _api.post(
      '/auth/register',
      public: true,
      body: {'storeName': storeName, 'ownerName': ownerName, 'email': email, 'password': password},
    );
    return parseLoginResult(res as Map<String, dynamic>);
  }

  Future<LoginResult> login({required String email, required String password, String? tenantId}) async {
    final res = await _api.post(
      '/auth/login',
      public: true,
      body: {'email': email, 'password': password, if (tenantId != null) 'tenantId': tenantId},
    ) as Map<String, dynamic>;
    return parseLoginResult(res);
  }

  /// Segundo paso: código de la app autenticadora o código de recuperación.
  Future<LoginResult> verifyTwoFactor({required String challenge, String? code, String? recoveryCode, String? tenantId}) async {
    final res = await _api.post('/auth/2fa/verify', public: true, body: {
      'challenge': challenge,
      if (code != null) 'code': code,
      if (recoveryCode != null) 'recoveryCode': recoveryCode,
      if (tenantId != null) 'tenantId': tenantId,
    },) as Map<String, dynamic>;
    return parseLoginResult(res);
  }

  /// Cambia la contraseña; la API cierra las demás sesiones y devuelve una nueva para este dispositivo.
  Future<StoredTokens> changePassword({required String current, required String next}) async =>
      tokensFromJson(await _api.post('/auth/password', body: {'currentPassword': current, 'newPassword': next}) as Map<String, dynamic>);

  Future<void> logoutEverywhere() => _api.post('/auth/logout-all');

  Future<void> forgotPassword(String email) => _api.post('/auth/password/forgot', public: true, body: {'email': email});
  Future<void> resetPassword(String token, String newPassword) =>
      _api.post('/auth/password/reset', public: true, body: {'token': token, 'newPassword': newPassword});

  Future<({String secret, String uri})> setupTwoFactor() async {
    final r = await _api.post('/auth/2fa/setup') as Map<String, dynamic>;
    return (secret: r['secret'] as String, uri: r['otpauthUri'] as String);
  }

  Future<List<String>> enableTwoFactor(String code) async =>
      ((await _api.post('/auth/2fa/enable', body: {'code': code}) as Map<String, dynamic>)['recoveryCodes'] as List<dynamic>).cast<String>();

  Future<void> disableTwoFactor({required String password, String? code, String? recoveryCode}) => _api.post('/auth/2fa/disable', body: {
        'password': password,
        if (code != null) 'code': code,
        if (recoveryCode != null) 'recoveryCode': recoveryCode,
      },);

  Future<LoginResult> acceptInvitation({required String token, String? name, required String password}) async {
    final res = await _api.post(
      '/auth/invitations/accept',
      public: true,
      body: {'token': token, if (name != null && name.isNotEmpty) 'name': name, 'password': password},
    );
    return parseLoginResult(res as Map<String, dynamic>);
  }

  Future<StoredTokens> switchByPin({required String branchId, required String pin}) async {
    final res = await _api.post('/auth/pin', body: {'branchId': branchId, 'pin': pin});
    return tokensFromJson(res as Map<String, dynamic>);
  }

  Future<Me> me() async => Me.fromJson(await _api.get('/auth/me') as Map<String, dynamic>);

  Future<void> logout(String refreshToken) =>
      _api.post('/auth/logout', public: true, body: refreshToken == kCookieSession ? const {} : {'refreshToken': refreshToken});
}
