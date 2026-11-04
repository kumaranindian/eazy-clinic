import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late BillingClinic k;

  Future<List<Object?>> listOf(String path, {String uid = 'recep'}) async =>
      h.list(await h.call('GET', path, uid: uid));

  setUp(() async {
    h = PlatformHarness();
    k = BillingClinic(h);
    await k.init();
  });

  group('access control', () {
    test('unauthenticated, wrong role and other clinics are refused', () async {
      expect(await h.status('GET', '/billing/invoices'), 401);
      expect(await h.status('GET', '/billing/invoices', uid: 'nurse'), 403);
      expect(await h.status('GET', '/billing/invoices', uid: 'docuser'), 403);
      expect(
        await h.status('GET', '/finance/dashboard', uid: 'recep'),
        403,
        reason: 'receptionists have no finance reports',
      );
      final inv = await k.finalized();
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status(
          'GET',
          '/billing/invoices/${inv['invoiceId']}',
          uid: 'ownerB',
        ),
        404,
      );
      final list = await listOf('/billing/invoices', uid: 'ownerB');
      expect(list, isEmpty);
    });

    test('a clinic whose plan has no billing is refused', () async {
      final h2 = PlatformHarness();
      h2.user('root', role: PlatformRole.superAdmin);
      await h2.createClinic('o2', billing: false);
      expect(await h2.status('GET', '/billing/invoices', uid: 'o2'), 403);
    });

    test('a branch-scoped user cannot reach another branch', () async {
      final inv = await k.finalized();
      final br2 = await h.newBranch('owner', code: 'BR2');
      h.member(
        'recep2',
        k.tid,
        'receptionist',
        allBranches: false,
        branchIds: [br2],
      );
      expect(
        await h.status(
          'GET',
          '/billing/invoices/${inv['invoiceId']}',
          uid: 'recep2',
        ),
        404,
      );
      expect(
        await h.status(
          'POST',
          '/billing/invoices',
          uid: 'recep2',
          body: k.invoiceBody(),
        ),
        404,
        reason: 'the patient and branch are outside the scope',
      );
    });
  });

  group('service catalogue', () {
    test('owner and admin manage it; others cannot', () async {
      final s = await k.service();
      expect(s['currency'], 'INR');
      expect(s['version'], 1);
      expect(
        await h.status(
          'POST',
          '/billing/services',
          uid: 'recep',
          body: {'name': 'X Test', 'category': 'custom', 'amountMinor': 1},
        ),
        403,
      );
      expect(
        await h.status(
          'POST',
          '/billing/services',
          uid: 'acct',
          body: {'name': 'X Test', 'category': 'custom', 'amountMinor': 1},
        ),
        403,
      );
      await k.service(name: 'Admin Service', uid: 'admin');
      // everyone with billing.view can read
      final page = await listOf('/billing/services', uid: 'recep');
      expect(page, hasLength(2));
    });

    test('validates amounts, categories and unknown fields', () async {
      Future<int> create(Map<String, Object?> b) =>
          h.status('POST', '/billing/services', uid: 'owner', body: b);
      expect(
        await create({'name': 'Test', 'category': 'bogus', 'amountMinor': 100}),
        422,
      );
      expect(
        await create({'name': 'Test', 'category': 'custom', 'amountMinor': -5}),
        422,
      );
      expect(
        await create({
          'name': 'Test',
          'category': 'custom',
          'amountMinor': 10.5,
        }),
        422,
      );
      expect(
        await create({
          'name': 'Test',
          'category': 'custom',
          'amountMinor': 100,
          'tenantId': 'x',
        }),
        422,
      );
      expect(
        await create({
          'name': 'Test',
          'category': 'procedure',
          'amountMinor': 100,
          'doctorFees': {'d': 1},
        }),
        422,
      );
      expect(
        await create({
          'name': 'Test',
          'category': 'custom',
          'amountMinor': 100,
          'taxRuleId': 'tx_missing',
        }),
        404,
      );
    });

    test(
      'price changes are versioned and never alter a finalized invoice',
      () async {
        final s = await k.service(amount: 50000);
        final sid = s['serviceId']! as String;
        final d = await k.draft(
          lines: [
            {'serviceId': sid, 'quantity': 2},
          ],
        );
        expect(d['grandTotal'], 100000);
        final fin = await h.okData(
          h.call(
            'POST',
            '/billing/invoices/${d['invoiceId']}/finalize',
            uid: 'recep',
          ),
        );
        expect(fin['grandTotal'], 100000);

        final upd = await h.okData(
          h.call(
            'PATCH',
            '/billing/services/$sid',
            uid: 'owner',
            body: {'amountMinor': 90000, 'reason': 'Annual revision'},
          ),
        );
        expect(upd['version'], 2);
        final after = await k.invoice(d['invoiceId']! as String);
        expect(after['grandTotal'], 100000, reason: 'snapshot unchanged');
        expect(((after['lines']! as List).first as Map)['unitMinor'], 50000);

        final hist = await h.okData(
          h.call('GET', '/billing/services/$sid/price-history', uid: 'recep'),
        );
        final versions = (hist['history']! as List)
            .map((e) => (e as Map)['amountMinor'])
            .toList();
        expect(versions, [50000, 90000]);

        // a new invoice uses the new price
        final d2 = await k.draft(
          lines: [
            {'serviceId': sid, 'quantity': 1},
          ],
        );
        expect(d2['grandTotal'], 90000);
      },
    );

    test('doctor fee beats branch price beats the default', () async {
      final s = await k.service(
        extra: {
          'branchPrices': {k.br: 40000},
          'doctorFees': {k.doctor: 70000},
        },
      );
      final sid = s['serviceId']! as String;
      final withDoc = await k.draft(
        extra: {'doctorId': k.doctor},
        lines: [
          {'serviceId': sid, 'quantity': 1},
        ],
      );
      expect(withDoc['grandTotal'], 70000);
      final noDoc = await k.draft(
        patientId: await k.c.morePatient(2),
        lines: [
          {'serviceId': sid, 'quantity': 1},
        ],
      );
      expect(noDoc['grandTotal'], 40000);
    });

    test(
      'inactive, future and out-of-scope services cannot be billed',
      () async {
        final s = await k.service();
        final sid = s['serviceId']! as String;
        await h.okData(
          h.call(
            'PATCH',
            '/billing/services/$sid',
            uid: 'owner',
            body: {'status': 'inactive'},
          ),
        );
        expect(
          await h.status(
            'POST',
            '/billing/invoices',
            uid: 'recep',
            body: k.invoiceBody(
              lines: [
                {'serviceId': sid, 'quantity': 1},
              ],
            ),
          ),
          409,
        );
        final future = await k.service(
          name: 'Future Service',
          extra: {'effectiveFrom': '2030-01-01'},
        );
        expect(
          await h.status(
            'POST',
            '/billing/invoices',
            uid: 'recep',
            body: k.invoiceBody(
              lines: [
                {'serviceId': future['serviceId'], 'quantity': 1},
              ],
            ),
          ),
          409,
        );
        final br2 = await h.newBranch('owner', code: 'BR2');
        final other = await k.service(
          name: 'Branch Two Only',
          extra: {
            'branchIds': [br2],
          },
        );
        expect(
          await h.status(
            'POST',
            '/billing/invoices',
            uid: 'recep',
            body: k.invoiceBody(
              lines: [
                {'serviceId': other['serviceId'], 'quantity': 1},
              ],
            ),
          ),
          409,
        );
      },
    );

    test(
      'tax rules reject rates above 100% and are configuration only',
      () async {
        expect(
          await h.status(
            'POST',
            '/billing/tax-rules',
            uid: 'owner',
            body: {
              'name': 'Too much',
              'components': [
                {'name': 'A', 'rateBps': 6000},
                {'name': 'B', 'rateBps': 6000},
              ],
            },
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/billing/tax-rules',
            uid: 'recep',
            body: {
              'name': 'Nope',
              'components': [
                {'name': 'A', 'rateBps': 100},
              ],
            },
          ),
          403,
        );
        final rule = await k.taxRule();
        expect(rule['status'], 'active');
      },
    );
  });

  group('invoice drafts and calculation', () {
    test(
      'the server prices catalogue lines; client amounts are rejected',
      () async {
        final tax = await k.taxRule();
        final s = await k.service(taxRuleId: tax['taxRuleId']! as String);
        final sid = s['serviceId']! as String;
        final d = await k.draft(
          lines: [
            {'serviceId': sid, 'quantity': 1},
          ],
        );
        expect(d['subtotal'], 50000);
        expect(d['taxTotal'], 9000);
        expect(d['grandTotal'], 59000);
        final line = (d['lines']! as List).first as Map;
        expect(line['taxRuleName'], 'GST 18%');
        expect((line['taxParts']! as List).map((p) => (p as Map)['amount']), [
          4500,
          4500,
        ]);

        // price, category, tax cannot be sent for a catalogue line
        for (final bad in [
          {'serviceId': sid, 'quantity': 1, 'unitMinor': 1},
          {'serviceId': sid, 'quantity': 1, 'taxRuleId': 'x'},
          {'serviceId': sid, 'quantity': 1, 'category': 'custom'},
        ]) {
          expect(
            await h.status(
              'POST',
              '/billing/invoices',
              uid: 'recep',
              body: k.invoiceBody(lines: [bad]),
            ),
            422,
          );
        }
        // totals cannot be supplied at all
        for (final f in [
          'grandTotal',
          'taxTotal',
          'status',
          'amountPaid',
          'outstanding',
          'tenantId',
          'invoiceNumber',
        ]) {
          expect(
            await h.status(
              'POST',
              '/billing/invoices',
              uid: 'recep',
              body: k.invoiceBody(extra: {f: 1}),
            ),
            422,
            reason: f,
          );
        }
      },
    );

    test('inclusive tax keeps the entered price as the total', () async {
      final tax = await k.taxRule(name: 'GST inc', inclusive: true);
      final d = await k.draft(
        lines: [
          {
            'description': 'Dental scaling',
            'unitMinor': 118000,
            'quantity': 1,
            'taxRuleId': tax['taxRuleId'],
          },
        ],
      );
      expect(d['grandTotal'], 118000);
      expect(d['taxTotal'], 18000);
    });

    test('tax exemption needs a reason and removes the tax', () async {
      final tax = await k.taxRule();
      Map<String, Object?> line(Map<String, Object?> extra) => {
        'description': 'Vaccination',
        'unitMinor': 100000,
        'quantity': 1,
        'taxRuleId': tax['taxRuleId'],
        ...extra,
      };
      expect(
        await h.status(
          'POST',
          '/billing/invoices',
          uid: 'recep',
          body: k.invoiceBody(
            lines: [
              line({'taxExempt': true}),
            ],
          ),
        ),
        422,
      );
      final d = await k.draft(
        lines: [
          line({
            'taxExempt': true,
            'taxExemptReason': 'Exempt by clinic accountant',
          }),
        ],
      );
      expect(d['taxTotal'], 0);
      expect(d['grandTotal'], 100000);
    });

    test('discounts need permission and respect the role limit', () async {
      final line = {
        'description': 'Procedure',
        'unitMinor': 100000,
        'quantity': 1,
      };
      // receptionists hold no discount permission
      expect(
        await h.status(
          'POST',
          '/billing/invoices',
          uid: 'recep',
          body: k.invoiceBody(
            lines: [line],
            extra: {
              'discount': {'type': 'percent', 'value': 500},
            },
          ),
        ),
        403,
      );
      // accountant: default limit 10%
      Future<int> acct(Map<String, Object?> dsc) => h.status(
        'POST',
        '/billing/invoices',
        uid: 'acct',
        body: k.invoiceBody(lines: [line], extra: {'discount': dsc}),
      );
      expect(await acct({'type': 'percent', 'value': 1001}), 403);
      expect(await acct({'type': 'fixed', 'value': 10001}), 403);
      expect(await acct({'type': 'percent', 'value': 1000}), 201);
      // admin is allowed up to the limit configured for the role
      final d = await h.okData(
        h.call(
          'POST',
          '/billing/invoices',
          uid: 'admin',
          body: k.invoiceBody(
            lines: [line],
            extra: {
              'discount': {'type': 'percent', 'value': 2500},
            },
          ),
        ),
        status: 201,
      );
      expect(d['invoiceDiscount'], 25000);
      expect(d['grandTotal'], 75000);

      // the owner can tighten the accountant's limit
      await h.okData(
        h.call(
          'PUT',
          '/billing/settings',
          uid: 'owner',
          body: {
            'discountLimitsBps': {'accountant': 200},
          },
        ),
      );
      expect(await acct({'type': 'percent', 'value': 500}), 403);
    });

    test(
      'line discount and invoice discount combine deterministically',
      () async {
        final tax = await k.taxRule();
        final d = await h.okData(
          h.call(
            'POST',
            '/billing/invoices',
            uid: 'owner',
            body: k.invoiceBody(
              lines: [
                {
                  'description': 'Item A',
                  'unitMinor': 60000,
                  'quantity': 1,
                  'taxRuleId': tax['taxRuleId'],
                  'discount': {'type': 'percent', 'value': 1000},
                },
                {'description': 'Item B', 'unitMinor': 40000, 'quantity': 1},
              ],
              extra: {
                'discount': {'type': 'fixed', 'value': 5000},
              },
            ),
          ),
          status: 201,
        );
        // line A 54000 after 10%, B 40000; invoice discount 5000 shared 54000:40000
        expect(d['subtotal'], 100000);
        expect(d['lineDiscountTotal'], 6000);
        expect(d['invoiceDiscount'], 5000);
        final shares = (d['lines']! as List)
            .map((l) => (l as Map)['invoiceDiscountShare'] as int)
            .toList();
        expect(shares.fold<int>(0, (a, b) => a + b), 5000);
        final lineTotals = (d['lines']! as List).fold<int>(
          0,
          (a, l) => a + ((l as Map)['total'] as int),
        );
        expect(d['grandTotal'], lineTotals);
      },
    );

    test(
      'draft edit replaces lines and recalculates; stale edits conflict',
      () async {
        final d = await k.draft(
          lines: [
            {'description': 'Item A', 'unitMinor': 1000, 'quantity': 1},
          ],
        );
        final id = d['invoiceId']! as String;
        final e = await h.okData(
          h.call(
            'PATCH',
            '/billing/invoices/$id',
            uid: 'recep',
            body: {
              'lines': [
                {'description': 'Item A', 'unitMinor': 1000, 'quantity': 2},
                {'description': 'Item B', 'unitMinor': 500, 'quantity': 1},
              ],
              'expectedRev': d['rev'],
            },
          ),
        );
        expect(e['grandTotal'], 2500);
        expect((e['lines']! as List), hasLength(2));
        expect(
          await h.status(
            'PATCH',
            '/billing/invoices/$id',
            uid: 'recep',
            body: {'notes': 'x', 'expectedRev': d['rev']},
          ),
          409,
        );
        expect(
          await h.status(
            'PATCH',
            '/billing/invoices/$id',
            uid: 'recep',
            body: {'grandTotal': 1},
          ),
          422,
        );
        expect(
          await h.status(
            'PATCH',
            '/billing/invoices/$id',
            uid: 'nurse',
            body: {'notes': 'x'},
          ),
          403,
        );
      },
    );

    test('lines are limited and validated', () async {
      Future<int> post(List<Map<String, Object?>> lines) => h.status(
        'POST',
        '/billing/invoices',
        uid: 'recep',
        body: k.invoiceBody(lines: lines),
      );
      expect(
        await post([
          {'description': 'Item A', 'unitMinor': 100, 'quantity': 0},
        ]),
        422,
      );
      expect(
        await post([
          {'description': 'Item A', 'unitMinor': -1, 'quantity': 1},
        ]),
        422,
      );
      expect(
        await post([
          {'description': '', 'unitMinor': 1, 'quantity': 1},
        ]),
        422,
      );
      expect(
        await post([
          for (var i = 0; i < 51; i++)
            {'description': 'Line $i', 'unitMinor': 1, 'quantity': 1},
        ]),
        422,
      );
    });
  });

  group('finalization', () {
    test(
      'assigns a number, snapshots totals and refuses further edits',
      () async {
        final d = await k.draft(
          lines: [
            {'description': 'Item A', 'unitMinor': 25000, 'quantity': 1},
          ],
        );
        expect(d['invoiceNumber'], isNull);
        expect(d['outstanding'], 0, reason: 'a draft is not a debt');
        final f = await h.okData(
          h.call(
            'POST',
            '/billing/invoices/${d['invoiceId']}/finalize',
            uid: 'recep',
          ),
        );
        expect(f['invoiceNumber'], 'INV-000001');
        expect(f['status'], 'finalized');
        expect(f['outstanding'], 25000);
        expect(f['finalizedBy'], 'recep');
        expect(
          await h.status(
            'PATCH',
            '/billing/invoices/${d['invoiceId']}',
            uid: 'recep',
            body: {'notes': 'late edit'},
          ),
          409,
        );
        expect(
          k.auditActions(),
          containsAll(['invoice.created', 'invoice.finalized']),
        );
      },
    );

    test('finalizing twice is a replay: one number, one audit entry', () async {
      final d = await k.draft(
        lines: [
          {'description': 'Item A', 'unitMinor': 25000, 'quantity': 1},
        ],
      );
      final id = d['invoiceId']! as String;
      final a = await h.okData(
        h.call('POST', '/billing/invoices/$id/finalize', uid: 'recep'),
      );
      final b = await h.okData(
        h.call('POST', '/billing/invoices/$id/finalize', uid: 'recep'),
      );
      expect(b['idempotentReplay'], true);
      expect(b['invoiceNumber'], a['invoiceNumber']);
      expect(
        k.auditActions().where((x) => x == 'invoice.finalized'),
        hasLength(1),
      );
      expect(h.docsOf('invoice_numbers'), hasLength(1));
    });

    test('an invoice without lines cannot be finalized', () async {
      final d = await k.draft();
      expect(
        await h.status(
          'POST',
          '/billing/invoices/${d['invoiceId']}/finalize',
          uid: 'recep',
        ),
        422,
      );
    });

    test('concurrent finalizations get unique, gap-free numbers', () async {
      final ids = <String>[];
      for (var i = 0; i < 6; i++) {
        final d = await k.draft(
          lines: [
            {'description': 'Item $i', 'unitMinor': 1000, 'quantity': 1},
          ],
        );
        ids.add(d['invoiceId']! as String);
      }
      final res = await Future.wait([
        for (final id in ids)
          h.call('POST', '/billing/invoices/$id/finalize', uid: 'recep'),
      ]);
      expect(res.map((r) => r.statusCode), everyElement(200));
      final numbers = [for (final d in h.docsOf('invoices')) d['invoiceNumber']]
        ..sort((a, b) => '$a'.compareTo('$b'));
      expect(numbers, [
        for (var i = 1; i <= 6; i++) 'INV-${i.toString().padLeft(6, '0')}',
      ]);
    });

    test('racing finalize requests for one invoice yield one number', () async {
      final d = await k.draft(
        lines: [
          {'description': 'Item A', 'unitMinor': 1000, 'quantity': 1},
        ],
      );
      final id = d['invoiceId']! as String;
      await Future.wait([
        for (var i = 0; i < 4; i++)
          h.call('POST', '/billing/invoices/$id/finalize', uid: 'recep'),
      ]);
      expect(h.docsOf('invoice_numbers'), hasLength(1));
      expect(
        k.auditActions().where((x) => x == 'invoice.finalized'),
        hasLength(1),
      );
    });

    test('only holders of billing.finalize can finalize', () async {
      final d = await k.draft(
        lines: [
          {'description': 'Item A', 'unitMinor': 1000, 'quantity': 1},
        ],
      );
      expect(
        await h.status(
          'POST',
          '/billing/invoices/${d['invoiceId']}/finalize',
          uid: 'nurse',
        ),
        403,
      );
    });
  });

  group('cancellation and adjustments', () {
    test('cancel needs a reason, frees the visit and is audited', () async {
      final d = await k.draft(
        lines: [
          {'description': 'Item A', 'unitMinor': 1000, 'quantity': 1},
        ],
      );
      final id = d['invoiceId']! as String;
      expect(
        await h.status(
          'POST',
          '/billing/invoices/$id/cancel',
          uid: 'acct',
          body: {},
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/billing/invoices/$id/cancel',
          uid: 'recep',
          body: {'reason': 'Entered by mistake'},
        ),
        403,
      );
      final c = await h.okData(
        h.call(
          'POST',
          '/billing/invoices/$id/cancel',
          uid: 'acct',
          body: {'reason': 'Entered by mistake'},
        ),
      );
      expect(c['status'], 'cancelled');
      expect(c['cancelReason'], 'Entered by mistake');
      final again = await h.okData(
        h.call(
          'POST',
          '/billing/invoices/$id/cancel',
          uid: 'acct',
          body: {'reason': 'Entered by mistake'},
        ),
      );
      expect(again['idempotentReplay'], true);
      expect(
        k.auditActions().where((x) => x == 'invoice.cancelled'),
        hasLength(1),
      );
    });

    test('an invoice with payments cannot be cancelled', () async {
      final inv = await k.finalized(amount: 1000);
      await k.pay(inv['invoiceId']! as String, 400);
      expect(
        await h.status(
          'POST',
          '/billing/invoices/${inv['invoiceId']}/cancel',
          uid: 'acct',
          body: {'reason': 'Changed my mind'},
        ),
        409,
      );
    });

    test('credit and debit notes correct a finalized invoice', () async {
      final inv = await k.finalized(amount: 100000);
      final id = inv['invoiceId']! as String;
      final debit = await h.okData(
        h.call(
          'POST',
          '/billing/invoices/$id/adjustments',
          uid: 'acct',
          body: {
            'type': 'debit',
            'amountMinor': 20000,
            'reason': 'Extra dressing used',
          },
        ),
        status: 201,
      );
      expect((debit['adjustment']! as Map)['number'], 'DN-000001');
      expect((debit['invoice']! as Map)['outstanding'], 120000);
      expect(
        (debit['invoice']! as Map)['grandTotal'],
        100000,
        reason: 'the original total is untouched',
      );
      final credit = await h.okData(
        h.call(
          'POST',
          '/billing/invoices/$id/adjustments',
          uid: 'acct',
          body: {
            'type': 'credit',
            'amountMinor': 30000,
            'reason': 'Goodwill reduction',
          },
        ),
        status: 201,
      );
      expect((credit['adjustment']! as Map)['number'], 'CN-000001');
      expect((credit['invoice']! as Map)['outstanding'], 90000);
      expect((credit['invoice']! as Map)['adjustedTotal'], 90000);
      final detail = await k.invoice(id);
      expect((detail['adjustments']! as List), hasLength(2));
    });

    test('a credit note cannot exceed the outstanding balance', () async {
      final inv = await k.finalized(amount: 100000);
      final id = inv['invoiceId']! as String;
      await k.pay(id, 80000);
      expect(
        await h.status(
          'POST',
          '/billing/invoices/$id/adjustments',
          uid: 'acct',
          body: {
            'type': 'credit',
            'amountMinor': 30000,
            'reason': 'Too generous',
          },
        ),
        409,
      );
      final ok = await h.okData(
        h.call(
          'POST',
          '/billing/invoices/$id/adjustments',
          uid: 'acct',
          body: {
            'type': 'credit',
            'amountMinor': 20000,
            'reason': 'Balance waived',
          },
        ),
        status: 201,
      );
      expect((ok['invoice']! as Map)['status'], 'paid');
      expect((ok['invoice']! as Map)['outstanding'], 0);
    });

    test(
      'adjustments need billing.adjust, a reason and a finalized invoice',
      () async {
        final inv = await k.finalized();
        final id = inv['invoiceId']! as String;
        final body = {
          'type': 'debit',
          'amountMinor': 100,
          'reason': 'Extra item',
        };
        expect(
          await h.status(
            'POST',
            '/billing/invoices/$id/adjustments',
            uid: 'recep',
            body: body,
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/billing/invoices/$id/adjustments',
            uid: 'acct',
            body: {...body, 'reason': 'no'},
          ),
          422,
        );
        final d = await k.draft(
          lines: [
            {'description': 'Item A', 'unitMinor': 1, 'quantity': 1},
          ],
        );
        expect(
          await h.status(
            'POST',
            '/billing/invoices/${d['invoiceId']}/adjustments',
            uid: 'acct',
            body: body,
          ),
          409,
        );
      },
    );
  });

  group('lookup and lists', () {
    test('one open invoice per appointment', () async {
      final a = await h.bookOk('recep', k.c.body());
      final aid = a['appointmentId']! as String;
      final first = await k.draft(extra: {'appointmentId': aid});
      expect(first['doctorId'], k.doctor, reason: 'taken from the appointment');
      expect(
        await h.status(
          'POST',
          '/billing/invoices',
          uid: 'recep',
          body: k.invoiceBody(extra: {'appointmentId': aid}),
        ),
        409,
      );
      // cancelling releases the visit
      await h.okData(
        h.call(
          'POST',
          '/billing/invoices/${first['invoiceId']}/cancel',
          uid: 'acct',
          body: {'reason': 'Billed elsewhere'},
        ),
      );
      final second = await k.draft(extra: {'appointmentId': aid});
      expect(second['invoiceId'], isNot(first['invoiceId']));
    });

    test('an appointment of another patient is not found', () async {
      final a = await h.bookOk('recep', k.c.body());
      final p2 = await k.c.morePatient(2);
      expect(
        await h.status(
          'POST',
          '/billing/invoices',
          uid: 'recep',
          body: k.invoiceBody(
            patientId: p2,
            extra: {'appointmentId': a['appointmentId']},
          ),
        ),
        404,
      );
    });

    test('list filters by status, patient, number and overdue', () async {
      final a = await k.finalized(amount: 1000);
      await k.draft(
        lines: [
          {'description': 'Item D', 'unitMinor': 5, 'quantity': 1},
        ],
      );
      final all = await listOf('/billing/invoices', uid: 'recep');
      expect(all, hasLength(2));
      expect(
        await listOf('/billing/invoices?status=draft', uid: 'recep'),
        hasLength(1),
      );
      final byNumber = await listOf(
        '/billing/invoices?q=${a['invoiceNumber']}',
      );
      expect(byNumber, hasLength(1));
      expect(
        await h.status('GET', '/billing/invoices?status=bogus', uid: 'recep'),
        400,
      );
      // not overdue yet; nine days later it is
      expect(
        await listOf('/billing/invoices?status=overdue', uid: 'recep'),
        isEmpty,
      );
      h.clock.now = DateTime.utc(2026, 6, 10, 10);
      final overdue = await listOf(
        '/billing/invoices?status=overdue',
        uid: 'recep',
      );
      expect(overdue, hasLength(1));
      final detail = await k.invoice(a['invoiceId']! as String);
      expect(detail['displayStatus'], 'overdue');
      expect(
        detail['status'],
        'finalized',
        reason: 'stored status is unchanged',
      );
    });
  });
}
