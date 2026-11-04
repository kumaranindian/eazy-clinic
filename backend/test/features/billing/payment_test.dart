import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late BillingClinic k;

  setUp(() async {
    h = PlatformHarness();
    k = BillingClinic(h);
    await k.init();
  });

  Future<List<Object?>> listOf(String path, {String uid = 'recep'}) async =>
      h.list(await h.call('GET', path, uid: uid));

  group('collecting payments', () {
    test('a full payment settles the invoice and issues a receipt', () async {
      final inv = await k.finalized(amount: 100000);
      final id = inv['invoiceId']! as String;
      final p = await k.pay(id, 100000);
      expect(p['status'], 'completed');
      expect(p['source'], 'offline');
      expect(p['receivedBy'], 'recep');
      expect(p['currency'], 'INR');
      final rc = p['receipt']! as Map;
      expect(rc['receiptNumber'], 'RCT-000001');
      expect(rc['amount'], 100000);
      expect(
        (rc['invoices']! as List).first,
        containsPair('outstandingAfter', 0),
      );
      final after = await k.invoice(id);
      expect(after['status'], 'paid');
      expect(after['outstanding'], 0);
      expect(after['amountPaid'], 100000);
      expect(k.auditActions(), contains('payment.collected'));
    });

    test('partial payments add up until the invoice is paid', () async {
      final inv = await k.finalized(amount: 100000);
      final id = inv['invoiceId']! as String;
      await k.pay(id, 30000, method: 'upi', reference: 'UTR123456');
      var d = await k.invoice(id);
      expect(d['status'], 'partially_paid');
      expect(d['outstanding'], 70000);
      await k.pay(id, 50000, method: 'card', reference: 'AUTH998');
      d = await k.invoice(id);
      expect(d['outstanding'], 20000);
      await k.pay(id, 20000);
      d = await k.invoice(id);
      expect(d['status'], 'paid');
      expect(d['amountPaid'], 100000);
      final pays = await h.okData(
        h.call('GET', '/billing/invoices/$id/payments', uid: 'recep'),
      );
      expect((pays['payments']! as List), hasLength(3));
    });

    test('one payment can settle several invoices', () async {
      final a = await k.finalized(amount: 40000);
      final b = await k.finalized(amount: 60000);
      final p = await h.okData(
        h.call(
          'POST',
          '/billing/payments',
          uid: 'recep',
          headers: {'idempotency-key': k.key()},
          body: {
            'patientId': k.patient,
            'branchId': k.br,
            'amountMinor': 100000,
            'method': 'cash',
            'allocations': [
              {'invoiceId': a['invoiceId'], 'amountMinor': 40000},
              {'invoiceId': b['invoiceId'], 'amountMinor': 60000},
            ],
          },
        ),
        status: 201,
      );
      expect((p['allocations']! as List), hasLength(2));
      expect((await k.invoice(a['invoiceId']! as String))['status'], 'paid');
      expect((await k.invoice(b['invoiceId']! as String))['status'], 'paid');
    });

    test('overpayment is rejected unless it is an explicit advance', () async {
      final inv = await k.finalized(amount: 50000);
      final id = inv['invoiceId']! as String;
      Map<String, Object?> body({
        int amount = 60000,
        int alloc = 50000,
        bool? advance,
      }) => {
        'patientId': k.patient,
        'branchId': k.br,
        'amountMinor': amount,
        'method': 'cash',
        'allocations': [
          {'invoiceId': id, 'amountMinor': alloc},
        ],
        'advance': ?advance,
      };
      // 10000 left over without saying so
      expect(await k.payStatus(body(), idemKey: k.key()), 422);
      // allocating more than is outstanding
      expect(
        await k.payStatus(body(alloc: 60000, advance: true), idemKey: k.key()),
        409,
      );
      // allocation larger than the payment itself
      expect(await k.payStatus(body(amount: 40000), idemKey: k.key()), 422);
      expect(
        (await k.invoice(id))['outstanding'],
        50000,
        reason: 'nothing was recorded',
      );
      // the explicit workflow needs payment.record_advance (nurses have none; receptionists do)
      final ok = await h.okData(
        h.call(
          'POST',
          '/billing/payments',
          uid: 'recep',
          headers: {'idempotency-key': k.key()},
          body: body(advance: true),
        ),
        status: 201,
      );
      expect(ok['advanceAmount'], 10000);
      expect((await k.credits())['balance'], 10000);
    });

    test(
      'method and reference are validated; online is not available',
      () async {
        final inv = await k.finalized(amount: 10000);
        final id = inv['invoiceId']! as String;
        Map<String, Object?> body(String method, {String? ref}) => {
          'patientId': k.patient,
          'branchId': k.br,
          'amountMinor': 1000,
          'method': method,
          'reference': ?ref,
          'allocations': [
            {'invoiceId': id, 'amountMinor': 1000},
          ],
        };
        expect(await k.payStatus(body('razorpay'), idemKey: k.key()), 422);
        expect(await k.payStatus(body('online'), idemKey: k.key()), 422);
        expect(
          await k.payStatus(body('upi'), idemKey: k.key()),
          422,
          reason: 'UPI needs the reference',
        );
        expect(await k.payStatus(body('cheque'), idemKey: k.key()), 422);
        expect(
          await k.payStatus(body('upi', ref: 'UTR1'), idemKey: k.key()),
          201,
        );
        // custom methods come from settings
        expect(await k.payStatus(body('wallet'), idemKey: k.key()), 422);
        await h.okData(
          h.call(
            'PUT',
            '/billing/settings',
            uid: 'owner',
            body: {
              'customPaymentMethods': ['wallet'],
            },
          ),
        );
        expect(await k.payStatus(body('wallet'), idemKey: k.key()), 201);
        expect(
          await h.status(
            'PUT',
            '/billing/settings',
            uid: 'owner',
            body: {
              'customPaymentMethods': ['razorpay'],
            },
          ),
          422,
        );
      },
    );

    test(
      'the client cannot set status, tenant, receiver or amounts paid',
      () async {
        final inv = await k.finalized(amount: 10000);
        final id = inv['invoiceId']! as String;
        for (final f in [
          'status',
          'tenantId',
          'receivedBy',
          'allocatedTotal',
          'receiptNumber',
          'source',
          'paid',
        ]) {
          expect(
            await k.payStatus({
              'patientId': k.patient,
              'branchId': k.br,
              'amountMinor': 1000,
              'method': 'cash',
              'allocations': [
                {'invoiceId': id, 'amountMinor': 1000},
              ],
              f: 'x',
            }, idemKey: k.key()),
            422,
            reason: f,
          );
        }
        expect(h.docsOf('payments'), isEmpty);
      },
    );

    test('permissions: nurses and doctors cannot collect', () async {
      final inv = await k.finalized(amount: 10000);
      final id = inv['invoiceId']! as String;
      for (final uid in ['nurse', 'docuser']) {
        expect(
          await k.payStatus(
            {
              'patientId': k.patient,
              'branchId': k.br,
              'amountMinor': 1000,
              'method': 'cash',
              'allocations': [
                {'invoiceId': id, 'amountMinor': 1000},
              ],
            },
            uid: uid,
            idemKey: k.key(),
          ),
          403,
        );
      }
    });

    test(
      'a draft or cancelled invoice and another patient\'s invoice take no payment',
      () async {
        final draft = await k.draft(
          lines: [
            {'description': 'Item A', 'unitMinor': 1000, 'quantity': 1},
          ],
        );
        expect(
          await k.payStatus({
            'patientId': k.patient,
            'branchId': k.br,
            'amountMinor': 100,
            'method': 'cash',
            'allocations': [
              {'invoiceId': draft['invoiceId'], 'amountMinor': 100},
            ],
          }, idemKey: k.key()),
          409,
        );
        final other = await k.c.morePatient(2);
        final inv = await k.finalized(amount: 1000);
        expect(
          await k.payStatus({
            'patientId': other,
            'branchId': k.br,
            'amountMinor': 100,
            'method': 'cash',
            'allocations': [
              {'invoiceId': inv['invoiceId'], 'amountMinor': 100},
            ],
          }, idemKey: k.key()),
          404,
        );
      },
    );

    test(
      'payments in another clinic cannot reach this clinic\'s invoice',
      () async {
        final inv = await k.finalized(amount: 1000);
        await h.createClinic('ownerB', name: 'Other Clinic');
        final brB = await h.newBranch('ownerB', code: 'BEE');
        final pB = (await h.newPatient('ownerB', brB))['patientId']! as String;
        expect(
          await k.payStatus(
            {
              'patientId': pB,
              'branchId': brB,
              'amountMinor': 100,
              'method': 'cash',
              'allocations': [
                {'invoiceId': inv['invoiceId'], 'amountMinor': 100},
              ],
            },
            uid: 'ownerB',
            idemKey: k.key(),
          ),
          404,
        );
        expect(await listOf('/billing/payments', uid: 'ownerB'), isEmpty);
      },
    );
  });

  group('idempotency and concurrency', () {
    test('repeating a request with the same key records one payment', () async {
      final inv = await k.finalized(amount: 100000);
      final id = inv['invoiceId']! as String;
      final a = await k.pay(id, 30000, idemKey: 'key-same-0001');
      final b = await k.pay(id, 30000, idemKey: 'key-same-0001', status: 201);
      expect(b['idempotentReplay'], true);
      expect(b['paymentId'], a['paymentId']);
      expect(h.docsOf('payments'), hasLength(1));
      expect(h.docsOf('receipts'), hasLength(1));
      expect((await k.invoice(id))['amountPaid'], 30000);
    });

    test(
      'the same key with another body is a conflict; a missing key is refused',
      () async {
        final inv = await k.finalized(amount: 100000);
        final id = inv['invoiceId']! as String;
        await k.pay(id, 30000, idemKey: 'key-same-0002');
        expect(
          await k.payStatus({
            'patientId': k.patient,
            'branchId': k.br,
            'amountMinor': 40000,
            'method': 'cash',
            'allocations': [
              {'invoiceId': id, 'amountMinor': 40000},
            ],
          }, idemKey: 'key-same-0002'),
          409,
        );
        expect(
          await k.payStatus({
            'patientId': k.patient,
            'branchId': k.br,
            'amountMinor': 100,
            'method': 'cash',
            'allocations': [
              {'invoiceId': id, 'amountMinor': 100},
            ],
          }),
          400,
        );
        expect(await k.payStatus({'x': 1}, idemKey: 'short'), 400);
      },
    );

    test('racing duplicate requests record exactly one payment', () async {
      final inv = await k.finalized(amount: 100000);
      final id = inv['invoiceId']! as String;
      final res = await Future.wait([
        for (var i = 0; i < 5; i++)
          h.call(
            'POST',
            '/billing/payments',
            uid: 'recep',
            headers: {'idempotency-key': 'key-race-0001'},
            body: {
              'patientId': k.patient,
              'branchId': k.br,
              'amountMinor': 20000,
              'method': 'cash',
              'allocations': [
                {'invoiceId': id, 'amountMinor': 20000},
              ],
            },
          ),
      ]);
      expect(res.map((r) => r.statusCode), everyElement(anyOf(200, 201)));
      expect(h.docsOf('payments'), hasLength(1));
      expect((await k.invoice(id))['amountPaid'], 20000);
    });

    test('racing different payments never overpay the invoice', () async {
      final inv = await k.finalized(amount: 100000);
      final id = inv['invoiceId']! as String;
      final res = await Future.wait([
        for (var i = 0; i < 5; i++)
          h.call(
            'POST',
            '/billing/payments',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'patientId': k.patient,
              'branchId': k.br,
              'amountMinor': 40000,
              'method': 'cash',
              'allocations': [
                {'invoiceId': id, 'amountMinor': 40000},
              ],
            },
          ),
      ]);
      final okCount = res.where((r) => r.statusCode == 201).length;
      expect(okCount, 2, reason: '40000 x 2 fits, a third would exceed 100000');
      final d = await k.invoice(id);
      expect(d['amountPaid'], 80000);
      expect(d['outstanding'], 20000);
      expect(h.docsOf('payments'), hasLength(2));
    });

    test('receipt numbers are unique under concurrency', () async {
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        ids.add((await k.finalized(amount: 1000))['invoiceId']! as String);
      }
      final res = await Future.wait([
        for (final id in ids)
          h.call(
            'POST',
            '/billing/payments',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'patientId': k.patient,
              'branchId': k.br,
              'amountMinor': 1000,
              'method': 'cash',
              'allocations': [
                {'invoiceId': id, 'amountMinor': 1000},
              ],
            },
          ),
      ]);
      expect(res.map((r) => r.statusCode), everyElement(201));
      final numbers = [for (final d in h.docsOf('receipts')) d['receiptNumber']]
        ..sort((a, b) => '$a'.compareTo('$b'));
      expect(numbers, [
        for (var i = 1; i <= 5; i++) 'RCT-${i.toString().padLeft(6, '0')}',
      ]);
    });
  });

  group('receipts', () {
    test('a receipt can be read again without creating a payment', () async {
      final inv = await k.finalized(amount: 100000);
      final p = await k.pay(
        inv['invoiceId']! as String,
        40000,
        method: 'upi',
        reference: 'UTR777',
      );
      expect(h.docsOf('payments'), hasLength(1));
      final byPayment = await h.okData(
        h.call(
          'GET',
          '/billing/payments/${p['paymentId']}/receipt',
          uid: 'recep',
        ),
      );
      final byId = await h.okData(
        h.call(
          'GET',
          '/billing/receipts/${(p['receipt']! as Map)['receiptId']}',
          uid: 'acct',
        ),
      );
      expect(byPayment['receiptNumber'], byId['receiptNumber']);
      expect(byPayment['method'], 'upi');
      expect(byPayment['reference'], 'UTR777');
      expect((byPayment['clinic']! as Map)['name'], isNotNull);
      expect(byPayment['patientMrn'], isNotNull);
      expect(byPayment['patientOutstandingNow'], 60000);
      expect(h.docsOf('payments'), hasLength(1));
      expect(h.docsOf('receipts'), hasLength(1));
      expect(
        k.auditActions().where((a) => a == 'receipt.viewed'),
        hasLength(2),
      );
    });

    test('receipts are tenant and branch scoped', () async {
      final inv = await k.finalized(amount: 1000);
      final p = await k.pay(inv['invoiceId']! as String, 1000);
      final rid = (p['receipt']! as Map)['receiptId'];
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status('GET', '/billing/receipts/$rid', uid: 'ownerB'),
        404,
      );
      expect(
        await h.status(
          'GET',
          '/billing/payments/${p['paymentId']}/receipt',
          uid: 'ownerB',
        ),
        404,
      );
      final br2 = await h.newBranch('owner', code: 'BR2');
      h.member(
        'recep2',
        k.tid,
        'receptionist',
        allBranches: false,
        branchIds: [br2],
      );
      expect(
        await h.status('GET', '/billing/receipts/$rid', uid: 'recep2'),
        404,
      );
      expect(
        await h.status(
          'GET',
          '/billing/payments/${p['paymentId']}',
          uid: 'recep2',
        ),
        404,
      );
      expect(
        await h.status('GET', '/billing/receipts/$rid', uid: 'nurse'),
        403,
      );
    });
  });

  group('advance payments and patient credit', () {
    test(
      'an advance becomes credit that can be applied to an invoice',
      () async {
        final adv = await k.advance(50000);
        expect(adv['advanceAmount'], 50000);
        expect((adv['receipt']! as Map)['receiptNumber'], 'RCT-000001');
        var c = await k.credits();
        expect(c['balance'], 50000);
        final source = (c['sources']! as List).single as Map;
        expect(source['remaining'], 50000);
        final inv = await k.finalized(amount: 70000);
        final applied = await h.okData(
          h.call(
            'POST',
            '/billing/patient-credits/${source['entryId']}/allocations',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'allocations': [
                {'invoiceId': inv['invoiceId'], 'amountMinor': 50000},
              ],
            },
          ),
          status: 201,
        );
        expect(applied['remaining'], 0);
        expect(applied['balance'], 0);
        final d = await k.invoice(inv['invoiceId']! as String);
        expect(d['status'], 'partially_paid');
        expect(d['outstanding'], 20000);
        c = await k.credits();
        expect(c['balance'], 0);
        expect(c['sources'], isEmpty);
        expect(
          (c['ledger']! as List).map((e) => (e as Map)['type']),
          containsAll(['advance_in', 'applied']),
        );
      },
    );

    test('credit cannot be applied twice or beyond what is left', () async {
      final adv = await k.advance(30000);
      final src = (adv['creditId'])! as String;
      final inv = await k.finalized(amount: 100000);
      Future<int> apply(int amount, {String? idem}) => h.status(
        'POST',
        '/billing/patient-credits/$src/allocations',
        uid: 'recep',
        headers: {'idempotency-key': idem ?? k.key()},
        body: {
          'allocations': [
            {'invoiceId': inv['invoiceId'], 'amountMinor': amount},
          ],
        },
      );
      expect(await apply(40000), 409, reason: 'only 30000 exists');
      expect(await apply(20000, idem: 'key-credit-001'), 201);
      // the same request again is a replay, not a second application
      expect(await apply(20000, idem: 'key-credit-001'), 201);
      expect((await k.credits())['balance'], 10000);
      // a fresh key asking for more than the remaining 10000
      expect(await apply(20000), 409);
      expect(await apply(10000), 201);
      expect((await k.credits())['balance'], 0);
      expect(await apply(1), 409);
      expect(
        (await k.invoice(inv['invoiceId']! as String))['amountPaid'],
        30000,
      );
    });

    test(
      'credit cannot be applied to another patient\'s invoice or beyond the invoice due',
      () async {
        final adv = await k.advance(30000);
        final src = (adv['creditId'])! as String;
        final p2 = await k.c.morePatient(2);
        final other = await k.finalized(amount: 5000, patientId: p2);
        final mine = await k.finalized(amount: 5000);
        Future<int> apply(String invoiceId, int amount) => h.status(
          'POST',
          '/billing/patient-credits/$src/allocations',
          uid: 'recep',
          headers: {'idempotency-key': k.key()},
          body: {
            'allocations': [
              {'invoiceId': invoiceId, 'amountMinor': amount},
            ],
          },
        );
        expect(await apply(other['invoiceId']! as String, 1000), 404);
        expect(await apply(mine['invoiceId']! as String, 6000), 409);
        expect(await apply(mine['invoiceId']! as String, 5000), 201);
      },
    );

    test(
      'the payment allocations endpoint applies the leftover of that payment',
      () async {
        final adv = await k.advance(30000);
        final inv = await k.finalized(amount: 10000);
        final r = await h.okData(
          h.call(
            'POST',
            '/billing/payments/${adv['paymentId']}/allocations',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'allocations': [
                {'invoiceId': inv['invoiceId'], 'amountMinor': 10000},
              ],
            },
          ),
          status: 201,
        );
        expect(r['remaining'], 20000);
        // a payment that was fully allocated has nothing to apply
        final paid = await k.finalized(amount: 1000);
        final p = await k.pay(paid['invoiceId']! as String, 1000);
        expect(
          await h.status(
            'POST',
            '/billing/payments/${p['paymentId']}/allocations',
            uid: 'recep',
            headers: {'idempotency-key': k.key()},
            body: {
              'allocations': [
                {'invoiceId': inv['invoiceId'], 'amountMinor': 1},
              ],
            },
          ),
          409,
        );
      },
    );

    test('the ledger always explains the balance', () async {
      final a1 = await k.advance(40000);
      await k.advance(25000);
      final inv = await k.finalized(amount: 50000);
      await h.okData(
        h.call(
          'POST',
          '/billing/patient-credits/${a1['creditId']}/allocations',
          uid: 'recep',
          headers: {'idempotency-key': k.key()},
          body: {
            'allocations': [
              {'invoiceId': inv['invoiceId'], 'amountMinor': 30000},
            ],
          },
        ),
        status: 201,
      );
      // a reasoned adjustment (needs billing.adjust)
      await h.okData(
        h.call(
          'POST',
          '/billing/patient-credits',
          uid: 'acct',
          headers: {'idempotency-key': k.key()},
          body: {
            'kind': 'adjustment',
            'patientId': k.patient,
            'branchId': k.br,
            'direction': 'in',
            'amountMinor': 5000,
            'reason': 'Goodwill credit',
          },
        ),
        status: 201,
      );
      final c = await k.credits();
      final signed = (c['ledger']! as List).fold<int>(0, (a, e) {
        final m = e as Map;
        return a +
            (m['direction'] == 'in'
                ? m['amount'] as int
                : -(m['amount'] as int));
      });
      expect(c['balance'], signed);
      expect(c['balance'], 40000);
      final sourceSum = (c['sources']! as List).fold<int>(
        0,
        (a, e) => a + ((e as Map)['remaining'] as int),
      );
      expect(sourceSum, c['balance']);
      // every ledger entry records the balance after it
      for (final e in (c['ledger']! as List)) {
        expect((e as Map)['balanceAfter'], isA<int>());
      }
    });

    test(
      'adjustments need a reason, permission and cannot go below zero',
      () async {
        final adv = await k.advance(10000);
        Future<int> adjust(Map<String, Object?> b, {String uid = 'acct'}) =>
            h.status(
              'POST',
              '/billing/patient-credits',
              uid: uid,
              headers: {'idempotency-key': k.key()},
              body: {
                'kind': 'adjustment',
                'patientId': k.patient,
                'branchId': k.br,
                ...b,
              },
            );
        expect(
          await adjust({
            'direction': 'out',
            'amountMinor': 1,
            'reason': 'x',
            'creditId': adv['creditId'],
          }),
          422,
        );
        expect(
          await adjust({
            'direction': 'out',
            'amountMinor': 1000,
            'reason': 'Entered twice',
            'creditId': adv['creditId'],
          }, uid: 'recep'),
          403,
        );
        expect(
          await adjust({
            'direction': 'out',
            'amountMinor': 1000,
            'reason': 'Entered twice',
          }),
          422,
          reason: 'must name the credit',
        );
        expect(
          await adjust({
            'direction': 'out',
            'amountMinor': 20000,
            'reason': 'Entered twice',
            'creditId': adv['creditId'],
          }),
          409,
        );
        expect(
          await adjust({
            'direction': 'out',
            'amountMinor': 10000,
            'reason': 'Entered twice',
            'creditId': adv['creditId'],
          }),
          201,
        );
        expect((await k.credits())['balance'], 0);
        expect(
          await adjust({
            'direction': 'out',
            'amountMinor': 1,
            'reason': 'Again please',
            'creditId': adv['creditId'],
          }),
          409,
        );
      },
    );

    test('an advance needs its own permission and kind', () async {
      expect(
        await h.status(
          'POST',
          '/billing/patient-credits',
          uid: 'nurse',
          headers: {'idempotency-key': k.key()},
          body: {
            'kind': 'advance',
            'patientId': k.patient,
            'branchId': k.br,
            'amountMinor': 100,
            'method': 'cash',
          },
        ),
        403,
      );
      expect(
        await h.status(
          'POST',
          '/billing/patient-credits',
          uid: 'recep',
          headers: {'idempotency-key': k.key()},
          body: {'kind': 'bogus'},
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/billing/patient-credits',
          uid: 'recep',
          headers: {'idempotency-key': k.key()},
          body: {
            'kind': 'advance',
            'patientId': k.patient,
            'branchId': k.br,
            'amountMinor': 100,
            'method': 'cash',
            'allocations': <Object?>[],
          },
        ),
        422,
      );
    });
  });

  group('lists', () {
    test('payments can be filtered by method and date', () async {
      final inv = await k.finalized(amount: 100000);
      final id = inv['invoiceId']! as String;
      await k.pay(id, 10000);
      await k.pay(id, 20000, method: 'upi', reference: 'UTR1');
      expect(await listOf('/billing/payments'), hasLength(2));
      expect(await listOf('/billing/payments?method=upi'), hasLength(1));
      expect(
        await listOf('/billing/payments?from=2026-06-01&to=2026-06-01'),
        hasLength(2),
      );
      expect(await listOf('/billing/payments?from=2026-06-02'), isEmpty);
      expect(
        await h.status('GET', '/billing/payments?from=bad', uid: 'recep'),
        400,
      );
    });
  });
}
