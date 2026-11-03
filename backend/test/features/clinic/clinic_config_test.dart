import 'dart:convert';

import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/auth_fixtures.dart' show errorCode;
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late String tid;
  setUp(() async {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    tid = await h.createClinic('owner');
  });

  group('clinic profile', () {
    test('defaults come from the approved application', () async {
      final p = await h.okData(h.call('GET', '/clinics/current', uid: 'owner'));
      expect(p['tenantId'], tid);
      expect((p['profile']! as Map)['name'], 'Green Valley Clinic');
      expect((p['profile']! as Map)['email'], 'info@greenvalley.test');
      expect(p['verificationStatus'], 'unverified');
    });

    test(
      'owner edits permitted fields; platform tenant record stays in sync',
      () async {
        final r = await h.okData(
          h.call(
            'PATCH',
            '/clinics/current',
            uid: 'owner',
            body: {
              'name': 'Green Valley Family Clinic',
              'specialities': ['Paediatrics', 'General medicine'],
              'alternatePhone': '9876500000',
              'address': {'city': 'Pimpri'},
            },
          ),
        );
        expect((r['profile']! as Map)['name'], 'Green Valley Family Clinic');
        expect(((r['profile']! as Map)['address']! as Map)['city'], 'Pimpri');
        expect(
          ((r['profile']! as Map)['address']! as Map)['line1'],
          '12 Main Road',
          reason: 'address merges',
        );
        expect(
          h.store.docs['tenants/$tid']!['clinicName'],
          'Green Valley Family Clinic',
        );
        expect(
          h.store.docs['tenants/$tid']!['clinicNameLower'],
          'green valley family clinic',
        );
        expect(
          h.store.docs.values.any(
            (d) => d['action'] == 'clinic.profile_updated',
          ),
          isTrue,
        );
      },
    );

    test(
      'identity, ownership and verification are not client-editable',
      () async {
        for (final field in [
          'tenantId',
          'ownerUid',
          'status',
          'slug',
          'verificationStatus',
          'subscriptionId',
          'logo',
          'approvedBy',
        ]) {
          final r = await h.call(
            'PATCH',
            '/clinics/current',
            uid: 'owner',
            body: {field: 'x'},
          );
          expect(r.statusCode, 422, reason: field);
        }
        expect(h.store.docs['tenants/$tid']!['ownerUid'], 'owner');
      },
    );

    test(
      'validation: bad email, phone, PIN, type, website, empty patch',
      () async {
        Future<int> code(Map<String, Object?> b) async => (await h.call(
          'PATCH',
          '/clinics/current',
          uid: 'owner',
          body: b,
        )).statusCode;
        expect(await code({'email': 'nope'}), 422);
        expect(await code({'phone': '123'}), 422);
        expect(
          await code({
            'address': {'postalCode': '12'},
          }),
          422,
        );
        expect(await code({'type': 'astrology'}), 422);
        expect(await code({'website': 'ftp://x'}), 422);
        expect(await code({'specialities': List.filled(11, 'x')}), 422);
        expect(await code(<String, Object?>{}), 400);
      },
    );

    test(
      'users without clinic.update cannot edit; reading needs clinic.view',
      () async {
        h.member('rec', tid, 'receptionist');
        expect(
          (await h.call(
            'PATCH',
            '/clinics/current',
            uid: 'rec',
            body: {'name': 'Hacked Name'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call('GET', '/clinics/current', uid: 'rec')).statusCode,
          200,
        );
        h.member('doc', tid, 'doctor');
        expect(
          (await h.call(
            'PATCH',
            '/clinics/current',
            uid: 'doc',
            body: {'name': 'Hacked Name'},
          )).statusCode,
          403,
        );
      },
    );
  });

  group('settings and operating hours', () {
    test(
      'unconfigured by default: no assumed time zone, all days closed',
      () async {
        final s = await h.okData(
          h.call('GET', '/clinics/current/settings', uid: 'owner'),
        );
        expect(s['configured'], false);
        expect(s['timezone'], isNull);
        expect(((s['weeklyHours']! as Map)['1']! as Map)['open'], false);
      },
    );

    test(
      'saves explicit time zone, hours, breaks, holidays and special days',
      () async {
        final s = await h.okData(
          h.call(
            'PATCH',
            '/clinics/current/settings',
            uid: 'owner',
            body: {
              'timezone': 'Asia/Kolkata',
              'appointmentDurationMinutes': 20,
              'consultationDurationMinutes': 30,
              'weeklyHours': {
                '1': day('09:00', '17:00', [
                  {'from': '13:00', 'to': '14:00'},
                  {'from': '11:00', 'to': '11:15'},
                ]),
                '2': day('09:00', '17:00'),
                '6': day('10:00', '14:00'),
              },
              'holidays': [
                {'date': '2026-12-25', 'name': 'Christmas'},
              ],
              'specialDays': [
                {
                  'date': '2026-12-27',
                  'open': true,
                  'from': '10:00',
                  'to': '12:00',
                },
              ],
            },
          ),
        );
        expect(s['configured'], true);
        expect(s['timezone'], 'Asia/Kolkata');
        expect(
          ((s['weeklyHours']! as Map)['1']! as Map)['breaks'],
          hasLength(2),
        );
        expect(
          ((s['weeklyHours']! as Map)['3']! as Map)['open'],
          false,
          reason: 'missing days are closed',
        );
        expect(s['holidays'], hasLength(1));
        final again = await h.okData(
          h.call('GET', '/clinics/current/settings', uid: 'owner'),
        );
        expect(again['appointmentDurationMinutes'], 20);
      },
    );

    test('supports overnight operation', () async {
      final s = await h.okData(
        h.call(
          'PATCH',
          '/clinics/current/settings',
          uid: 'owner',
          body: {
            'weeklyHours': {
              '5': day('20:00', '06:00', [
                {'from': '01:00', 'to': '02:00'},
              ]),
            },
          },
        ),
      );
      final fri = (s['weeklyHours']! as Map)['5']! as Map;
      expect(fri['overnight'], true);
    });

    Future<Map<String, Object?>> bad(Map<String, Object?> body) async {
      final r = await h.call(
        'PATCH',
        '/clinics/current/settings',
        uid: 'owner',
        body: body,
      );
      expect(r.statusCode, 422, reason: '$body');
      return (jsonDecode(await r.readAsString()) as Map)
          .cast<String, Object?>();
    }

    test('rejects invalid and overlapping periods', () async {
      await bad({
        'weeklyHours': {'1': day('09:00', '09:00')},
      });
      await bad({
        'weeklyHours': {'1': day('25:00', '17:00')},
      });
      await bad({
        'weeklyHours': {'1': day('9:00', '17:00')},
      });
      await bad({
        'weeklyHours': {'8': day('09:00', '17:00')},
      });
      await bad({
        'weeklyHours': {
          '1': day('09:00', '17:00', [
            {'from': '08:00', 'to': '09:30'},
          ]),
        },
      }); // before opening
      await bad({
        'weeklyHours': {
          '1': day('09:00', '17:00', [
            {'from': '12:00', 'to': '14:00'},
            {'from': '13:00', 'to': '15:00'},
          ]),
        },
      }); // overlap
      await bad({
        'weeklyHours': {
          '1': day('09:00', '17:00', [
            {'from': '14:00', 'to': '13:00'},
          ]),
        },
      }); // reversed
      await bad({
        'weeklyHours': {
          '1': day(
            '09:00',
            '17:00',
            List.generate(6, (i) => {'from': '1${i}:00', 'to': '1$i:10'}),
          ),
        },
      }); // too many
      await bad({
        'weeklyHours': {
          '1': {'open': true, 'from': '09:00'},
        },
      });
    });

    test(
      'rejects bad zones, durations, dates and conflicting special days',
      () async {
        await bad({'timezone': 'India Standard Time'});
        await bad({'timezone': '../../etc/passwd'});
        await bad({'appointmentDurationMinutes': 2});
        await bad({'consultationDurationMinutes': 500});
        await bad({'currency': 'USD'});
        await bad({'language': 'xx'});
        await bad({
          'holidays': [
            {'date': '2026-02-30'},
          ],
        });
        await bad({
          'holidays': [
            {'date': '2026-12-25'},
            {'date': '2026-12-25'},
          ],
        });
        await bad({
          'holidays': [
            {'date': '2026-12-25'},
          ],
          'specialDays': [
            {
              'date': '2026-12-25',
              'open': true,
              'from': '10:00',
              'to': '12:00',
            },
          ],
        });
        await bad({
          'specialDays': [
            {'date': '2026-12-27', 'open': false},
          ],
        });
        await bad({'tenantId': 'other'});
      },
    );

    test(
      'holiday added later cannot collide with an existing special day',
      () async {
        await h.okData(
          h.call(
            'PATCH',
            '/clinics/current/settings',
            uid: 'owner',
            body: {
              'specialDays': [
                {
                  'date': '2026-12-27',
                  'open': true,
                  'from': '10:00',
                  'to': '12:00',
                },
              ],
            },
          ),
        );
        await bad({
          'holidays': [
            {'date': '2026-12-27'},
          ],
        });
      },
    );

    test(
      'receptionist and doctor cannot change settings; they can read',
      () async {
        h.member('rec', tid, 'receptionist');
        h.member('doc', tid, 'doctor');
        for (final u in ['rec', 'doc']) {
          expect(
            (await h.call(
              'PATCH',
              '/clinics/current/settings',
              uid: u,
              body: {'timezone': 'Asia/Kolkata'},
            )).statusCode,
            403,
            reason: u,
          );
          expect(
            (await h.call(
              'GET',
              '/clinics/current/settings',
              uid: u,
            )).statusCode,
            200,
          );
        }
      },
    );

    test('clinic admin may manage settings', () async {
      h.member('adm', tid, 'clinic_admin');
      expect(
        (await h.call(
          'PATCH',
          '/clinics/current/settings',
          uid: 'adm',
          body: {'timezone': 'Asia/Kolkata'},
        )).statusCode,
        200,
      );
    });
  });

  group('logo', () {
    Map<String, Object?> logo(List<int> bytes, [String type = 'image/png']) => {
      'contentType': type,
      'dataBase64': base64Encode(bytes),
    };

    test(
      'accepts a PNG, stores it under the tenant path and serves it back privately',
      () async {
        final bytes = pngBytes();
        final meta = await h.okData(
          h.call(
            'PUT',
            '/clinics/current/logo',
            uid: 'owner',
            body: logo(bytes),
          ),
        );
        expect(meta['path'], 'tenants/$tid/branding/clinic-logo/logo.png');
        expect(
          h.storage.objects.keys.single,
          'tenants/$tid/branding/clinic-logo/logo.png',
        );
        final r = await h.call('GET', '/clinics/current/logo', uid: 'owner');
        expect(r.statusCode, 200);
        expect(r.headers['content-type'], 'image/png');
        expect(r.headers['cache-control'], contains('no-store'));
        expect(await r.read().expand((c) => c).toList(), bytes);
        expect(
          h.store.docs.values.any((d) => d['action'] == 'clinic.logo_updated'),
          isTrue,
        );
      },
    );

    test(
      'rejects wrong type, spoofed content type, oversize, empty and non-base64',
      () async {
        Future<int> put(Map<String, Object?> b) async => (await h.call(
          'PUT',
          '/clinics/current/logo',
          uid: 'owner',
          body: b,
        )).statusCode;
        expect(
          await put(logo([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])),
          422,
          reason: 'not an image',
        );
        expect(
          await put(logo(pngBytes(), 'image/jpeg')),
          422,
          reason: 'declared type must match the bytes',
        );
        expect(await put(logo(pngBytes(600 * 1024))), 422, reason: 'too big');
        expect(
          await put({'contentType': 'image/png', 'dataBase64': '!!!'}),
          422,
        );
        expect(
          await put({
            'contentType': 'image/png',
            'dataBase64': '',
            'path': 'x',
          }),
          422,
        );
        expect(
          await put({
            ...logo(pngBytes()),
            'path': '../../other-tenant/logo.png',
          }),
          422,
          reason: 'clients cannot choose the path',
        );
        expect(h.storage.objects, isEmpty);
      },
    );

    test('only clinic.update holders can upload; no logo → 404', () async {
      h.member('rec', tid, 'receptionist');
      expect(
        (await h.call(
          'PUT',
          '/clinics/current/logo',
          uid: 'rec',
          body: logo(pngBytes()),
        )).statusCode,
        403,
      );
      expect(
        (await h.call('GET', '/clinics/current/logo', uid: 'owner')).statusCode,
        404,
      );
    });

    test('a clinic can only read its own logo', () async {
      await h.call(
        'PUT',
        '/clinics/current/logo',
        uid: 'owner',
        body: logo(pngBytes()),
      );
      final other = await h.createClinic(
        'owner2',
        name: 'Other Clinic',
        city: 'Mumbai',
        pin: '400001',
      );
      expect(
        (await h.call(
          'GET',
          '/clinics/current/logo',
          uid: 'owner2',
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'GET',
          '/clinics/current/logo',
          uid: 'owner2',
          headers: {'x-tenant-id': tid},
        )).statusCode,
        403,
      );
      expect(other, isNot(tid));
    });
  });

  group('tenant guard', () {
    test('no membership → 403; unauthenticated → 401', () async {
      h.user('nobody');
      expect(
        (await h.call('GET', '/clinics/current', uid: 'nobody')).statusCode,
        403,
      );
      expect((await h.call('GET', '/clinics/current')).statusCode, 401);
    });

    test(
      'suspended tenant is blocked for everyone, including the owner',
      () async {
        await h.call(
          'POST',
          '/platform/tenants/$tid/suspend',
          uid: 'root',
          body: {'reason': 'Policy review'},
        );
        final r = await h.call('GET', '/clinics/current', uid: 'owner');
        expect(r.statusCode, 403);
        expect(await errorCode(r), 'forbidden');
      },
    );

    test('past-due tenant is read-only', () async {
      final sid = h.store.docs['tenants/$tid']!['subscriptionId']! as String;
      await h.call(
        'POST',
        '/platform/subscriptions/$sid/mark-past-due',
        uid: 'root',
      );
      expect(
        (await h.call('GET', '/clinics/current', uid: 'owner')).statusCode,
        200,
      );
      expect(
        (await h.call(
          'PATCH',
          '/clinics/current',
          uid: 'owner',
          body: {'name': 'New Name'},
        )).statusCode,
        403,
      );
    });

    test('expired subscription blocks', () async {
      h.clock.now = h.clock.now.add(const Duration(days: 60));
      expect(
        (await h.call('GET', '/clinics/current', uid: 'owner')).statusCode,
        403,
      );
    });

    test('a deactivated membership grants nothing', () async {
      h.member('gone', tid, 'clinic_admin', status: 'deactivated');
      expect(
        (await h.call('GET', '/clinics/current', uid: 'gone')).statusCode,
        403,
      );
    });

    test('unknown role in the membership is denied', () async {
      h.member('weird', tid, 'wizard');
      expect(
        (await h.call('GET', '/clinics/current', uid: 'weird')).statusCode,
        403,
      );
    });

    test('cannot reach another clinic by header or query', () async {
      final b = await h.createClinic(
        'owner2',
        name: 'Other Clinic',
        city: 'Mumbai',
        pin: '400001',
      );
      expect(
        (await h.call(
          'GET',
          '/clinics/current',
          uid: 'owner',
          headers: {'x-tenant-id': b},
        )).statusCode,
        403,
      );
      final r = await h.okData(
        h.call('GET', '/clinics/current?tenantId=$b', uid: 'owner'),
      );
      expect(r['tenantId'], tid);
    });
  });
}
