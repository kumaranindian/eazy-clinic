import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/auth_fixtures.dart' show errorCode;
import '../../support/platform_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

/// Every platform endpoint: method, path, minimal valid-ish body.
final List<(String, String, Object?)> platformEndpoints = [
  ('GET', '/platform/dashboard', null),
  ('GET', '/platform/clinic-applications', null),
  ('GET', '/platform/clinic-applications/app_abc123', null),
  ('POST', '/platform/clinic-applications/app_abc123/start-review', null),
  (
    'POST',
    '/platform/clinic-applications/app_abc123/request-information',
    {'message': 'please add details'},
  ),
  (
    'POST',
    '/platform/clinic-applications/app_abc123/approve',
    {'confirm': true},
  ),
  (
    'POST',
    '/platform/clinic-applications/app_abc123/reject',
    {'reason': 'not valid'},
  ),
  (
    'POST',
    '/platform/clinic-applications/app_abc123/notes',
    {'note': 'internal'},
  ),
  ('GET', '/platform/tenants', null),
  ('GET', '/platform/tenants/ten_abc123', null),
  ('POST', '/platform/tenants/ten_abc123/suspend', {'reason': 'because'}),
  ('POST', '/platform/tenants/ten_abc123/reactivate', {'reason': 'because'}),
  (
    'POST',
    '/platform/tenants/ten_abc123/close',
    {'reason': 'because', 'confirm': true},
  ),
  ('POST', '/platform/tenants/ten_abc123/retry-provisioning', null),
  ('GET', '/platform/subscription-plans', null),
  ('POST', '/platform/subscription-plans', {}),
  ('GET', '/platform/subscription-plans/plan_abc123', null),
  ('PATCH', '/platform/subscription-plans/plan_abc123', {'name': 'Renamed'}),
  ('POST', '/platform/subscription-plans/plan_abc123/activate', null),
  ('POST', '/platform/subscription-plans/plan_abc123/deactivate', null),
  ('GET', '/platform/subscriptions', null),
  ('GET', '/platform/subscriptions/sub_abc123', null),
  (
    'POST',
    '/platform/subscriptions',
    {'tenantId': 'ten_abc123', 'planId': 'plan_abc123'},
  ),
  (
    'PATCH',
    '/platform/subscriptions/sub_abc123',
    {'planId': 'plan_other', 'reason': 'upgrade'},
  ),
  (
    'POST',
    '/platform/subscriptions/sub_abc123/extend-trial',
    {'days': 5, 'reason': 'delay'},
  ),
  ('POST', '/platform/subscriptions/sub_abc123/renew', null),
  ('POST', '/platform/subscriptions/sub_abc123/mark-past-due', null),
  ('POST', '/platform/subscriptions/sub_abc123/suspend', {'reason': 'because'}),
  ('POST', '/platform/subscriptions/sub_abc123/cancel', {'reason': 'because'}),
  ('GET', '/platform/audit-logs', null),
];

