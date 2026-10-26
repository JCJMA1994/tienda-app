import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';

/// Nivel de acceso de un rol a un permiso, tal como lo publica GET /roles.
enum Access {
  yes,
  no,
  approval,
  ownBranch;

  static Access parse(String v) => switch (v) {
        'yes' => Access.yes,
        'approval' => Access.approval,
        'own_branch' => Access.ownBranch,
        _ => Access.no,
      };
}

class PermissionInfo {
  const PermissionInfo({required this.key, required this.label, required this.group});
  final String key;
  final String label;
  final String group;
}

class RoleInfo {
  const RoleInfo({required this.key, required this.label, required this.access, required this.assignable});
  final String key;
  final String label;
  final Map<String, Access> access;
  final List<String> assignable;
}

class RolesCatalog {
  const RolesCatalog({required this.permissions, required this.roles});
  final List<PermissionInfo> permissions;
  final List<RoleInfo> roles;

  RoleInfo role(String key) => roles.firstWhere((r) => r.key == key);
  String label(String key) => roles.where((r) => r.key == key).firstOrNull?.label ?? key;

  /// Permisos agrupados en el orden que define la API.
  Map<String, List<PermissionInfo>> get byGroup {
    final out = <String, List<PermissionInfo>>{};
    for (final p in permissions) {
      out.putIfAbsent(p.group, () => []).add(p);
    }
    return out;
  }

  factory RolesCatalog.fromJson(Map<String, dynamic> j) => RolesCatalog(
        permissions: (j['permissions'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((p) => PermissionInfo(key: p['key'] as String, label: p['label'] as String, group: p['group'] as String))
            .toList(),
        roles: (j['roles'] as List<dynamic>).cast<Map<String, dynamic>>().map((r) {
          final access = (r['access'] as Map<String, dynamic>).map((k, v) => MapEntry(k, Access.parse(v as String)));
          return RoleInfo(
            key: r['key'] as String,
            label: r['label'] as String,
            access: access,
            assignable: (r['assignable'] as List<dynamic>).cast<String>(),
          );
        }).toList(),
      );
}

/// La matriz viene de la API (misma fuente que aplican los guards): la app no la duplica.
/// keepAlive: cambia solo con un deploy, no hace falta pedirla en cada pantalla.
final rolesProvider = FutureProvider<RolesCatalog>((ref) async {
  ref.watch(sessionProvider.select((s) => s is SignedIn));
  final res = await ref.watch(apiClientProvider).get('/roles');
  return RolesCatalog.fromJson(res as Map<String, dynamic>);
});
