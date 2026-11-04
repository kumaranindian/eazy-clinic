import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/portal_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

const _token = 'fcm-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late PlatformHarness h;
  late PortalClinic p;

  setUp(() async {
    h = PlatformHarness();
    p = PortalClinic(h);
    await p.init();
  });

  Future<List<Map<String, Object?>>> inbox({String uid = 'asha'}) async =>
      ((await p.get('/patient/notifications', uid: uid))['items']! as List)
          .cast<Map<String, Object?>>();

  group('devices', () {
    test(
      'register, refresh and unregister a device for the signed-in user',
      () async {
        final r = await h.okData(
          h.call(
            'POST',
            '/patient/devices',
            uid: 'asha',
            body: {
              'deviceId': 'device-0001',
              'token': _token,
              'platform': 'android',
              'appVersion': '1.0.0',
            },
          ),
          status: 201,
        );
        expect(r['registered'], true);
        expect(
          r.containsKey('token'),
          isFalse,
          reason: 'a token is never returned',
        );
        // refresh with a new token for the same device
        await h.okData(
          h.call(
            'POST',
            '/patient/devices',
            uid: 'asha',
            body: {
              'deviceId': 'device-0001',
              'token': '${_token}2',
              'platform': 'android',
            },
          ),
          status: 201,
        );
        expect(
          h.docsOf('patient_devices').where((d) => d['active'] == true),
          hasLength(2),
        );
        await h.okData(
          h.call('DELETE', '/patient/devices/device-0001', uid: 'asha'),
        );
        expect(
          h.docsOf('patient_devices').where((d) => d['active'] == true),
          isEmpty,
        );
      },
    );

    test(
      'a token moves to the latest user, and nobody can deactivate another user\'s device',
      () async {
        await h.okData(
          h.call(
            'POST',
            '/patient/devices',
            uid: 'asha',
            body: {
              'deviceId': 'device-0001',
              'token': _token,
              'platform': 'android',
            },
          ),
          status: 201,
        );
        await p.createAccount('ravi');
        await h.okData(
          h.call(
            'POST',
            '/patient/devices',
            uid: 'ravi',
            body: {
              'deviceId': 'device-0009',
              'token': _token,
              'platform': 'android',
            },
          ),
          status: 201,
        );
        final doc = h.docsOf('patient_devices').single;
        expect(doc['uid'], 'ravi');
        await h.okData(
          h.call('DELETE', '/patient/devices/device-0001', uid: 'asha'),
        );
        expect(
          h.docsOf('patient_devices').single['active'],
          true,
          reason: 'asha cannot touch ravi\'s device',
        );
      },
    );

    test('input is validated and needs an account', () async {
      Future<int> reg(Map<String, Object?> b, {String uid = 'asha'}) =>
          p.status('POST', '/patient/devices', uid: uid, body: b);
      expect(
        await reg({'deviceId': 'x', 'token': _token, 'platform': 'android'}),
        422,
      );
      expect(
        await reg({
          'deviceId': 'device-0001',
          'token': 'short',
          'platform': 'android',
        }),
        422,
      );
      expect(
        await reg({
          'deviceId': 'device-0001',
          'token': _token,
          'platform': 'ios',
        }),
        422,
      );
      expect(
        await reg({
          'deviceId': 'device-0001',
          'token': _token,
          'platform': 'android',
          'uid': 'someone',
        }),
        422,
      );
      h.user('nobody');
      expect(
        await reg({
          'deviceId': 'device-0001',
          'token': _token,
          'platform': 'android',
        }, uid: 'nobody'),
        anyOf(403, 404),
      );
    });
  });

  group('inbox', () {
    test(
      'events create generic notifications for the right account, once',
      () async {
        final a = await p.book();
        expect(
          (await inbox()).map((n) => n['category']),
          contains('appointment_booked'),
        );
        final n = (await inbox()).single;
        expect(n['resourceType'], 'appointment');
        expect(n['resourceId'], a['appointmentId']);
        expect(n['read'], false);
        // a repeat of the same booking does not add a second entry
        await h.call(
          'POST',
          '/patient/appointments',
          uid: 'asha',
          headers: {'idempotency-key': 'key-book-0001'},
          body: p.bookBody(time: '09:30'),
        );
        await h.call(
          'POST',
          '/patient/appointments',
          uid: 'asha',
          headers: {'idempotency-key': 'key-book-0001'},
          body: p.bookBody(time: '09:30'),
        );
        expect(
          (await inbox()).where((n) => n['category'] == 'appointment_booked'),
          hasLength(2),
        );
        await h.okData(
          h.call(
            'POST',
            '/patient/clinics/${p.tid}/appointments/${a['appointmentId']}/cancel',
            uid: 'asha',
            body: {},
          ),
        );
        await h.okData(
          h.call(
            'POST',
            '/patient/clinics/${p.tid}/appointments/${a['appointmentId']}/cancel',
            uid: 'asha',
            body: {},
          ),
        );
        expect(
          (await inbox()).where(
            (n) => n['category'] == 'appointment_cancelled',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'clinical and billing events reach the patient without sensitive text',
      () async {
        final cid = await p.k.readyConsultation();
        final rx = await p.k.newRx(cid);
        await h.actOk(
          'docuser',
          '/prescriptions/${rx['prescriptionId']}/finalize',
        );
        await h.actOk('docuser', '/consultations/$cid/finalize');
        await h.actOk('docuser', '/consultations/$cid/release');
        final inv = await p.invoice(amount: 250000);
        await p.pay(inv['invoiceId']! as String, 250000);
        final cats = (await inbox()).map((n) => n['category']).toSet();
        expect(
          cats,
          containsAll([
            'summary_available',
            'prescription_available',
            'invoice_generated',
            'payment_received',
          ]),
        );
        final text = (await inbox())
            .map((n) => '${n['title']} ${n['body']}')
            .join(' ')
            .toLowerCase();
        for (final secret in [
          'fever',
          'paracetamol',
          'viral',
          '2500',
          '₹',
          'diagnosis:',
          'mg',
        ]) {
          expect(text, isNot(contains(secret)), reason: secret);
        }
      },
    );

    test(
      'only the owner can read or mark a notification, and not for unlinked records',
      () async {
        await p.book();
        final id = (await inbox()).single['notificationId']! as String;
        await p.createAccount('mallory');
        expect(await inbox(uid: 'mallory'), isEmpty);
        expect(
          await p.status(
            'POST',
            '/patient/notifications/$id/read',
            uid: 'mallory',
            body: {},
          ),
          404,
        );
        await h.okData(
          h.call(
            'POST',
            '/patient/notifications/$id/read',
            uid: 'asha',
            body: {},
          ),
        );
        final data = await p.get('/patient/notifications');
        expect(data['unread'], 0);
        // events about an unlinked clinic record notify nobody
        final lone =
            (await h.okData(
                  h.call(
                    'POST',
                    '/patients',
                    uid: 'recep',
                    body: patientBody(
                      p.br,
                      name: 'No App',
                      dob: '1975-05-05',
                      phone: '9876500999',
                    ),
                  ),
                  status: 201,
                ))['patientId']!
                as String;
        final inv = await h.okData(
          h.call(
            'POST',
            '/billing/invoices',
            uid: 'recep',
            body: {
              'patientId': lone,
              'branchId': p.br,
              'lines': [
                {'description': 'Item', 'unitMinor': 100, 'quantity': 1},
              ],
            },
          ),
          status: 201,
        );
        await h.okData(
          h.call(
            'POST',
            '/billing/invoices/${inv['invoiceId']}/finalize',
            uid: 'recep',
          ),
        );
        expect(
          h
              .docsOf('patient_notifications')
              .where((n) => n['category'] == 'invoice_generated'),
          isEmpty,
        );
      },
    );

    test('preferences are per account and validated', () async {
      final d = await p.get('/patient/notifications/preferences');
      expect(d['pushEnabled'], true);
      expect((d['categories']! as Map)['appointment_reminder'], true);
      final u = await h.okData(
        h.call(
          'PUT',
          '/patient/notifications/preferences',
          uid: 'asha',
          body: {
            'pushEnabled': false,
            'categories': {'clinic_announcement': false},
          },
        ),
      );
      expect(u['pushEnabled'], false);
      expect((u['categories']! as Map)['clinic_announcement'], false);
      expect((u['categories']! as Map)['payment_received'], true);
      await p.createAccount('other');
      expect(
        (await p.get(
          '/patient/notifications/preferences',
          uid: 'other',
        ))['pushEnabled'],
        true,
      );
      expect(
        await p.status(
          'PUT',
          '/patient/notifications/preferences',
          body: {
            'categories': {'not_a_category': true},
          },
        ),
        422,
      );
      expect(
        await p.status(
          'PUT',
          '/patient/notifications/preferences',
          body: {'accountId': 'pa_x'},
        ),
        422,
      );
    });
  });

  group('profile', () {
    test(
      'shows completion and linked clinics; edits only low-risk fields',
      () async {
        final d = await p.get('/patient/profile');
        expect(d['accountId'], p.accountId);
        expect(d.containsKey('uid'), isFalse);
        expect((d['linkedClinics']! as List), hasLength(1));
        expect(
          d['profileMissing'],
          containsAll(['address', 'emergencyContact']),
        );
        final u = await h.okData(
          h.call(
            'PATCH',
            '/patient/profile',
            uid: 'asha',
            body: {
              'preferredLanguage': 'hi',
              'address': {
                'line1': '12 Main Road',
                'city': 'Pune',
                'postalCode': '411001',
              },
              'emergencyContact': {
                'name': 'Ravi Patil',
                'phone': '9876500777',
                'relationship': 'spouse',
              },
            },
          ),
        );
        expect(u['preferredLanguage'], 'hi');
        expect((u['profileMissing']! as List), isNot(contains('address')));
        expect(
          u['profileCompletion'],
          greaterThan(d['profileCompletion'] as int),
        );
        // the clinic's record is not touched by a profile edit
        expect(
          h.store.docs['tenants/${p.tid}/patients/${p.patientId}']!['phone'],
          isNot('9876500777'),
        );
      },
    );

    test('identity fields and server fields cannot be edited here', () async {
      for (final f in [
        {'displayName': 'Someone Else'},
        {'dateOfBirth': '1970-01-01'},
        {'phone': '9876500000'},
        {'email': 'x@y.test'},
        {'status': 'verified'},
        {'accountId': 'pa_x'},
        {'kind': 'dependent'},
        {'preferredLanguage': 'xx'},
      ]) {
        expect(
          await p.status('PATCH', '/patient/profile', body: f),
          422,
          reason: '$f',
        );
      }
    });

    test(
      'a deletion request is recorded, repeated safely, and deletes nothing',
      () async {
        final r = await h.okData(
          h.call(
            'POST',
            '/patient/account/deletion-request',
            uid: 'asha',
            body: {'reason': 'No longer needed'},
          ),
          status: 201,
        );
        expect(r['status'], 'pending');
        final again = await h.okData(
          h.call(
            'POST',
            '/patient/account/deletion-request',
            uid: 'asha',
            body: {},
          ),
          status: 201,
        );
        expect(again['idempotentReplay'], true);
        expect(h.docsOf('account_deletion_requests'), hasLength(1));
        expect(h.docsOf('patient_accounts'), isNotEmpty);
        expect(
          h.store.docs['tenants/${p.tid}/patients/${p.patientId}'],
          isNotNull,
          reason: 'clinic record retained',
        );
        expect(
          (await p.get('/patient/profile'))['deletionRequest'],
          containsPair('status', 'pending'),
        );
      },
    );
  });

  group('consent', () {
    test(
      'the catalogue is versioned; decisions are recorded and can be withdrawn',
      () async {
        final cat = await p.get('/patient/consent-catalog');
        expect(cat['version'], isNotNull);
        expect((cat['purposes']! as List), isNotEmpty);
        final before = (await p.list(
          '/patient/clinics/${p.tid}/consents',
        )).length;
        final c = await h.okData(
          h.call(
            'POST',
            '/patient/consents',
            uid: 'asha',
            body: {
              'clinicId': p.tid,
              'type': 'record_sharing',
              'decision': 'granted',
              'textVersion': cat['version'],
            },
          ),
          status: 201,
        );
        expect(c['status'], 'granted');
        final list = await p.list('/patient/clinics/${p.tid}/consents');
        expect(list.length, before + 1);
        // the same grant twice is refused rather than duplicated
        expect(
          await p.status(
            'POST',
            '/patient/consents',
            body: {
              'clinicId': p.tid,
              'type': 'record_sharing',
              'decision': 'granted',
              'textVersion': cat['version'],
            },
          ),
          409,
        );
        final w = await h.okData(
          h.call(
            'POST',
            '/patient/clinics/${p.tid}/consents/${c['consentId']}/revoke',
            uid: 'asha',
            body: {'reason': 'Changed my mind'},
          ),
        );
        expect(w['status'], 'revoked');
        // history keeps both facts
        expect(
          (await p.list('/patient/clinics/${p.tid}/consents')).length,
          before + 1,
        );
      },
    );

    test(
      'an outdated text version, unknown purpose or other person\'s consent is refused',
      () async {
        expect(
          await p.status(
            'POST',
            '/patient/consents',
            body: {
              'clinicId': p.tid,
              'type': 'record_sharing',
              'decision': 'granted',
              'textVersion': '0.1',
            },
          ),
          422,
        );
        expect(
          await p.status(
            'POST',
            '/patient/consents',
            body: {
              'clinicId': p.tid,
              'type': 'sell_my_data',
              'decision': 'granted',
              'textVersion': '1.0',
            },
          ),
          422,
        );
        final c = await h.okData(
          h.call(
            'POST',
            '/patient/consents',
            uid: 'asha',
            body: {
              'clinicId': p.tid,
              'type': 'record_sharing',
              'decision': 'granted',
              'textVersion': '1.0',
            },
          ),
          status: 201,
        );
        await p.createAccount('mallory');
        expect(
          await p.status(
            'POST',
            '/patient/clinics/${p.tid}/consents/${c['consentId']}/revoke',
            uid: 'mallory',
            body: {},
          ),
          404,
        );
        expect(
          await p.status(
            'POST',
            '/patient/consents',
            uid: 'mallory',
            body: {
              'clinicId': p.tid,
              'type': 'record_sharing',
              'decision': 'granted',
              'textVersion': '1.0',
            },
          ),
          404,
        );
        expect(
          await p.status(
            'GET',
            '/patient/clinics/${p.tid}/consents',
            uid: 'mallory',
          ),
          404,
        );
      },
    );
  });

  group('family', () {
    test('lists people with names only, and who may act for whom', () async {
      await p.createAccount('ravi', name: 'Ravi Patil');
      final rel = await h.okData(
        h.call(
          'POST',
          '/patient-accounts/me/family',
          uid: 'ravi',
          body: {
            'relationshipType': 'caregiver',
            'subjectAccountId': p.accountId,
            'permissionScope': ['manage_appointments'],
          },
        ),
        status: 201,
      );
      final pending =
          (await p.list('/patient/family', uid: 'ravi')).single! as Map;
      expect(pending['canActFor'], false, reason: 'not verified yet');
      expect(pending['direction'], 'i_manage');
      await h.okData(
        h.call(
          'POST',
          '/family-relationships/${rel['relationshipId']}/verify',
          uid: 'asha',
          body: {'decision': 'approve'},
        ),
      );
      final live =
          (await p.list('/patient/family', uid: 'ravi')).single! as Map;
      expect(live['canActFor'], true);
      expect(live['otherAccountId'], p.accountId);
      final theirs =
          (await p.list('/patient/family', uid: 'asha')).single! as Map;
      expect(theirs['direction'], 'manages_me');
      expect(theirs['canActFor'], false);
      expect(theirs['otherName'], 'Ravi Patil');
      for (final leak in ['uid', 'email', 'phone', 'dateOfBirth']) {
        expect(theirs.containsKey(leak), isFalse, reason: leak);
      }
      await p.createAccount('mallory');
      expect(await p.list('/patient/family', uid: 'mallory'), isEmpty);
    });
  });

  group('security regressions', () {
    test(
      'nothing in the portal accepts a patient, tenant or role chosen by the client',
      () async {
        for (final f in [
          'tenantId',
          'patientId',
          'role',
          'status',
          'permissions',
        ]) {
          expect(
            await p.status(
              'POST',
              '/patient/appointments',
              body: {...p.bookBody(), f: 'x'},
              headers: {'idempotency-key': p.key()},
            ),
            422,
            reason: f,
          );
        }
        expect(
          await p.status(
            'POST',
            '/patient/consents',
            body: {
              'clinicId': p.tid,
              'type': 'record_sharing',
              'decision': 'granted',
              'textVersion': '1.0',
              'patientId': 'pt_other',
            },
          ),
          422,
        );
      },
    );

    test('an invalid token is refused everywhere', () async {
      final res = await h.call(
        'GET',
        '/patient/appointments',
        headers: {'authorization': 'Bearer not-a-token'},
      );
      expect(res.statusCode, 401);
    });

    test(
      'a clinic that turns the patient app off disappears for linked patients too',
      () async {
        final a = await p.book();
        expect(a['status'], 'pending');
        // patient_mobile_app removed from the clinic's plan
        for (final d in h.store.docs.entries) {
          if (d.key.startsWith('platform_subscriptions/') &&
              d.value['features'] != null) {
            (d.value['features']! as Map)['patient_mobile_app'] = false;
          }
        }
        expect(
          await p.status(
            'POST',
            '/patient/appointments',
            body: p.bookBody(time: '09:30'),
            headers: {'idempotency-key': p.key()},
          ),
          anyOf(403, 404),
        );
        expect(
          await p.status(
            'GET',
            '/patient/clinics/${p.tid}/availability?branchId=${p.br}&doctorId=${p.doctor}&date=$tuesday',
          ),
          anyOf(403, 404),
        );
        expect(await p.list('/patient/clinics'), isEmpty);
      },
    );
  });
}
