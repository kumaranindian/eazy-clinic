import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

void main() {
  test('only active may access protected features', () {
    expect(AccountStatus.values.where((s) => s.canAccessProtectedFeatures), [
      AccountStatus.active,
    ]);
  });

  test('disabled is terminal; suspended is reversible', () {
    for (final s in AccountStatus.values) {
      expect(AccountStatus.disabled.canTransitionTo(s), isFalse);
    }
    expect(
      AccountStatus.suspended.canTransitionTo(AccountStatus.active),
      isTrue,
    );
    expect(
      AccountStatus.active.canTransitionTo(AccountStatus.pending),
      isFalse,
    );
  });

  test('permission policy denies unknown and unmapped roles', () {
    expect(PermissionPolicy.forPlatformRole(null), isEmpty);
    expect(PermissionPolicy.forClinicRole(ClinicRole.clinicOwner), isEmpty);
    expect(
      PermissionPolicy.platformRoleHas(
        PlatformRole.platformSupportAdmin,
        Permission.revokeUserSessions,
      ),
      isFalse,
    );
  });
}
