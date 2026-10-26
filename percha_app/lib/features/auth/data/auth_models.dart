import '../../../core/storage/token_storage.dart';

/// Lo que devuelve GET /auth/me: quién soy, en qué tienda y qué puedo hacer.
class Me {
  const Me({
    required this.userId,
    required this.tenantId,
    required this.membershipId,
    required this.role,
    required this.branchId,
    required this.name,
    required this.email,
    required this.tenantName,
    required this.permissions,
    this.isPlatformAdmin = false,
    this.twoFactorEnabled = false,
  });

  final String userId;
  final String tenantId;
  final String membershipId;
  final String role;
  final String? branchId;
  final String name;
  final String email;
  final String tenantName;
  final Set<String> permissions;

  /// Superadmin de Percha: ve el backoffice. Los endpoints /admin lo verifican en el servidor.
  final bool isPlatformAdmin;

  /// Verificación en dos pasos activa en la cuenta.
  final bool twoFactorEnabled;

  /// La UI oculta lo que no se puede hacer, pero la API es quien decide:
  /// esto es comodidad, no seguridad.
  bool can(String permission) => permissions.contains(permission);

  String get firstName => name.split(' ').first;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        userId: j['userId'] as String,
        tenantId: j['tenantId'] as String,
        membershipId: j['membershipId'] as String,
        role: j['role'] as String,
        branchId: j['branchId'] as String?,
        name: j['name'] as String,
        email: j['email'] as String,
        tenantName: j['tenantName'] as String,
        permissions: {...(j['permissions'] as List<dynamic>).cast<String>()},
        isPlatformAdmin: j['isPlatformAdmin'] as bool? ?? false,
        twoFactorEnabled: j['twoFactorEnabled'] as bool? ?? false,
      );
}

class TenantOption {
  const TenantOption({required this.tenantId, required this.name, required this.role});
  final String tenantId;
  final String name;
  final String role;

  factory TenantOption.fromJson(Map<String, dynamic> j) =>
      TenantOption(tenantId: j['tenantId'] as String, name: j['name'] as String, role: j['role'] as String);
}

/// El login puede terminar en sesión, en "elige tu tienda" o en "ingresa tu código" (2FA).
sealed class LoginResult {
  const LoginResult();
}

class LoginOk extends LoginResult {
  const LoginOk(this.tokens);
  final StoredTokens tokens;
}

class LoginNeedsTenant extends LoginResult {
  const LoginNeedsTenant(this.tenants, {this.challenge});
  final List<TenantOption> tenants;

  /// Si ya pasó el segundo factor: con este desafío elige tienda sin repetir el código.
  final String? challenge;
}

class LoginNeedsTwoFactor extends LoginResult {
  const LoginNeedsTwoFactor(this.challenge);
  final String challenge;
}

/// Interpreta cualquier respuesta que pueda terminar en sesión (login, registro, invitación, 2FA).
LoginResult parseLoginResult(Map<String, dynamic> res) {
  if (res['requiresTwoFactor'] == true) return LoginNeedsTwoFactor(res['challenge'] as String);
  if (res['requiresTenantSelection'] == true) {
    final list = (res['tenants'] as List<dynamic>).cast<Map<String, dynamic>>();
    return LoginNeedsTenant(list.map(TenantOption.fromJson).toList(), challenge: res['challenge'] as String?);
  }
  return LoginOk(tokensFromJson(res));
}

StoredTokens tokensFromJson(Map<String, dynamic> j) =>
    // En web el refresh token no viene en el JSON (va en una cookie HttpOnly).
    StoredTokens(accessToken: j['accessToken'] as String, refreshToken: j['refreshToken'] as String? ?? kCookieSession);

const roleLabels = {
  'owner': 'Dueño',
  'manager': 'Encargado',
  'seller': 'Vendedor',
  'stock': 'Almacén',
};
