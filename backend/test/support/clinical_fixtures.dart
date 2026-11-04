import 'patient_fixtures.dart';
import 'platform_http_fixtures.dart';
import 'scheduling_fixtures.dart';

/// A clinic with a second doctor and everything needed for clinical flows.
class ClinicalClinic {
  ClinicalClinic(this.h) : c = Clinic(h);

  final PlatformHarness h;
  final Clinic c;
  late String doc2;

  String get tid => c.tid;
  String get br => c.br;
  String get patient => c.patient;

  Future<void> init() async {
    await c.init();
    doc2 = await h.newDoctor(
      'owner',
      branchIds: [br],
      name: 'Dr Second',
      n: '2',
    );
    await h.newSchedule('owner', doc2, br);
    h.member('doc2user', tid, 'doctor');
    h.store.docs['tenants/$tid/members/doc2user']!['doctorId'] = doc2;
  }

  Map<String, Object?> consult({
    String? patientId,
    String? appointmentId,
    Map<String, Object?>? extra,
  }) => {
    'patientId': patientId ?? patient,
    if (appointmentId != null)
      'appointmentId': appointmentId
    else
      'branchId': br,
    'chiefComplaint': {'reason': 'Fever for three days'},
    ...?extra,
  };

  Future<Map<String, Object?>> newConsultation({
    String uid = 'docuser',
    String? patientId,
    String? appointmentId,
    Map<String, Object?>? extra,
  }) => h.okData(
    h.call(
      'POST',
      '/consultations',
      uid: uid,
      body: consult(
        patientId: patientId,
        appointmentId: appointmentId,
        extra: extra,
      ),
    ),
    status: 201,
  );

  Future<Map<String, Object?>> primaryDx(
    String cid, {
    String uid = 'docuser',
  }) => h.okData(
    h.call(
      'POST',
      '/consultations/$cid/diagnoses',
      uid: uid,
      body: {
        'kind': 'primary',
        'certainty': 'provisional',
        'label': 'Viral fever',
      },
    ),
    status: 201,
  );

  /// A consultation that is started and ready to finalize.
  Future<String> readyConsultation({String uid = 'docuser'}) async {
    final cid = (await newConsultation(uid: uid))['consultationId']! as String;
    await h.actOk(uid, '/consultations/$cid/start');
    await primaryDx(cid, uid: uid);
    return cid;
  }

  /// Books a visit for tuesday 09:00, moves the clock to 10:00 IST that day and
  /// checks the patient in. Returns the appointment id.
  Future<String> checkedInVisit({
    String? patientId,
    String start = '09:00',
  }) async {
    final a = await h.bookOk(
      'recep',
      c.body(start: start, patientId: patientId),
    );
    h.clock.now = DateTime.utc(2026, 6, 2, 4, 30);
    await h.actOk('recep', '/appointments/${a['appointmentId']}/check-in');
    return a['appointmentId']! as String;
  }

  Map<String, Object?> medicine({
    String name = 'Paracetamol',
    Map<String, Object?>? extra,
  }) => {
    'name': name,
    'strength': '500 mg',
    'dosage': '1 tablet',
    'route': 'oral',
    'frequency': 'three times a day',
    'durationValue': 5,
    'durationUnit': 'days',
    'foodRelation': 'after_food',
    ...?extra,
  };

  Future<Map<String, Object?>> newRx(
    String cid, {
    String uid = 'docuser',
    List<Map<String, Object?>>? meds,
  }) => h.okData(
    h.call(
      'POST',
      '/consultations/$cid/prescriptions',
      uid: uid,
      body: {
        'medicines': meds ?? [medicine()],
      },
    ),
    status: 201,
  );

  List<String> clinicalActions({String? consultationId}) => [
    for (final d in h.docsOf('clinical_audit_logs'))
      if (consultationId == null || d['consultationId'] == consultationId)
        d['action']! as String,
  ];
}

extension ClinicalCalls on PlatformHarness {
  List<String> clinicalActions({String? consultationId}) => [
    for (final d in docsOf('clinical_audit_logs'))
      if (consultationId == null || d['consultationId'] == consultationId)
        d['action']! as String,
  ];

  Future<Map<String, Object?>> get(String uid, String path) =>
      okData(call('GET', path, uid: uid));
}
