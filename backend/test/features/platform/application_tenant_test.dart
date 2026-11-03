import 'package:backend/core/data/document_store.dart';
import 'package:backend/core/errors/api_exception.dart';
import 'package:backend/features/platform/applications/application_service.dart';
import 'package:backend/features/platform/audit/audit_service.dart';
import 'package:backend/features/platform/plans/plan_service.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../support/platform_fixtures.dart';

Matcher status(int code) => throwsA(
  isA<ApiException>().having((e) => e.code.httpStatus, 'status', code),
);

void main() {
  late PlatformServices s;
  setUp(() => s = PlatformServices());

  group('application validation', () {
    test('accepts a complete application', () {
      final input = ApplicationInput.parse(applicationBody(), partial: false);
      expect(input.clinic['email'], 'info@greenvalley.test');
      expect(input.address['postalCode'], '411001');
    });

    test('reports every invalid field', () {
      try {
        ApplicationInput.parse({
          'clinic': {
            'name': 'x',
            'type': 'astrology',
            'email': 'nope',
            'phone': '123',
          },
          'address': {
            'line1': '12 Main',
            'city': 'Pune',
            'state': 'MH',
            'country': 'India',
            'postalCode': '12',
          },
          'owner': {'fullName': 'A', 'email': 'a@b.co', 'phone': '9876543211'},
          'expectations': {'doctors': -1, 'staff': 1, 'monthlyPatients': 1},
        }, partial: false);
        fail('expected validation failure');
      } on ApiException catch (e) {
        final fields = e.issues.map((i) => i.field).toSet();
        expect(
          fields,
          containsAll([
            'clinic.name',
            'clinic.type',
            'clinic.email',
            'clinic.phone',
            'address.postalCode',
            'owner.fullName',
            'expectations.doctors',
          ]),
        );
      }
    });

    test('rejects status / applicant / tenant fields', () {
      for (final extra in [
        {'status': 'approved'},
        {'applicantUid': 'other'},
        {'tenantId': 't1'},
        {'applicationId': 'app_x'},
      ]) {
        expect(
          () => ApplicationInput.parse({
            ...applicationBody(),
            ...extra,
          }, partial: false),
          status(422),
        );
      }
    });

    test('missing sections are required on submit', () {
      expect(
        () => ApplicationInput.parse({
          'clinic': applicationBody()['clinic'],
        }, partial: false),
        status(422),
      );
    });
  });

  group('submission rules', () {
    test('creates a submitted application with history and audit', () async {
      final app = await s.submitApplication();
      expect(app['status'], 'submitted');
      expect(app['applicationId'], startsWith('app_'));
      final id = app['applicationId'] as String;
      expect(
        s.store.docs.keys.where(
          (k) => k.startsWith('clinic_applications/$id/history/'),
        ),
        hasLength(1),
      );
      expect(
        s.store.docs.values.any((d) => d['action'] == 'application.submitted'),
        isTrue,
      );
    });

    test('one open application per applicant', () async {
      await s.submitApplication();
      await expectLater(
        s.submitApplication(body: applicationBody(name: 'Other Clinic')),
        status(409),
      );
    });

    test(
      'duplicate clinic (same name+city+PIN) is refused for other applicants',
      () async {
        await s.submitApplication();
        await expectLater(
          s.submitApplication(uid: 'someone-else'),
          status(409),
        );
        // different city is fine
        await s.submitApplication(
          uid: 'someone-else',
          body: applicationBody(city: 'Mumbai', postalCode: '400001'),
        );
      },
    );

    test('unknown or inactive preferred plan → 422', () async {
      await expectLater(
        s.submitApplication(
          body: applicationBody(preferredPlanId: 'plan_missing'),
        ),
        status(422),
      );
    });

    test('rejection cool-off applies, withdrawn does not', () async {
      final app = await s.submitApplication();
      final id = app['applicationId'] as String;
      await s.applications.reject(id, 'Incomplete registration proof', admin);
      await expectLater(
        s.submitApplication(body: applicationBody(name: 'Second Try')),
        status(409),
      );
      s.clock.now = s.clock.now.add(const Duration(days: 8));
      final second = await s.submitApplication(
        body: applicationBody(name: 'Second Try'),
      );
      await s.applications.withdraw(
        second['applicationId']! as String,
        'applicant-1',
      );
      await s.submitApplication(body: applicationBody(name: 'Third Try'));
    });

    test(
      'applicants only see their own applications (404 otherwise)',
      () async {
        final app = await s.submitApplication();
        final id = app['applicationId'] as String;
        await expectLater(s.applications.getMine(id, 'intruder'), status(404));
        final mine = await s.applications.getMine(id, 'applicant-1');
        expect(mine.containsKey('dupKey'), isFalse);
        expect(mine.containsKey('reviewedBy'), isFalse);
      },
    );
  });

  group('review workflow', () {
    late String id;
    setUp(
      () async =>
          id = (await s.submitApplication())['applicationId']! as String,
    );

    test('request info → respond → back to submitted', () async {
      await s.applications.requestInformation(
        id,
        'Please upload registration proof',
        admin,
      );
      expect(
        (await s.applications.getMine(id, 'applicant-1'))['status'],
        'additional_information_required',
      );
      final after = await s.applications.respond(
        id: id,
        uid: 'applicant-1',
        message: 'Registration number corrected',
        updates: ApplicationInput.parse({
          'clinic': {'registrationNumber': 'MH/2021/9'},
        }, partial: true),
      );
      expect(after['status'], 'submitted');
      expect(((after['clinic']! as Map)['registrationNumber']), 'MH/2021/9');
      expect(
        ((after['clinic']! as Map)['name']),
        'Green Valley Clinic',
        reason: 'untouched fields kept',
      );
    });

    test('respond is only possible when information was requested', () async {
      await expectLater(
        s.applications.respond(
          id: id,
          uid: 'applicant-1',
          message: 'hi',
          updates: ApplicationInput.parse({}, partial: true),
        ),
        status(409),
      );
    });

    test('only the applicant can respond', () async {
      await s.applications.requestInformation(id, 'more', admin);
      await expectLater(
        s.applications.respond(
          id: id,
          uid: 'intruder',
          message: 'hi',
          updates: ApplicationInput.parse({}, partial: true),
        ),
        status(404),
      );
    });

    test(
      'reject keeps history and reason; final states cannot change',
      () async {
        await s.applications.reject(id, 'Unverifiable clinic', admin);
        final detail = await s.applications.detail(id);
        expect(detail['status'], 'rejected');
        expect(detail['decisionReason'], 'Unverifiable clinic');
        expect((detail['history']! as List), hasLength(2));
        await expectLater(s.applications.startReview(id, admin), status(409));
        await expectLater(
          s.tenants.approve(applicationId: id, actor: admin),
          status(409),
        );
      },
    );

    test('internal notes are hidden from the applicant', () async {
      await s.applications.addNote(id, 'Looks suspicious, call them', admin);
      expect((await s.applications.detail(id))['internalNotes'], hasLength(1));
      final mine = await s.applications.getMine(id, 'applicant-1');
      expect(mine.toString(), isNot(contains('suspicious')));
    });

    test('search by name prefix and by id, with status filter', () async {
      final req = _req();
      final byName = await s.applications.list(req, q: 'green');
      expect(byName.docs, hasLength(1));
      expect((await s.applications.list(req, q: 'zzz')).docs, isEmpty);
      expect((await s.applications.list(req, q: id)).docs, hasLength(1));
      expect(
        (await s.applications.list(
          req,
          status: ApplicationStatus.approved,
        )).docs,
        isEmpty,
      );
    });
  });

  group('approval and provisioning', () {
    late String id;
    late String planId;
    setUp(() async {
      planId = await s.activePlan();
      id = (await s.submitApplication())['applicationId']! as String;
    });

    test('approve creates one active tenant with owner membership', () async {
      final r = await s.tenants.approve(
        applicationId: id,
        actor: admin,
        initialPlanId: planId,
        startTrial: true,
      );
      expect(r.completed, isTrue);
      expect(r.tenantStatus, TenantStatus.active);
      final tenant = s.store.docs['tenants/${r.tenantId}']!;
      expect(tenant['ownerUid'], 'applicant-1');
      expect(tenant['slug'], 'green-valley-clinic');
      expect(tenant['applicationId'], id);
      expect(tenant['subscriptionId'], isNotNull);
      final member = s.store.docs['tenants/${r.tenantId}/members/applicant-1']!;
      expect(member['role'], 'clinic_owner');
      expect(s.store.docs['tenant_slugs/green-valley-clinic'], isNotNull);
      expect(s.store.docs['clinic_applications/$id']!['status'], 'approved');
      expect(
        s.store.docs['tenant_provisioning_jobs/${r.tenantId}']!['status'],
        'completed',
      );
      final sub =
          s.store.docs['platform_subscriptions/${tenant['subscriptionId']}']!;
      expect(sub['status'], 'trial');
    });

    test(
      'approval without a plan creates a tenant without a subscription',
      () async {
        final r = await s.tenants.approve(applicationId: id, actor: admin);
        expect(r.completed, isTrue);
        expect(
          s.store.docs['tenants/${r.tenantId}']!['subscriptionId'],
          isNull,
        );
      },
    );

    test(
      'repeated approval is idempotent: one tenant, one membership, one subscription',
      () async {
        final a = await s.tenants.approve(
          applicationId: id,
          actor: admin,
          initialPlanId: planId,
        );
        final b = await s.tenants.approve(
          applicationId: id,
          actor: admin,
          initialPlanId: planId,
        );
        expect(b.tenantId, a.tenantId);
        expect(
          s.store.docs.keys.where(
            (k) => RegExp(r'^tenants/[^/]+$').hasMatch(k),
          ),
          hasLength(1),
        );
        expect(
          s.store.docs.keys.where((k) => k.contains('/members/')),
          hasLength(1),
        );
        expect(
          s.store.docs.keys.where(
            (k) => RegExp(r'^platform_subscriptions/[^/]+$').hasMatch(k),
          ),
          hasLength(1),
        );
      },
    );

    test('concurrent approvals create exactly one tenant', () async {
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          s.tenants.approve(
            applicationId: id,
            actor: admin,
            initialPlanId: planId,
          ),
      ]);
      expect(results.map((r) => r.tenantId).toSet(), hasLength(1));
      expect(
        s.store.docs.keys.where((k) => RegExp(r'^tenants/[^/]+$').hasMatch(k)),
        hasLength(1),
      );
      expect(
        s.store.docs.keys.where(
          (k) => RegExp(r'^platform_subscriptions/[^/]+$').hasMatch(k),
        ),
        hasLength(1),
      );
    });

    test(
      'applicant cannot approve their own application, even as admin',
      () async {
        await expectLater(
          s.tenants.approve(
            applicationId: id,
            actor: const Actor('applicant-1', 'super_admin'),
          ),
          status(403),
        );
        expect(s.store.docs.keys.any((k) => k.startsWith('tenants/')), isFalse);
      },
    );

    test('approval needs a reviewable status', () async {
      await s.applications.requestInformation(id, 'more info', admin);
      await expectLater(
        s.tenants.approve(applicationId: id, actor: admin),
        status(409),
      );
    });

    test(
      'inactive initial plan blocks approval before anything is created',
      () async {
        final inactive =
            (await s.plans.create(
                  PlanInput.parse(planBody(name: 'Inactive'), partial: false),
                  admin,
                ))['planId']!
                as String;
        await expectLater(
          s.tenants.approve(
            applicationId: id,
            actor: admin,
            initialPlanId: inactive,
          ),
          status(409),
        );
        expect(s.store.docs['clinic_applications/$id']!['status'], 'submitted');
        expect(s.store.docs.keys.any((k) => k.startsWith('tenants/')), isFalse);
      },
    );

    test('slug collisions get a suffix', () async {
      await s.tenants.approve(applicationId: id, actor: admin);
      final other =
          (await s.submitApplication(
                uid: 'applicant-2',
                body: applicationBody(city: 'Nagpur', postalCode: '440001'),
              ))['applicationId']!
              as String;
      final r = await s.tenants.approve(applicationId: other, actor: admin);
      expect(
        s.store.docs['tenants/${r.tenantId}']!['slug'],
        isNot('green-valley-clinic'),
      );
      expect(
        s.store.docs['tenants/${r.tenantId}']!['slug'],
        startsWith('green-valley-clinic-'),
      );
    });

    test('reserved slugs are prefixed', () async {
      final a =
          (await s.submitApplication(
                uid: 'u9',
                body: applicationBody(
                  name: 'Admin',
                  city: 'Goa',
                  postalCode: '403001',
                ),
              ))['applicationId']!
              as String;
      final r = await s.tenants.approve(applicationId: a, actor: admin);
      expect(s.store.docs['tenants/${r.tenantId}']!['slug'], 'clinic-admin');
    });

    group('partial failure and recovery', () {
      test(
        'membership failure leaves the tenant provisioning, then retry completes it',
        () async {
          s.store.failWhen = (ops) =>
              ops.any((o) => o.path.contains('/members/'));
          final r = await s.tenants.approve(
            applicationId: id,
            actor: admin,
            initialPlanId: planId,
          );
          expect(r.completed, isFalse);
          expect(r.tenantStatus, TenantStatus.provisioning);
          final tid = r.tenantId;
          expect(s.store.docs['tenants/$tid']!['status'], 'provisioning');
          expect(
            s.store.docs['tenant_provisioning_jobs/$tid']!['status'],
            'failed',
          );
          expect(s.store.docs['tenant_provisioning_jobs/$tid']!['attempts'], 1);
          expect(
            s.store.docs.keys.any((k) => k.contains('/members/')),
            isFalse,
          );
          expect(
            s.store.docs.values.any(
              (d) => d['action'] == 'tenant.provisioning_failed',
            ),
            isTrue,
          );

          // A repeated approval request while failing does not duplicate anything.
          final again = await s.tenants.approve(
            applicationId: id,
            actor: admin,
            initialPlanId: planId,
          );
          expect(again.tenantId, tid);
          expect(
            s.store.docs.keys.where(
              (k) => RegExp(r'^tenants/[^/]+$').hasMatch(k),
            ),
            hasLength(1),
          );

          s.store.failWhen = null;
          final retried = await s.tenants.retryProvisioning(tid, admin);
          expect(retried.completed, isTrue);
          expect(s.store.docs['tenants/$tid']!['status'], 'active');
          expect(
            s.store.docs['tenant_provisioning_jobs/$tid']!['status'],
            'completed',
          );
          expect(
            s.store.docs.keys.where((k) => k.contains('/members/')),
            hasLength(1),
          );
        },
      );

      test('subscription failure never activates the tenant', () async {
        s.store.failWhen = (ops) => ops.any(
          (o) => o.path.startsWith('platform_subscriptions/') && o is CreateOp,
        );
        final r = await s.tenants.approve(
          applicationId: id,
          actor: admin,
          initialPlanId: planId,
        );
        expect(r.completed, isFalse);
        expect(
          s.store.docs['tenants/${r.tenantId}']!['status'],
          'provisioning',
        );
        s.store.failWhen = null;
        await s.tenants.retryProvisioning(r.tenantId, admin);
        expect(s.store.docs['tenants/${r.tenantId}']!['status'], 'active');
        expect(
          s.store.docs['tenants/${r.tenantId}']!['subscriptionId'],
          isNotNull,
        );
        expect(
          s.store.docs.keys.where(
            (k) => RegExp(r'^platform_subscriptions/[^/]+$').hasMatch(k),
          ),
          hasLength(1),
        );
      });

      test('retry is refused for non-provisioning tenants', () async {
        final r = await s.tenants.approve(applicationId: id, actor: admin);
        await expectLater(
          s.tenants.retryProvisioning(r.tenantId, admin),
          status(409),
        );
      });
    });
  });

  group('tenant lifecycle', () {
    late String tid;
    late String planId;
    setUp(() async {
      planId = await s.activePlan();
      final id = (await s.submitApplication())['applicationId']! as String;
      tid = (await s.tenants.approve(
        applicationId: id,
        actor: admin,
        initialPlanId: planId,
      )).tenantId;
    });

    test(
      'suspend requires active; keeps data; records reason and actor',
      () async {
        final t = await s.tenants.suspend(tid, 'Non-payment', admin);
        expect(t['status'], 'suspended');
        expect(t['statusReason'], 'Non-payment');
        expect(s.store.docs['tenants/$tid/members/applicant-1'], isNotNull);
        await expectLater(s.tenants.suspend(tid, 'again', admin), status(409));
      },
    );

    test(
      'reactivate needs a valid subscription and does not happen automatically',
      () async {
        await s.tenants.suspend(tid, 'Review', admin);
        final subId =
            s.store.docs['tenants/$tid']!['subscriptionId']! as String;
        await s.subscriptions.cancel(subId, admin, reason: 'ended');
        // subscription change alone does not touch the tenant
        expect(s.store.docs['tenants/$tid']!['status'], 'suspended');
        await expectLater(
          s.tenants.reactivate(tid, 'Resolved', admin),
          status(409),
        );
        await s.subscriptions.assign(
          tenantId: tid,
          planId: planId,
          trial: false,
          actor: admin,
        );
        final t = await s.tenants.reactivate(tid, 'Resolved', admin);
        expect(t['status'], 'active');
      },
    );

    test('reactivating an expired subscription tenant is refused', () async {
      await s.tenants.suspend(tid, 'Review', admin);
      s.clock.now = s.clock.now.add(const Duration(days: 90));
      await expectLater(
        s.tenants.reactivate(tid, 'Resolved', admin),
        status(409),
      );
    });

    test(
      'close cancels the live subscription and is final; data is preserved',
      () async {
        final subId =
            s.store.docs['tenants/$tid']!['subscriptionId']! as String;
        final t = await s.tenants.close(tid, 'Clinic shut down', admin);
        expect(t['status'], 'closed');
        expect(
          s.store.docs['platform_subscriptions/$subId']!['status'],
          'cancelled',
        );
        expect(
          s.store.docs['platform_subscriptions/$subId']!['cancellationReason'],
          'tenant_closed',
        );
        expect(s.store.docs['tenants/$tid/members/applicant-1'], isNotNull);
        await expectLater(s.tenants.reactivate(tid, 'x', admin), status(409));
        await expectLater(s.tenants.suspend(tid, 'x', admin), status(409));
      },
    );

    test('detail aggregates owner, application, subscription, audit', () async {
      final d = await s.tenants.detail(tid);
      expect((d['owner']! as Map)['fullName'], 'Dr Asha Rao');
      expect((d['subscription']! as Map)['effectiveStatus'], 'active');
      expect((d['auditHistory']! as List), isNotEmpty);
    });

    test('every lifecycle change is audited', () async {
      await s.tenants.suspend(tid, 'r1', admin);
      await s.tenants.reactivate(tid, 'r2', admin);
      final actions = s.store.docs.values.map((d) => d['action']).toSet();
      expect(
        actions,
        containsAll([
          'tenant.created',
          'tenant.activated',
          'tenant.suspended',
          'tenant.reactivated',
          'application.approved',
        ]),
      );
    });
  });
}

Request _req() => Request('GET', Uri.parse('http://x/list'));
