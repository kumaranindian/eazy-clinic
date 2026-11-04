import 'clinical_fixtures.dart';
import 'platform_http_fixtures.dart';
import 'scheduling_fixtures.dart';

/// A clinic whose patient `asha` has a patient account linked to a clinic
/// record, ready for patient-app flows.
class PortalClinic {
  PortalClinic(this.h) : k = ClinicalClinic(h);

  final PlatformHarness h;
  final ClinicalClinic k;

  String get tid => k.tid;
  String get br => k.br;
  String get doctor => k.c.doc;
  String get type => k.c.type;
  String get patientId => k.patient;
  late String accountId;

  int _n = 0;
  String key([String tag = 'k']) =>
      'pk-$tag-${(_n++).toString().padLeft(6, '0')}';

  Future<void> init() async {
    await k.init();
    await createAccount('asha');
    accountId =
        (await h.okData(
              h.call('GET', '/patient-accounts/me', uid: 'asha'),
            ))['accountId']!
            as String;
    await link('asha', patientId);
  }

  Future<Map<String, Object?>> createAccount(String uid, {String? name}) async {
    h.user(uid);
    return h.okData(
      h.call(
        'POST',
        '/patient-accounts',
        uid: uid,
        body: {'displayName': name ?? 'Test $uid'},
      ),
      status: 201,
    );
  }

  /// Staff identify the patient and issue a code; the patient claims it.
  Future<Map<String, Object?>> link(
    String uid,
    String pid, {
    String staff = 'recep',
  }) async {
    final code =
        (await h.okData(
              h.call(
                'POST',
                '/patients/$pid/link-account',
                uid: staff,
                body: {
                  'verificationMethod': 'government_id_sighted',
                  'identityConfirmed': true,
                },
              ),
              status: 201,
            ))['code']!
            as String;
    return h.okData(
      h.call(
        'POST',
        '/patient-accounts/me/link-clinic-record',
        uid: uid,
        body: {'code': code},
      ),
      status: 201,
    );
  }

  Future<Map<String, Object?>> get(
    String path, {
    String uid = 'asha',
    int status = 200,
  }) => h.okData(h.call('GET', path, uid: uid), status: status);

  Future<List<Object?>> list(String path, {String uid = 'asha'}) async =>
      h.list(await h.call('GET', path, uid: uid));

  Future<int> status(
    String method,
    String path, {
    String? uid = 'asha',
    Object? body,
    Map<String, String> headers = const {},
  }) async => (await h.call(
    method,
    path,
    uid: uid,
    body: body,
    headers: headers,
  )).statusCode;

  Map<String, Object?> bookBody({
    String date = tuesday,
    String time = '09:00',
    String? accountId,
    String? clinicId,
  }) => {
    'clinicId': clinicId ?? tid,
    'branchId': br,
    'doctorId': doctor,
    'typeId': type,
    'date': date,
    'startTime': time,
    'accountId': ?accountId,
  };

  Future<Map<String, Object?>> book({
    String uid = 'asha',
    String date = tuesday,
    String time = '09:00',
    String? accountId,
    String? idemKey,
  }) => h.okData(
    h.call(
      'POST',
      '/patient/appointments',
      uid: uid,
      headers: {'idempotency-key': idemKey ?? key('bk')},
      body: bookBody(date: date, time: time, accountId: accountId),
    ),
    status: 201,
  );

  /// A finalized, released consultation with a primary diagnosis.
  Future<String> releasedConsultation() async {
    final cid = await k.readyConsultation();
    await h.actOk('docuser', '/consultations/$cid/finalize');
    await h.actOk('docuser', '/consultations/$cid/release');
    return cid;
  }
}

extension PortalBilling on PortalClinic {
  /// A finalized invoice of [amount] paise for [pid].
  Future<Map<String, Object?>> invoice({
    int amount = 100000,
    String? pid,
  }) async {
    final d = await h.okData(
      h.call(
        'POST',
        '/billing/invoices',
        uid: 'recep',
        body: {
          'patientId': pid ?? patientId,
          'branchId': br,
          'lines': [
            {
              'description': 'Minor procedure',
              'unitMinor': amount,
              'quantity': 1,
            },
          ],
        },
      ),
      status: 201,
    );
    return h.okData(
      h.call(
        'POST',
        '/billing/invoices/${d['invoiceId']}/finalize',
        uid: 'recep',
      ),
    );
  }

  Future<Map<String, Object?>> pay(
    String invoiceId,
    int amount, {
    String? pid,
  }) => h.okData(
    h.call(
      'POST',
      '/billing/payments',
      uid: 'recep',
      headers: {'idempotency-key': key('pay')},
      body: {
        'patientId': pid ?? patientId,
        'branchId': br,
        'amountMinor': amount,
        'method': 'cash',
        'allocations': [
          {'invoiceId': invoiceId, 'amountMinor': amount},
        ],
      },
    ),
    status: 201,
  );
}
