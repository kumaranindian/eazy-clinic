import 'dart:async';

import 'patient_fixtures.dart';
import 'platform_http_fixtures.dart';
import 'scheduling_fixtures.dart';

/// A clinic ready for billing flows: owner, admin, receptionist, nurse,
/// accountant, one doctor, a patient and a branch.
class BillingClinic {
  BillingClinic(this.h) : c = Clinic(h);

  final PlatformHarness h;
  final Clinic c;

  String get tid => c.tid;
  String get br => c.br;
  String get patient => c.patient;
  String get doctor => c.doc;

  int keyCounter = 0;
  String key([String? tag]) =>
      'key-${tag ?? 'k'}-${(keyCounter++).toString().padLeft(6, '0')}';

  Future<void> init() => c.init();

  Future<Map<String, Object?>> taxRule({
    String name = 'GST 18%',
    bool inclusive = false,
    List<Map<String, Object?>>? components,
    String uid = 'owner',
  }) => h.okData(
    h.call(
      'POST',
      '/billing/tax-rules',
      uid: uid,
      body: {
        'name': name,
        'inclusive': inclusive,
        'components':
            components ??
            [
              {'name': 'CGST', 'rateBps': 900},
              {'name': 'SGST', 'rateBps': 900},
            ],
      },
    ),
    status: 201,
  );

  Future<Map<String, Object?>> service({
    String name = 'General Consultation',
    String category = 'consultation',
    int amount = 50000,
    String? taxRuleId,
    Map<String, Object?>? extra,
    String uid = 'owner',
  }) => h.okData(
    h.call(
      'POST',
      '/billing/services',
      uid: uid,
      body: {
        'name': name,
        'category': category,
        'amountMinor': amount,
        'taxRuleId': ?taxRuleId,
        ...?extra,
      },
    ),
    status: 201,
  );

  Map<String, Object?> invoiceBody({
    String? patientId,
    List<Map<String, Object?>>? lines,
    Map<String, Object?>? extra,
  }) => {
    'patientId': patientId ?? patient,
    'branchId': br,
    'lines': ?lines,
    ...?extra,
  };

  Future<Map<String, Object?>> draft({
    String uid = 'recep',
    String? patientId,
    List<Map<String, Object?>>? lines,
    Map<String, Object?>? extra,
  }) => h.okData(
    h.call(
      'POST',
      '/billing/invoices',
      uid: uid,
      body: invoiceBody(patientId: patientId, lines: lines, extra: extra),
    ),
    status: 201,
  );

  /// A finalized invoice with one manual line of [amount].
  Future<Map<String, Object?>> finalized({
    int amount = 100000,
    String? patientId,
    String uid = 'recep',
    List<Map<String, Object?>>? lines,
    Map<String, Object?>? extra,
  }) async {
    final d = await draft(
      uid: uid,
      patientId: patientId,
      lines:
          lines ??
          [
            {
              'description': 'Minor procedure',
              'unitMinor': amount,
              'quantity': 1,
            },
          ],
      extra: extra,
    );
    return h.okData(
      h.call('POST', '/billing/invoices/${d['invoiceId']}/finalize', uid: uid),
    );
  }

  Future<Map<String, Object?>> pay(
    String invoiceId,
    int amount, {
    String uid = 'recep',
    String method = 'cash',
    String? patientId,
    String? idemKey,
    String? reference,
    bool advance = false,
    Map<String, Object?>? extra,
    int status = 201,
  }) => h.okData(
    h.call(
      'POST',
      '/billing/payments',
      uid: uid,
      headers: {'idempotency-key': idemKey ?? key('pay')},
      body: {
        'patientId': patientId ?? patient,
        'branchId': br,
        'amountMinor': amount,
        'method': method,
        'reference': ?reference,
        'allocations': [
          {'invoiceId': invoiceId, 'amountMinor': amount},
        ],
        ...?extra,
      },
    ),
    status: status,
  );

  Future<int> payStatus(
    Object? body, {
    String uid = 'recep',
    String? idemKey,
  }) async => (await h.call(
    'POST',
    '/billing/payments',
    uid: uid,
    headers: {if (idemKey != null) 'idempotency-key': idemKey},
    body: body,
  )).statusCode;

  Future<Map<String, Object?>> advance(
    int amount, {
    String uid = 'recep',
    String? patientId,
    String? idemKey,
    String method = 'cash',
  }) => h.okData(
    h.call(
      'POST',
      '/billing/patient-credits',
      uid: uid,
      headers: {'idempotency-key': idemKey ?? key('adv')},
      body: {
        'kind': 'advance',
        'patientId': patientId ?? patient,
        'branchId': br,
        'amountMinor': amount,
        'method': method,
      },
    ),
    status: 201,
  );

  Future<Map<String, Object?>> invoice(String id, {String uid = 'owner'}) =>
      h.okData(h.call('GET', '/billing/invoices/$id', uid: uid));

  Future<Map<String, Object?>> credits({
    String? patientId,
    String uid = 'owner',
  }) => h.okData(
    h.call(
      'GET',
      '/billing/patients/${patientId ?? patient}/credits',
      uid: uid,
    ),
  );

  Future<Map<String, Object?>> requestRefund(
    String paymentId,
    int amount, {
    String? invoiceId,
    String uid = 'recep',
    String? idemKey,
    String reason = 'Service not rendered',
    int status = 201,
  }) => h.okData(
    h.call(
      'POST',
      '/billing/refunds',
      uid: uid,
      headers: {'idempotency-key': idemKey ?? key('rf')},
      body: {
        'paymentId': paymentId,
        'invoiceId': ?invoiceId,
        'amountMinor': amount,
        'reason': reason,
      },
    ),
    status: status,
  );

  Future<Map<String, Object?>> refundAction(
    String id,
    String action, {
    String uid = 'owner',
    Map<String, Object?>? body,
    int status = 200,
  }) => h.okData(
    h.call('POST', '/billing/refunds/$id/$action', uid: uid, body: body ?? {}),
    status: status,
  );

  /// Request → approve (owner) → complete (accountant) for [amount].
  Future<Map<String, Object?>> refundDone(
    String paymentId,
    int amount, {
    String? invoiceId,
  }) async {
    final rf = await requestRefund(paymentId, amount, invoiceId: invoiceId);
    final id = rf['refundId']! as String;
    await refundAction(id, 'approve');
    return refundAction(
      id,
      'complete',
      uid: 'acct',
      body: {'outcome': 'completed', 'method': 'cash'},
    );
  }

  List<String> auditActions() => [
    for (final d in h.docsOf('financial_audit_logs')) d['action']! as String,
  ];
}
