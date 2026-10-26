import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/auth/data/auth_models.dart';

void main() {
  test('interpreta sesión, elección de tienda y verificación en dos pasos', () {
    expect(parseLoginResult({'accessToken': 'a', 'refreshToken': 'r'}), isA<LoginOk>());
    final twoFa = parseLoginResult({'requiresTwoFactor': true, 'challenge': 'c'});
    expect(twoFa, isA<LoginNeedsTwoFactor>());
    expect((twoFa as LoginNeedsTwoFactor).challenge, 'c');
    final tenant = parseLoginResult({
      'requiresTenantSelection': true,
      'tenants': [
        {'tenantId': 't', 'name': 'Alma', 'role': 'owner'},
      ],
      'challenge': 'v',
    });
    expect((tenant as LoginNeedsTenant).challenge, 'v');
    expect(tenant.tenants.single.name, 'Alma');
  });
}
