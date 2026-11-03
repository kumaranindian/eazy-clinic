import 'dart:convert';
import 'dart:typed_data';

import 'platform_http_fixtures.dart';

Map<String, Object?> consentBody({
  String method = 'in_person_signed',
  Map<String, Object?>? grantedBy,
}) => {
  'granted': true,
  'textVersion': '1.0',
  'collectionMethod': method,
  'grantedBy': ?grantedBy,
};

Map<String, Object?> patientBody(
  String branchId, {
  String name = 'Asha Patil',
  String dob = '1990-05-14',
  String phone = '9876500001',
  String? email,
  String gender = 'female',
  Map<String, Object?>? guardian,
  Map<String, Object?>? consent,
  Map<String, Object?>? extra,
}) => {
  'branchId': branchId,
  'fullName': name,
  'dateOfBirth': dob,
  'gender': gender,
  'phone': phone,
  'email': ?email,
  'address': {
    'line1': '5 Lake Road',
    'city': 'Pune',
    'state': 'Maharashtra',
    'country': 'India',
    'postalCode': '411001',
  },
  'guardian': ?guardian,
  'consent': consent ?? consentBody(),
  ...?extra,
};

extension PatientFlows on PlatformHarness {
  Future<String> newBranch(String uid, {String code = 'MAIN'}) async =>
      (await okData(
            call(
              'POST',
              '/branches',
              uid: uid,
              body: branchBody(code: code),
            ),
            status: 201,
          ))['branchId']!
          as String;

  Future<Map<String, Object?>> newPatient(
    String uid,
    String branchId, {
    String name = 'Asha Patil',
    String dob = '1990-05-14',
    String phone = '9876500001',
    String? email,
    Map<String, Object?>? extra,
    Map<String, Object?>? guardian,
    Map<String, Object?>? consent,
  }) => okData(
    call(
      'POST',
      '/patients',
      uid: uid,
      body: patientBody(
        branchId,
        name: name,
        dob: dob,
        phone: phone,
        email: email,
        extra: extra,
        guardian: guardian,
        consent: consent,
      ),
    ),
    status: 201,
  );

  /// Records a granted consent as [uid].
  Future<Map<String, Object?>> grant(
    String uid,
    String patientId,
    String type,
  ) => okData(
    call(
      'POST',
      '/patients/$patientId/consents',
      uid: uid,
      body: {
        'type': type,
        'decision': 'granted',
        'textVersion': '1.0',
        'collectionMethod': 'in_person_signed',
        'grantedBy': {'type': 'patient'},
      },
    ),
    status: 201,
  );

  Future<int> status(
    String method,
    String path, {
    String? uid,
    Object? body,
    Map<String, String> headers = const {},
    bool emailVerified = true,
  }) async => (await call(
    method,
    path,
    uid: uid,
    body: body,
    headers: headers,
    emailVerified: emailVerified,
  )).statusCode;

  /// All stored documents under a collection name (any tenant).
  Iterable<Map<String, Object?>> docsOf(String collection) => [
    for (final e in store.docs.entries)
      if (e.key.contains('/$collection/') || e.key.startsWith('$collection/'))
        e.value,
  ];

  List<String> auditActions(String patientId) => [
    for (final d in docsOf('patient_audit_logs'))
      if (d['patientId'] == patientId) d['action']! as String,
  ];
}

String b64(Uint8List b) => base64Encode(b);

Uint8List pdfBytes([int extra = 32]) => Uint8List.fromList([
  0x25,
  0x50,
  0x44,
  0x46,
  0x2D,
  ...List.filled(extra, 0x31),
]);
