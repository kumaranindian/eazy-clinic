import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

void main() {
  test('session DTO round-trips', () {
    const dto = AuthSessionDto(
      uid: 'u1',
      accountStatus: AccountStatus.active,
      emailVerified: true,
      accessGranted: true,
      platformRole: PlatformRole.superAdmin,
      memberships: [
        MembershipSummaryDto(tenantId: 't1', role: 'doctor', branchIds: ['b1']),
      ],
    );
    final back = AuthSessionDto.fromJson(dto.toJson());
    expect(back.platformRole, PlatformRole.superAdmin);
    expect(back.memberships.single.branchIds, ['b1']);
    expect(back.accessGranted, true);
  });

  test('unknown status deserializes to disabled (deny by default)', () {
    final dto = AuthSessionDto.fromJson({
      'uid': 'u1',
      'accountStatus': 'something-new',
      'accessGranted': true,
    });
    expect(dto.accountStatus, AccountStatus.disabled);
  });

  test('profile DTO omits absent optional fields', () {
    const dto = AuthProfileDto(
      uid: 'u1',
      displayName: 'A',
      email: 'a@example.test',
      emailVerified: false,
      accountStatus: AccountStatus.pending,
    );
    expect(dto.toJson().containsKey('phoneNumber'), isFalse);
  });

  test('new account error codes map to 401/403', () {
    expect(ApiErrorCode.tokenExpired.httpStatus, 401);
    expect(ApiErrorCode.sessionRevoked.httpStatus, 401);
    for (final c in [
      ApiErrorCode.accountPending,
      ApiErrorCode.accountSuspended,
      ApiErrorCode.accountDisabled,
      ApiErrorCode.accountNotProvisioned,
    ]) {
      expect(c.httpStatus, 403);
    }
  });
}
