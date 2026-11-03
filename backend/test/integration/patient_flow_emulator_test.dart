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
import 'package:backend/features/patients/patient_module.dart';
import 'package:backend/features/platform/audit/audit_service.dart';
import 'package:backend/features/platform/entitlements/entitlement_service.dart';
import 'package:common_models/common_models.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/patient_fixtures.dart' show consentBody, patientBody;
import '../support/platform_http_fixtures.dart'
    show MemoryObjectStorage, branchBody;

class _Client extends http.BaseClient {
  _Client(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

/// Patient foundation on the real Firestore REST store: the MRN counter
/// transaction, uniqueness keys, seat limit, range + equality queries used by
/// the directory, consent gating, the collection-group link-code lookup and
/// tenant isolation. Sequential (the emulator serializes transactions).
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  group(
    'patient management on the Firestore emulator',
    () {
      test('register, search, consent, link and isolate', () async {
        final store = FirestoreDocumentStore(
          projectId: 'demo-eazyclinic',
          host: 'http://$host',
          client: _Client(http.Client()),
        );
        final suffix = DateTime.now().microsecondsSinceEpoch.toString();
        final now = DateTime.now().toUtc();
        Future<String> tenant(String tag, {int? maxPatients}) async {
          final tid = 'ten_$tag$suffix';
          await store.commit([
            CreateOp('tenants/$tid', {
              'tenantId': tid,
              'clinicName': 'Emu $tag',
              'status': 'active',
              'subscriptionId': 'sub_$tag$suffix',
              'createdAt': now,
            }),
            CreateOp('platform_subscriptions/sub_$tag$suffix', {
              'subscriptionId': 'sub_$tag$suffix',
              'tenantId': tid,
              'status': 'active',
              'name': 'P',
              'planId': 'p',
              'limits': {
                'max_branches': 2,
                'max_doctors': 2,
                'max_staff': 2,
                'max_patients': maxPatients,
              },
              'features': {'multiple_branches': true},
              'startDate': now,
              'endDate': now.add(const Duration(days: 30)),
              'overrides': <String, Object?>{},
            }),
          ]);
          return tid;
        }

        final deps = ClinicDeps(
          store: store,
          audit: AuditService(store),
          seats: SeatService(store),
          entitlements: EntitlementService(store),
        );
        final module = PatientModule(deps, MemoryObjectStorage());
        final branches = BranchService(deps);
        final tidA = await tenant('a', maxPatients: 2);
        final tidB = await tenant('b');

        Future<TenantContext> ctx(
          String tid,
          ClinicRole role, {
          String uid = 'staff',
        }) async => TenantContext(
          tenantId: tid,
          uid: '$uid$suffix',
          role: role,
          scope: const BranchScope(allBranches: true, branchIds: {}),
          entitlements: await deps.entitlements.forTenant(tid),
        );

        var owner = await ctx(tidA, ClinicRole.clinicOwner, uid: 'owner');
        final br = (await branches.create(
          owner,
          branchBody(code: 'EMU'),
        ))['branchId']!;
        final ownerB = await ctx(tidB, ClinicRole.clinicOwner, uid: 'ownerB');
        await branches.create(ownerB, branchBody(code: 'EMUB'));

        // registration: MRN counter, seat limit, uniqueness
        final p1 = await module.patients.create(
          owner,
          patientBody(br as String, email: 'asha@example.test'),
        );
        final p2 = await module.patients.create(
          owner,
          patientBody(
            br,
            name: 'Ravi Kulkarni',
            dob: '1985-01-02',
            phone: '9876500002',
          ),
        );
        expect(p1['mrn'], 'MRN-000001');
        expect(p2['mrn'], 'MRN-000002');
        await expectLater(
          module.patients.create(
            owner,
            patientBody(
              br,
              name: 'Third Person',
              dob: '1970-01-01',
              phone: '9876500003',
            ),
          ),
          throwsA(isA<Object>()),
          reason: 'max_patients = 2',
        );
        final mrnKeys = await store.query(
          DocQuery('tenants/$tidA/patient_mrns'),
        );
        expect(mrnKeys, hasLength(2));

        // duplicate detection uses equality queries on stored keys
        final dup = await module.patients.duplicateCheck(owner, {
          'fullName': 'Asha Patil',
          'dateOfBirth': '1990-05-14',
        });
        expect((dup['matches']! as List).single['level'], 'high');

        // directory queries: name range + order, identifiers, status
        Request req(String q) =>
            Request('GET', Uri.parse('http://x/api/v1/patients?$q'));
        Future<List<String>> names(String q, {String status = ''}) async {
          final page = await module.patients.list(
            owner,
            req(q),
            q: Uri.splitQueryString(q)['q'],
            status: status.isEmpty ? null : status,
          );
          return [for (final d in page.docs) '${d.data['fullName']}'];
        }

        expect(await names('q=as'), ['Asha Patil']);
        expect(await names('q=ra'), ['Ravi Kulkarni']);
        expect(await names('q=MRN-000002'), ['Ravi Kulkarni']);
        expect(await names('q=9876500001'), ['Asha Patil']);
        expect(await names('q=asha@example.test'), ['Asha Patil']);
        expect(await names('q=zz'), isEmpty);

        // consent gates new clinical data; revocation is enforced
        final doctor = await ctx(tidA, ClinicRole.doctor, uid: 'doc');
        final id1 = p1['patientId']! as String;
        await module.records.create(doctor, module.specs.allergy, id1, {
          'allergen': 'Penicillin',
          'category': 'drug',
        });
        final consent = (await store.query(
          DocQuery(
            'tenants/$tidA/patient_consents',
            filters: [QueryFilter('patientId', FilterOp.eq, id1)],
          ),
        )).single;
        await module.consents.revoke(owner, id1, consent.id, {
          'reason': 'Patient request',
        });
        await expectLater(
          module.records.create(doctor, module.specs.allergy, id1, {
            'allergen': 'Dust',
            'category': 'environmental',
          }),
          throwsA(isA<Object>()),
          reason: 'revoked consent',
        );

        // account linking through the collection-group code lookup
        AuthContext caller(String uid, {bool verified = true}) => AuthContext(
          identity: VerifiedIdentity(
            uid: uid,
            email: '$uid@example.test',
            emailVerified: verified,
            authTime: now,
            issuedAt: now,
            expiresAt: now.add(const Duration(hours: 1)),
            signInProvider: 'password',
          ),
          user: PlatformUser(
            uid: uid,
            displayName: 'Asha',
            email: '$uid@example.test',
            emailVerified: verified,
            accountStatus: AccountStatus.active,
            createdAt: now,
            updatedAt: now,
          ),
          memberships: const [],
        );
        final asha = caller('asha$suffix');
        final account = await module.accounts.create(asha, {});
        final code = (await module.identity.createLinkCode(owner, id1, {
          'verificationMethod': 'government_id_sighted',
          'identityConfirmed': true,
        }))['code']!;
        await expectLater(
          module.identity.claim(caller('mallory$suffix'), {'code': code}),
          throwsA(isA<Object>()),
          reason: 'no patient account',
        );
        final link = await module.identity.claim(asha, {'code': code});
        expect(link['tenantId'], tidA);
        expect(
          (await store.get('tenants/$tidA/patients/$id1'))!['patientAccountId'],
          account['accountId'],
        );
        await expectLater(
          module.identity.claim(asha, {'code': code}),
          throwsA(isA<Object>()),
          reason: 'single use',
        );
        expect(await module.accounts.clinicLinks(asha), hasLength(1));

        // another clinic sees none of it
        await expectLater(
          module.patients.detail(ownerB, id1),
          throwsA(isA<Object>()),
        );
        expect((await module.patients.list(ownerB, req(''))).docs, isEmpty);
        await expectLater(
          module.consents.list(ownerB, id1, req('')),
          throwsA(isA<Object>()),
        );

        // unlink, then the audit trail lists everything newest first
        await module.identity.unlinkByClinic(owner, id1, {
          'reason': 'Patient left the clinic',
        });
        owner = await ctx(tidA, ClinicRole.clinicOwner, uid: 'owner');
        final audit = await module.auditLogs(owner, id1, req(''));
        final actions = [for (final d in audit.docs) d.data['action']];
        expect(
          actions,
          containsAll([
            'patient.created',
            'allergy.created',
            'consent.revoked',
            'patient.link_code_created',
            'patient.account_linked',
            'patient.account_unlinked',
          ]),
        );
        expect(consentBody(), isNotEmpty);
      });
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : null,
  );
}
