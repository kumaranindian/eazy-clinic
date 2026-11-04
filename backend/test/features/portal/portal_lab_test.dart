import 'dart:convert';

import 'package:test/test.dart';

import '../../support/clinical_fixtures.dart';
import '../../support/lab_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/portal_fixtures.dart';

void main() {
  late PlatformHarness h;
  late PortalClinic p;
  late LabClinic k;
  late String testId;

  setUp(() async {
    h = PlatformHarness();
    p = PortalClinic(h);
    await p.init();
    k = LabClinic.on(h, p.k.c);
    testId = (await k.test())['testId']! as String;
  });

  Future<Map<String, Object?>> publish() async {
    final id = await k.verified(testId, value: 10.2);
    return {
      'orderId': id,
      ...await k.post('labtech2', '/laboratory/orders/$id/publish'),
    };
  }

  test('nothing is visible before publication', () async {
    final id = await k.verified(testId);
    expect(await p.list('/patient/lab-reports'), isEmpty);
    expect(id, isNotEmpty);
  });

  test('a published report appears with allow-listed results', () async {
    final r = await publish();
    final rows = await p.list('/patient/lab-reports');
    expect(rows.length, 1);
    final row = rows.first! as Map;
    expect(row['reportId'], r['reportId']);
    expect(row['clinicId'], p.tid);
    expect(row['tests'], ['Haemoglobin']);
    final d = await p.get(
      '/patient/clinics/${p.tid}/lab-reports/${r['reportId']}',
    );
    final obs =
        (((d['tests']! as List).first as Map)['observations']! as List).first
            as Map;
    expect(obs['flag'], 'low');
    expect(obs['value'], 10.2);
    final raw = jsonEncode(d);
    for (final hidden in [
      'internalComment',
      'enteredBy',
      'verifiedBy',
      'storagePath',
      'revisions',
      'history',
      'labtech',
    ]) {
      expect(raw.contains(hidden), isFalse, reason: hidden);
    }
    final dl = await h.call(
      'GET',
      '/patient/clinics/${p.tid}/lab-reports/${r['reportId']}/download',
      uid: 'asha',
    );
    expect(dl.statusCode, 200);
    expect(dl.headers['content-type'], 'application/pdf');
    expect(dl.headers['cache-control'], contains('no-store'));
    expect(
      h.docsOf('patient_audit_logs').map((e) => e['action']),
      contains('portal.lab_report_downloaded'),
    );
  });

  test('another patient cannot read it', () async {
    final r = await publish();
    await p.createAccount('ravi');
    expect(
      await p.status(
        'GET',
        '/patient/clinics/${p.tid}/lab-reports/${r['reportId']}',
        uid: 'ravi',
      ),
      404,
    );
    expect(await p.list('/patient/lab-reports', uid: 'ravi'), isEmpty);
    expect(
      await p.status(
        'GET',
        '/patient/clinics/${p.tid}/lab-reports/${r['reportId']}/download',
        uid: 'ravi',
      ),
      404,
    );
  });

  test('a superseded version is not offered', () async {
    final r = await publish();
    final item =
        ((await h.get(
                      'labtech',
                      '/laboratory/orders/${r['orderId']}',
                    ))['items']!
                    as List)
                .first
            as Map;
    await k.post(
      'labtech',
      '/laboratory/orders/${r['orderId']}/results/${item['itemId']}/amend',
      {
        'reason': 'Correction after recheck',
        'observations': [
          {'code': 'HGB', 'value': 13.0},
        ],
      },
      201,
    );
    await k.post('labtech2', '/laboratory/orders/${r['orderId']}/verify');
    final v2 = await k.post(
      'labtech2',
      '/laboratory/orders/${r['orderId']}/publish',
    );
    final rows = await p.list('/patient/lab-reports');
    expect(rows.length, 1);
    expect((rows.first! as Map)['reportId'], v2['reportId']);
    expect(
      await p.status(
        'GET',
        '/patient/clinics/${p.tid}/lab-reports/${r['reportId']}',
      ),
      404,
    );
  });

  test('publication notifies the patient once', () async {
    await publish();
    final inbox = (await p.get('/patient/notifications'))['items']! as List;
    expect(
      inbox
          .where((n) => (n! as Map)['category'] == 'lab_report_available')
          .length,
      1,
    );
  });
}