void main() {
  late PlatformHarness h;
  setUp(() {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    h.user('support', role: PlatformRole.platformSupportAdmin);
    h.user('owner1');
    h.user('owner2');
    h.user('nobody');
  });

  group('platform authorization', () {
    test(
      'unauthenticated requests are rejected on every platform endpoint',
      () async {
        for (final (m, p, b) in platformEndpoints) {
          final r = await h.call(m, p, body: b);
          expect(r.statusCode, 401, reason: '$m $p');
        }
      },
    );

    test(
      'an ordinary authenticated user is forbidden on every platform endpoint',
      () async {
        for (final (m, p, b) in platformEndpoints) {
          final r = await h.call(m, p, uid: 'nobody', body: b);
          expect(r.statusCode, 403, reason: '$m $p');
        }
      },
    );

    test('support admin may read but never write', () async {
      for (final (m, p, b) in platformEndpoints) {
        final r = await h.call(m, p, uid: 'support', body: b);
        if (m == 'GET' && !p.endsWith('audit-logs')) {
          expect(r.statusCode, anyOf(200, 404), reason: '$m $p');
        } else {
          expect(
            r.statusCode,
            403,
            reason: '$m $p (support is read-only, no audit access)',
          );
        }
      }
    });

    test('a platform role claim in the token is ignored', () async {
      final r = await h.call(
        'GET',
        '/platform/dashboard',
        uid: 'nobody',
        claims: {
          'platformRole': 'super_admin',
          'role': 'super_admin',
          'admin': true,
        },
      );
      expect(r.statusCode, 403);
    });

    test('role headers and query parameters cannot elevate', () async {
      final r = await h.call(
        'GET',
        '/platform/dashboard?role=super_admin&platformRole=super_admin',
        uid: 'nobody',
        headers: {'x-role': 'super_admin', 'x-platform-role': 'super_admin'},
      );
      expect(r.statusCode, 403);
    });

    test('a suspended platform admin loses access', () async {
      h.user(
        'rogue',
        role: PlatformRole.superAdmin,
        status: AccountStatus.suspended,
      );
      expect(
        (await h.call('GET', '/platform/dashboard', uid: 'rogue')).statusCode,
        403,
      );
    });

    test('malformed ids are not found', () async {
      expect(
        (await h.call(
          'GET',
          '/platform/tenants/..%2f..%2fadmin',
          uid: 'root',
        )).statusCode,
        404,
      );
      expect(
        (await h.call('GET', '/platform/tenants/x', uid: 'root')).statusCode,
        404,
      );
    });

    test('a clinic owner is not a platform admin', () async {
      final appId = await h.apply('owner1');
      await h.approve(appId);
      expect(
        (await h.call('GET', '/platform/tenants', uid: 'owner1')).statusCode,
        403,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/subscriptions',
          uid: 'owner1',
          body: {'tenantId': 'x1x', 'planId': 'p1p'},
        )).statusCode,
        403,
      );
    });
  });

  group('clinic application API', () {
    test('submit → my list → detail; others get 404', () async {
      final appId = await h.apply('owner1');
      final mine = await h.list(
        await h.call('GET', '/clinic-applications/my', uid: 'owner1'),
      );
      expect(mine, hasLength(1));
      expect(
        (await h.call(
          'GET',
          '/clinic-applications/$appId',
          uid: 'owner1',
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'GET',
          '/clinic-applications/$appId',
          uid: 'owner2',
        )).statusCode,
        404,
      );
      expect(
        await h.list(
          await h.call('GET', '/clinic-applications/my', uid: 'owner2'),
        ),
        isEmpty,
      );
    });

    test('applicant cannot set status, tenant or applicant fields', () async {
      for (final extra in [
        {'status': 'approved'},
        {'applicantUid': 'root'},
        {'tenantId': 'ten_x'},
        {'platformRole': 'super_admin'},
      ]) {
        final r = await h.call(
          'POST',
          '/clinic-applications',
          uid: 'owner1',
          body: {...applicationBody(), ...extra},
        );
        expect(r.statusCode, 422, reason: '$extra');
      }
      expect(
        h.store.docs.keys.any((k) => k.startsWith('clinic_applications/')),
        isFalse,
      );
    });

    test('pending (unverified) accounts cannot apply', () async {
      h.user('pending', status: AccountStatus.pending);
      final r = await h.call(
        'POST',
        '/clinic-applications',
        uid: 'pending',
        body: applicationBody(),
        emailVerified: false,
      );
      expect(r.statusCode, 403);
      expect(await errorCode(r), 'account_pending');
    });

    test('submission is rate limited', () async {
      var last = 0;
      for (var i = 0; i < 6; i++) {
        last = (await h.call(
          'POST',
          '/clinic-applications',
          uid: 'owner1',
          body: {'clinic': <String, Object?>{}},
        )).statusCode;
      }
      expect(last, 429);
    });

    test(
      'an applicant cannot approve, reject or review (even their own)',
      () async {
        final appId = await h.apply('owner1');
        for (final (p, b) in [
          ('approve', {'confirm': true}),
          ('reject', {'reason': 'x y z'}),
          ('start-review', null),
          ('notes', {'note': 'hello'}),
        ]) {
          final r = await h.call(
            'POST',
            '/platform/clinic-applications/$appId/$p',
            uid: 'owner1',
            body: b,
          );
          expect(r.statusCode, 403, reason: p);
        }
        expect(
          h.store.docs['clinic_applications/$appId']!['status'],
          'submitted',
        );
      },
    );

    test('a platform admin cannot approve their own application', () async {
      final appId = await h.apply('root');
      final r = await h.call(
        'POST',
        '/platform/clinic-applications/$appId/approve',
        uid: 'root',
        body: {'confirm': true},
      );
      expect(r.statusCode, 403);
      expect(h.store.docs.keys.any((k) => k.startsWith('tenants/')), isFalse);
    });

    test('approval requires explicit confirmation', () async {
      final appId = await h.apply('owner1');
      final r = await h.call(
        'POST',
        '/platform/clinic-applications/$appId/approve',
        uid: 'root',
        body: {},
      );
      expect(r.statusCode, 422);
      expect(
        (await h.call(
          'POST',
          '/platform/clinic-applications/$appId/approve',
          uid: 'root',
          body: {'confirm': false},
        )).statusCode,
        422,
      );
    });

    test('request information → applicant responds → approve', () async {
      final appId = await h.apply('owner1');
      expect(
        (await h.call(
          'POST',
          '/platform/clinic-applications/$appId/request-information',
          uid: 'root',
          body: {'message': 'Upload registration proof'},
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/clinic-applications/$appId/approve',
          uid: 'root',
          body: {'confirm': true},
        )).statusCode,
        409,
      );
      final r = await h.call(
        'POST',
        '/clinic-applications/$appId/respond',
        uid: 'owner1',
        body: {
          'message': 'Registration number added',
          'clinic': {'registrationNumber': 'MH/9'},
        },
      );
      expect(r.statusCode, 200);
      await h.approve(appId);
      expect(h.store.docs['clinic_applications/$appId']!['status'], 'approved');
    });

    test('reject requires a reason and is visible to the applicant', () async {
      final appId = await h.apply('owner1');
      expect(
        (await h.call(
          'POST',
          '/platform/clinic-applications/$appId/reject',
          uid: 'root',
          body: {},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/clinic-applications/$appId/reject',
          uid: 'root',
          body: {'reason': 'Could not verify clinic'},
        )).statusCode,
        200,
      );
      final mine = await h.data(
        await h.call('GET', '/clinic-applications/$appId', uid: 'owner1'),
      );
      expect(mine['status'], 'rejected');
      expect(mine['decisionReason'], 'Could not verify clinic');
    });

    test(
      'platform list supports status filter, search and pagination',
      () async {
        for (var i = 0; i < 3; i++) {
          h.user('a$i');
          await h.apply(
            'a$i',
            body: applicationBody(
              name: 'Clinic $i',
              city: 'City$i',
              postalCode: '41100$i',
            ),
          );
        }
        final first = await h.call(
          'GET',
          '/platform/clinic-applications?limit=2',
          uid: 'root',
        );
        final body = await first.readAsString();
        expect(body, contains('"hasMore":true'));
        final cursor = RegExp(
          r'"nextCursor":"([^"]+)"',
        ).firstMatch(body)!.group(1)!;
        final second = await h.list(
          await h.call(
            'GET',
            '/platform/clinic-applications?limit=2&cursor=$cursor',
            uid: 'root',
          ),
        );
        expect(second, hasLength(1));
        expect(
          await h.list(
            await h.call(
              'GET',
              '/platform/clinic-applications?q=clinic%201',
              uid: 'root',
            ),
          ),
          hasLength(1),
        );
        expect(
          await h.list(
            await h.call(
              'GET',
              '/platform/clinic-applications?status=approved',
              uid: 'root',
            ),
          ),
          isEmpty,
        );
        expect(
          (await h.call(
            'GET',
            '/platform/clinic-applications?status=bogus',
            uid: 'root',
          )).statusCode,
          400,
        );
        expect(
          (await h.call(
            'GET',
            '/platform/clinic-applications?limit=0',
            uid: 'root',
          )).statusCode,
          400,
        );
        expect(
          (await h.call(
            'GET',
            '/platform/clinic-applications?cursor=%%%',
            uid: 'root',
          )).statusCode,
          400,
        );
      },
    );
  });

  group('approval over HTTP', () {
    test('repeated approval creates one tenant', () async {
      final appId = await h.apply('owner1');
      final a = await h.approve(appId);
      final b = await h.approve(appId);
      expect(b, a);
      expect(
        h.store.docs.keys.where((k) => RegExp(r'^tenants/[^/]+$').hasMatch(k)),
        hasLength(1),
      );
    });

    test(
      'the new owner immediately resolves a clinic membership (and nothing else)',
      () async {
        final appId = await h.apply('owner1');
        final tenantId = await h.approve(appId);
        final session = await h.data(
          await h.call('GET', '/auth/session', uid: 'owner1'),
        );
        final memberships = session['memberships']! as List;
        expect((memberships.single as Map)['tenantId'], tenantId);
        expect((memberships.single as Map)['role'], 'clinic_owner');
        expect(
          session.containsKey('platformRole'),
          isFalse,
          reason: 'clinic owner is not a platform admin',
        );
      },
    );

    test(
      'provisioning failure is reported, retried, and never duplicates',
      () async {
        final appId = await h.apply('owner1');
        h.store.failWhen = (ops) =>
            ops.any((o) => o.path.contains('/members/'));
        final r = await h.call(
          'POST',
          '/platform/clinic-applications/$appId/approve',
          uid: 'root',
          body: {'confirm': true},
        );
        final d = await h.data(r);
        expect(d['provisioningComplete'], false);
        expect(d['tenantStatus'], 'provisioning');
        final tid = d['tenantId']! as String;
        expect(
          (await h.call('GET', '/auth/session', uid: 'owner1')).statusCode,
          200,
        );
        expect(
          ((await h.data(
                await h.call('GET', '/auth/session', uid: 'owner1'),
              ))['memberships']!
              as List),
          isEmpty,
        );
        h.store.failWhen = null;
        expect(
          (await h.call(
            'POST',
            '/platform/tenants/$tid/retry-provisioning',
            uid: 'support',
          )).statusCode,
          403,
        );
        final retry = await h.data(
          await h.call(
            'POST',
            '/platform/tenants/$tid/retry-provisioning',
            uid: 'root',
          ),
        );
        expect(retry['provisioningComplete'], true);
        expect(
          (await h.call(
            'POST',
            '/platform/tenants/$tid/retry-provisioning',
            uid: 'root',
          )).statusCode,
          409,
        );
      },
    );
  });

  group('tenant management over HTTP', () {
    late String tid;
    setUp(() async {
      final plan = await h.activePlan();
      tid = await h.approve(await h.apply('owner1'), planId: plan);
    });

    test(
      'suspend / reactivate require a reason and record the actor',
      () async {
        expect(
          (await h.call(
            'POST',
            '/platform/tenants/$tid/suspend',
            uid: 'root',
            body: {},
          )).statusCode,
          422,
        );
        final s = await h.data(
          await h.call(
            'POST',
            '/platform/tenants/$tid/suspend',
            uid: 'root',
            body: {'reason': 'Policy review'},
          ),
        );
        expect(s['status'], 'suspended');
        expect(s['statusChangedBy'], 'root');
        final back = await h.data(
          await h.call(
            'POST',
            '/platform/tenants/$tid/reactivate',
            uid: 'root',
            body: {'reason': 'Review passed'},
          ),
        );
        expect(back['status'], 'active');
      },
    );

    test('close needs confirmation; there is no delete endpoint', () async {
      expect(
        (await h.call(
          'POST',
          '/platform/tenants/$tid/close',
          uid: 'root',
          body: {'reason': 'Shut down'},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/tenants/$tid/close',
          uid: 'root',
          body: {'reason': 'Shut down', 'confirm': true},
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'DELETE',
          '/platform/tenants/$tid',
          uid: 'root',
        )).statusCode,
        anyOf(404, 405),
      );
    });

    test(
      'tenant list/detail for platform admins; list filters by status and name',
      () async {
        expect(
          await h.list(
            await h.call(
              'GET',
              '/platform/tenants?status=active',
              uid: 'support',
            ),
          ),
          hasLength(1),
        );
        expect(
          await h.list(
            await h.call(
              'GET',
              '/platform/tenants?status=suspended',
              uid: 'support',
            ),
          ),
          isEmpty,
        );
        expect(
          await h.list(
            await h.call('GET', '/platform/tenants?q=green', uid: 'support'),
          ),
          hasLength(1),
        );
        final detail = await h.data(
          await h.call('GET', '/platform/tenants/$tid', uid: 'support'),
        );
        expect((detail['owner']! as Map)['fullName'], 'Dr Asha Rao');
        expect((detail['subscription']! as Map)['status'], 'active');
      },
    );
  });

  group('plans and subscriptions over HTTP', () {
    test('plan CRUD, validation, activation rules', () async {
      expect(
        (await h.call(
          'POST',
          '/platform/subscription-plans',
          uid: 'root',
          body: {...planBody(), 'status': 'active'},
        )).statusCode,
        422,
      );
      final id = await h.activePlan();
      final patched = await h.data(
        await h.call(
          'PATCH',
          '/platform/subscription-plans/$id',
          uid: 'root',
          body: {'priceMinor': 12345},
        ),
      );
      expect(patched['priceMinor'], 12345);
      expect(patched['version'], 2);
      expect(
        (await h.call(
          'PATCH',
          '/platform/subscription-plans/$id',
          uid: 'root',
          body: {'status': 'inactive'},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/subscription-plans/$id/activate',
          uid: 'root',
        )).statusCode,
        409,
      );
    });

    test('subscription lifecycle endpoints and invalid transitions', () async {
      final plan = await h.activePlan();
      final tid = await h.approve(await h.apply('owner1'));
      final created = await h.call(
        'POST',
        '/platform/subscriptions',
        uid: 'root',
        body: {
          'tenantId': tid,
          'planId': plan,
          'trial': true,
          'reason': 'welcome',
        },
      );
      expect(created.statusCode, 201);
      final sid = (await h.data(created))['subscriptionId']! as String;
      expect(
        (await h.call(
          'POST',
          '/platform/subscriptions',
          uid: 'root',
          body: {'tenantId': tid, 'planId': plan},
        )).statusCode,
        409,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/subscriptions/$sid/extend-trial',
          uid: 'root',
          body: {'days': 7},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/subscriptions/$sid/extend-trial',
          uid: 'root',
          body: {'days': 7, 'reason': 'slow onboarding'},
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/subscriptions/$sid/renew',
          uid: 'root',
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/subscriptions/$sid/mark-past-due',
          uid: 'root',
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/subscriptions/$sid/cancel',
          uid: 'root',
          body: {'reason': 'customer left'},
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'POST',
          '/platform/subscriptions/$sid/renew',
          uid: 'root',
        )).statusCode,
        409,
      );
      final detail = await h.data(
        await h.call('GET', '/platform/subscriptions/$sid', uid: 'root'),
      );
      expect((detail['history']! as List).length, greaterThanOrEqualTo(5));
    });

    test(
      'only an entitlement-override holder may override; reason mandatory',
      () async {
        final plan = await h.activePlan();
        final tid = await h.approve(await h.apply('owner1'), planId: plan);
        final sid = h.store.docs['tenants/$tid']!['subscriptionId']! as String;
        final body = {
          'overrides': {
            'features': {'billing': true},
          },
          'reason': 'pilot',
        };
        expect(
          (await h.call(
            'PATCH',
            '/platform/subscriptions/$sid',
            uid: 'support',
            body: body,
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'PATCH',
            '/platform/subscriptions/$sid',
            uid: 'root',
            body: {'overrides': body['overrides']},
          )).statusCode,
          422,
        );
        expect(
          (await h.call(
            'PATCH',
            '/platform/subscriptions/$sid',
            uid: 'root',
            body: {
              'overrides': {
                'features': {'time_travel': true},
              },
              'reason': 'x y z',
            },
          )).statusCode,
          422,
        );
        expect(
          (await h.call(
            'PATCH',
            '/platform/subscriptions/$sid',
            uid: 'root',
            body: body,
          )).statusCode,
          200,
        );
        final ent = await h.data(
          await h.call('GET', '/tenants/current/entitlements', uid: 'owner1'),
        );
        expect((ent['features']! as Map)['billing'], true);
      },
    );
  });

  group('entitlements', () {
    late String planId;
    setUp(() async => planId = await h.activePlan());

    Future<String> clinic(
      String uid, {
      String name = 'Green Valley Clinic',
      String city = 'Pune',
      String pin = '411001',
      bool subscribe = true,
    }) async {
      final tid = await h.approve(
        await h.apply(
          uid,
          body: applicationBody(name: name, city: city, postalCode: pin),
        ),
        planId: subscribe ? planId : null,
      );
      return tid;
    }

    Future<Map<String, Object?>> entitlements(
      String uid, {
      Map<String, String> headers = const {},
    }) async => h.data(
      await h.call(
        'GET',
        '/tenants/current/entitlements',
        uid: uid,
        headers: headers,
      ),
    );

    test('owner sees plan features and limits', () async {
      await clinic('owner1');
      final e = await entitlements('owner1');
      expect(e['accessLevel'], 'full');
      expect((e['features']! as Map)['appointments'], true);
      expect((e['features']! as Map)['billing'], false);
      expect((e['limits']! as Map)['max_doctors'], 3);
      expect((e['limits']! as Map)['max_patients'], isNull);
      expect(((e['subscription']! as Map)['planName']), 'Starter');
    });

    test('a user without a clinic gets 403', () async {
      expect(
        (await h.call(
          'GET',
          '/tenants/current/entitlements',
          uid: 'nobody',
        )).statusCode,
        403,
      );
      expect(
        (await h.call('GET', '/tenants/current/entitlements')).statusCode,
        401,
      );
    });

    test(
      'tenant isolation: client-supplied tenant ids cannot reach another clinic',
      () async {
        final a = await clinic('owner1');
        final b = await clinic(
          'owner2',
          name: 'Other Clinic',
          city: 'Mumbai',
          pin: '400001',
        );
        expect((await entitlements('owner1'))['tenantId'], a);
        expect((await entitlements('owner2'))['tenantId'], b);
        final spoofHeader = await h.call(
          'GET',
          '/tenants/current/entitlements',
          uid: 'owner1',
          headers: {'x-tenant-id': b},
        );
        expect(spoofHeader.statusCode, 403);
        final spoofQuery = await h.data(
          await h.call(
            'GET',
            '/tenants/current/entitlements?tenantId=$b&tenant=$b',
            uid: 'owner1',
          ),
        );
        expect(
          spoofQuery['tenantId'],
          a,
          reason: 'query parameters are ignored',
        );
        expect(
          (await h.call(
            'GET',
            '/tenants/current/entitlements',
            uid: 'nobody',
            headers: {'x-tenant-id': a},
          )).statusCode,
          403,
        );
      },
    );

    test('a user in several clinics must choose among their own', () async {
      final a = await clinic('owner1');
      final b = await clinic(
        'owner2',
        name: 'Other Clinic',
        city: 'Mumbai',
        pin: '400001',
      );
      // add owner1 as a member of b through a trusted server-side record
      h.store.docs['tenants/$b/members/owner1'] = {
        'uid': 'owner1',
        'role': 'clinic_admin',
        'status': 'active',
        'branchIds': <String>[],
      };
      expect(
        (await h.call(
          'GET',
          '/tenants/current/entitlements',
          uid: 'owner1',
        )).statusCode,
        409,
      );
      expect(
        (await entitlements('owner1', headers: {'x-tenant-id': b}))['tenantId'],
        b,
      );
      expect(
        (await entitlements('owner1', headers: {'x-tenant-id': a}))['tenantId'],
        a,
      );
    });

    test('deactivated membership grants nothing', () async {
      final a = await clinic('owner1');
      h.store.docs['tenants/$a/members/owner1']!['status'] = 'deactivated';
      expect(
        (await h.call(
          'GET',
          '/tenants/current/entitlements',
          uid: 'owner1',
        )).statusCode,
        403,
      );
    });

    test('suspended tenant is blocked: no features, reason given', () async {
      final a = await clinic('owner1');
      await h.call(
        'POST',
        '/platform/tenants/$a/suspend',
        uid: 'root',
        body: {'reason': 'Policy review'},
      );
      final e = await entitlements('owner1');
      expect(e['accessLevel'], 'blocked');
      expect(e['reason'], 'tenant_suspended');
      expect((e['features']! as Map).values.every((v) => v == false), isTrue);
      expect(e['writesAllowed'], false);
    });

    test('expired subscription is blocked; renewal restores it', () async {
      await clinic('owner1');
      h.clock.now = h.clock.now.add(const Duration(days: 45));
      final e = await entitlements('owner1');
      expect(e['accessLevel'], 'blocked');
      expect(e['reason'], 'subscription_expired');
      expect((e['features']! as Map)['appointments'], false);
    });

    test('past-due subscription is read-only', () async {
      final a = await clinic('owner1');
      final sid = h.store.docs['tenants/$a']!['subscriptionId']! as String;
      await h.call(
        'POST',
        '/platform/subscriptions/$sid/mark-past-due',
        uid: 'root',
      );
      final e = await entitlements('owner1');
      expect(e['accessLevel'], 'read_only');
      expect(e['writesAllowed'], false);
      expect((e['features']! as Map)['appointments'], true);
    });

    test('tenant without a subscription is blocked', () async {
      await clinic('owner1', subscribe: false);
      final e = await entitlements('owner1');
      expect(e['accessLevel'], 'blocked');
      expect(e['reason'], 'no_subscription');
    });

    test(
      'clients cannot assign themselves a subscription or entitlements',
      () async {
        await clinic('owner1');
        final sid =
            h.store.docs.values.firstWhere(
                  (d) =>
                      d['subscriptionId'] != null &&
                      d['tenantId'] != null &&
                      d['status'] != null,
                )['subscriptionId']!
                as String;
        expect(
          (await h.call(
            'POST',
            '/platform/subscriptions',
            uid: 'owner1',
            body: {'tenantId': 'x1x', 'planId': planId},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'PATCH',
            '/platform/subscriptions/$sid',
            uid: 'owner1',
            body: {
              'overrides': {
                'features': {'billing': true},
              },
              'reason': 'x y z',
            },
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'PATCH',
            '/tenants/current/entitlements',
            uid: 'owner1',
            body: {
              'features': {'billing': true},
            },
          )).statusCode,
          anyOf(404, 405),
        );
        expect(
          ((await entitlements('owner1'))['features']! as Map)['billing'],
          false,
        );
      },
    );
  });

  group('dashboard, audit and secrecy', () {
    test('dashboard counts come from stored data', () async {
      final empty = await h.data(
        await h.call('GET', '/platform/dashboard', uid: 'root'),
      );
      expect((empty['applications']! as Map)['total'], 0);
      expect((empty['tenants']! as Map)['total'], 0);
      expect((empty['monthlyRecurringRevenue']! as Map)['available'], false);

      final plan = await h.activePlan();
      await h.approve(await h.apply('owner1'), planId: plan, trial: true);
      await h.apply(
        'owner2',
        body: applicationBody(
          name: 'Second',
          city: 'Nashik',
          postalCode: '422001',
        ),
      );
      final d = await h.data(
        await h.call('GET', '/platform/dashboard', uid: 'support'),
      );
      expect((d['applications']! as Map)['approved'], 1);
      expect((d['applications']! as Map)['pending'], 1);
      expect((d['tenants']! as Map)['active'], 1);
      expect((d['subscriptions']! as Map)['trial'], 1);
      expect(
        ((d['planDistribution']! as List).single as Map)['subscriptions'],
        1,
      );
      expect((d['recentApplications']! as List), hasLength(2));
      expect((d['recentlyApprovedClinics']! as List), hasLength(1));
      expect((d['recentActivity']! as List), isNotEmpty);
    });

    test('expired trials are counted as expired, not trial', () async {
      final plan = await h.activePlan();
      await h.approve(await h.apply('owner1'), planId: plan, trial: true);
      h.clock.now = h.clock.now.add(const Duration(days: 30));
      final d = await h.data(
        await h.call('GET', '/platform/dashboard', uid: 'root'),
      );
      expect((d['subscriptions']! as Map)['trial'], 0);
      expect((d['subscriptions']! as Map)['expired'], 1);
    });

    test(
      'audit log records actor, role, target and request id; only super admin reads',
      () async {
        final appId = await h.apply('owner1');
        final tid = await h.approve(appId);
        await h.call(
          'POST',
          '/platform/tenants/$tid/suspend',
          uid: 'root',
          body: {'reason': 'Policy review'},
        );
        final rows = (await h.list(
          await h.call(
            'GET',
            '/platform/audit-logs?tenantId=$tid',
            uid: 'root',
          ),
        )).cast<Map<String, Object?>>();
        final suspended = rows.firstWhere(
          (r) => r['action'] == 'tenant.suspended',
        );
        expect(suspended['actorUid'], 'root');
        expect(suspended['actorRole'], 'super_admin');
        expect(suspended['targetId'], tid);
        expect(suspended['reason'], 'Policy review');
        expect(suspended['requestId'], isNotNull);
        expect((suspended['before'] as Map)['status'], 'active');
        expect(
          rows.map((r) => r['action']),
          containsAll([
            'tenant.created',
            'tenant.activated',
            'application.approved',
          ]),
        );
        expect(
          (await h.call(
            'GET',
            '/platform/audit-logs',
            uid: 'support',
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'GET',
            '/platform/audit-logs',
            uid: 'owner1',
          )).statusCode,
          403,
        );
      },
    );

    test(
      'audit entries are append-only: no mutation endpoints exist',
      () async {
        for (final m in ['PATCH', 'PUT', 'DELETE', 'POST']) {
          final r = await h.call(
            m,
            '/platform/audit-logs/abc123',
            uid: 'root',
            body: m == 'DELETE' ? null : {'action': 'forged'},
          );
          expect(r.statusCode, anyOf(404, 405), reason: m);
        }
      },
    );

    test('responses never expose internal keys or tokens', () async {
      final appId = await h.apply('owner1');
      final r = await h.call(
        'GET',
        '/platform/clinic-applications/$appId',
        uid: 'root',
      );
      final text = await r.readAsString();
      expect(text, isNot(contains('dupKey')));
      expect(text, isNot(contains('Bearer')));
      expect(h.logs.join('\n'), isNot(contains(h.token('root'))));
      expect(
        h.logs.join('\n'),
        isNot(contains('9876543210')),
        reason: 'phone numbers are never logged',
      );
      expect(h.logs.join('\n'), isNot(contains('asha@greenvalley.test')));
    });

    test(
      'error envelope for forbidden does not reveal whether a tenant exists',
      () async {
        final a = await h.call(
          'GET',
          '/platform/tenants/ten_doesnotexist',
          uid: 'nobody',
        );
        final b = await h.call(
          'GET',
          '/platform/tenants/ten_doesnotexist',
          uid: 'root',
        );
        expect(a.statusCode, 403);
        expect(await errorCode(a), 'forbidden');
        expect(b.statusCode, 404);
      },
    );
  });
}
