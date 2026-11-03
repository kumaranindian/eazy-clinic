import 'package:common_models/common_models.dart';

import 'patient_fixtures.dart';
import 'platform_http_fixtures.dart';

/// Test clock: 2026-06-01 10:00 UTC = 15:30 in Asia/Kolkata (a Monday).
const String today = '2026-06-01';
const String tuesday = '2026-06-02';
const String wednesday = '2026-06-03';
const String sunday = '2026-06-07';

Map<String, Object?> weekly({
  List<Map<String, String>> sessions = const [
    {'from': '09:00', 'to': '13:00'},
  ],
  List<Map<String, String>> breaks = const [],
  List<int> days = const [1, 2, 3, 4, 5, 6],
}) => {
  for (final d in days) '$d': {'sessions': sessions, 'breaks': breaks},
};

extension SchedulingFlows on PlatformHarness {
  Future<String> newDoctor(
    String uid, {
    required List<String> branchIds,
    String name = 'Dr Asha Rao',
    String n = '1',
  }) async =>
      (await okData(
            call(
              'POST',
              '/doctors',
              uid: uid,
              body: {
                'fullName': name,
                'email': 'doc$n@gv.test',
                'phone': '98765432${n.padLeft(2, '1')}',
                'registrationNumber': 'MH/2010/1234$n',
                'registrationCouncil': 'Maharashtra Medical Council',
                'specialty': 'General Medicine',
                'branchIds': branchIds,
              },
            ),
            status: 201,
          ))['doctorId']!
          as String;

  Future<String> newType(
    String uid, {
    String name = 'General Consultation',
    int duration = 30,
    int buffer = 0,
  }) async =>
      (await okData(
            call(
              'POST',
              '/appointment-types',
              uid: uid,
              body: {
                'name': name,
                'durationMinutes': duration,
                'bufferMinutes': buffer,
              },
            ),
            status: 201,
          ))['typeId']!
          as String;

  Future<Map<String, Object?>> newSchedule(
    String uid,
    String doctorId,
    String branchId, {
    Map<String, Object?>? hours,
    int capacity = 1,
    int duration = 30,
    int buffer = 0,
    String? from,
    String? to,
    Map<String, Object?>? extra,
  }) => okData(
    call(
      'POST',
      '/doctors/$doctorId/availability',
      uid: uid,
      body: {
        'branchId': branchId,
        'weeklyHours': hours ?? weekly(),
        'defaultDurationMinutes': duration,
        'bufferMinutes': buffer,
        'maxPerSlot': capacity,
        'effectiveFrom': from ?? '2026-01-01',
        'effectiveTo': ?to,
        ...?extra,
      },
    ),
    status: 201,
  );

  Future<List<Map<String, Object?>>> freeSlots(
    String uid,
    String branchId,
    String doctorId,
    String date, {
    String? typeId,
  }) async {
    final d = await okData(
      call(
        'GET',
        '/appointments/available-slots?branchId=$branchId&doctorId=$doctorId&date=$date${typeId == null ? '' : '&typeId=$typeId'}',
        uid: uid,
      ),
    );
    return (d['slots']! as List).cast<Map<String, Object?>>();
  }

  Future<int> bookStatus(
    String uid,
    Map<String, Object?> body, {
    String key = 'key-aaaaaaaa',
  }) async => (await call(
    'POST',
    '/appointments',
    uid: uid,
    body: body,
    headers: {'idempotency-key': key},
  )).statusCode;

  Future<Map<String, Object?>> bookOk(
    String uid,
    Map<String, Object?> body, {
    String? key,
    int status = 201,
  }) => okData(
    call(
      'POST',
      '/appointments',
      uid: uid,
      body: body,
      headers: {
        'idempotency-key':
            (key ?? 'key-${body['startTime']}-${body['date']}-${body['patientId']}')
                .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'),
      },
    ),
    status: status,
  );

  Map<String, Object?> bookBody({
    required String patientId,
    required String doctorId,
    required String branchId,
    required String typeId,
    String date = tuesday,
    String startTime = '09:00',
    Map<String, Object?>? extra,
  }) => {
    'patientId': patientId,
    'doctorId': doctorId,
    'branchId': branchId,
    'typeId': typeId,
    'date': date,
    'startTime': startTime,
    ...?extra,
  };

  Future<int> act(
    String uid,
    String path, {
    Object? body,
    String method = 'POST',
  }) => status(method, path, uid: uid, body: body ?? <String, Object?>{});

  Future<Map<String, Object?>> actOk(
    String uid,
    String path, {
    Object? body,
    String method = 'POST',
    int status = 200,
  }) => okData(
    call(method, path, uid: uid, body: body ?? <String, Object?>{}),
    status: status,
  );

  Iterable<Map<String, Object?>> apptDocs() => docsOf('appointments');
  Iterable<Map<String, Object?>> reservations() =>
      docsOf('appointment_slot_reservations');
  List<String> apptActions(String appointmentId) => [
    for (final d in docsOf('appointment_audit_logs'))
      if (d['appointmentId'] == appointmentId) d['action']! as String,
  ];
}

/// A clinic with one branch, doctor, type, schedule and patient.
class Clinic {
  Clinic(this.h);
  final PlatformHarness h;
  late String tid;
  late String br;
  late String doc;
  late String type;
  late String patient;

  Future<void> init({
    int capacity = 1,
    int duration = 30,
    int buffer = 0,
    Map<String, Object?>? hours,
  }) async {
    h.user('root', role: PlatformRole.superAdmin);
    tid = await h.createClinic('owner');
    br = await h.newBranch('owner');
    for (final e in {
      'recep': 'receptionist',
      'nurse': 'nurse',
      'admin': 'clinic_admin',
      'acct': 'accountant',
    }.entries) {
      h.member(e.key, tid, e.value);
    }
    doc = await h.newDoctor('owner', branchIds: [br]);
    // the doctor's own login
    h.member('docuser', tid, 'doctor');
    h.store.docs['tenants/$tid/members/docuser']!['doctorId'] = doc;
    type = await h.newType('owner', duration: duration, buffer: buffer);
    await h.newSchedule(
      'owner',
      doc,
      br,
      capacity: capacity,
      duration: duration,
      buffer: buffer,
      hours: hours,
    );
    patient = (await h.newPatient('recep', br))['patientId']! as String;
  }

  Map<String, Object?> body({
    String date = tuesday,
    String start = '09:00',
    String? patientId,
    Map<String, Object?>? extra,
  }) => h.bookBody(
    patientId: patientId ?? patient,
    doctorId: doc,
    branchId: br,
    typeId: type,
    date: date,
    startTime: start,
    extra: extra,
  );

  Future<String> morePatient(int n) async =>
      (await h.newPatient(
            'recep',
            br,
            name: 'Patient Number$n',
            dob: '19${60 + n}-01-01',
            phone: '98765001${n.toString().padLeft(2, '0')}',
          ))['patientId']!
          as String;
}
