import 'dart:convert';

import 'patient_fixtures.dart';
import 'platform_http_fixtures.dart';
import 'scheduling_fixtures.dart';

/// A clinic ready for laboratory flows: owner, two lab technicians, a nurse,
/// a receptionist, a doctor (with login), a patient and a branch.
class LabClinic {
  LabClinic(this.h) : c = Clinic(h);

  /// Laboratory flows on a clinic that is already set up.
  LabClinic.on(this.h, this.c) {
    h.member('labtech', tid, 'lab_technician');
    h.member('labtech2', tid, 'lab_technician');
  }

  final PlatformHarness h;
  final Clinic c;
  int _k = 0;

  String get tid => c.tid;
  String get br => c.br;
  String get patient => c.patient;

  String key() => 'lab-key-${(_k++).toString().padLeft(6, '0')}';

  Future<void> init() async {
    await c.init();
    h.member('labtech', tid, 'lab_technician');
    h.member('labtech2', tid, 'lab_technician');
  }

  Map<String, Object?> testBody({
    String code = 'HB',
    String name = 'Haemoglobin',
    bool ranges = true,
    Map<String, Object?>? extra,
  }) => {
    'code': code,
    'name': name,
    'category': 'hematology',
    'sampleType': 'blood',
    'turnaroundHours': 6,
    'priceMinor': 25000,
    'parameters': [
      {
        'code': 'HGB',
        'name': 'Haemoglobin',
        'valueType': 'numeric',
        'unit': 'g/dL',
        if (ranges)
          'referenceRanges': [
            {
              'sex': 'female',
              'low': 12,
              'high': 15,
              'criticalLow': 7,
              'unit': 'g/dL',
              'source': 'Clinic lab SOP 2026',
            },
            {
              'sex': 'male',
              'low': 13,
              'high': 17,
              'criticalLow': 7,
              'unit': 'g/dL',
              'source': 'Clinic lab SOP 2026',
            },
          ],
      },
    ],
    ...?extra,
  };

  Future<Map<String, Object?>> test({
    String code = 'HB',
    String name = 'Haemoglobin',
    bool ranges = true,
    Map<String, Object?>? extra,
    String uid = 'owner',
  }) => h.okData(
    h.call(
      'POST',
      '/laboratory/tests',
      uid: uid,
      body: testBody(code: code, name: name, ranges: ranges, extra: extra),
    ),
    status: 201,
  );

  Future<Map<String, Object?>> order(
    String testId, {
    String uid = 'labtech',
    String priority = 'routine',
    String? patientId,
  }) => h.okData(
    h.call(
      'POST',
      '/laboratory/orders',
      uid: uid,
      headers: {'idempotency-key': key()},
      body: {
        'patientId': patientId ?? patient,
        'branchId': br,
        'priority': priority,
        'tests': [
          {'testId': testId},
        ],
      },
    ),
    status: 201,
  );

  Future<Map<String, Object?>> post(
    String uid,
    String path, [
    Map<String, Object?>? body,
    int status = 200,
  ]) => h.okData(
    h.call('POST', path, uid: uid, body: body),
    status: status,
  );

  /// Order accepted, sample created and collected (order: sample_collected).
  Future<Map<String, Object?>> collected(
    String testId, {
    String? identifier,
  }) async {
    identifier ??= 'SMP-A${(_k++).toString().padLeft(4, '0')}';
    final o = await order(testId);
    final id = o['orderId']! as String;
    await post('labtech', '/laboratory/orders/$id/accept', {});
    final s = await post('nurse', '/laboratory/orders/$id/samples', {}, 201);
    await post('nurse', '/laboratory/samples/${s['sampleId']}/collect', {
      'identifier': identifier,
      'confirmedMrn': await mrn(),
    });
    return {...o, 'sampleId': s['sampleId']};
  }

  Future<String> mrn() async {
    final p = h.store.docs['tenants/$tid/patients/$patient']!;
    return '${p['mrn']}';
  }

  Future<Map<String, Object?>> enter(
    String orderId,
    String itemId,
    num value, {
    String uid = 'labtech',
    int status = 200,
  }) => h.okData(
    h.call(
      'PUT',
      '/laboratory/orders/$orderId/results/$itemId',
      uid: uid,
      body: {
        'observations': [
          {'code': 'HGB', 'value': value},
        ],
      },
    ),
    status: status,
  );

  /// Drives an order to `verified`.
  Future<String> verified(String testId, {num value = 13.5}) async {
    final o = await collected(testId);
    final id = o['orderId']! as String;
    final item = ((o['items']! as List).first as Map)['itemId']! as String;
    await enter(id, item, value);
    await post('labtech', '/laboratory/orders/$id/submit-verification');
    await post('labtech2', '/laboratory/orders/$id/verify');
    return id;
  }

  List<String> actions() => [
    for (final d in h.docsOf('lab_audit_logs')) d['action']! as String,
  ];

  String b64(List<int> bytes) => base64.encode(bytes);
}
