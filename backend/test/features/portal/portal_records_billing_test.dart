import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/portal_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late PortalClinic p;

  setUp(() async {
    h = PlatformHarness();
    p = PortalClinic(h);
    await p.init();
  });

  Future<String> otherPatient({
    String uid = 'ravi',
    String name = 'Ravi Kumar',
    String phone = '9876500123',
  }) async {
    await p.createAccount(uid);
    final pid =
        (await h.okData(
              h.call(
                'POST',
                '/patients',
                uid: 'recep',
                body: patientBody(
                  p.br,
                  name: name,
                  dob: '1985-02-02',
                  phone: phone,
                ),
              ),
              status: 201,
            ))['patientId']!
            as String;
    await p.link(uid, pid);
    return pid;
  }

  group('medical overview', () {
    test(
      'shows the patient\'s own allergies, history and medicines — allow-listed',
      () async {
        await h.okData(
          h.call(
            'POST',
            '/patients/${p.patientId}/allergies',
            uid: 'docuser',
            body: {
              'allergen': 'Penicillin',
              'category': 'drug',
              'reaction': 'Rash',
              'severity': 'severe',
            },
          ),
          status: 201,
        );
        await h.okData(
          h.call(
            'POST',
            '/patients/${p.patientId}/medical-history',
            uid: 'docuser',
            body: {
              'category': 'surgery',
              'title': 'Appendectomy',
              'notes': 'clinic-only remark',
            },
          ),
          status: 201,
        );
        await h.okData(
          h.call(
            'POST',
            '/patients/${p.patientId}/medications',
            uid: 'docuser',
            body: {
              'name': 'Metformin',
              'dosage': '500 mg',
              'status': 'current',
            },
          ),
          status: 201,
        );
        final o = await p.list('/patient/medical-records');
        expect(o, hasLength(1));
        final m = o.single! as Map;
        expect(m['clinicId'], p.tid);
        expect(
          (m['allergies']! as List).single,
          containsPair('allergen', 'Penicillin'),
        );
        expect(
          (m['history']! as List).single,
          containsPair('title', 'Appendectomy'),
        );
        expect(
          (m['medications']! as List).single,
          containsPair('name', 'Metformin'),
        );
        final text = m.toString();
        expect(text, isNot(contains('clinic-only remark')));
        expect(text, isNot(contains('restrictedNotes')));
        expect(
          h.docsOf('patient_audit_logs').map((d) => d['action']),
          contains('portal.records_viewed'),
        );
      },
    );

    test(
      'another patient never sees it, and ids in the query cannot widen access',
      () async {
        await h.okData(
          h.call(
            'POST',
            '/patients/${p.patientId}/allergies',
            uid: 'docuser',
            body: {'allergen': 'Penicillin', 'category': 'drug'},
          ),
          status: 201,
        );
        await otherPatient();
        final o = await p.list('/patient/medical-records', uid: 'ravi');
        expect((o.single! as Map)['allergies'], isEmpty);
        expect(
          await p.status(
            'GET',
            '/patient/medical-records?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          404,
        );
        expect(
          await p.status('GET', '/patient/medical-records?clinicId=ten_other'),
          200,
        );
        expect(
          await p.list('/patient/medical-records?clinicId=ten_other'),
          isEmpty,
        );
      },
    );

    test('documents and reports are honestly unavailable', () async {
      final d = await p.get('/patient/documents');
      expect(d['available'], false);
      expect(d['documents'], isEmpty);
      expect((await p.get('/patient/reports'))['available'], false);
    });
  });

  group('consultation summaries', () {
    test(
      'only released, finalized summaries appear, without clinician notes',
      () async {
        final draft = await p.k.readyConsultation();
        expect(
          await p.list('/patient/consultations'),
          isEmpty,
          reason: 'draft',
        );
        await h.actOk('docuser', '/consultations/$draft/finalize');
        expect(
          await p.list('/patient/consultations'),
          isEmpty,
          reason: 'finalized but not released',
        );
        // a doctor who is not the author cannot release it
        expect(
          await p.status(
            'POST',
            '/consultations/$draft/release',
            uid: 'doc2user',
            body: {},
          ),
          404,
        );
        expect(
          await p.status(
            'POST',
            '/consultations/$draft/release',
            uid: 'recep',
            body: {},
          ),
          403,
        );
        await h.actOk('docuser', '/consultations/$draft/release');
        final list = await p.list('/patient/consultations');
        expect(list, hasLength(1));
        final c = list.single! as Map;
        expect(c['doctorName'], isNotNull);
        expect(
          (c['diagnoses']! as List).single,
          containsPair('label', 'Viral fever'),
        );
        final text = c.toString();
        for (final hidden in [
          'observations',
          'assessment',
          'chiefComplaint',
          'Fever for three days',
          'createdBy',
          'version',
        ]) {
          expect(text, isNot(contains(hidden)), reason: hidden);
        }
        // released again is a replay; withdrawing hides it again
        expect(
          (await h.actOk(
            'docuser',
            '/consultations/$draft/release',
          ))['idempotentReplay'],
          true,
        );
        await h.actOk('docuser', '/consultations/$draft/unrelease');
        expect(await p.list('/patient/consultations'), isEmpty);
      },
    );

    test('a consultation still in progress cannot be released', () async {
      final cid = (await p.k.newConsultation())['consultationId']! as String;
      expect(
        await p.status(
          'POST',
          '/consultations/$cid/release',
          uid: 'docuser',
          body: {},
        ),
        409,
      );
    });

    test('another patient\'s summaries are not visible', () async {
      await p.releasedConsultation();
      await otherPatient();
      expect(await p.list('/patient/consultations', uid: 'ravi'), isEmpty);
      expect(
        await p.status(
          'GET',
          '/patient/consultations?accountId=${p.accountId}',
          uid: 'ravi',
        ),
        404,
      );
    });
  });

  group('prescriptions', () {
    test(
      'finalized prescriptions are read-only, current vs superseded, with their disclaimer',
      () async {
        final cid = await p.k.readyConsultation();
        final rx = await p.k.newRx(cid);
        final id = rx['prescriptionId']! as String;
        expect(
          await p.list('/patient/prescriptions'),
          isEmpty,
          reason: 'draft is not visible',
        );
        await h.actOk('docuser', '/prescriptions/$id/finalize');
        final list = await p.list('/patient/prescriptions');
        final r = list.single! as Map;
        expect(r['number'], startsWith('RX-'));
        expect(r['current'], true);
        expect(r['superseded'], false);
        final med = (r['medicines']! as List).single as Map;
        expect(med['name'], 'Paracetamol');
        expect(med['dosage'], '1 tablet');
        expect(med['frequency'], 'three times a day');
        expect(r['disclaimer'], contains('Follow your doctor'));
        for (final hidden in [
          'finalizedBy',
          'createdBy',
          'rev',
          'consultationId',
          'catalogueId',
        ]) {
          expect(r.toString(), isNot(contains(hidden)), reason: hidden);
        }
        // the patient has no way to change it
        for (final m in ['PATCH', 'PUT', 'DELETE', 'POST']) {
          expect(
            await p.status(m, '/patient/prescriptions', body: {}),
            anyOf(404, 405),
            reason: m,
          );
        }
        // an amendment: the old version stays as history
        final amended = await h.actOk(
          'docuser',
          '/prescriptions/$id/amend',
          body: {'reason': 'Dose corrected'},
          status: 201,
        );
        await h.actOk(
          'docuser',
          '/prescriptions/${amended['prescriptionId']}/finalize',
        );
        final after = await p.list('/patient/prescriptions');
        expect(after, hasLength(2));
        expect(
          after.where((e) => (e! as Map)['current'] == true),
          hasLength(1),
        );
        expect(
          after.where((e) => (e! as Map)['superseded'] == true),
          hasLength(1),
        );
      },
    );

    test('other patients cannot read it', () async {
      final cid = await p.k.readyConsultation();
      final rx = await p.k.newRx(cid);
      await h.actOk(
        'docuser',
        '/prescriptions/${rx['prescriptionId']}/finalize',
      );
      await otherPatient();
      expect(await p.list('/patient/prescriptions', uid: 'ravi'), isEmpty);
    });
  });

  group('cross-clinic isolation', () {
    test('records of another clinic never mix into this patient\'s view', () async {
      final h2 = PlatformHarness();
      final p2 = PortalClinic(h2);
      await p2.init();
      // same shared nothing: each harness is its own backend; inside one, a second tenant
      await h.createClinic('ownerB', name: 'Other Clinic');
      final brB = await h.newBranch('ownerB', code: 'BEE');
      final pB = (await h.newPatient('ownerB', brB))['patientId']! as String;
      await h.okData(
        h.call(
          'POST',
          '/patients/$pB/allergies',
          uid: 'ownerB',
          body: {'allergen': 'Dust', 'category': 'environmental'},
        ),
        status: 201,
      );
      // asha is not linked there
      final o = await p.list('/patient/medical-records');
      expect(o, hasLength(1));
      expect(o.single.toString(), isNot(contains('Dust')));
      expect(
        await p.list(
          '/patient/medical-records?clinicId=${(await h.okData(h.call('GET', '/tenants/current/entitlements', uid: 'ownerB')))['tenantId']}',
        ),
        isEmpty,
      );
    });
  });

  group('billing', () {
    test(
      'invoices, payments, receipts and balances of the patient only, drafts hidden',
      () async {
        final draft = await h.okData(
          h.call(
            'POST',
            '/billing/invoices',
            uid: 'recep',
            body: {
              'patientId': p.patientId,
              'branchId': p.br,
              'lines': [
                {'description': 'Draft item', 'unitMinor': 500, 'quantity': 1},
              ],
            },
          ),
          status: 201,
        );
        expect(draft['status'], 'draft');
        expect(await p.list('/patient/invoices'), isEmpty);
        final inv = await p.invoice(amount: 100000);
        final id = inv['invoiceId']! as String;
        final pay = await p.pay(id, 40000);
        final invoices = await p.list('/patient/invoices');
        final i = invoices.single! as Map;
        expect(i['invoiceNumber'], 'INV-000001');
        expect(i['outstanding'], 60000);
        expect(i['status'], 'partially_paid');
        for (final hidden in [
          'createdBy',
          'finalizedBy',
          'notes',
          'lines',
          'rev',
        ]) {
          expect(i.containsKey(hidden), isFalse, reason: hidden);
        }
        final d = await p.get('/patient/clinics/${p.tid}/invoices/$id');
        expect((d['lines']! as List), hasLength(1));
        expect((d['payments']! as List).single, containsPair('amount', 40000));
        expect((d['onlinePayment']! as Map)['available'], false);
        final pays = await p.list('/patient/payments');
        expect((pays.single! as Map)['amount'], 40000);
        expect((pays.single! as Map).containsKey('receivedBy'), isFalse);
        final rid = (pay['receipt']! as Map)['receiptId'];
        final rc = await p.get('/patient/clinics/${p.tid}/receipts/$rid');
        expect(rc['receiptNumber'], 'RCT-000001');
        expect(rc.containsKey('receivedBy'), isFalse);
        final s = await p.list('/patient/billing-summary');
        expect((s.single! as Map)['outstanding'], 60000);
        // drafts are not reachable by id either
        expect(
          await p.status(
            'GET',
            '/patient/clinics/${p.tid}/invoices/${draft['invoiceId']}',
          ),
          404,
        );
      },
    );

    test(
      'another patient cannot read an invoice, receipt or refund by id',
      () async {
        final inv = await p.invoice(amount: 100000);
        final id = inv['invoiceId']! as String;
        final pay = await p.pay(id, 100000);
        final rid = (pay['receipt']! as Map)['receiptId'];
        await otherPatient();
        expect(
          await p.status(
            'GET',
            '/patient/clinics/${p.tid}/invoices/$id',
            uid: 'ravi',
          ),
          404,
        );
        expect(
          await p.status(
            'GET',
            '/patient/clinics/${p.tid}/receipts/$rid',
            uid: 'ravi',
          ),
          404,
        );
        expect(await p.list('/patient/invoices', uid: 'ravi'), isEmpty);
        expect(await p.list('/patient/payments', uid: 'ravi'), isEmpty);
        expect(await p.list('/patient/refunds', uid: 'ravi'), isEmpty);
        expect(
          await p.status(
            'GET',
            '/patient/invoices?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          404,
        );
      },
    );

    test(
      'refund status is visible, and staff-only money data is not',
      () async {
        final inv = await p.invoice(amount: 100000);
        final id = inv['invoiceId']! as String;
        final pay = await p.pay(id, 100000);
        final rf = await h.okData(
          h.call(
            'POST',
            '/billing/refunds',
            uid: 'recep',
            headers: {'idempotency-key': p.key()},
            body: {
              'paymentId': pay['paymentId'],
              'invoiceId': id,
              'amountMinor': 20000,
              'reason': 'Overcharged by mistake',
            },
          ),
          status: 201,
        );
        final list = await p.list('/patient/refunds');
        final r = list.single! as Map;
        expect(r['status'], 'requested');
        expect(r['amount'], 20000);
        expect(r.containsKey('history'), isFalse);
        expect(r.containsKey('requestedBy'), isFalse);
        expect(rf['refundId'], r['refundId']);
        // no route exposes clinic finance to a patient
        for (final path in [
          '/finance/dashboard',
          '/expenses',
          '/billing/services',
          '/billing/refunds',
        ]) {
          expect(await p.status('GET', path), 403, reason: path);
        }
      },
    );

    test(
      'a caregiver without the records scope sees no billing; with it, sees it',
      () async {
        final inv = await p.invoice();
        await p.pay(inv['invoiceId']! as String, 1000);
        await p.createAccount('ravi');
        final rel = await h.okData(
          h.call(
            'POST',
            '/patient-accounts/me/family',
            uid: 'ravi',
            body: {
              'relationshipType': 'caregiver',
              'subjectAccountId': p.accountId,
              'permissionScope': ['view_records'],
            },
          ),
          status: 201,
        );
        await h.okData(
          h.call(
            'POST',
            '/family-relationships/${rel['relationshipId']}/verify',
            uid: 'asha',
            body: {'decision': 'approve'},
          ),
        );
        expect(
          await p.list(
            '/patient/invoices?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          hasLength(1),
        );
        expect(
          await p.status(
            'GET',
            '/patient/appointments?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          404,
          reason: 'no appointment scope',
        );
        await h.okData(
          h.call(
            'POST',
            '/family-relationships/${rel['relationshipId']}/revoke',
            uid: 'asha',
            body: {},
          ),
        );
        expect(
          await p.status(
            'GET',
            '/patient/invoices?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          404,
        );
      },
    );
  });
}
