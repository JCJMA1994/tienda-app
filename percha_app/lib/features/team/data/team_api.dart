import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';

class Member {
  const Member({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.branchId,
    required this.active,
    required this.hasPin,
    this.commissionBp,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? branchId;
  final bool active;
  final bool hasPin;

  /// Comisión en puntos básicos (300 = 3 %); null = sin comisión.
  final int? commissionBp;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        branchId: j['branchId'] as String?,
        active: j['status'] == 'active',
        hasPin: j['hasPin'] as bool,
        commissionBp: j['commissionBp'] as int?,
      );
}

class Invitation {
  const Invitation({required this.id, required this.email, required this.role, required this.expiresAt});
  final String id;
  final String email;
  final String role;
  final DateTime expiresAt;

  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
        id: j['id'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
      );
}

class TeamApi {
  const TeamApi(this._api);
  final ApiClient _api;

  Future<List<Member>> members() async =>
      (await _api.get('/team/members') as List<dynamic>).cast<Map<String, dynamic>>().map(Member.fromJson).toList();

  /// [commissionBp]: `null` no cambia; usar [clearCommission] para quitarla.
  Future<void> update(String id, {String? role, String? branchId, bool clearBranch = false, bool? active, int? commissionBp, bool clearCommission = false}) =>
      _api.patch('/team/members/$id', body: {
        if (role != null) 'role': role,
        if (commissionBp != null || clearCommission) 'commissionBp': commissionBp,
        if (branchId != null || clearBranch) 'branchId': branchId,
        if (active != null) 'status': active ? 'active' : 'disabled',
      });

  Future<void> setPin(String memberId, String pin) => _api.put('/team/members/$memberId/pin', body: {'pin': pin});

  /// Devuelve el token: se muestra una sola vez para armar el enlace.
  Future<String> invite({required String email, required String role, String? branchId}) async {
    final res = await _api.post('/team/invitations', body: {'email': email, 'role': role, 'branchId': branchId}) as Map<String, dynamic>;
    return res['token'] as String;
  }

  Future<List<Invitation>> invitations() async =>
      (await _api.get('/team/invitations') as List<dynamic>).cast<Map<String, dynamic>>().map(Invitation.fromJson).toList();

  Future<void> revoke(String id) => _api.delete('/team/invitations/$id');
}

final teamApiProvider = Provider<TeamApi>((ref) => TeamApi(ref.watch(apiClientProvider)));
final membersProvider = FutureProvider.autoDispose<List<Member>>((ref) => ref.watch(teamApiProvider).members());
final invitationsProvider = FutureProvider.autoDispose<List<Invitation>>((ref) => ref.watch(teamApiProvider).invitations());
