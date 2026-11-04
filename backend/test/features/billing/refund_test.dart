import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late BillingClinic k;
  late String invoiceId;
  late Map<String, Object?> payment;
  late String pid;

  setUp(() async {
    h = PlatformHarness();
    k = BillingClinic(h);
    await k.init();
    final inv = await k.finalized(amount: 100000);
    invoiceId = inv['invoiceId']! as String;
    payment = await k.pay(invoiceId, 100000);
    pid = payment['paymentId']! as String;
  });

  group('requesting', () {
    test(
      'a partial refund is requested against the payment and invoice',
      () async {
        final rf = await k.requestRefund(pid, 30000, invoiceId: invoiceId);
        expect(rf['status'], 'requested');
        expect(rf['amount'], 30000);
        expect(rf['requestedBy'], 'recep');
        expect(rf['paymentReceipt'], 'RCT-000001');
        // nothing moved yet
        final d = await k.invoice(invoiceId);
        expect(d['amountRefunded'], 0);
        expect(d['status'], 'paid');
        expect(k.auditActions(), contains('refund.requested'));
      },
    );

    test(
      'a refund cannot exceed what is eligible, including pending ones',
      () async {
        await k.requestRefund(pid, 60000, invoiceId: invoiceId);
        expect(
          await h.status(
            'POST',
            '/billing/refunds',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'paymentId': pid,
              'invoiceId': invoiceId,
              'amountMinor': 50000,
              'reason': 'Too much',
            },
          ),
          409,
          reason: 'only 40000 left after the pending 60000',
        );
        await k.requestRefund(pid, 40000, invoiceId: invoiceId);
        expect(
          await h.status(
            'POST',
            '/billing/refunds',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'paymentId': pid,
              'invoiceId': invoiceId,
              'amountMinor': 1,
              'reason': 'Nothing left',
            },
          ),
          409,
        );
      },
    );

    test('validation, permission and scope', () async {
      Future<int> post(
        Map<String, Object?> b, {
        String uid = 'recep',
        String? idem,
      }) => h.status(
        'POST',
        '/billing/refunds',
        uid: uid,
        headers: {'idempotency-key': idem ?? k.key()},
        body: b,
      );
      final ok = {
        'paymentId': pid,
        'invoiceId': invoiceId,
        'amountMinor': 100,
        'reason': 'Overcharged',
      };
      expect(await post({...ok, 'reason': 'no'}), 422);
      expect(await post({...ok, 'amountMinor': 0}), 422);
      expect(await post({...ok, 'status': 'completed'}), 422);
      expect(await post({...ok, 'tenantId': 'x'}), 422);
      expect(await post(ok, uid: 'nurse'), 403);
      expect(await post({...ok, 'paymentId': 'pay_missing'}), 404);
      expect(await post({...ok, 'invoiceId': 'inv_missing'}), 404);
      expect(
        await h.status('POST', '/billing/refunds', uid: 'recep', body: ok),
        400,
        reason: 'needs an Idempotency-Key',
      );
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(await post(ok, uid: 'ownerB'), 404);
    });

    test('a repeated request with the same key creates one refund', () async {
      final a = await k.requestRefund(
        pid,
        1000,
        invoiceId: invoiceId,
        idemKey: 'key-rf-0001',
      );
      final b = await k.requestRefund(
        pid,
        1000,
        invoiceId: invoiceId,
        idemKey: 'key-rf-0001',
      );
      expect(b['idempotentReplay'], true);
      expect(b['refundId'], a['refundId']);
      expect(h.docsOf('refunds'), hasLength(1));
    });

    test('racing requests for the last amount hold it only once', () async {
      final res = await Future.wait([
        for (var i = 0; i < 4; i++)
          h.call(
            'POST',
            '/billing/refunds',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'paymentId': pid,
              'invoiceId': invoiceId,
              'amountMinor': 100000,
              'reason': 'Full refund requested',
            },
          ),
      ]);
      expect(res.where((r) => r.statusCode == 201), hasLength(1));
      expect(res.where((r) => r.statusCode == 409), hasLength(3));
    });
  });

  group('decisions', () {
    test(
      'approval is for refund.approve holders, never the requester',
      () async {
        final rf = await k.requestRefund(
          pid,
          10000,
          invoiceId: invoiceId,
          uid: 'acct',
        );
        final id = rf['refundId']! as String;
        // receptionists and accountants hold no approval permission
        expect(
          await h.status(
            'POST',
            '/billing/refunds/$id/approve',
            uid: 'recep',
            body: {},
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/billing/refunds/$id/approve',
            uid: 'acct',
            body: {},
          ),
          403,
        );
        // an owner who requested their own refund cannot approve it
        final own = await k.requestRefund(
          pid,
          5000,
          invoiceId: invoiceId,
          uid: 'owner',
        );
        expect(
          await h.status(
            'POST',
            '/billing/refunds/${own['refundId']}/approve',
            uid: 'owner',
            body: {},
          ),
          403,
        );
        final ok = await k.refundAction(id, 'approve', uid: 'admin');
        expect(ok['status'], 'approved');
        expect(ok['approvedBy'], 'admin');
        final again = await k.refundAction(id, 'approve', uid: 'admin');
        expect(again['idempotentReplay'], true);
      },
    );

    test('policy can allow self-approval explicitly', () async {
      await h.okData(
        h.call(
          'PUT',
          '/billing/settings',
          uid: 'owner',
          body: {'allowSelfApproval': true},
        ),
      );
      final own = await k.requestRefund(
        pid,
        5000,
        invoiceId: invoiceId,
        uid: 'owner',
      );
      final ok = await k.refundAction(
        own['refundId']! as String,
        'approve',
        uid: 'owner',
      );
      expect(ok['status'], 'approved');
    });

    test('rejection needs a reason and is final', () async {
      final rf = await k.requestRefund(pid, 10000, invoiceId: invoiceId);
      final id = rf['refundId']! as String;
      expect(
        await h.status(
          'POST',
          '/billing/refunds/$id/reject',
          uid: 'owner',
          body: {},
        ),
        422,
      );
      final r = await k.refundAction(
        id,
        'reject',
        body: {'reason': 'Service was delivered'},
      );
      expect(r['status'], 'rejected');
      expect(r['rejectReason'], 'Service was delivered');
      expect(
        await h.status(
          'POST',
          '/billing/refunds/$id/approve',
          uid: 'owner',
          body: {},
        ),
        409,
      );
      expect(
        await h.status(
          'POST',
          '/billing/refunds/$id/complete',
          uid: 'acct',
          body: {'outcome': 'completed', 'method': 'cash'},
        ),
        409,
      );
      // a rejected refund releases the amount
      await k.requestRefund(pid, 100000, invoiceId: invoiceId);
    });

    test('a refund cannot be completed before approval', () async {
      final rf = await k.requestRefund(pid, 10000, invoiceId: invoiceId);
      expect(
        await h.status(
          'POST',
          '/billing/refunds/${rf['refundId']}/complete',
          uid: 'acct',
          body: {'outcome': 'completed', 'method': 'cash'},
        ),
        409,
      );
    });
  });

  group('completion', () {
    test(
      'a completed refund updates the invoice and keeps the payment',
      () async {
        final done = await k.refundDone(pid, 30000, invoiceId: invoiceId);
        expect(done['status'], 'completed');
        expect(done['processedBy'], 'acct');
        expect(done['method'], 'cash');
        var d = await k.invoice(invoiceId);
        expect(d['status'], 'partially_refunded');
        expect(d['amountRefunded'], 30000);
        expect(
          d['amountPaid'],
          100000,
          reason: 'the original payment is preserved',
        );
        expect(d['outstanding'], 0);
        final p = await h.okData(
          h.call('GET', '/billing/payments/$pid', uid: 'acct'),
        );
        expect(p['amount'], 100000);
        expect(p['refundedTotal'], 30000);
        expect(p['status'], 'completed');

        await k.refundDone(pid, 70000, invoiceId: invoiceId);
        d = await k.invoice(invoiceId);
        expect(d['status'], 'refunded');
        expect(d['amountRefunded'], 100000);
        expect(
          await h.status(
            'POST',
            '/billing/refunds',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'paymentId': pid,
              'invoiceId': invoiceId,
              'amountMinor': 1,
              'reason': 'One more paisa',
            },
          ),
          409,
        );
        expect(
          k.auditActions(),
          containsAll(['refund.approved', 'refund.completed']),
        );
      },
    );

    test(
      'offline refunds record the actual method; non-cash needs a reference',
      () async {
        final rf = await k.requestRefund(pid, 10000, invoiceId: invoiceId);
        final id = rf['refundId']! as String;
        await k.refundAction(id, 'approve');
        Future<int> complete(Map<String, Object?> b) => h.status(
          'POST',
          '/billing/refunds/$id/complete',
          uid: 'acct',
          body: b,
        );
        expect(await complete({'outcome': 'completed'}), 422);
        expect(await complete({'outcome': 'completed', 'method': 'upi'}), 422);
        expect(
          await complete({'outcome': 'completed', 'method': 'razorpay'}),
          422,
        );
        expect(await complete({'outcome': 'bogus', 'method': 'cash'}), 422);
        expect(
          await h.status(
            'POST',
            '/billing/refunds/$id/complete',
            uid: 'recep',
            body: {'outcome': 'completed', 'method': 'cash'},
          ),
          403,
        );
        expect(
          await complete({
            'outcome': 'completed',
            'method': 'upi',
            'reference': 'UTR-RF-1',
          }),
          200,
        );
        final d = await h.okData(
          h.call('GET', '/billing/refunds/$id', uid: 'acct'),
        );
        expect(d['method'], 'upi');
        expect(d['reference'], 'UTR-RF-1');
      },
    );

    test('a failed refund is kept and can be retried', () async {
      final rf = await k.requestRefund(pid, 20000, invoiceId: invoiceId);
      final id = rf['refundId']! as String;
      await k.refundAction(id, 'approve');
      final failed = await k.refundAction(
        id,
        'complete',
        uid: 'acct',
        body: {'outcome': 'failed', 'failureReason': 'Bank transfer bounced'},
      );
      expect(failed['status'], 'failed');
      expect(failed['failureReason'], 'Bank transfer bounced');
      expect(
        (await k.invoice(invoiceId))['amountRefunded'],
        0,
        reason: 'no money moved',
      );
      // the failed attempt still holds the amount, so it cannot be requested twice
      expect(
        await h.status(
          'POST',
          '/billing/refunds',
          uid: 'recep',
          headers: {'idempotency-key': k.key()},
          body: {
            'paymentId': pid,
            'invoiceId': invoiceId,
            'amountMinor': 90000,
            'reason': 'Duplicate attempt',
          },
        ),
        409,
      );
      final retry = await k.refundAction(
        id,
        'complete',
        uid: 'acct',
        body: {'outcome': 'completed', 'method': 'cash'},
      );
      expect(retry['status'], 'completed');
      expect(retry['attempts'], 2);
      expect((retry['history']! as List).map((e) => (e as Map)['status']), [
        'requested',
        'approved',
        'failed',
        'completed',
      ]);
      expect((await k.invoice(invoiceId))['amountRefunded'], 20000);
    });

    test(
      'a failed refund can be abandoned, which releases the amount',
      () async {
        final rf = await k.requestRefund(pid, 20000, invoiceId: invoiceId);
        final id = rf['refundId']! as String;
        await k.refundAction(id, 'approve');
        await k.refundAction(
          id,
          'complete',
          uid: 'acct',
          body: {'outcome': 'failed', 'failureReason': 'Account closed'},
        );
        final r = await k.refundAction(
          id,
          'reject',
          body: {'reason': 'Patient declined the refund'},
        );
        expect(r['status'], 'rejected');
        await k.requestRefund(pid, 100000, invoiceId: invoiceId);
      },
    );

    test('completing twice is a replay and never refunds twice', () async {
      final rf = await k.requestRefund(pid, 20000, invoiceId: invoiceId);
      final id = rf['refundId']! as String;
      await k.refundAction(id, 'approve');
      final body = {'outcome': 'completed', 'method': 'cash'};
      await k.refundAction(id, 'complete', uid: 'acct', body: body);
      final again = await k.refundAction(
        id,
        'complete',
        uid: 'acct',
        body: body,
      );
      expect(again['idempotentReplay'], true);
      expect(
        await h.status(
          'POST',
          '/billing/refunds/$id/complete',
          uid: 'acct',
          body: {
            'outcome': 'completed',
            'method': 'cheque',
            'reference': 'CHQ1',
          },
        ),
        409,
      );
      expect((await k.invoice(invoiceId))['amountRefunded'], 20000);
      expect(
        k.auditActions().where((a) => a == 'refund.completed'),
        hasLength(1),
      );
    });

    test('racing completions apply the refund once', () async {
      final rf = await k.requestRefund(pid, 20000, invoiceId: invoiceId);
      final id = rf['refundId']! as String;
      await k.refundAction(id, 'approve');
      final res = await Future.wait([
        for (var i = 0; i < 4; i++)
          h.call(
            'POST',
            '/billing/refunds/$id/complete',
            uid: 'acct',
            body: {'outcome': 'completed', 'method': 'cash'},
          ),
      ]);
      expect(res.map((r) => r.statusCode), everyElement(200));
      expect((await k.invoice(invoiceId))['amountRefunded'], 20000);
    });

    test('processing is an intermediate state', () async {
      final rf = await k.requestRefund(pid, 20000, invoiceId: invoiceId);
      final id = rf['refundId']! as String;
      await k.refundAction(id, 'approve');
      final p = await k.refundAction(
        id,
        'complete',
        uid: 'acct',
        body: {
          'outcome': 'processing',
          'method': 'cheque',
          'reference': 'CHQ-77',
        },
      );
      expect(p['status'], 'processing');
      expect((await k.invoice(invoiceId))['amountRefunded'], 0);
      final done = await k.refundAction(
        id,
        'complete',
        uid: 'acct',
        body: {
          'outcome': 'completed',
          'method': 'cheque',
          'reference': 'CHQ-77',
        },
      );
      expect(done['status'], 'completed');
    });

    test(
      'an unapplied advance can be refunded out of the credit ledger',
      () async {
        final adv = await k.advance(30000);
        final rf = await k.requestRefund(adv['paymentId']! as String, 12000);
        expect(rf.containsKey('invoiceId'), isFalse);
        await k.refundAction(rf['refundId']! as String, 'approve');
        await k.refundAction(
          rf['refundId']! as String,
          'complete',
          uid: 'acct',
          body: {'outcome': 'completed', 'method': 'cash'},
        );
        final c = await k.credits();
        expect(c['balance'], 18000);
        expect(
          (c['ledger']! as List).map((e) => (e as Map)['type']),
          contains('refund_out'),
        );
        // cannot refund more than is left unapplied
        expect(
          await h.status(
            'POST',
            '/billing/refunds',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'paymentId': adv['paymentId'],
              'amountMinor': 20000,
              'reason': 'Too much',
            },
          ),
          409,
        );
        // a payment without an advance needs an invoice
        expect(
          await h.status(
            'POST',
            '/billing/refunds',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'paymentId': pid,
              'amountMinor': 100,
              'reason': 'No invoice named',
            },
          ),
          409,
        );
      },
    );
  });

  group('reads', () {
    test('refunds list by status and stay within the clinic', () async {
      await k.refundDone(pid, 10000, invoiceId: invoiceId);
      await k.requestRefund(pid, 5000, invoiceId: invoiceId);
      Future<List<Object?>> list(String q, {String uid = 'acct'}) async =>
          h.list(await h.call('GET', '/billing/refunds$q', uid: uid));
      expect(await list(''), hasLength(2));
      expect(await list('?status=completed'), hasLength(1));
      expect(await list('?status=requested'), hasLength(1));
      expect(
        await h.status('GET', '/billing/refunds?status=bogus', uid: 'acct'),
        400,
      );
      expect(await h.status('GET', '/billing/refunds', uid: 'nurse'), 403);
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(await list('', uid: 'ownerB'), isEmpty);
    });
  });
}
