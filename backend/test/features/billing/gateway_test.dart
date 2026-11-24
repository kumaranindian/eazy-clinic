import 'dart:convert';

import 'package:backend/features/billing/gateway/provider.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  group('state machine', () {
    test('final states never move; capture needs an open payment', () {
      for (final f in ['failed', 'cancelled', 'refunded']) {
        for (final to in gatewayStatuses) {
          expect(canMoveGateway(f, to), isFalse, reason: '$f -> $to');
        }
      }
      expect(canMoveGateway('pending', 'captured'), isTrue);
      expect(canMoveGateway('captured', 'pending'), isFalse);
      expect(canMoveGateway('captured', 'authorized'), isFalse);
      expect(canMoveGateway('intent', 'captured'), isFalse);
      expect(canMoveGateway('disputed', 'captured'), isTrue);
    });

    test('signatures: constant-time compare, case-insensitive hex', () {
      final h = hmacHex('s', utf8.encode('body'));
      expect(signaturesEqual(h, h.toUpperCase()), isTrue);
      expect(signaturesEqual(h, '${h}0'), isFalse);
      expect(
        signaturesEqual(h, h.replaceFirst(h[0], h[0] == 'a' ? 'b' : 'a')),
        isFalse,
      );
    });

    test('environment credentials need all three parts and a valid ref', () {
      final r = EnvCredentialResolver({
        'PAYMENT_CRED_ACME_1_KEY': 'k',
        'PAYMENT_CRED_ACME_1_SECRET': 'sekret-xyz',
        'PAYMENT_CRED_ACME_1_WEBHOOK': 'w',
        'PAYMENT_CRED_HALF_KEY': 'k',
      });
      expect(r.resolve('ACME_1')?.webhookSecret, 'w');
      expect(r.resolve('HALF'), isNull);
      expect(r.resolve('acme_1'), isNull);
      expect(r.resolve('ACME_1; rm'), isNull);
      expect(r.resolve('ACME_1')!.toString(), isNot(contains('sekret')));
    });
  });

  group('online payments', () {
    late PlatformHarness h;
    late BillingClinic k;

    String hex(String secret, String raw) => hmacHex(secret, utf8.encode(raw));

    Future<Response> hook(
      Map<String, Object?> payload, {
      String? sig,
      String secret = 'whsec_1',
      String provider = 'sandbox',
      String? tenant,
      String? rawOverride,
    }) {
      final raw = rawOverride ?? jsonEncode(payload);
      return Future.sync(
        () => h.handler(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/api/v1/webhooks/payments/$provider/${tenant ?? k.tid}',
            ),
            headers: {
              'content-type': 'application/json',
              'x-signature': sig ?? hex(secret, raw),
            },
            body: raw,
          ),
        ),
      );
    }

    int ev = 0;
    Map<String, Object?> event(
      String type,
      String ref, {
      int? amount,
      String currency = 'INR',
      String? id,
      Map<String, Object?>? extra,
    }) => {
      'id': id ?? 'evt_${ev++}',
      'type': type,
      'ref': ref,
      'amountMinor': ?amount,
      'currency': currency,
      ...?extra,
    };

    Future<void> setup({bool configure = true}) async {
      await h.okData(
        h.call(
          'POST',
          '/platform/payments/eligibility/seed-baseline',
          uid: 'root',
        ),
      );
      if (configure) {
        await h.okData(
          h.call(
            'PUT',
            '/billing/gateway/config',
            uid: 'owner',
            body: {
              'provider': 'sandbox',
              'mode': 'test',
              'credentialRef': 'TEST_ACME_1',
            },
          ),
        );
      }
    }

    Future<Map<String, Object?>> intent(
      String invoiceId, {
      int? amount,
      String? idem,
      String uid = 'recep',
    }) => h.okData(
      h.call(
        'POST',
        '/billing/gateway/intents',
        uid: uid,
        headers: {'idempotency-key': idem ?? k.key('gw')},
        body: {'invoiceId': invoiceId, 'amountMinor': ?amount},
      ),
      status: 201,
    );

    Future<Map<String, Object?>> invoice(String id) async {
      final d = await h.okData(
        h.call('GET', '/billing/invoices/$id', uid: 'recep'),
      );
      return ((d['invoice'] ?? d) as Map).cast<String, Object?>();
    }

    Future<List<Map<String, Object?>>> payments() async =>
        h.docsOf('payments').toList();

    setUp(() async {
      h = PlatformHarness();
      h.user('root', role: PlatformRole.superAdmin);
      h.user('support', role: PlatformRole.platformSupportAdmin);
      k = BillingClinic(h);
      await k.init();
    });

    group('eligibility and configuration', () {
      test(
        'platform permissions; candidates cannot be approved; live is off',
        () async {
          await setup(configure: false);
          expect(
            await h.status(
              'GET',
              '/platform/payments/eligibility',
              uid: 'support',
            ),
            200,
          );
          expect(
            await h.status(
              'POST',
              '/platform/payments/eligibility/seed-baseline',
              uid: 'support',
            ),
            403,
          );
          expect(
            await h.status(
              'GET',
              '/platform/payments/eligibility',
              uid: 'owner',
            ),
            403,
          );
          expect(await h.status('GET', '/platform/payments/eligibility'), 401);
          final list = await h.okData(
            h.call('GET', '/platform/payments/eligibility', uid: 'root'),
          );
          final in_ =
              (list['items']! as List).firstWhere(
                    (e) => (e as Map)['countryCode'] == 'IN',
                  )
                  as Map;
          final razor =
              (in_['providers']! as List).firstWhere(
                    (p) => (p as Map)['provider'] == 'razorpay',
                  )
                  as Map;
          expect(razor['status'], 'candidate');
          expect(razor['modes'], isEmpty);
          Future<int> patch(String provider, Map<String, Object?> b) =>
              h.status(
                'PATCH',
                '/platform/payments/eligibility/IN/$provider',
                uid: 'root',
                body: {
                  'expectedVersion': in_['version'],
                  'reason': 'Commercial review',
                  ...b,
                },
              );
          expect(
            await patch('razorpay', {
              'status': 'approved',
              'modes': ['test'],
            }),
            409,
            reason: 'no adapter',
          );
          expect(
            await patch('sandbox', {
              'modes': ['live'],
            }),
            409,
            reason: 'live is disabled',
          );
          expect(await patch('sandbox', {'liveApproved': true}), 409);
          expect(
            await patch('razorpay', {
              'modes': ['test'],
            }),
            409,
            reason: 'not approved',
          );
          expect(await patch('sandbox', {'status': 'bogus'}), 422);
          expect(
            await patch('sandbox', {
              'currencies': ['rupee'],
            }),
            422,
          );
          expect(await patch('nope', {'status': 'disabled'}), 404);
          expect(
            await h.status(
              'PATCH',
              '/platform/payments/eligibility/IN/sandbox',
              uid: 'support',
              body: {
                'expectedVersion': 1,
                'reason': 'x y z',
                'status': 'disabled',
              },
            ),
            403,
          );
          final b = await h.call(
            'POST',
            '/platform/payments/eligibility/seed-baseline',
            uid: 'root',
          );
          expect(b.statusCode, 200);
          expect(
            await patch('sandbox', {'status': 'disabled', 'modes': []}),
            200,
          );
          expect(
            await patch('sandbox', {'status': 'disabled'}),
            409,
            reason: 'stale version',
          );
        },
      );

      test(
        'configuration: owner only, eligibility, credentials, no live',
        () async {
          await setup(configure: false);
          Future<int> put(String uid, Map<String, Object?> b) =>
              h.status('PUT', '/billing/gateway/config', uid: uid, body: b);
          final ok = {
            'provider': 'sandbox',
            'mode': 'test',
            'credentialRef': 'TEST_ACME_1',
          };
          expect(await put('recep', ok), 403);
          expect(await put('nurse', ok), 403);
          expect(await put('acct', ok), 403);
          expect(await put('owner', {...ok, 'provider': 'razorpay'}), 409);
          expect(await put('owner', {...ok, 'mode': 'live'}), 409);
          expect(await put('owner', {...ok, 'credentialRef': 'NOPE_1'}), 422);
          expect(await put('owner', {...ok, 'extra': 1}), 422);
          expect(await put('owner', ok), 200);
          expect(await put('admin', {...ok, 'enabled': false}), 200);
          final cfg = await h.okData(
            h.call('GET', '/billing/gateway/config', uid: 'recep'),
          );
          expect(cfg['provider'], 'sandbox');
          expect(
            cfg.containsKey('credentialRef'),
            isFalse,
            reason: 'only managers see the reference',
          );
          expect(cfg['eligibleProviders'], isEmpty);
          final owner = await h.okData(
            h.call('GET', '/billing/gateway/config', uid: 'owner'),
          );
          expect(owner['credentialRef'], 'TEST_ACME_1');
          expect(jsonEncode(owner), isNot(contains('whsec')));
          expect(jsonEncode(owner), isNot(contains('secret_1')));
          expect(
            h.store.docs.values.map((d) => '$d').join(),
            isNot(contains('whsec_1')),
          );
          expect(
            await h.status('GET', '/billing/gateway/config', uid: 'nurse'),
            403,
          );
        },
      );

      test(
        'a clinic whose currency the provider does not accept is refused',
        () async {
          await setup(configure: false);
          await h.createClinic(
            'ownerAE',
            name: 'Dubai',
            countryCode: 'AE',
            billing: true,
          );
          expect(
            await h.status(
              'PUT',
              '/billing/gateway/config',
              uid: 'ownerAE',
              body: {
                'provider': 'sandbox',
                'mode': 'test',
                'credentialRef': 'TEST_ACME_1',
              },
            ),
            409,
            reason: 'the clinic bills in INR, the AE entry accepts AED',
          );
        },
      );
    });

    group('intents', () {
      test(
        'amount comes from the invoice; idempotent; one open intent',
        () async {
          await setup();
          final inv = await k.finalized(amount: 100000);
          final id = inv['invoiceId']! as String;
          final key = k.key('same');
          final a = await intent(id, idem: key);
          expect(a['amountMinor'], 100000);
          expect(a['currency'], 'INR');
          expect(a['status'], 'pending');
          expect((a['providerRef']! as String).startsWith('sbx_'), isTrue);
          expect(a['checkoutToken'], isNotNull);
          final again = await h.okData(
            h.call(
              'POST',
              '/billing/gateway/intents',
              uid: 'recep',
              headers: {'idempotency-key': key},
              body: {'invoiceId': id},
            ),
            status: 201,
          );
          expect(again['transactionId'], a['transactionId']);
          expect(again['idempotentReplay'], isTrue);
          expect(
            h.sandbox.intentKeys.length,
            1,
            reason: 'the provider was called once',
          );
          expect(
            await h.status(
              'POST',
              '/billing/gateway/intents',
              uid: 'recep',
              headers: {'idempotency-key': key},
              body: {'invoiceId': id, 'amountMinor': 5},
            ),
            409,
            reason: 'key reused with another body',
          );
          expect(
            await h.status(
              'POST',
              '/billing/gateway/intents',
              uid: 'recep',
              headers: {'idempotency-key': k.key('x')},
              body: {'invoiceId': id},
            ),
            409,
            reason: 'already open',
          );
          expect(
            await h.status(
              'POST',
              '/billing/gateway/intents',
              uid: 'recep',
              body: {'invoiceId': id},
            ),
            400,
            reason: 'key required',
          );
        },
      );

      test(
        'cannot ask for more than is due; draft, unknown and foreign invoices refused',
        () async {
          await setup();
          final inv = await k.finalized(amount: 100000);
          final id = inv['invoiceId']! as String;
          Future<int> post(Map<String, Object?> b, {String uid = 'recep'}) =>
              h.status(
                'POST',
                '/billing/gateway/intents',
                uid: uid,
                headers: {'idempotency-key': k.key('i')},
                body: b,
              );
          expect(await post({'invoiceId': id, 'amountMinor': 100001}), 409);
          expect(await post({'invoiceId': id, 'amountMinor': 0}), 422);
          expect(await post({'invoiceId': id, 'amountMinor': -5}), 422);
          expect(await post({'invoiceId': id, 'status': 'captured'}), 422);
          final d = await k.draft(
            lines: [
              {'description': 'x y', 'unitMinor': 1000, 'quantity': 1},
            ],
          );
          expect(await post({'invoiceId': d['invoiceId']}), 409);
          expect(await post({'invoiceId': 'inv_unknown'}), 404);
          expect(await post({'invoiceId': id}, uid: 'nurse'), 403);
          await h.createClinic('ownerB', name: 'Other');
          expect(await post({'invoiceId': id}, uid: 'ownerB'), anyOf(404, 409));
          final list = await h.okData(
            h.call('GET', '/billing/gateway/transactions', uid: 'ownerB'),
          );
          expect(list['items'], isEmpty);
        },
      );

      test('not configured or disabled: nothing is created', () async {
        await setup(configure: false);
        final inv = await k.finalized();
        expect(
          await h.status(
            'POST',
            '/billing/gateway/intents',
            uid: 'recep',
            headers: {'idempotency-key': k.key('a')},
            body: {'invoiceId': inv['invoiceId']},
          ),
          409,
        );
        expect(h.docsOf('gateway_transactions'), isEmpty);
      });

      test(
        'a provider failure marks the transaction failed and allows a retry',
        () async {
          await setup();
          final inv = await k.finalized();
          h.sandbox.failIntents = true;
          expect(
            await h.status(
              'POST',
              '/billing/gateway/intents',
              uid: 'recep',
              headers: {'idempotency-key': k.key('a')},
              body: {'invoiceId': inv['invoiceId']},
            ),
            503,
          );
          expect(h.docsOf('gateway_transactions').single['status'], 'failed');
          h.sandbox.failIntents = false;
          final ok = await intent(inv['invoiceId']! as String);
          expect(ok['status'], 'pending');
        },
      );
    });

    group('webhooks', () {
      Future<(String, String, int)> openIntent({
        int amount = 100000,
        int? partial,
      }) async {
        final inv = await k.finalized(amount: amount);
        final t = await intent(inv['invoiceId']! as String, amount: partial);
        return (
          inv['invoiceId']! as String,
          t['providerRef']! as String,
          t['amountMinor']! as int,
        );
      }

      test(
        'a verified capture records one payment and pays the invoice',
        () async {
          await setup();
          final (invId, ref, amt) = await openIntent();
          final res = await hook(event('payment.captured', ref, amount: amt));
          expect(res.statusCode, 200);
          final pay = (await payments()).single;
          expect(pay['source'], 'gateway');
          expect(pay['method'], 'online');
          expect(pay['amount'], 100000);
          expect(pay['gatewayProvider'], 'sandbox');
          expect(pay['reference'], ref);
          expect((await invoice(invId))['status'], 'paid');
          expect((await invoice(invId))['outstanding'], 0);
          final t = h.docsOf('gateway_transactions').single;
          expect(t['status'], 'captured');
          expect(t['paymentId'], pay['paymentId']);
          expect(h.docsOf('receipts'), hasLength(1));
          expect(k.auditActions(), contains('payment.collected'));
        },
      );

      test('duplicate delivery cannot duplicate a payment', () async {
        await setup();
        final (_, ref, amt) = await openIntent();
        final payload = event(
          'payment.captured',
          ref,
          amount: amt,
          id: 'evt_dup',
        );
        expect((await hook(payload)).statusCode, 200);
        final second = await hook(payload);
        expect(second.statusCode, 200);
        expect(
          jsonDecode(await second.readAsString())['data']['duplicate'],
          isTrue,
        );
        final both = await Future.wait([
          hook(payload),
          hook(payload),
          hook(payload),
        ]);
        expect(both.every((r) => r.statusCode == 200), isTrue);
        expect(await payments(), hasLength(1));
        // the same capture under a new event id is also not a second payment
        expect(
          (await hook(
            event('payment.captured', ref, amount: amt, id: 'evt_other'),
          )).statusCode,
          200,
        );
        expect(await payments(), hasLength(1));
        expect(h.docsOf('receipts'), hasLength(1));
      });

      test(
        'invalid signatures, bodies and providers are refused without effect',
        () async {
          await setup();
          final (_, ref, amt) = await openIntent();
          final good = event('payment.captured', ref, amount: amt);
          expect((await hook(good, sig: 'deadbeef')).statusCode, 401);
          expect(
            (await hook(good, secret: 'whsec_2')).statusCode,
            401,
            reason: 'another clinic\'s secret',
          );
          expect((await hook(good, provider: 'razorpay')).statusCode, 401);
          expect((await hook(good, tenant: 'ten_unknown_x')).statusCode, 401);
          expect(
            (await hook(good, tenant: "bad'path")).statusCode,
            anyOf(401, 404),
          );
          final raw = jsonEncode(good);
          expect(
            (await hook(
              good,
              rawOverride: raw,
              sig: hex('whsec_1', '$raw '),
            ).then((r) => r)).statusCode,
            401,
            reason: 'signature is over the exact bytes',
          );
          expect(
            (await hook(
              {},
              rawOverride: 'not json',
              secret: 'whsec_1',
            )).statusCode,
            401,
          );
          expect(
            (await hook({'id': 'x', 'type': 'payment.captured'})).statusCode,
            401,
            reason: 'signed but malformed',
          );
          expect((await hook(event('payment.exploded', ref))).statusCode, 401);
          expect(await payments(), isEmpty);
          expect(
            h.docsOf('gateway_events'),
            isEmpty,
            reason: 'unauthentic events are not even recorded',
          );
          expect(h.docsOf('gateway_transactions').single['status'], 'pending');
        },
      );

      test('an oversized body is refused', () async {
        await setup();
        final res = await hook({}, rawOverride: 'x' * 70000);
        expect(res.statusCode, anyOf(413, 400));
      });

      test(
        'amount or currency mismatch is never recorded; it opens an exception',
        () async {
          await setup();
          final (_, ref, amt) = await openIntent();
          expect(
            (await hook(
              event('payment.captured', ref, amount: amt - 1),
            )).statusCode,
            200,
          );
          expect(
            (await hook(
              event('payment.captured', ref, amount: amt, currency: 'AED'),
            )).statusCode,
            200,
          );
          expect(
            (await hook(event('payment.captured', ref))).statusCode,
            200,
            reason: 'no amount at all',
          );
          expect(await payments(), isEmpty);
          expect(h.docsOf('gateway_transactions').single['status'], 'pending');
          final types = h
              .docsOf('gateway_exceptions')
              .map((e) => e['type'])
              .toSet();
          expect(types, containsAll(['amount_mismatch', 'currency_mismatch']));
        },
      );

      test(
        'events for unknown transactions open an exception and change nothing',
        () async {
          await setup();
          await openIntent();
          expect(
            (await hook(
              event('payment.captured', 'sbx_gtx_nothing', amount: 1),
            )).statusCode,
            200,
          );
          expect(await payments(), isEmpty);
          expect(
            h.docsOf('gateway_exceptions').single['type'],
            'unknown_transaction',
          );
        },
      );

      test(
        'capture after failure/cancellation is a late-capture exception',
        () async {
          await setup();
          final (_, ref, amt) = await openIntent();
          await hook(event('payment.failed', ref));
          expect(h.docsOf('gateway_transactions').single['status'], 'failed');
          await hook(event('payment.captured', ref, amount: amt));
          expect(await payments(), isEmpty);
          expect(h.docsOf('gateway_exceptions').single['type'], 'late_capture');
          expect(h.docsOf('gateway_transactions').single['status'], 'failed');
        },
      );

      test(
        'authorized then captured; a later failure is a state conflict',
        () async {
          await setup();
          final (_, ref, amt) = await openIntent();
          await hook(event('payment.authorized', ref));
          expect(
            h.docsOf('gateway_transactions').single['status'],
            'authorized',
          );
          await hook(event('payment.captured', ref, amount: amt));
          expect(h.docsOf('gateway_transactions').single['status'], 'captured');
          await hook(event('payment.failed', ref));
          expect(h.docsOf('gateway_transactions').single['status'], 'captured');
          expect(
            h.docsOf('gateway_exceptions').map((e) => e['type']),
            contains('state_conflict'),
          );
          expect(await payments(), hasLength(1));
        },
      );

      test(
        'partial payment leaves a balance; more than is due becomes an advance',
        () async {
          await setup();
          final (invId, ref, amt) = await openIntent(partial: 40000);
          await hook(event('payment.captured', ref, amount: amt));
          final inv = await invoice(invId);
          expect(inv['outstanding'], 60000);
          expect(inv['status'], 'partially_paid');
          // new intent for the rest, but the clinic collects cash first
          final t2 = await intent(invId);
          await k.pay(invId, 60000);
          await hook(
            event(
              'payment.captured',
              t2['providerRef']! as String,
              amount: 60000,
            ),
          );
          final pays = await payments();
          expect(pays, hasLength(3));
          final online = pays.where((p) => p['source'] == 'gateway').toList();
          expect(online, hasLength(2));
          expect(
            online.last['advanceAmount'],
            60000,
            reason: 'nothing left to pay: the money is kept as an advance',
          );
          expect((await invoice(invId))['outstanding'], 0);
        },
      );

      test('settlement facts are stored apart and never computed', () async {
        await setup();
        final (_, ref, amt) = await openIntent();
        await hook(
          event(
            'payment.captured',
            ref,
            amount: amt,
            extra: {
              'settlement': {
                'currency': 'USD',
                'amountMinor': 1180,
                'feeMinor': 30,
                'fxRate': '0.01190',
                'settledAt': '2026-06-03T00:00:00Z',
              },
            },
          ),
        );
        var t = h.docsOf('gateway_transactions').single;
        expect(t['amountMinor'], 100000);
        expect(t['currency'], 'INR');
        final s = t['settlement']! as Map;
        expect(s['currency'], 'USD');
        expect(s['amountMinor'], 1180);
        expect(s['feeMinor'], 30);
        expect(s['fxRate'], '0.01190');
        await hook(
          event(
            'settlement.updated',
            ref,
            extra: {
              'settlement': {'currency': 'USD', 'amountMinor': 1181},
            },
          ),
        );
        t = h.docsOf('gateway_transactions').single;
        expect((t['settlement']! as Map)['amountMinor'], 1181);
        expect(t['amountMinor'], 100000);
      });

      test('disputes move the transaction and need attention', () async {
        await setup();
        final (_, ref, amt) = await openIntent();
        await hook(event('payment.captured', ref, amount: amt));
        await hook(event('dispute.opened', ref));
        expect(h.docsOf('gateway_transactions').single['status'], 'disputed');
        expect(
          h.docsOf('gateway_exceptions').map((e) => e['type']),
          contains('dispute_opened'),
        );
        await hook(event('dispute.closed', ref));
        expect(h.docsOf('gateway_transactions').single['status'], 'captured');
      });

      test(
        'another clinic cannot be reached with this clinic\'s transaction',
        () async {
          await setup();
          final (_, ref, amt) = await openIntent();
          await h.createClinic('ownerB', name: 'Other');
          final tidB =
              h
                      .docsOf('tenants')
                      .firstWhere(
                        (t) => t['clinicName'] == 'Other',
                      )['tenantId']!
                  as String;
          await h.okData(
            h.call(
              'PUT',
              '/billing/gateway/config',
              uid: 'ownerB',
              body: {
                'provider': 'sandbox',
                'mode': 'test',
                'credentialRef': 'TEST_ACME_1',
              },
            ),
          );
          final res = await hook(
            event('payment.captured', ref, amount: amt),
            tenant: tidB,
          );
          expect(res.statusCode, 200);
          expect(
            await payments(),
            isEmpty,
            reason: 'clinic B has no such transaction',
          );
          expect(h.docsOf('gateway_transactions').single['status'], 'pending');
          expect(
            await h.status(
              'GET',
              '/billing/gateway/transactions/${h.docsOf('gateway_transactions').single['transactionId']}',
              uid: 'ownerB',
            ),
            404,
          );
        },
      );
    });

    group('refunds', () {
      Future<(String, String, String)> captured({int amount = 100000}) async {
        final inv = await k.finalized(amount: amount);
        final t = await intent(inv['invoiceId']! as String);
        await hook(
          event(
            'payment.captured',
            t['providerRef']! as String,
            amount: amount,
          ),
        );
        final pay = (await payments()).single;
        return (
          inv['invoiceId']! as String,
          pay['paymentId']! as String,
          t['providerRef']! as String,
        );
      }

      Future<String> approvedRefund(
        String payId,
        String invId,
        int amount,
      ) async {
        final rf = await k.requestRefund(payId, amount, invoiceId: invId);
        final id = rf['refundId']! as String;
        await k.refundAction(id, 'approve');
        return id;
      }

      test(
        'full refund through the provider completes the refund and the transaction',
        () async {
          await setup();
          final (invId, payId, _) = await captured();
          final id = await approvedRefund(payId, invId, 100000);
          final done = await h.okData(
            h.call('POST', '/billing/refunds/$id/gateway', uid: 'acct'),
          );
          expect(done['status'], 'completed');
          expect(done['method'], 'online');
          expect((done['reference']! as String).startsWith('sbxr_'), isTrue);
          expect(
            h.sandbox.refundKeys,
            [id],
            reason: 'the refund id is the provider idempotency key',
          );
          final t = h.docsOf('gateway_transactions').single;
          expect(t['status'], 'refunded');
          expect(t['refundedTotal'], 100000);
          // repeating is safe
          final again = await h.okData(
            h.call('POST', '/billing/refunds/$id/gateway', uid: 'acct'),
          );
          expect(again['status'], 'completed');
          expect(
            h.docsOf('gateway_transactions').single['refundedTotal'],
            100000,
          );
        },
      );

      test(
        'partial refunds accumulate and cannot exceed the payment',
        () async {
          await setup();
          final (invId, payId, _) = await captured();
          final a = await approvedRefund(payId, invId, 30000);
          await h.okData(
            h.call('POST', '/billing/refunds/$a/gateway', uid: 'acct'),
          );
          expect(
            h.docsOf('gateway_transactions').single['status'],
            'partially_refunded',
          );
          final b = await approvedRefund(payId, invId, 70000);
          await h.okData(
            h.call('POST', '/billing/refunds/$b/gateway', uid: 'acct'),
          );
          expect(h.docsOf('gateway_transactions').single['status'], 'refunded');
          expect(
            h.docsOf('gateway_transactions').single['refundedTotal'],
            100000,
          );
        },
      );

      test(
        'a provider that declines leaves the transaction untouched and the refund retryable',
        () async {
          await setup();
          final (invId, payId, _) = await captured();
          final id = await approvedRefund(payId, invId, 100000);
          h.sandbox.refundOutcome = 'failed';
          final failed = await h.okData(
            h.call('POST', '/billing/refunds/$id/gateway', uid: 'acct'),
          );
          expect(failed['status'], 'failed');
          expect(h.docsOf('gateway_transactions').single['status'], 'captured');
          h.sandbox.refundOutcome = 'completed';
          final retry = await h.okData(
            h.call('POST', '/billing/refunds/$id/gateway', uid: 'acct'),
          );
          expect(retry['status'], 'completed');
        },
      );

      test('processing refunds finish when the provider confirms', () async {
        await setup();
        final (invId, payId, _) = await captured();
        final id = await approvedRefund(payId, invId, 100000);
        h.sandbox.refundOutcome = 'processing';
        final p = await h.okData(
          h.call('POST', '/billing/refunds/$id/gateway', uid: 'acct'),
        );
        expect(p['status'], 'processing');
        final ref =
            h.docsOf('gateway_transactions').single['providerRef']! as String;
        expect(h.docsOf('gateway_transactions').single['status'], 'captured');
        await hook(
          event('refund.processed', ref, extra: {'refundRef': 'sbxr_$id'}),
        );
        final r = await h.okData(
          h.call('GET', '/billing/refunds/$id', uid: 'acct'),
        );
        expect(r['status'], 'completed');
        expect(h.docsOf('gateway_transactions').single['status'], 'refunded');
        // the same confirmation again changes nothing
        await hook(
          event('refund.processed', ref, extra: {'refundRef': 'sbxr_$id'}),
        );
        expect(
          h.docsOf('gateway_transactions').single['refundedTotal'],
          100000,
        );
        // a confirmation we never asked for needs a human
        await hook(
          event(
            'refund.processed',
            ref,
            extra: {'refundRef': 'other_dashboard_refund'},
          ),
        );
        expect(
          h.docsOf('gateway_exceptions').map((e) => e['type']),
          contains('external_refund'),
        );
      });

      test(
        'manual completion of an online payment and the gateway for a cash payment are refused',
        () async {
          await setup();
          final (invId, payId, _) = await captured();
          final id = await approvedRefund(payId, invId, 1000);
          expect(
            await h.status(
              'POST',
              '/billing/refunds/$id/complete',
              uid: 'acct',
              body: {'outcome': 'completed', 'method': 'cash'},
            ),
            409,
          );
          final cash = await k.finalized(amount: 5000);
          final p = await k.pay('${cash['invoiceId']}', 5000);
          final rf = await k.requestRefund(
            '${p['paymentId']}',
            5000,
            invoiceId: '${cash['invoiceId']}',
          );
          await k.refundAction('${rf['refundId']}', 'approve');
          expect(
            await h.status(
              'POST',
              '/billing/refunds/${rf['refundId']}/gateway',
              uid: 'acct',
            ),
            409,
          );
          // and the cash refund still works the old way
          final done = await k.refundAction(
            '${rf['refundId']}',
            'complete',
            uid: 'acct',
            body: {'outcome': 'completed', 'method': 'cash'},
          );
          expect(done['status'], 'completed');
        },
      );

      test('permissions: only refund processors reach the provider', () async {
        await setup();
        final (invId, payId, _) = await captured();
        final id = await approvedRefund(payId, invId, 1000);
        expect(
          await h.status('POST', '/billing/refunds/$id/gateway', uid: 'recep'),
          403,
        );
        expect(
          await h.status('POST', '/billing/refunds/$id/gateway', uid: 'nurse'),
          403,
        );
        expect(
          await h.status('POST', '/billing/refunds/nope/gateway', uid: 'acct'),
          404,
        );
      });
    });

    group('reconciliation and operations', () {
      test('inquiry applies provider status through the same checks', () async {
        await setup();
        final inv = await k.finalized();
        final t = await intent(inv['invoiceId']! as String);
        final ref = t['providerRef']! as String;
        h.sandbox.simulated[ref] = const ProviderStatus(
          status: 'captured',
          amountMinor: 100000,
          currency: 'INR',
        );
        final r = await h.okData(
          h.call(
            'POST',
            '/billing/gateway/transactions/${t['transactionId']}/sync',
            uid: 'acct',
          ),
        );
        expect(r['status'], 'captured');
        expect(await payments(), hasLength(1));
        await h.okData(
          h.call(
            'POST',
            '/billing/gateway/transactions/${t['transactionId']}/sync',
            uid: 'acct',
          ),
        );
        expect(await payments(), hasLength(1));
        // a webhook for the same capture afterwards is not a second payment
        await hook(event('payment.captured', ref, amount: 100000));
        expect(await payments(), hasLength(1));
      });

      test('inquiry with a different amount opens an exception', () async {
        await setup();
        final inv = await k.finalized();
        final t = await intent(inv['invoiceId']! as String);
        h.sandbox.simulated[t['providerRef']! as String] = const ProviderStatus(
          status: 'captured',
          amountMinor: 1,
          currency: 'INR',
        );
        await h.okData(
          h.call(
            'POST',
            '/billing/gateway/transactions/${t['transactionId']}/sync',
            uid: 'acct',
          ),
        );
        expect(await payments(), isEmpty);
        expect(
          h.docsOf('gateway_exceptions').single['type'],
          'amount_mismatch',
        );
      });

      test(
        'reconciliation lists exceptions and stale payments; exceptions can be resolved',
        () async {
          await setup();
          final inv = await k.finalized();
          final t = await intent(inv['invoiceId']! as String);
          await hook(event('payment.captured', 'sbx_unknown_1', amount: 1));
          var rec = await h.okData(
            h.call('GET', '/billing/gateway/reconciliation', uid: 'acct'),
          );
          expect((rec['exceptions']! as List), hasLength(1));
          expect((rec['staleTransactions']! as List), isEmpty);
          h.clock.now = h.clock.now.add(const Duration(minutes: 31));
          rec = await h.okData(
            h.call('GET', '/billing/gateway/reconciliation', uid: 'owner'),
          );
          expect(
            ((rec['staleTransactions']! as List).single
                as Map)['transactionId'],
            t['transactionId'],
          );
          expect((rec['counts']! as Map)['pending'], 1);
          final exId =
              ((rec['exceptions']! as List).single as Map)['exceptionId'];
          expect(
            await h.status(
              'POST',
              '/billing/gateway/exceptions/$exId/resolve',
              uid: 'recep',
              body: {'note': 'Looked into it'},
            ),
            403,
          );
          expect(
            await h.status(
              'POST',
              '/billing/gateway/exceptions/$exId/resolve',
              uid: 'acct',
              body: {'note': 'x'},
            ),
            422,
          );
          final done = await h.okData(
            h.call(
              'POST',
              '/billing/gateway/exceptions/$exId/resolve',
              uid: 'acct',
              body: {'note': 'Confirmed with provider'},
            ),
          );
          expect(done['status'], 'resolved');
          rec = await h.okData(
            h.call('GET', '/billing/gateway/reconciliation', uid: 'acct'),
          );
          expect(rec['exceptions'], isEmpty);
          expect(
            await h.status(
              'GET',
              '/billing/gateway/reconciliation',
              uid: 'recep',
            ),
            403,
          );
          expect(
            await h.status(
              'POST',
              '/billing/gateway/exceptions/nope/resolve',
              uid: 'acct',
              body: {'note': 'Nothing here'},
            ),
            404,
          );
        },
      );

      test(
        'credential rotation keeps in-flight webhooks working until retired',
        () async {
          await setup();
          final inv = await k.finalized();
          final t = await intent(inv['invoiceId']! as String);
          final ref = t['providerRef']! as String;
          expect(
            await h.status(
              'POST',
              '/billing/gateway/config/rotate',
              uid: 'recep',
              body: {'credentialRef': 'TEST_ACME_2'},
            ),
            403,
          );
          expect(
            await h.status(
              'POST',
              '/billing/gateway/config/rotate',
              uid: 'owner',
              body: {'credentialRef': 'NOPE_2'},
            ),
            422,
          );
          expect(
            await h.status(
              'POST',
              '/billing/gateway/config/rotate',
              uid: 'owner',
              body: {'credentialRef': 'TEST_ACME_1'},
            ),
            409,
          );
          final cfg = await h.okData(
            h.call(
              'POST',
              '/billing/gateway/config/rotate',
              uid: 'owner',
              body: {'credentialRef': 'TEST_ACME_2'},
            ),
          );
          expect(cfg['credentialVersion'], 2);
          expect(
            (await hook(
              event('payment.authorized', ref),
              secret: 'whsec_1',
            )).statusCode,
            200,
          );
          expect(
            (await hook(
              event('payment.authorized', ref),
              secret: 'whsec_2',
            )).statusCode,
            200,
          );
          await h.okData(
            h.call(
              'POST',
              '/billing/gateway/config/rotate',
              uid: 'owner',
              body: {'retirePrevious': true},
            ),
          );
          expect(
            (await hook(
              event('payment.captured', ref, amount: 100000),
              secret: 'whsec_1',
            )).statusCode,
            401,
          );
          expect(await payments(), isEmpty);
          expect(
            (await hook(
              event('payment.captured', ref, amount: 100000),
              secret: 'whsec_2',
            )).statusCode,
            200,
          );
          expect(await payments(), hasLength(1));
        },
      );

      test('platform health counts without payer data', () async {
        await setup();
        final inv = await k.finalized();
        final t = await intent(inv['invoiceId']! as String);
        await hook(
          event(
            'payment.captured',
            t['providerRef']! as String,
            amount: 100000,
          ),
        );
        await hook(event('payment.captured', 'sbx_none', amount: 1));
        final hl = await h.okData(
          h.call('GET', '/platform/payments/health', uid: 'support'),
        );
        expect(hl['livePaymentsEnabled'], isFalse);
        final sb = (hl['providers']! as List).single as Map;
        expect(sb['provider'], 'sandbox');
        expect(sb['clinicsConfigured'], 1);
        expect(sb['liveClinics'], 0);
        expect((sb['transactions']! as Map)['captured'], 1);
        expect(hl['unattributedOpenExceptions'], 1);
        expect(jsonEncode(hl), isNot(contains('patient')));
        expect(
          await h.status('GET', '/platform/payments/health', uid: 'owner'),
          403,
        );
      });

      test(
        'manual collection keeps working and cannot pose as online',
        () async {
          await setup();
          final inv = await k.finalized(amount: 20000);
          final p = await k.pay('${inv['invoiceId']}', 20000);
          expect(p['source'], 'offline');
          expect(p['method'], 'cash');
          final inv2 = await k.finalized(amount: 20000);
          expect(
            await h.status(
              'POST',
              '/billing/payments',
              uid: 'recep',
              headers: {'idempotency-key': k.key('o')},
              body: {
                'patientId': k.patient,
                'branchId': k.br,
                'amountMinor': 20000,
                'method': 'online',
                'allocations': [
                  {'invoiceId': inv2['invoiceId'], 'amountMinor': 20000},
                ],
              },
            ),
            422,
            reason:
                'online money arrives only through verified provider events',
          );
        },
      );
    });
  });
}
