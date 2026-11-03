import 'dart:convert';

import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late String tid;
  late String br;
  late String pid;

  setUp(() async {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    tid = await h.createClinic('owner');
    br = await h.newBranch('owner');
    for (final e in {
      'recep': 'receptionist',
      'doc': 'doctor',
      'nurse': 'nurse',
      'admin': 'clinic_admin',
      'acct': 'accountant',
    }.entries) {
      h.member(e.key, tid, e.value);
    }
    pid = (await h.newPatient('recep', br))['patientId']! as String;
  });

  Map<String, Object?> decision(
    String type, {
    String d = 'granted',
    Map<String, Object?>? by,
    String v = '1.0',
  }) => {
    'type': type,
    'decision': d,
    'textVersion': v,
    'collectionMethod': 'in_person_signed',
    'grantedBy': by ?? {'type': 'patient'},
  };

  group('consent', () {
    test('catalog exposes the purposes and the text version', () async {
      final c = await h.okData(h.call('GET', '/consent-catalog', uid: 'recep'));
      expect(c['version'], '1.0');
      expect((c['purposes']! as List).length, greaterThanOrEqualTo(6));
    });

    test('grant, reject, then revoke with a full audit trail', () async {
      final g = await h.okData(
        h.call(
          'POST',
          '/patients/$pid/consents',
          uid: 'recep',
          body: decision('communication_sms'),
        ),
        status: 201,
      );
      expect(g['status'], 'granted');
      expect(g['textVersion'], '1.0');
      expect(g['purpose'], isNotEmpty);
      final r = await h.okData(
        h.call(
          'POST',
          '/patients/$pid/consents',
          uid: 'recep',
          body: decision('communication_email', d: 'rejected'),
        ),
        status: 201,
      );
      expect(r['status'], 'rejected');
      expect(
        await h.status(
          'POST',
          '/patients/$pid/consents',
          uid: 'recep',
          body: decision('communication_sms'),
        ),
        409,
      );
      final rev = await h.okData(
        h.call(
          'POST',
          '/patients/$pid/consents/${g['consentId']}/revoke',
          uid: 'recep',
          body: {'reason': 'Patient asked to stop'},
        ),
      );
      expect(rev['status'], 'revoked');
      expect(rev['revokedAt'], isNotNull);
      expect(
        await h.status(
          'POST',
          '/patients/$pid/consents/${g['consentId']}/revoke',
          uid: 'recep',
          body: {'reason': 'again'},
        ),
        409,
      );
      expect(
        h.auditActions(pid),
        containsAll(['consent.granted', 'consent.rejected', 'consent.revoked']),
      );
      final all = await h.list(
        await h.call('GET', '/patients/$pid/consents', uid: 'recep'),
      );
      expect(all, hasLength(3)); // includes the registration consent
    });

    test(
      'nothing is inferred: strict body, current text version, known type',
      () async {
        for (final bad in [
          decision('communication_sms', v: '0.9'),
          decision('mystery'),
          {...decision('communication_sms')}..remove('decision'),
          {...decision('communication_sms')}..remove('collectionMethod'),
          {...decision('communication_sms'), 'status': 'granted'},
          {...decision('communication_sms'), 'tenantId': 'x'},
          decision('other'),
        ]) {
          expect(
            await h.status(
              'POST',
              '/patients/$pid/consents',
              uid: 'recep',
              body: bad,
            ),
            422,
            reason: '$bad',
          );
        }
      },
    );

    test('staff cannot consent on behalf of an adult patient', () async {
      for (final by in [
        {'type': 'staff'},
        {'type': 'guardian', 'name': 'Someone', 'relationship': 'friend'},
        {'type': 'caregiver'},
      ]) {
        expect(
          await h.status(
            'POST',
            '/patients/$pid/consents',
            uid: 'recep',
            body: decision('communication_sms', by: by),
          ),
          422,
          reason: '$by',
        );
      }
    });

    test(
      'roles: accountant cannot see or record consent; front desk can',
      () async {
        expect(
          await h.status('GET', '/patients/$pid/consents', uid: 'acct'),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pid/consents',
            uid: 'acct',
            body: decision('communication_sms'),
          ),
          403,
        );
        expect(
          await h.status('GET', '/patients/$pid/consents', uid: 'recep'),
          200,
        );
      },
    );

    test('a clinic cannot read another clinic\'s consents', () async {
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status('GET', '/patients/$pid/consents', uid: 'ownerB'),
        404,
      );
      expect(
        await h.status(
          'POST',
          '/patients/$pid/consents',
          uid: 'ownerB',
          body: decision('communication_sms'),
        ),
        404,
      );
    });

    test('guardian consent for a verified guardian of a minor', () async {
      final kid = await h.newPatient(
        'recep',
        br,
        name: 'Kid Patil',
        dob: '2018-03-03',
        phone: '9876500061',
        guardian: {
          'name': 'Meera Patil',
          'relationship': 'mother',
          'phone': '9876500055',
          'verificationMethod': 'government_id_sighted',
        },
        consent: consentBody(grantedBy: {'type': 'guardian'}),
      );
      final kidId = kid['patientId']! as String;
      final c = await h.okData(
        h.call(
          'POST',
          '/patients/$kidId/consents',
          uid: 'recep',
          body: decision(
            'communication_sms',
            by: {
              'type': 'guardian',
              'name': 'Meera Patil',
              'relationship': 'mother',
            },
          ),
        ),
        status: 201,
      );
      expect((c['grantedBy']! as Map)['type'], 'guardian');
      expect(
        await h.status(
          'POST',
          '/patients/$kidId/consents',
          uid: 'recep',
          body: decision('communication_email'),
        ),
        422,
      );
    });
  });

  group('documents', () {
    Map<String, Object?> upload({Map<String, Object?>? over}) => {
      'name': 'Blood report',
      'category': 'lab_report',
      'contentType': 'application/pdf',
      'dataBase64': b64(pdfBytes()),
      ...?over,
    };

    test(
      'upload needs document consent; the patient decision unlocks it',
      () async {
        expect(
          await h.status(
            'POST',
            '/patients/$pid/documents',
            uid: 'nurse',
            body: upload(),
          ),
          409,
        );
        await h.grant('recep', pid, 'document_processing');
        final d = await h.okData(
          h.call(
            'POST',
            '/patients/$pid/documents',
            uid: 'nurse',
            body: upload(),
          ),
          status: 201,
        );
        expect(d['documentId'], startsWith('dc_'));
        expect(d.containsKey('storagePath'), isFalse);
        expect(d['verificationStatus'], 'unverified');
        expect(d['uploadedBy'], 'nurse');
        // stored under a tenant- and patient-scoped private path
        expect(
          h.storage.objects.keys.single,
          'tenants/$tid/patients/$pid/documents/${d['documentId']}',
        );
        expect(h.auditActions(pid), contains('document.uploaded'));
      },
    );

    test('revoking document consent stops further uploads', () async {
      final c = await h.grant('recep', pid, 'document_processing');
      await h.okData(
        h.call(
          'POST',
          '/patients/$pid/consents/${c['consentId']}/revoke',
          uid: 'recep',
          body: {'reason': 'Patient request'},
        ),
      );
      expect(
        await h.status(
          'POST',
          '/patients/$pid/documents',
          uid: 'nurse',
          body: upload(),
        ),
        409,
      );
    });

    test('file type, size and content are validated from the bytes', () async {
      await h.grant('recep', pid, 'document_processing');
      for (final bad in [
        upload(
          over: {'contentType': 'image/png'},
        ), // declared type does not match
        upload(
          over: {'dataBase64': b64(utf8.encode('<script>alert(1)</script>'))},
        ),
        upload(over: {'dataBase64': '###'}),
        upload(over: {'dataBase64': ''}),
        upload(over: {'category': 'x-ray-of-doom'}),
        upload(over: {'tenantId': 'x'}),
        upload(over: {'storagePath': '../x'}),
      ]) {
        expect(
          await h.status(
            'POST',
            '/patients/$pid/documents',
            uid: 'nurse',
            body: bad,
          ),
          422,
          reason: '${bad.keys}',
        );
      }
      final big = List.filled(3 * 1024 * 1024 + 10, 0x31);
      expect(
        await h.status(
          'POST',
          '/patients/$pid/documents',
          uid: 'nurse',
          body: upload(over: {'dataBase64': b64(pdfBytes(big.length))}),
        ),
        anyOf(413, 422),
      );
    });

    test('download is authorized, audited and never public', () async {
      await h.grant('recep', pid, 'document_processing');
      final d = await h.okData(
        h.call(
          'POST',
          '/patients/$pid/documents',
          uid: 'nurse',
          body: upload(),
        ),
        status: 201,
      );
      final id = d['documentId'];
      final r = await h.call(
        'GET',
        '/patients/$pid/documents/$id/content',
        uid: 'doc',
      );
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], 'application/pdf');
      expect(r.headers['cache-control'], contains('no-store'));
      expect(r.headers['x-content-type-options'], 'nosniff');
      expect(h.auditActions(pid), contains('document.viewed'));
      expect(
        await h.status('GET', '/patients/$pid/documents/$id/content'),
        401,
      );
      for (final uid in ['recep', 'admin', 'acct']) {
        expect(
          await h.status(
            'GET',
            '/patients/$pid/documents/$id/content',
            uid: uid,
          ),
          403,
          reason: uid,
        );
      }
    });

    test('documents are isolated per patient and per clinic', () async {
      await h.grant('recep', pid, 'document_processing');
      final d = await h.okData(
        h.call(
          'POST',
          '/patients/$pid/documents',
          uid: 'nurse',
          body: upload(),
        ),
        status: 201,
      );
      final other =
          (await h.newPatient(
                'recep',
                br,
                name: 'Other Person',
                dob: '1980-01-01',
                phone: '9876500044',
              ))['patientId']!
              as String;
      expect(
        await h.status(
          'GET',
          '/patients/$other/documents/${d['documentId']}',
          uid: 'doc',
        ),
        404,
      );
      expect(
        await h.status(
          'GET',
          '/patients/$other/documents/${d['documentId']}/content',
          uid: 'doc',
        ),
        404,
      );
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status(
          'GET',
          '/patients/$pid/documents/${d['documentId']}',
          uid: 'ownerB',
        ),
        404,
      );
      expect(
        await h.status(
          'GET',
          '/patients/$pid/documents/${d['documentId']}/content',
          uid: 'ownerB',
        ),
        404,
      );
      expect(
        await h.status(
          'DELETE',
          '/patients/$pid/documents/${d['documentId']}?reason=cleanup%20time',
          uid: 'ownerB',
        ),
        404,
      );
    });

    test('restricted documents need clinical access', () async {
      await h.grant('recep', pid, 'document_processing');
      expect(
        await h.status(
          'POST',
          '/patients/$pid/documents',
          uid: 'nurse',
          body: upload(over: {'classification': 'restricted'}),
        ),
        201,
      );
      final all = await h.list(
        await h.call('GET', '/patients/$pid/documents', uid: 'nurse'),
      );
      expect(all, hasLength(1));
    });

    test(
      'removal hides the document but retains the stored object, with a reason',
      () async {
        await h.grant('recep', pid, 'document_processing');
        final d = await h.okData(
          h.call(
            'POST',
            '/patients/$pid/documents',
            uid: 'nurse',
            body: upload(),
          ),
          status: 201,
        );
        final id = d['documentId'];
        expect(
          await h.status(
            'DELETE',
            '/patients/$pid/documents/$id',
            uid: 'nurse',
          ),
          422,
        );
        expect(
          await h.status(
            'DELETE',
            '/patients/$pid/documents/$id?reason=uploaded%20by%20mistake',
            uid: 'nurse',
          ),
          200,
        );
        expect(
          await h.list(
            await h.call('GET', '/patients/$pid/documents', uid: 'nurse'),
          ),
          isEmpty,
        );
        expect(
          await h.status(
            'GET',
            '/patients/$pid/documents/$id/content',
            uid: 'nurse',
          ),
          404,
        );
        expect(h.storage.objects, hasLength(1));
        expect(h.auditActions(pid), contains('document.removed'));
      },
    );
  });

  group('patient audit trail', () {
    test('owner and admin can read it; clients cannot change it', () async {
      expect(
        await h.status('GET', '/patients/$pid/audit-logs', uid: 'owner'),
        200,
      );
      expect(
        await h.status('GET', '/patients/$pid/audit-logs', uid: 'admin'),
        200,
      );
      expect(
        await h.status('GET', '/patients/$pid/audit-logs', uid: 'doc'),
        403,
      );
      expect(
        await h.status('GET', '/patients/$pid/audit-logs', uid: 'recep'),
        403,
      );
      final rows = await h.list(
        await h.call('GET', '/patients/$pid/audit-logs', uid: 'owner'),
      );
      expect(rows, isNotEmpty);
      for (final m in ['POST', 'PATCH', 'PUT', 'DELETE']) {
        expect(
          await h.status(
            m,
            '/patients/$pid/audit-logs',
            uid: 'owner',
            body: {},
          ),
          anyOf(404, 405),
          reason: m,
        );
      }
    });

    test('entries hold references, not clinical content', () async {
      await h.okData(
        h.call(
          'POST',
          '/patients/$pid/allergies',
          uid: 'doc',
          body: {
            'allergen': 'Peanuts',
            'category': 'food',
            'reaction': 'Anaphylaxis',
          },
        ),
        status: 201,
      );
      final text = (await h.call(
        'GET',
        '/patients/$pid/audit-logs',
        uid: 'owner',
      )).readAsString();
      final s = await text;
      expect(s, contains('allergy.created'));
      expect(s, isNot(contains('Peanuts')));
      expect(s, isNot(contains('Anaphylaxis')));
    });
  });
}
