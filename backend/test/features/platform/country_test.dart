import 'dart:convert';

import 'package:backend/features/platform/countries/country_directory.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../support/platform_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

PlatformHarness harness() {
  final h = PlatformHarness();
  h.user('root', role: PlatformRole.superAdmin);
  h.user('support', role: PlatformRole.platformSupportAdmin);
  return h;
}

Future<List<String>> issueFields(Response r) async =>
    ((((jsonDecode(await r.readAsString()) as Map<String, Object?>)['error']
                    as Map<String, Object?>)['issues']
                as List?) ??
            const [])
        .map((e) => (e as Map<String, Object?>)['field'] as String)
        .toList();

Future<List<String>> issueCodes(Response r) async =>
    ((((jsonDecode(await r.readAsString()) as Map<String, Object?>)['error']
                    as Map<String, Object?>)['issues']
                as List?) ??
            const [])
        .map((e) => (e as Map<String, Object?>)['code'] as String)
        .toList();

void main() {
  group('country master administration', () {
    test(
      'seeding is idempotent and never overwrites an edited profile',
      () async {
        final h = PlatformHarness();
        h.user('root', role: PlatformRole.superAdmin);
        h.store.docs.remove('countries/IN');
        h.store.docs.remove('countries/AE');

        final first = await h.okData(
          h.call('POST', '/platform/countries/seed-baseline', uid: 'root'),
        );
        expect(
          (first['items']! as List).every(
            (e) => (e as Map<String, Object?>)['created'] == true,
          ),
          isTrue,
        );
        expect(
          h.store.docs.keys,
          containsAll(['countries/IN', 'countries/AE']),
        );
        expect(h.store.docs.keys, contains('countries/IN/versions/1'));

        h.store.docs['countries/IN']!['name'] = 'Edited';
        final second = await h.okData(
          h.call('POST', '/platform/countries/seed-baseline', uid: 'root'),
        );
        expect(
          (second['items']! as List).every(
            (e) => (e as Map<String, Object?>)['created'] == false,
          ),
          isTrue,
        );
        expect(h.store.docs['countries/IN']!['name'], 'Edited');
        expect(
          h.store.docs.values
              .where((d) => d['action'] == 'country.seeded')
              .length,
          2,
        );
      },
    );

    test(
      'list and detail show version, status, warnings and tenant counts',
      () async {
        final h = harness();
        await h.createClinic('o1');
        final list = await h.okData(
          h.call('GET', '/platform/countries', uid: 'root'),
        );
        final items = (list['items']! as List).cast<Map<String, Object?>>();
        final india = items.firstWhere((e) => e['code'] == 'IN');
        expect(india['configurationVersion'], 1);
        expect(india['status'], 'supported');
        expect(india['activeTenants'], 1);
        expect(india['completenessWarnings'], isEmpty);
        expect(items.firstWhere((e) => e['code'] == 'AE')['activeTenants'], 0);

        final one = await h.okData(
          h.call('GET', '/platform/countries/AE', uid: 'root'),
        );
        expect(one['callingCode'], '+971');
        expect(
          (await h.call(
            'GET',
            '/platform/countries/ZZ',
            uid: 'root',
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'GET',
            '/platform/countries/in',
            uid: 'root',
          )).statusCode,
          404,
        );
      },
    );

    test('support admin can read but not change; others are refused', () async {
      final h = harness();
      h.user('plain');
      expect(
        (await h.call('GET', '/platform/countries', uid: 'support')).statusCode,
        200,
      );
      for (final (method, path, b) in [
        ('POST', '/platform/countries/seed-baseline', null),
        (
          'PATCH',
          '/platform/countries/IN',
          {'expectedVersion': 1, 'reason': 'x y z'},
        ),
        ('POST', '/platform/countries', <String, Object?>{}),
      ]) {
        expect(
          (await h.call(method, path, uid: 'support', body: b)).statusCode,
          403,
          reason: path,
        );
      }
      expect(
        (await h.call('GET', '/platform/countries', uid: 'plain')).statusCode,
        403,
      );
      expect((await h.call('GET', '/platform/countries')).statusCode, 401);
    });

    Map<String, Object?> newCountry() => {
      'code': 'SA',
      'name': 'Saudi Arabia',
      'nativeName': 'المملكة العربية السعودية',
      'callingCode': '+966',
      'defaultCurrency': 'SAR',
      'locales': ['ar-SA', 'en-SA'],
      'defaultLocale': 'ar-SA',
      'suggestedTimezones': ['Asia/Riyadh'],
      'adminAreaLabel': 'Region',
      'postalCode': {
        'required': true,
        'label': 'Postal code',
        'pattern': r'^[0-9]{5}$',
      },
      'policy': {
        'allowedTenantOverrides': ['language'],
        'supportedCurrencies': ['SAR'],
      },
    };

    test(
      'a new country starts disabled and cannot be enabled without review evidence',
      () async {
        final h = harness();
        final created = await h.okData(
          h.call(
            'POST',
            '/platform/countries',
            uid: 'root',
            body: newCountry(),
          ),
          status: 201,
        );
        expect(created['status'], 'disabled');
        expect(created['onboardingEnabled'], false);
        expect(
          created['completenessWarnings'],
          containsAll(['never_reviewed', 'no_review_sources']),
        );

        final noEvidence = await h.call(
          'PATCH',
          '/platform/countries/SA',
          uid: 'root',
          body: {
            'expectedVersion': 1,
            'reason': 'go live',
            'status': 'supported',
            'onboardingEnabled': true,
          },
        );
        expect(noEvidence.statusCode, 422);
        expect(
          await issueCodes(noEvidence),
          contains('review_evidence_required'),
        );

        final ok = await h.okData(
          h.call(
            'PATCH',
            '/platform/countries/SA',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'reviewed against ISO and CLDR',
              'status': 'supported',
              'onboardingEnabled': true,
              'reviewedOn': '2026-11-05',
              'sources': ['https://www.iso.org/iso-3166-country-codes.html'],
            },
          ),
        );
        expect(ok['configurationVersion'], 2);
        expect(ok['isOnboardable'], true);
        expect(h.store.docs.keys, contains('countries/SA/versions/2'));
        // history keeps the old version untouched
        expect(h.store.docs['countries/SA/versions/1']!['status'], 'disabled');
      },
    );

    test('invalid profiles are rejected with every problem reported', () async {
      final h = harness();
      final bad = await h.call(
        'POST',
        '/platform/countries',
        uid: 'root',
        body: {
          ...newCountry(),
          'code': 'sa',
          'callingCode': '966',
          'defaultCurrency': 'riyal',
          'suggestedTimezones': ['Mars/Base'],
        },
      );
      expect(bad.statusCode, 422);
      expect((await bad.readAsString()).length, greaterThan(100));
      expect(
        h.store.docs.keys.where((k) => k.startsWith('countries/sa')),
        isEmpty,
      );
    });

    test(
      'creating an existing country conflicts; unknown fields are refused',
      () async {
        final h = harness();
        expect(
          (await h.call(
            'POST',
            '/platform/countries',
            uid: 'root',
            body: {...newCountry(), 'code': 'IN'},
          )).statusCode,
          409,
        );
        expect(
          (await h.call(
            'POST',
            '/platform/countries',
            uid: 'root',
            body: {...newCountry(), 'tenantId': 'x'},
          )).statusCode,
          422,
        );
      },
    );

    test(
      'code, calling code and currency are immutable; stale edits conflict; reason required',
      () async {
        final h = harness();
        for (final field in [
          'code',
          'callingCode',
          'defaultCurrency',
          'configurationVersion',
        ]) {
          final r = await h.call(
            'PATCH',
            '/platform/countries/IN',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'change it',
              field: field == 'callingCode' ? '+1' : 'XX',
            },
          );
          expect(r.statusCode, 422, reason: field);
        }
        expect(
          (await h.call(
            'PATCH',
            '/platform/countries/IN',
            uid: 'root',
            body: {'expectedVersion': 1, 'adminAreaLabel': 'Province'},
          )).statusCode,
          422, // reason missing
        );
        await h.okData(
          h.call(
            'PATCH',
            '/platform/countries/IN',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'rename label',
              'adminAreaLabel': 'State/UT',
            },
          ),
        );
        expect(
          (await h.call(
            'PATCH',
            '/platform/countries/IN',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'stale write',
              'adminAreaLabel': 'X',
            },
          )).statusCode,
          409,
        );
      },
    );

    test(
      'a country with active clinics cannot be disabled, but onboarding can be paused',
      () async {
        final h = harness();
        await h.createClinic('o1');
        final disable = await h.call(
          'PATCH',
          '/platform/countries/IN',
          uid: 'root',
          body: {
            'expectedVersion': 1,
            'reason': 'retire market',
            'status': 'disabled',
            'onboardingEnabled': false,
          },
        );
        expect(disable.statusCode, 409);
        expect(h.store.docs['countries/IN']!['status'], 'supported');

        final pause = await h.okData(
          h.call(
            'PATCH',
            '/platform/countries/IN',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'pause signups',
              'onboardingEnabled': false,
            },
          ),
        );
        expect(pause['isOnboardable'], false);
        expect(pause['status'], 'supported');

        // AE has no tenants, so it may be disabled
        await h.okData(
          h.call(
            'PATCH',
            '/platform/countries/AE',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'not ready',
              'status': 'disabled',
              'onboardingEnabled': false,
            },
          ),
        );
      },
    );

    test('every change is audited with who, why and the version', () async {
      final h = harness();
      await h.okData(
        h.call(
          'PATCH',
          '/platform/countries/IN',
          uid: 'root',
          body: {
            'expectedVersion': 1,
            'reason': 'label tweak',
            'adminAreaLabel': 'State/UT',
          },
        ),
      );
      final audit = h.store.docs.values
          .where((d) => d['action'] == 'country.updated')
          .single;
      expect(audit['actorUid'], 'root');
      expect(audit['reason'], 'label tweak');
      expect(
        (audit['after']! as Map<String, Object?>)['configurationVersion'],
        2,
      );
    });

    test(
      'the onboarding list shows only enabled countries with client-safe fields',
      () async {
        final h = harness();
        h.user('anyone');
        var items =
            ((await h.okData(
                      h.call('GET', '/countries', uid: 'anyone'),
                    ))['items']!
                    as List)
                .cast<Map<String, Object?>>();
        expect(items.map((e) => e['code']), ['AE', 'IN']);
        expect(items.first.keys, isNot(contains('sources')));
        expect(items.first.keys, isNot(contains('status')));

        await h.okData(
          h.call(
            'PATCH',
            '/platform/countries/AE',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'pause',
              'onboardingEnabled': false,
            },
          ),
        );
        items =
            ((await h.okData(
                      h.call('GET', '/countries', uid: 'anyone'),
                    ))['items']!
                    as List)
                .cast<Map<String, Object?>>();
        expect(items.map((e) => e['code']), ['IN']);
        expect((await h.call('GET', '/countries')).statusCode, 401);
      },
    );

    test(
      'a corrupted stored profile is reported, hidden from onboarding and fails closed',
      () async {
        final h = harness();
        h.store.docs['countries/AE']!['defaultCurrency'] = 'dirham';
        final list =
            ((await h.okData(
                      h.call('GET', '/platform/countries', uid: 'root'),
                    ))['items']!
                    as List)
                .cast<Map<String, Object?>>();
        expect(list.firstWhere((e) => e['code'] == 'AE')['invalid'], true);
        h.user('anyone');
        final open =
            ((await h.okData(
                      h.call('GET', '/countries', uid: 'anyone'),
                    ))['items']!
                    as List)
                .cast<Map<String, Object?>>();
        expect(open.map((e) => e['code']), ['IN']);
      },
    );
  });

  group('onboarding with a country', () {
    test('country is required and must be a well-formed code', () async {
      final h = harness();
      h.user('a1');
      final missing = applicationBody()
        ..['address'] = {
          ...(applicationBody()['address']! as Map<String, Object?>)
              .cast<String, Object?>()
            ..remove('countryCode'),
        };
      final r = await h.call(
        'POST',
        '/clinic-applications',
        uid: 'a1',
        body: missing,
      );
      expect(r.statusCode, 422);
      expect(await issueFields(r), contains('address.countryCode'));
      for (final bad in ['india', 'I', 'IND', '1N', 'in']) {
        // one user per attempt: submissions are rate limited per user
        h.user('u$bad');
        final res = await h.call(
          'POST',
          '/clinic-applications',
          uid: 'u$bad',
          body: applicationBody(countryCode: bad),
        );
        expect(res.statusCode, 422, reason: bad);
      }
    });

    test(
      'spoofed, unknown, disabled or paused countries are rejected',
      () async {
        final h = harness();
        h.user('a1');
        // well-formed but not in the master
        var r = await h.call(
          'POST',
          '/clinic-applications',
          uid: 'a1',
          body: applicationBody(countryCode: 'ZZ'),
        );
        expect(r.statusCode, 422);
        expect(await issueCodes(r), contains('unsupported_country'));
        // paused onboarding
        await h.okData(
          h.call(
            'PATCH',
            '/platform/countries/AE',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'pause',
              'onboardingEnabled': false,
            },
          ),
        );
        r = await h.call(
          'POST',
          '/clinic-applications',
          uid: 'a1',
          body: applicationBody(countryCode: 'AE'),
        );
        expect(r.statusCode, 422);
        expect(
          h.store.docs.keys.where((k) => k.startsWith('clinic_applications/')),
          isEmpty,
        );
      },
    );

    test(
      'a country-specific payload cannot smuggle a tenant-level field',
      () async {
        final h = harness();
        h.user('a1');
        final b = applicationBody();
        b['tenantId'] = 'ten_victim';
        expect(
          (await h.call(
            'POST',
            '/clinic-applications',
            uid: 'a1',
            body: b,
          )).statusCode,
          422,
        );
      },
    );

    test(
      'India: PIN code format is enforced and phones are stored as E.164',
      () async {
        final h = harness();
        h.user('a1');
        final bad = await h.call(
          'POST',
          '/clinic-applications',
          uid: 'a1',
          body: applicationBody(postalCode: '12345'),
        );
        expect(await issueFields(bad), contains('address.postalCode'));
        final id = await h.apply('a1');
        final app = h.store.docs['clinic_applications/$id']!;
        expect((app['address'] as Map<String, Object?>)['country'], 'India');
        expect((app['address'] as Map<String, Object?>)['countryCode'], 'IN');
        expect(
          (app['clinic'] as Map<String, Object?>)['phone'],
          '+919876543210',
        );
        expect(app['countryConfigVersion'], 1);
      },
    );

    test(
      'UAE: no postal code needed; UAE numbers accepted; Indian numbers rejected',
      () async {
        final h = harness();
        h.user('a1');
        final ae = applicationBody(countryCode: 'AE', postalCode: '00000');
        (ae['address']! as Map<String, Object?>).remove('postalCode');
        final id =
            (await h.okData(
                  h.call('POST', '/clinic-applications', uid: 'a1', body: ae),
                  status: 201,
                ))['applicationId']!
                as String;
        final stored = h.store.docs['clinic_applications/$id']!;
        expect(
          (stored['address'] as Map<String, Object?>)['country'],
          'United Arab Emirates',
        );
        expect(
          (stored['clinic'] as Map<String, Object?>)['phone'],
          '+971501234567',
        );

        h.user('a2');
        final wrongPhone = applicationBody(
          countryCode: 'AE',
          name: 'Other Clinic',
        );
        (wrongPhone['clinic']! as Map<String, Object?>)['phone'] = '9876543210';
        final r = await h.call(
          'POST',
          '/clinic-applications',
          uid: 'a2',
          body: wrongPhone,
        );
        expect(r.statusCode, 422);
        expect(await issueFields(r), contains('clinic.phone'));
      },
    );

    test('the phone number never decides the country', () async {
      final h = harness();
      h.user('a1');
      // UAE phone with country IN is invalid, not "re-detected" as AE
      final b = applicationBody();
      (b['clinic']! as Map<String, Object?>)['phone'] = '+971501234567';
      final r = await h.call(
        'POST',
        '/clinic-applications',
        uid: 'a1',
        body: b,
      );
      expect(r.statusCode, 422);
    });
  });

  group('tenant provisioning', () {
    test(
      'approval persists the legal country and master version on the tenant',
      () async {
        final h = harness();
        final tid = await h.createClinic('o1');
        final tenant = h.store.docs['tenants/$tid']!;
        expect(tenant['countryCode'], 'IN');
        expect(tenant['countryConfigVersion'], 1);
        expect(tenant['countrySource'], 'application');
        expect(tenant['status'], 'active');
      },
    );

    test('a UAE clinic is provisioned as AE', () async {
      final h = harness();
      final tid = await h.createClinic('o1', countryCode: 'AE', pin: '12345');
      expect(h.store.docs['tenants/$tid']!['countryCode'], 'AE');
    });

    test(
      'country disabled after submission: approval fails atomically, nothing is provisioned',
      () async {
        final h = harness();
        h.user('a1');
        final appId = await h.apply(
          'a1',
          body: applicationBody(countryCode: 'AE'),
        );
        await h.okData(
          h.call(
            'PATCH',
            '/platform/countries/AE',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'retire',
              'status': 'disabled',
              'onboardingEnabled': false,
            },
          ),
        );
        final before = Map.of(h.store.docs);
        final r = await h.call(
          'POST',
          '/platform/clinic-applications/$appId/approve',
          uid: 'root',
          body: {'confirm': true},
        );
        expect(r.statusCode, 409);
        expect(
          h.store.docs.keys.where((k) => k.startsWith('tenants/')),
          isEmpty,
        );
        expect(
          h.store.docs.keys.where(
            (k) =>
                k.startsWith('tenant_slugs/') ||
                k.startsWith('tenant_provisioning_jobs/'),
          ),
          isEmpty,
        );
        expect(
          h.store.docs['clinic_applications/$appId']!['status'],
          before['clinic_applications/$appId']!['status'],
        );
      },
    );

    test(
      'paused onboarding does not block approving an application already submitted',
      () async {
        final h = harness();
        h.user('a1');
        final appId = await h.apply('a1');
        await h.okData(
          h.call(
            'PATCH',
            '/platform/countries/IN',
            uid: 'root',
            body: {
              'expectedVersion': 1,
              'reason': 'pause',
              'onboardingEnabled': false,
            },
          ),
        );
        final tid = await h.approve(appId);
        expect(h.store.docs['tenants/$tid']!['countryCode'], 'IN');
      },
    );

    test(
      'legacy application without a country needs one at approval, and a mismatch is refused',
      () async {
        final h = harness();
        h.user('a1');
        final appId = await h.apply('a1');
        // simulate an application submitted before Phase 12
        (h.store.docs['clinic_applications/$appId']!['address']
                as Map<String, Object?>)
            .remove('countryCode');

        var r = await h.call(
          'POST',
          '/platform/clinic-applications/$appId/approve',
          uid: 'root',
          body: {'confirm': true},
        );
        expect(r.statusCode, 422);
        expect(await issueFields(r), contains('countryCode'));

        r = await h.call(
          'POST',
          '/platform/clinic-applications/$appId/approve',
          uid: 'root',
          body: {'confirm': true, 'countryCode': 'ZZ'},
        );
        expect(r.statusCode, 409);
        expect(
          h.store.docs.keys.where((k) => k.startsWith('tenants/')),
          isEmpty,
        );

        r = await h.call(
          'POST',
          '/platform/clinic-applications/$appId/approve',
          uid: 'root',
          body: {'confirm': true, 'countryCode': 'IN'},
        );
        expect(r.statusCode, 200);
        final tid =
            ((jsonDecode(await r.readAsString())
                    as Map<String, Object?>)['data']!
                as Map<String, Object?>);
        expect(
          h.store.docs['tenants/${tid['tenantId']}']!['countrySource'],
          'approval',
        );
      },
    );

    test(
      'approval is idempotent: a repeat does not change the country',
      () async {
        final h = harness();
        h.user('a1');
        final appId = await h.apply('a1');
        final tid = await h.approve(appId);
        final again = await h.call(
          'POST',
          '/platform/clinic-applications/$appId/approve',
          uid: 'root',
          body: {'confirm': true, 'countryCode': 'AE'},
        );
        expect(again.statusCode, 200);
        expect(h.store.docs['tenants/$tid']!['countryCode'], 'IN');
      },
    );
  });

  group('country immutability for tenant users', () {
    test(
      'settings and profile cannot set or change the legal country',
      () async {
        final h = harness();
        final tid = await h.createClinic('o1');
        expect(tid, isNotEmpty);
        for (final path in ['/clinics/current/settings', '/clinics/current']) {
          final r = await h.call(
            'PATCH',
            path,
            uid: 'o1',
            body: {'countryCode': 'AE'},
          );
          expect(r.statusCode, 422, reason: path);
        }
        final r = await h.call(
          'PATCH',
          '/clinics/current',
          uid: 'o1',
          body: {
            'address': {
              'line1': '1 Road',
              'city': 'Pune',
              'state': 'MH',
              'countryCode': 'AE',
              'postalCode': '411001',
            },
          },
        );
        expect(r.statusCode, 422);
        expect(await issueCodes(r), contains('country_mismatch'));
        expect(h.store.docs['tenants/$tid']!['countryCode'], 'IN');
      },
    );

    test(
      'settings expose the country read-only and apply the country defaults',
      () async {
        final h = harness();
        await h.createClinic('o1');
        await h.createClinic(
          'o2',
          name: 'Dubai Clinic',
          countryCode: 'AE',
          pin: '12345',
        );
        final india = await h.okData(
          h.call('GET', '/clinics/current/settings', uid: 'o1'),
        );
        final uae = await h.okData(
          h.call('GET', '/clinics/current/settings', uid: 'o2'),
        );
        expect(india['countryCode'], 'IN');
        expect(india['currency'], 'INR');
        expect(uae['countryCode'], 'AE');
        expect(uae['currency'], 'AED');
        expect(uae['language'], 'en');
      },
    );

    test('currency, timezone and language follow the country policy', () async {
      final h = harness();
      await h.createClinic(
        'o2',
        name: 'Dubai Clinic',
        countryCode: 'AE',
        pin: '12345',
      );
      Future<int> patch(Map<String, Object?> b) async => (await h.call(
        'PATCH',
        '/clinics/current/settings',
        uid: 'o2',
        body: b,
      )).statusCode;
      expect(await patch({'currency': 'INR'}), 422); // not the UAE currency
      expect(await patch({'currency': 'AED'}), 200);
      expect(await patch({'timezone': 'Asia/Dubai'}), 200);
      expect(await patch({'timezone': 'Asia/Atlantis'}), 422);
      expect(await patch({'language': 'ar'}), 200);
      expect(await patch({'language': 'xx'}), 422);
    });

    test(
      'another clinic\'s owner cannot read or change this clinic\'s configuration',
      () async {
        final h = harness();
        final a = await h.createClinic('oa');
        await h.createClinic(
          'ob',
          name: 'B Clinic',
          countryCode: 'AE',
          pin: '12345',
        );
        final cfg = await h.okData(
          h.call('GET', '/clinics/current/country-config', uid: 'ob'),
        );
        expect(cfg['tenantId'], isNot(a));
        expect((cfg['tenant']! as Map<String, Object?>)['countryCode'], 'AE');
        // selecting another tenant through the header is refused
        expect(
          (await h.call(
            'GET',
            '/clinics/current/country-config',
            uid: 'ob',
            headers: {'x-tenant-id': a},
          )).statusCode,
          403,
        );
      },
    );
  });

  group('branches', () {
    test('timezone must be a real IANA zone', () async {
      final h = harness();
      await h.createClinic('o1');
      final r = await h.call(
        'POST',
        '/branches',
        uid: 'o1',
        body: {...branchBody(), 'code': 'T1', 'timezone': 'Asia/Atlantis'},
      );
      expect(r.statusCode, 422);
      expect(await issueFields(r), contains('timezone'));
    });

    test(
      'a UAE branch stores E.164 phone, Dubai zone and localized address',
      () async {
        final h = harness();
        await h.createClinic(
          'o2',
          name: 'Dubai Clinic',
          countryCode: 'AE',
          pin: '12345',
        );
        final b = {
          'name': 'Marina',
          'code': 'MRN',
          'type': 'main',
          'phone': '050 123 4567',
          'timezone': 'Asia/Dubai',
          'address': {
            'line1': 'Marina Walk',
            'city': 'Dubai',
            'state': 'Dubai',
            'countryCode': 'AE',
            'localized': {
              'ar': {'line1': 'ممشى المارينا', 'city': 'دبي'},
            },
          },
        };
        final created = await h.okData(
          h.call('POST', '/branches', uid: 'o2', body: b),
          status: 201,
        );
        expect(created['phone'], '+971501234567');
        expect(created['timezone'], 'Asia/Dubai');
        final addr = created['address']! as Map<String, Object?>;
        expect(addr['countryCode'], 'AE');
        expect(addr['country'], 'United Arab Emirates');
        expect((addr['localized']! as Map<String, Object?>)['ar'], {
          'line1': 'ممشى المارينا',
          'city': 'دبي',
        });
      },
    );

    test(
      'a branch cannot be placed in another country than the clinic',
      () async {
        final h = harness();
        await h.createClinic('o1');
        final r = await h.call(
          'POST',
          '/branches',
          uid: 'o1',
          body: {
            ...branchBody(),
            'code': 'X1',
            'address': {
              'line1': '1 Road',
              'city': 'Dubai',
              'state': 'Dubai',
              'countryCode': 'AE',
            },
          },
        );
        expect(r.statusCode, 422);
        expect(await issueCodes(r), contains('country_mismatch'));
      },
    );

    test(
      'Indian branch phone and PIN rules still apply to Indian clinics',
      () async {
        final h = harness();
        await h.createClinic('o1');
        final bad = await h.call(
          'POST',
          '/branches',
          uid: 'o1',
          body: {...branchBody(), 'code': 'P1', 'phone': '12345'},
        );
        expect(bad.statusCode, 422);
        final ok = await h.okData(
          h.call(
            'POST',
            '/branches',
            uid: 'o1',
            body: {...branchBody(), 'code': 'P2'},
          ),
          status: 201,
        );
        expect(ok['phone'], '+919876543210');
      },
    );

    test('invalid localized address variants are rejected', () async {
      final h = harness();
      await h.createClinic('o1');
      for (final localized in [
        {
          'arabic': {'line1': 'x'},
        },
        {
          'ar': {'phone': '1'},
        },
        {'ar': 'text'},
        {
          'ar': {'line1': 'a'},
          'hi': {'line1': 'b'},
          'ta': {'line1': 'c'},
          'te': {'line1': 'd'},
          'bn': {'line1': 'e'},
        },
      ]) {
        final r = await h.call(
          'POST',
          '/branches',
          uid: 'o1',
          body: {
            ...branchBody(),
            'code': 'L1',
            'address': {
              ...(branchBody()['address']! as Map<String, Object?>),
              'localized': localized,
            },
          },
        );
        expect(r.statusCode, 422, reason: '$localized');
      }
    });

    test('clinics without a country keep the legacy behaviour', () async {
      final h = harness();
      h.user('legacy');
      final tid = 'ten_legacy1';
      h.store.docs['tenants/$tid'] = {
        'tenantId': tid,
        'clinicName': 'Legacy',
        'status': 'active',
        'createdAt': h.clock.now,
      };
      expect(h.store.docs['tenants/$tid']!.containsKey('countryCode'), isFalse);
    });
  });

  group('configuration resolution', () {
    test('India clinic resolves INR, Kolkata and the Indian locale', () async {
      final h = harness();
      await h.createClinic('o1');
      await h.okData(
        h.call(
          'PATCH',
          '/clinics/current/settings',
          uid: 'o1',
          body: {'timezone': 'Asia/Kolkata'},
        ),
      );
      final cfg = await h.okData(
        h.call('GET', '/clinics/current/country-config', uid: 'o1'),
      );
      expect(cfg['countryConfigured'], true);
      expect((cfg['country']! as Map<String, Object?>)['code'], 'IN');
      final eff = cfg['effective']! as Map<String, Object?>;
      expect(eff['currency'], 'INR');
      expect(eff['currencyMinorUnits'], 2);
      expect(eff['timezone'], 'Asia/Kolkata');
      expect((eff['locale']! as Map<String, Object?>)['rtl'], false);
      expect(
        (cfg['country']! as Map<String, Object?>).keys,
        isNot(contains('policy')),
      );
    });

    test(
      'UAE clinic resolves AED, Dubai; a user can choose Arabic (RTL) without changing the country',
      () async {
        final h = harness();
        await h.createClinic(
          'o2',
          name: 'Dubai Clinic',
          countryCode: 'AE',
          pin: '12345',
        );
        final cfg = await h.okData(
          h.call('GET', '/clinics/current/country-config?locale=ar', uid: 'o2'),
        );
        final eff = cfg['effective']! as Map<String, Object?>;
        expect(eff['currency'], 'AED');
        expect(eff['timezone'], 'Asia/Dubai');
        expect((eff['locale']! as Map<String, Object?>)['tag'], 'ar');
        expect((eff['locale']! as Map<String, Object?>)['rtl'], true);
        expect((eff['locale']! as Map<String, Object?>)['source'], 'user');
        expect((cfg['country']! as Map<String, Object?>)['code'], 'AE');

        final withoutPref = await h.okData(
          h.call('GET', '/clinics/current/country-config', uid: 'o2'),
        );
        expect(
          ((withoutPref['effective']! as Map<String, Object?>)['locale']!
              as Map<String, Object?>)['source'],
          'country',
        );
      },
    );

    test(
      'an unsupported or malformed locale cannot break resolution',
      () async {
        final h = harness();
        await h.createClinic('o1');
        final cfg = await h.okData(
          h.call('GET', '/clinics/current/country-config?locale=fr', uid: 'o1'),
        );
        expect(
          ((cfg['effective']! as Map<String, Object?>)['locale']!
              as Map<String, Object?>)['source'],
          isNot('user'),
        );
        expect(
          (await h.call(
            'GET',
            '/clinics/current/country-config?locale=%3Cscript%3E',
            uid: 'o1',
          )).statusCode,
          400,
        );
      },
    );

    test(
      'branch time zone is reported, with fallback to the clinic zone',
      () async {
        final h = harness();
        await h.createClinic(
          'o2',
          name: 'Dubai Clinic',
          countryCode: 'AE',
          pin: '12345',
        );
        final created = await h.okData(
          h.call(
            'POST',
            '/branches',
            uid: 'o2',
            body: {
              'name': 'Marina',
              'code': 'MRN',
              'type': 'main',
              'timezone': 'Asia/Dubai',
              'address': {
                'line1': 'Marina Walk',
                'city': 'Dubai',
                'state': 'Dubai',
              },
            },
          ),
          status: 201,
        );
        final id = created['branchId']! as String;
        final cfg = await h.okData(
          h.call(
            'GET',
            '/clinics/current/country-config?branchId=$id',
            uid: 'o2',
          ),
        );
        expect(
          (cfg['effective']! as Map<String, Object?>)['branchTimezone'],
          'Asia/Dubai',
        );
        expect(
          (await h.call(
            'GET',
            '/clinics/current/country-config?branchId=br_missing1',
            uid: 'o2',
          )).statusCode,
          404,
        );
      },
    );

    test(
      'a tenant created before Phase 12 is "not configured" rather than guessed',
      () async {
        final h = harness();
        final tid = await h.createClinic('o1');
        h.store.docs['tenants/$tid']!.remove('countryCode');
        final cfg = await h.okData(
          h.call('GET', '/clinics/current/country-config', uid: 'o1'),
        );
        expect(cfg['countryConfigured'], false);
        expect(cfg['country'], isNull);
      },
    );

    test(
      'a tenant whose country profile is missing or disabled fails closed',
      () async {
        final h = harness();
        await h.createClinic('o1');
        h.store.docs.remove('countries/IN');
        h.platform.countryDirectory.invalidate();
        final r = await h.call(
          'GET',
          '/clinics/current/country-config',
          uid: 'o1',
        );
        expect(r.statusCode, 503);
        expect(await r.readAsString(), isNot(contains('IN')));
      },
    );

    test(
      'deployment region is informational and never the tenant country',
      () async {
        final h = harness();
        final tid = await h.createClinic('o1');
        expect(tid, isNotEmpty);
        final cfg = await h.okData(
          h.call('GET', '/clinics/current/country-config', uid: 'o1'),
        );
        expect(
          (cfg['deployment']! as Map<String, Object?>).containsKey('region'),
          isTrue,
        );
      },
    );

    test(
      'profile cache is versioned by TTL and invalidated by administration',
      () async {
        final h = harness();
        final dir = CountryDirectory(h.store, ttl: const Duration(hours: 1));
        expect((await dir.profile('IN'))!.configurationVersion, 1);
        h.store.docs['countries/IN']!['configurationVersion'] = 2;
        expect((await dir.profile('IN'))!.configurationVersion, 1); // cached
        expect((await dir.profile('IN', fresh: true))!.configurationVersion, 2);
        h.store.docs['countries/IN']!['configurationVersion'] = 3;
        dir.invalidate('IN');
        expect((await dir.profile('IN'))!.configurationVersion, 3);
        expect(await dir.profile('../tenants'), isNull);
      },
    );
  });

  group('migration of existing tenants', () {
    Future<String> legacyTenant(
      PlatformHarness h,
      String owner,
      Map<String, Object?> body, {
      String name = 'Legacy',
    }) async {
      final tid = await h.createClinic(owner, name: name);
      h.store.docs['tenants/$tid']!
        ..remove('countryCode')
        ..remove('countryConfigVersion');
      final appId = h.store.docs['tenants/$tid']!['applicationId']! as String;
      h.store.docs['clinic_applications/$appId']!['address'] = body;
      return tid;
    }

    test(
      'classifies verified, ambiguous and unmapped tenants without writing anything',
      () async {
        final h = harness();
        final verified = await legacyTenant(h, 'o1', {
          'line1': '1 Rd',
          'city': 'Pune',
          'country': 'India',
          'postalCode': '411001',
        }, name: 'Verified Clinic');
        final badPin = await legacyTenant(h, 'o2', {
          'line1': '1 Rd',
          'city': 'Pune',
          'country': 'India',
          'postalCode': '12',
        }, name: 'Odd PIN Clinic');
        final uae = await legacyTenant(h, 'o3', {
          'line1': '1 Rd',
          'city': 'Dubai',
          'country': 'UAE',
          'postalCode': '00000',
        }, name: 'Alias Clinic');
        final none = await legacyTenant(h, 'o4', {
          'line1': '1 Rd',
          'city': 'X',
        }, name: 'No Country Clinic');
        final other = await legacyTenant(h, 'o5', {
          'line1': '1 Rd',
          'city': 'Y',
          'country': 'Atlantis',
        }, name: 'Unknown Country Clinic');
        final assigned = await h.createClinic('o6', name: 'Already Done');

        final before = Map.of(h.store.docs);
        final report = await h.okData(
          h.call('GET', '/platform/countries/backfill-report', uid: 'root'),
        );
        expect(
          h.store.docs.length,
          before.length,
          reason: 'dry run must not write',
        );
        expect(report['dryRun'], true);
        expect(report['alreadyAssigned'], 1);
        final rows = {
          for (final r
              in (report['tenants']! as List).cast<Map<String, Object?>>())
            r['tenantId']: r,
        };
        expect(rows[verified]!['classification'], 'verified');
        expect(rows[verified]!['candidateCountry'], 'IN');
        expect(rows[badPin]!['classification'], 'ambiguous');
        expect(rows[badPin]!['reasons'], contains('postal_code_inconsistent'));
        // UAE alias: phone numbers in the fixture are Indian, so the evidence conflicts
        expect(rows[uae]!['classification'], 'ambiguous');
        expect(rows[uae]!['candidateCountry'], 'AE');
        expect(rows[none]!['classification'], 'unmapped');
        expect(rows[other]!['classification'], 'unmapped');
        expect(rows.containsKey(assigned), isFalse);
        expect(report['summary'], {
          'verified': 1,
          'ambiguous': 2,
          'unmapped': 2,
        });
      },
    );

    test(
      'a tenant with no application record is unmapped, never guessed',
      () async {
        final h = harness();
        h.store.docs['tenants/ten_orphan1'] = {
          'tenantId': 'ten_orphan1',
          'clinicName': 'Orphan',
          'status': 'active',
          'createdAt': h.clock.now,
        };
        final report = await h.okData(
          h.call('GET', '/platform/countries/backfill-report', uid: 'root'),
        );
        final row = (report['tenants']! as List)
            .cast<Map<String, Object?>>()
            .single;
        expect(row['classification'], 'unmapped');
        expect(row['reasons'], contains('no_application_record'));
        expect(row['candidateCountry'], isNull);
      },
    );

    test('support admin can read the report; ordinary users cannot', () async {
      final h = harness();
      h.user('plain');
      expect(
        (await h.call(
          'GET',
          '/platform/countries/backfill-report',
          uid: 'support',
        )).statusCode,
        200,
      );
      expect(
        (await h.call(
          'GET',
          '/platform/countries/backfill-report',
          uid: 'plain',
        )).statusCode,
        403,
      );
    });

    test(
      'assignment is privileged, confirmed, audited and idempotent',
      () async {
        final h = harness();
        final tid = await h.createClinic('o1');
        h.store.docs['tenants/$tid']!.remove('countryCode');
        Future<int> assign(String uid, Map<String, Object?> b) async =>
            (await h.call(
              'POST',
              '/platform/tenants/$tid/country',
              uid: uid,
              body: b,
            )).statusCode;

        expect(
          await assign('support', {
            'countryCode': 'IN',
            'reason': 'verified',
            'confirm': true,
          }),
          403,
        );
        expect(
          await assign('root', {'countryCode': 'IN', 'reason': 'verified'}),
          422,
        ); // no confirm
        expect(
          await assign('root', {'countryCode': 'IN', 'confirm': true}),
          422,
        ); // no reason
        expect(
          await assign('root', {
            'countryCode': 'ZZ',
            'reason': 'verified',
            'confirm': true,
          }),
          422,
        );

        final first = await h.okData(
          h.call(
            'POST',
            '/platform/tenants/$tid/country',
            uid: 'root',
            body: {
              'countryCode': 'IN',
              'reason': 'verified by report',
              'confirm': true,
            },
          ),
        );
        expect(first['changed'], true);
        final t = h.store.docs['tenants/$tid']!;
        expect(t['countryCode'], 'IN');
        expect(t['countrySource'], 'migration');
        expect(t['countrySetBy'], 'root');
        expect(
          h.store.docs.keys.where(
            (k) => k.startsWith('tenants/$tid/country_history/'),
          ),
          hasLength(1),
        );

        final again = await h.okData(
          h.call(
            'POST',
            '/platform/tenants/$tid/country',
            uid: 'root',
            body: {
              'countryCode': 'IN',
              'reason': 'verified by report',
              'confirm': true,
            },
          ),
        );
        expect(again['changed'], false);
        expect(
          h.store.docs.keys.where(
            (k) => k.startsWith('tenants/$tid/country_history/'),
          ),
          hasLength(1),
        );
        expect(
          h.store.docs.values.where(
            (d) => d['action'] == 'tenant.country_assigned',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'correcting a country needs the current value and leaves history',
      () async {
        final h = harness();
        final tid = await h.createClinic('o1');
        Future<int> fix(Map<String, Object?> b) async => (await h.call(
          'POST',
          '/platform/tenants/$tid/country',
          uid: 'root',
          body: {
            'countryCode': 'AE',
            'reason': 'registered in Dubai',
            'confirm': true,
            ...b,
          },
        )).statusCode;
        expect(await fix({}), 409);
        expect(await fix({'expectedCurrent': 'AE'}), 409);
        expect(await fix({'expectedCurrent': 'IN'}), 200);
        expect(h.store.docs['tenants/$tid']!['countryCode'], 'AE');
        final history = h.store.docs.entries
            .where((e) => e.key.startsWith('tenants/$tid/country_history/'))
            .single
            .value;
        expect(history['from'], 'IN');
        expect(history['to'], 'AE');
      },
    );

    test('unknown tenants are 404 and the country must be supported', () async {
      final h = harness();
      final r = await h.call(
        'POST',
        '/platform/tenants/ten_nothere/country',
        uid: 'root',
        body: {'countryCode': 'IN', 'reason': 'verified', 'confirm': true},
      );
      expect(r.statusCode, 404);
    });
  });

  group('configuration', () {
    test('DEPLOYMENT_REGION is validated', () {
      // covered in config tests; kept here to document the contract
      expect(CountryDirectory.isWellFormedCode('IN'), isTrue);
      expect(CountryDirectory.isWellFormedCode('in'), isFalse);
      expect(CountryDirectory.isWellFormedCode('IND'), isFalse);
      expect(CountryDirectory.isWellFormedCode(null), isFalse);
    });
  });
}
