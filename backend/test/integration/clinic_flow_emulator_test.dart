@Tags(['emulator'])
library;

import 'dart:io';

import 'package:backend/core/data/document_store.dart';
import 'package:backend/core/data/firestore_document_store.dart';
import 'package:backend/features/auth/domain/auth_context.dart';
import 'package:backend/features/auth/domain/platform_user.dart';
import 'package:backend/features/auth/domain/verified_identity.dart';
import 'package:backend/features/clinic/branches/branch_service.dart';
import 'package:backend/features/clinic/common/clinic_deps.dart';
import 'package:backend/features/clinic/common/seat_service.dart';
import 'package:backend/features/clinic/common/tenant_context.dart';
import 'package:backend/features/clinic/doctors/doctor_service.dart';
import 'package:backend/features/clinic/invitations/invitation_service.dart';
import 'package:backend/features/clinic/staff/staff_service.dart';
import 'package:backend/features/platform/audit/audit_service.dart';
import 'package:backend/features/platform/entitlements/entitlement_service.dart';
import 'package:common_models/common_models.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/platform_http_fixtures.dart' show branchBody;

class _OwnerClient extends http.BaseClient {
  _OwnerClient(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

/// Clinic administration on the real Firestore REST store: seats and their
/// release (DeleteOp), uniqueness keys, the collection-group token lookup,
/// invitation acceptance and membership resolution. (Concurrency on seats is
/// covered against the in-memory store; the emulator serializes transactions
/// pessimistically, so these steps run sequentially.)
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  group(
    'clinic administration on the Firestore emulator',
    () {
      test(
        'branches, seats, doctors, staff and invitation acceptance',
        () async {
          final store = FirestoreDocumentStore(
            projectId: 'demo-eazyclinic',
            host: 'http://$host',
            client: _OwnerClient(http.Client()),
          );
          final suffix = DateTime.now().microsecondsSinceEpoch.toString();
          final tid = 'ten_emu$suffix';
          final now = DateTime.now().toUtc();
          // trusted records, as provisioning would have written them
          await store.commit([
            CreateOp('tenants/$tid', {
              'tenantId': tid,
              'clinicName': 'Emu',
              'status': 'active',
              'subscriptionId': 'sub_$suffix',
              'createdAt': now,
            }),
            CreateOp('platform_subscriptions/sub_$suffix', {
              'subscriptionId': 'sub_$suffix',
              'tenantId': tid,
              'status': 'active',
              'name': 'P',
              'planId': 'p',
              'limits': {
                'max_branches': 2,
                'max_doctors': 2,
                'max_staff': 2,
                'max_patients': null,
              },
              'features': {'multiple_branches': true},
              'startDate': now,
              'endDate': now.add(const Duration(days: 30)),
              'overrides': <String, Object?>{},
            }),
            CreateOp('tenants/$tid/members/owner$suffix', {
              'uid': 'owner$suffix',
              'role': 'clinic_owner',
              'status': 'active',
              'allBranches': true,
              'branchIds': <String>[],
              'createdAt': now,
            }),
          ]);
          final audit = AuditService(store);
          final entitlements = EntitlementService(store);
          final deps = ClinicDeps(
            store: store,
            audit: audit,
            seats: SeatService(store),
            entitlements: entitlements,
          );
          final branches = BranchService(deps);
          final doctors = DoctorService(deps, branches);
          final staff = StaffService(deps, branches);
          final invitations = InvitationService(deps, staff, doctors);

          Future<TenantContext> ctx() async => TenantContext(
            tenantId: tid,
            uid: 'owner$suffix',
            role: ClinicRole.clinicOwner,
            scope: const BranchScope(allBranches: true, branchIds: {}),
            entitlements: await entitlements.forTenant(tid),
          );

          // branches: limit 2, duplicate code, deactivate frees a seat
          var t = await ctx();
          final b1 = await branches.create(
            t,
            branchBody(name: 'One', code: 'ONE'),
          );
          final b2 = await branches.create(
            t,
            branchBody(name: 'Two', code: 'TWO'),
          );
          await expectLater(
            branches.create(t, branchBody(name: 'Three', code: 'THR')),
            throwsA(isA<Object>()),
          );
          await expectLater(
            branches.create(t, branchBody(name: 'Dup', code: 'one')),
            throwsA(isA<Object>()),
          );
          await branches.deactivate(t, b2['branchId']! as String);
          await branches.create(t, branchBody(name: 'Three', code: 'THR'));
          expect(await deps.seats.used(tid, SeatKind.branches), 2);

          // doctor + assignment uniqueness key
          final doc = await doctors.create(t, {
            'fullName': 'Dr Emu Test',
            'email': 'dr$suffix@example.test',
            'phone': '9876543211',
            'registrationNumber': 'EMU/$suffix',
            'branchIds': [b1['branchId']],
          });
          await expectLater(
            doctors.assign(t, doc['doctorId']! as String, {
              'branchId': b1['branchId'],
            }),
            throwsA(isA<Object>()),
          );
          expect(
            (await doctors.listAssignments(t, doc['doctorId']! as String)),
            hasLength(1),
          );

          // staff invitation + acceptance through the collection-group lookup
          final person = await staff.create(t, {
            'fullName': 'Nina Nurse',
            'email': 'nina$suffix@example.test',
            'role': 'nurse',
            'branchIds': [b1['branchId']],
          });
          final inv = await invitations.createForStaff(
            t,
            person['staffId']! as String,
          );
          final token = inv['inviteToken']! as String;
          final uid = 'nina$suffix';
          AuthContext caller({String? email}) => AuthContext(
            identity: VerifiedIdentity(
              uid: uid,
              email: email ?? 'nina$suffix@example.test',
              emailVerified: true,
              authTime: now,
              issuedAt: now,
              expiresAt: now.add(const Duration(hours: 1)),
              signInProvider: 'password',
            ),
            user: PlatformUser(
              uid: uid,
              displayName: 'Nina',
              email: 'nina$suffix@example.test',
              emailVerified: true,
              accountStatus: AccountStatus.active,
              createdAt: now,
              updatedAt: now,
            ),
            memberships: const [],
          );
          await expectLater(
            invitations.accept(caller(email: 'someone@else.test'), token),
            throwsA(isA<Object>()),
          );
          final accepted = await invitations.accept(caller(), token);
          expect(accepted['tenantId'], tid);
          await expectLater(
            invitations.accept(caller(), token),
            throwsA(isA<Object>()),
            reason: 'replay',
          );
          final member = (await store.get('tenants/$tid/members/$uid'))!;
          expect(member['role'], 'nurse');
          expect(member['allBranches'], false);
          expect(
            (await store.get(
              'tenants/$tid/staff/${person['staffId']}',
            ))!['status'],
            'active',
          );

          // staff seat accounting and release on deactivation (DeleteOp)
          t = await ctx();
          expect(await deps.seats.used(tid, SeatKind.staff), 1);
          await staff.setStatus(t, person['staffId']! as String, 'inactive');
          expect(await deps.seats.used(tid, SeatKind.staff), 0);
          expect(
            (await store.get('tenants/$tid/members/$uid'))!['status'],
            'deactivated',
          );
        },
      );
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : null,
  );
}
