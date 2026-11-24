import 'package:backend/features/billing/billing_math.dart';
import 'package:backend/features/billing/tax/einvoice.dart';
import 'package:backend/features/billing/tax/tax_baseline.dart';
import 'package:backend/features/billing/tax/tax_policy.dart';
import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

Map<String, Object?> _comp(String n, String supply, int bps, [String? to]) => {
  'name': n,
  'supply': supply,
  'rates': [
    {'effectiveFrom': '2000-01-01', 'effectiveTo': ?to, 'rateBps': bps},
  ],
};

Map<String, Object?> _policy({
  String key = 'test-tax',
  String country = 'IN',
  List<Map<String, Object?>>? components,
  List<Map<String, Object?>>? exemptions,
  String status = 'published',
  bool verified = true,
  String rounding = 'half_up',
}) => {
  'key': key,
  'title': 'Test tax',
  'countryCode': country,
  'taxType': 'GST',
  'mode': 'exclusive',
  'rounding': rounding,
  'defaultSupply': 'intra',
  'status': status,
  'version': 3,
  'components':
      components ??
      [
        _comp('CGST', 'intra', 900),
        _comp('SGST', 'intra', 900),
        _comp('IGST', 'inter', 1800),
      ],
  'exemptions':
      exemptions ??
      [
        {'key': 'healthcare', 'label': 'Health care', 'treatment': 'exempt'},
        {'key': 'export', 'label': 'Export', 'treatment': 'zero_rated'},
      ],
  'source': {'reference': 'https://example.test'},
  'verification': {'status': verified ? 'verified' : 'unverified'},
};

void main() {
  group('rounding and precision', () {
    test('division modes', () {
      expect(divRound(5, 2), 3); // 2.5 half up
      expect(divRound(5, 2, Rounding.halfEven), 2);
      expect(divRound(7, 2, Rounding.halfEven), 4);
      expect(divRound(5, 2, Rounding.down), 2);
      expect(divRound(14, 10), 1);
      expect(divRound(15, 10, Rounding.halfEven), 2);
      expect(percentOf(333, 1800), 60);
      expect(percentOf(333, 1800, Rounding.down), 59);
    });

    LineInput line(int unit, {bool inclusive = false}) => LineInput(
      quantity: 1,
      unitMinor: unit,
      taxRule: TaxRule(
        id: 'r',
        name: 'x',
        inclusive: inclusive,
        components: const [TaxComponent('A', 900), TaxComponent('B', 900)],
      ),
    );

    test('exclusive: rounding mode changes only the tax, parts add up', () {
      final up = calculateInvoice([line(333)]);
      final down = calculateInvoice([line(333)], rounding: Rounding.down);
      expect(up.taxTotal, 60); // 30 + 30 (29.97 each, rounded up)
      expect(down.taxTotal, 58); // 29 + 29
      expect(up.grandTotal, 393);
      expect(down.grandTotal, 391);
    });

    test('inclusive: total is unchanged, the split adds up exactly', () {
      for (final mode in Rounding.values) {
        final r = calculateInvoice([
          line(1000, inclusive: true),
        ], rounding: mode);
        expect(r.grandTotal, 1000);
        expect(r.lines.single.taxableBase + r.lines.single.tax, 1000);
        expect(
          r.lines.single.taxParts.fold<int>(0, (a, p) => a + p.amount),
          r.lines.single.tax,
        );
      }
    });

    test('discount before tax, invoice discount shared, no drift', () {
      final r = calculateInvoice([
        line(1000),
        line(1000),
      ], invoiceDiscount: const Discount.percent(1000));
      expect(r.invoiceDiscount, 200);
      expect(r.lines.map((l) => l.taxableBase), [900, 900]);
      expect(r.grandTotal, r.lines.fold<int>(0, (a, l) => a + l.total));
    });
  });

  group('policy resolution', () {
    PolicyTaxRule rule(
      Map<String, Object?>? p, {
      String country = 'IN',
      String date = '2026-06-01',
      String? exemption,
      String? supply,
    }) => resolvePolicyRule(
      p,
      countryCode: country,
      date: date,
      exemptionKey: exemption,
      supply: supply,
    );

    String reason(void Function() f) {
      try {
        f();
      } on TaxPolicyUnavailable catch (e) {
        return e.reason;
      }
      return 'none';
    }

    test('intra and inter supplies use different components', () {
      final intra = rule(_policy());
      expect(intra.components.map((c) => '${c.name}:${c.rateBps}'), [
        'CGST:900',
        'SGST:900',
      ]);
      final inter = rule(_policy(), supply: 'inter');
      expect(inter.components.map((c) => c.name), ['IGST']);
      expect(inter.policyVersion, 3);
      expect(inter.effectiveOn, '2026-06-01');
    });

    test('rates are effective-dated; no rate in force fails', () {
      final p = _policy(
        components: [
          {
            'name': 'VAT',
            'supply': 'any',
            'rates': [
              {
                'effectiveFrom': '2020-01-01',
                'effectiveTo': '2024-12-31',
                'rateBps': 500,
              },
              {'effectiveFrom': '2025-01-01', 'rateBps': 600},
            ],
          },
        ],
      );
      expect(rule(p, date: '2024-12-31').components.single.rateBps, 500);
      expect(rule(p, date: '2025-01-01').components.single.rateBps, 600);
      expect(reason(() => rule(p, date: '2019-12-31')), 'no_rate');
    });

    test('exempt has no tax; zero-rated has components at 0', () {
      final ex = rule(_policy(), exemption: 'healthcare');
      expect(ex.components, isEmpty);
      expect(ex.treatment, 'exempt');
      final z = rule(_policy(), exemption: 'export');
      expect(z.components.map((c) => c.rateBps), [0, 0]);
      expect(z.treatment, 'zero_rated');
      expect(
        reason(() => rule(_policy(), exemption: 'nope')),
        'unknown_exemption',
      );
    });

    test('refuses to guess: unverified, retired, other country, missing', () {
      expect(reason(() => rule(_policy(verified: false))), 'unverified');
      expect(reason(() => rule(_policy(status: 'retired'))), 'retired');
      expect(reason(() => rule(_policy(), country: 'AE')), 'wrong_country');
      expect(reason(() => rule(null)), 'not_found');
      expect(reason(() => rule(_policy(), supply: 'any')), 'no_components');
    });
  });

  group('policy validation', () {
    List<String> bad(Map<String, Object?> p) => [
      for (final (f, _) in validatePolicy(p)) f,
    ];

    test(
      'a well-formed policy is valid',
      () => expect(bad(_policy()), isEmpty),
    );

    test('rejects overlaps, bad rates, bad dates, empty components', () {
      expect(
        bad(
          _policy(
            components: [
              {
                'name': 'VAT',
                'supply': 'any',
                'rates': [
                  {'effectiveFrom': '2020-01-01', 'rateBps': 500},
                  {'effectiveFrom': '2022-01-01', 'rateBps': 600},
                ],
              },
            ],
          ),
        ),
        contains('components[0].rates'),
      );
      expect(
        bad(_policy(components: [_comp('X', 'any', 10001)])),
        contains('components[0].rates[0].rateBps'),
      );
      expect(
        bad(_policy(components: [_comp('X', 'any', -1)])),
        contains('components[0].rates[0].rateBps'),
      );
      expect(bad(_policy(components: [])), contains('components'));
      expect(bad({..._policy(), 'mode': 'maybe'}), contains('mode'));
      expect(bad({..._policy(), 'rounding': 'up'}), contains('rounding'));
      expect(bad({..._policy(), 'source': {}}), contains('source'));
      expect(
        bad(
          _policy(
            components: [
              {
                'name': 'X',
                'supply': 'any',
                'rates': [
                  {'effectiveFrom': '2020-13-45', 'rateBps': 1},
                ],
              },
            ],
          ),
        ),
        contains('components[0].rates[0].effectiveFrom'),
      );
    });

    test('baseline packs have no rates and are unverified', () {
      final base = baselineTaxPolicies();
      expect(base.map((p) => p['key']), ['in-gst', 'ae-vat']);
      for (final p in base) {
        expect(
          hasAnyRate(p),
          isFalse,
          reason: 'no universal rate is hardcoded',
        );
        expect((p['verification']! as Map)['status'], 'unverified');
        expect(validatePolicy({...p, 'version': 1}), isEmpty);
        expect(
          () => resolvePolicyRule(
            p,
            countryCode: p['countryCode']! as String,
            date: '2026-01-01',
          ),
          throwsA(isA<TaxPolicyUnavailable>()),
        );
      }
    });
  });

  group('e-invoice state machine', () {
    test('final states cannot move; failed can retry', () {
      expect(canMoveEInvoice('queued', 'submitted'), isTrue);
      expect(canMoveEInvoice('submitted', 'accepted'), isTrue);
      expect(canMoveEInvoice('failed', 'queued'), isTrue);
      for (final f in ['accepted', 'rejected', 'cancelled']) {
        for (final to in eInvoiceStatuses) {
          expect(canMoveEInvoice(f, to), isFalse, reason: '$f -> $to');
        }
      }
      expect(canMoveEInvoice('accepted', 'queued'), isFalse);
    });

    test('the shipped provider is disabled everywhere', () {
      const p = NotConfiguredEInvoiceProvider();
      expect(p.enabledFor('IN'), isFalse);
      expect(p.enabledFor('AE'), isFalse);
    });
  });

  group('API', () {
    late PlatformHarness h;
    late BillingClinic k;

    final cgst = [
      _comp('CGST', 'intra', 900),
      _comp('SGST', 'intra', 900),
      _comp('IGST', 'inter', 1800),
    ];

    Future<Map<String, Object?>> seeded() async {
      await h.okData(
        h.call('POST', '/platform/tax/policies/seed-baseline', uid: 'root'),
      );
      return h.okData(
        h.call('GET', '/platform/tax/policies/in-gst', uid: 'root'),
      );
    }

    Future<Map<String, Object?>> setRates(
      Map<String, Object?> cur,
      List<Map<String, Object?>> comps,
    ) => h.okData(
      h.call(
        'PATCH',
        '/platform/tax/policies/in-gst',
        uid: 'root',
        body: {
          'expectedVersion': cur['version'],
          'reason': 'Rates entered by tax specialist',
          'components': comps,
        },
      ),
    );

    Future<Map<String, Object?>> verify(Map<String, Object?> cur) => h.okData(
      h.call(
        'POST',
        '/platform/tax/policies/in-gst/verify',
        uid: 'root',
        body: {
          'expectedVersion': cur['version'],
          'decision': 'verify',
          'note': 'Checked by CA firm',
        },
      ),
    );

    Future<void> usable() async {
      final cur = await seeded();
      final v2 = await setRates(cur, cgst);
      await verify(v2);
    }

    Map<String, Object?> polLine([Map<String, Object?>? extra]) => {
      'description': 'Procedure',
      'unitMinor': 100000,
      'quantity': 1,
      'taxPolicyKey': 'in-gst',
      ...?extra,
    };

    setUp(() async {
      h = PlatformHarness();
      h.user('root', role: PlatformRole.superAdmin);
      h.user('support', role: PlatformRole.platformSupportAdmin);
      k = BillingClinic(h);
      await k.init();
    });

    test('permissions: only tax roles manage and verify', () async {
      await seeded();
      expect(
        await h.status('GET', '/platform/tax/policies', uid: 'support'),
        200,
      );
      expect(
        await h.status(
          'POST',
          '/platform/tax/policies/seed-baseline',
          uid: 'support',
        ),
        403,
      );
      expect(
        await h.status(
          'PATCH',
          '/platform/tax/policies/in-gst',
          uid: 'support',
          body: {'expectedVersion': 1, 'reason': 'x y z', 'status': 'retired'},
        ),
        403,
      );
      expect(
        await h.status(
          'POST',
          '/platform/tax/policies/in-gst/verify',
          uid: 'support',
          body: {
            'expectedVersion': 1,
            'decision': 'verify',
            'note': 'ok ok ok',
          },
        ),
        403,
      );
      expect(
        await h.status('GET', '/platform/tax/policies', uid: 'owner'),
        403,
      );
      expect(await h.status('GET', '/platform/tax/policies'), 401);
    });

    test(
      'seed is create-if-absent and shipped packs are unverified and rate-free',
      () async {
        final a = await h.okData(
          h.call('POST', '/platform/tax/policies/seed-baseline', uid: 'root'),
        );
        expect(
          (a['items']! as List).every((e) => (e as Map)['created'] == true),
          isTrue,
        );
        final b = await h.okData(
          h.call('POST', '/platform/tax/policies/seed-baseline', uid: 'root'),
        );
        expect(
          (b['items']! as List).every((e) => (e as Map)['created'] == false),
          isTrue,
        );
        final p = await h.okData(
          h.call('GET', '/platform/tax/policies/ae-vat', uid: 'root'),
        );
        expect((p['verification']! as Map)['status'], 'unverified');
      },
    );

    test(
      'a policy without rates cannot be verified; with rates it can',
      () async {
        final cur = await seeded();
        final res = await h.call(
          'POST',
          '/platform/tax/policies/in-gst/verify',
          uid: 'root',
          body: {
            'expectedVersion': cur['version'],
            'decision': 'verify',
            'note': 'Checked by CA firm',
          },
        );
        expect(res.statusCode, 409);
        final v2 = await setRates(cur, cgst);
        final ok = await verify(v2);
        expect((ok['verification']! as Map)['status'], 'verified');
        expect((ok['verification']! as Map)['verifiedVersion'], 2);
      },
    );

    test(
      'editing material fields voids the verification; stale verification refused',
      () async {
        await usable();
        final cur = await h.okData(
          h.call('GET', '/platform/tax/policies/in-gst', uid: 'root'),
        );
        expect((cur['verification']! as Map)['status'], 'verified');
        final v3 = await setRates(cur, [
          _comp('CGST', 'intra', 950),
          _comp('SGST', 'intra', 950),
          _comp('IGST', 'inter', 1900),
        ]);
        expect((v3['verification']! as Map)['status'], 'unverified');
        final stale = await h.call(
          'POST',
          '/platform/tax/policies/in-gst/verify',
          uid: 'root',
          body: {
            'expectedVersion': cur['version'],
            'decision': 'verify',
            'note': 'Checked by CA firm',
          },
        );
        expect(stale.statusCode, 409);
        // metadata-only edit keeps a verification
        await verify(v3);
        final t = await h.okData(
          h.call(
            'PATCH',
            '/platform/tax/policies/in-gst',
            uid: 'root',
            body: {
              'expectedVersion': v3['version'],
              'reason': 'Fix title text',
              'title': 'India GST (verified)',
            },
          ),
        );
        expect((t['verification']! as Map)['status'], 'verified');
        final versions = await h.okData(
          h.call('GET', '/platform/tax/policies/in-gst/versions', uid: 'root'),
        );
        expect((versions['items']! as List).length, 4);
      },
    );

    test(
      'update validation: version, reason, unknown fields, invalid content',
      () async {
        final cur = await seeded();
        Future<int> patch(Map<String, Object?> b) => h.status(
          'PATCH',
          '/platform/tax/policies/in-gst',
          uid: 'root',
          body: b,
        );
        expect(await patch({'reason': 'no version'}), 422);
        expect(await patch({'expectedVersion': 1}), 422);
        expect(
          await patch({
            'expectedVersion': 1,
            'reason': 'abc',
            'countryCode': 'AE',
          }),
          422,
        );
        expect(
          await patch({'expectedVersion': 1, 'reason': 'abc', 'mode': 'maybe'}),
          422,
        );
        expect(
          await patch({
            'expectedVersion': 9,
            'reason': 'abc',
            'title': 'Other',
          }),
          409,
        );
        expect(cur['version'], 1);
      },
    );

    test('invoice lines refuse an unverified or unknown policy', () async {
      await seeded();
      var res = await h.call(
        'POST',
        '/billing/invoices',
        uid: 'recep',
        body: k.invoiceBody(lines: [polLine()]),
      );
      expect(res.statusCode, 422);
      res = await h.call(
        'POST',
        '/billing/invoices',
        uid: 'recep',
        body: k.invoiceBody(
          lines: [
            polLine({'taxPolicyKey': 'nope-nope'}),
          ],
        ),
      );
      expect(res.statusCode, 422);
    });

    test(
      'policy line is taxed on the invoice date and is frozen at issue',
      () async {
        await usable();
        final inv = await k.finalized(lines: [polLine()]);
        expect(inv['taxTotal'], 18000);
        expect(inv['grandTotal'], 118000);
        final line = (inv['lines']! as List).single as Map;
        expect(line['taxPolicyKey'], 'in-gst');
        expect(line['taxPolicyVersion'], 2);
        expect(line['taxType'], 'GST');
        expect(line['taxEffectiveOn'], inv['invoiceDate']);
        // the policy changes afterwards: the issued invoice does not
        final cur = await h.okData(
          h.call('GET', '/platform/tax/policies/in-gst', uid: 'root'),
        );
        await setRates(cur, [
          _comp('CGST', 'intra', 1200),
          _comp('SGST', 'intra', 1200),
          _comp('IGST', 'inter', 2400),
        ]);
        final after = await h.okData(
          h.call('GET', '/billing/invoices/${inv['invoiceId']}', uid: 'recep'),
        );
        final inv2 = (after['invoice'] ?? after) as Map;
        expect(inv2['taxTotal'], 18000);
        expect(inv2['grandTotal'], 118000);
        expect((inv2['lines']! as List).single['taxPolicyVersion'], 2);
      },
    );

    test('exemptions and supply: exempt, zero-rated, inter-state', () async {
      await seeded();
      final cur = await h.okData(
        h.call('GET', '/platform/tax/policies/in-gst', uid: 'root'),
      );
      final v2 = await h.okData(
        h.call(
          'PATCH',
          '/platform/tax/policies/in-gst',
          uid: 'root',
          body: {
            'expectedVersion': cur['version'],
            'reason': 'Rates and exemptions from specialist',
            'components': cgst,
            'exemptions': [
              {
                'key': 'healthcare',
                'label': 'Health care services',
                'treatment': 'exempt',
              },
              {
                'key': 'export',
                'label': 'Export of services',
                'treatment': 'zero_rated',
              },
            ],
          },
        ),
      );
      await verify(v2);
      final ex = await k.finalized(
        lines: [
          polLine({'taxExemptionKey': 'healthcare'}),
        ],
      );
      expect(ex['taxTotal'], 0);
      expect(ex['grandTotal'], 100000);
      final z = await k.finalized(
        lines: [
          polLine({'taxExemptionKey': 'export'}),
        ],
      );
      expect(z['taxTotal'], 0);
      final inter = await k.finalized(
        lines: [
          polLine({'supply': 'inter'}),
        ],
      );
      expect(inter['taxTotal'], 18000);
      expect(((inter['lines']! as List).single as Map)['taxParts'], [
        {'name': 'IGST', 'rateBps': 1800, 'amount': 18000},
      ]);
      final bad = await h.call(
        'POST',
        '/billing/invoices',
        uid: 'recep',
        body: k.invoiceBody(
          lines: [
            polLine({'taxExemptionKey': 'zzz-zzz'}),
          ],
        ),
      );
      expect(bad.statusCode, 422);
      final mixed = await h.call(
        'POST',
        '/billing/invoices',
        uid: 'recep',
        body: k.invoiceBody(
          lines: [
            polLine({'taxExempt': true, 'taxExemptReason': 'Because reasons'}),
          ],
        ),
      );
      expect(mixed.statusCode, 422);
      final orphan = await h.call(
        'POST',
        '/billing/invoices',
        uid: 'recep',
        body: k.invoiceBody(
          lines: [
            {
              'description': 'x y',
              'unitMinor': 10,
              'quantity': 1,
              'supply': 'inter',
            },
          ],
        ),
      );
      expect(orphan.statusCode, 422);
    });

    test('a clinic cannot use another country\'s policy', () async {
      await usable();
      final h2 = h;
      final other = await h2.createClinic(
        'ownerAE',
        name: 'Dubai Clinic',
        countryCode: 'AE',
      );
      expect(other, isNotNull);
      final usableAe = await h.okData(
        h.call('GET', '/billing/tax/policies', uid: 'ownerAE'),
      );
      expect(usableAe['items'], isEmpty);
    });

    test(
      'finalization is refused when the policy changed after the draft',
      () async {
        await usable();
        final d = await k.draft(lines: [polLine()]);
        final cur = await h.okData(
          h.call('GET', '/platform/tax/policies/in-gst', uid: 'root'),
        );
        final v3 = await setRates(cur, [
          _comp('CGST', 'intra', 950),
          _comp('SGST', 'intra', 950),
          _comp('IGST', 'inter', 1900),
        ]);
        await verify(v3);
        final res = await h.call(
          'POST',
          '/billing/invoices/${d['invoiceId']}/finalize',
          uid: 'recep',
        );
        expect(res.statusCode, 409);
        // re-saving the lines applies the current policy
        await h.okData(
          h.call(
            'PATCH',
            '/billing/invoices/${d['invoiceId']}',
            uid: 'recep',
            body: {
              'lines': [polLine()],
            },
          ),
        );
        final f = await h.okData(
          h.call(
            'POST',
            '/billing/invoices/${d['invoiceId']}/finalize',
            uid: 'recep',
          ),
        );
        expect(f['taxTotal'], 19000);
      },
    );

    test(
      'usable policies list shows only verified ones with today\'s rate',
      () async {
        await seeded();
        expect(
          (await h.okData(
            h.call('GET', '/billing/tax/policies', uid: 'recep'),
          ))['items'],
          isEmpty,
        );
        final cur = await h.okData(
          h.call('GET', '/platform/tax/policies/in-gst', uid: 'root'),
        );
        await verify(await setRates(cur, cgst));
        final list = await h.okData(
          h.call('GET', '/billing/tax/policies', uid: 'recep'),
        );
        final item = (list['items']! as List).single as Map;
        expect(item['key'], 'in-gst');
        expect(
          (item['components']! as List).map((c) => (c as Map)['rateBps']),
          [900, 900, 1800],
        );
        expect(
          await h.status('GET', '/billing/tax/policies', uid: 'nurse'),
          403,
        );
      },
    );

    test(
      'issued invoice keeps seller, customer, numbering and template snapshot',
      () async {
        await h.okData(
          h.call(
            'PUT',
            '/billing/settings',
            uid: 'owner',
            body: {
              'legalName': 'Avail Care Pvt Ltd',
              'taxRegistrationNumber': 'TAX-12345',
            },
          ),
        );
        final inv = await k.finalized();
        final s = inv['issueSnapshot']! as Map;
        expect((s['seller']! as Map)['legalName'], 'Avail Care Pvt Ltd');
        expect((s['seller']! as Map)['taxRegistrationNumber'], 'TAX-12345');
        expect((s['seller']! as Map)['countryCode'], 'IN');
        expect((s['customer']! as Map)['name'], isNotNull);
        expect(s['currency'], 'INR');
        expect(s['currencyExponent'], 2);
        expect((s['numbering']! as Map)['prefix'], 'INV');
        expect(s['templateVersion'], 1);
        await h.okData(
          h.call(
            'PUT',
            '/billing/settings',
            uid: 'owner',
            body: {
              'legalName': 'Renamed Ltd',
              'taxRegistrationNumber': 'TAX-99999',
            },
          ),
        );
        final again = await h.okData(
          h.call('GET', '/billing/invoices/${inv['invoiceId']}', uid: 'recep'),
        );
        final s2 =
            ((again['invoice'] ?? again) as Map)['issueSnapshot']! as Map;
        expect((s2['seller']! as Map)['legalName'], 'Avail Care Pvt Ltd');
        expect((s2['seller']! as Map)['taxRegistrationNumber'], 'TAX-12345');
        expect(
          await h.status(
            'PUT',
            '/billing/settings',
            uid: 'owner',
            body: {'taxRegistrationNumber': '<script>'},
          ),
          422,
        );
      },
    );

    test(
      'invoice numbers are unique and gapless under concurrent finalization',
      () async {
        final drafts = [
          for (var i = 0; i < 8; i++)
            await k.draft(
              lines: [
                {'description': 'Item $i', 'unitMinor': 1000, 'quantity': 1},
              ],
            ),
        ];
        final res = await Future.wait([
          for (final d in drafts)
            h.okData(
              h.call(
                'POST',
                '/billing/invoices/${d['invoiceId']}/finalize',
                uid: 'recep',
              ),
            ),
        ]);
        final numbers = res.map((r) => r['invoiceNumber']).toList();
        expect(numbers.toSet().length, 8);
        final seq = [for (final n in numbers) int.parse('$n'.split('-').last)]
          ..sort();
        expect(seq, [1, 2, 3, 4, 5, 6, 7, 8]);
      },
    );

    test('credit and debit notes: tax part is declared and capped', () async {
      await usable();
      final inv = await k.finalized(lines: [polLine()]);
      final id = inv['invoiceId'];
      final cn = await h.okData(
        h.call(
          'POST',
          '/billing/invoices/$id/adjustments',
          uid: 'owner',
          body: {
            'type': 'credit',
            'amountMinor': 11800,
            'taxIncludedMinor': 1800,
            'reason': 'Service not delivered',
          },
        ),
        status: 201,
      );
      expect(
        ((cn['adjustment']! as Map)['number'] as String).startsWith('CN-'),
        isTrue,
      );
      expect((cn['adjustment']! as Map)['taxIncluded'], 1800);
      final over = await h.call(
        'POST',
        '/billing/invoices/$id/adjustments',
        uid: 'owner',
        body: {
          'type': 'credit',
          'amountMinor': 1000,
          'taxIncludedMinor': 99999,
          'reason': 'Too much tax',
        },
      );
      expect(over.statusCode, anyOf(409, 422));
      final over2 = await h.call(
        'POST',
        '/billing/invoices/$id/adjustments',
        uid: 'owner',
        body: {
          'type': 'credit',
          'amountMinor': 1000,
          'taxIncludedMinor': 2000,
          'reason': 'Too much tax',
        },
      );
      expect(over2.statusCode, 422);
    });

    test(
      'tax summary: revenue, liability and collections are separate',
      () async {
        await usable();
        final a = await k.finalized(lines: [polLine()]);
        await k.finalized(
          lines: [
            {'description': 'No tax item', 'unitMinor': 5000, 'quantity': 1},
          ],
        );
        await k.pay('${a['invoiceId']}', 100000);
        await h.okData(
          h.call(
            'POST',
            '/billing/invoices/${a['invoiceId']}/adjustments',
            uid: 'owner',
            body: {
              'type': 'credit',
              'amountMinor': 5900,
              'taxIncludedMinor': 900,
              'reason': 'Partial service credit',
            },
          ),
          status: 201,
        );
        final day = '${a['invoiceDate']}';
        final rep = await h.okData(
          h.call('GET', '/finance/reports/tax?from=$day&to=$day', uid: 'acct'),
        );
        final t = rep['totals']! as Map;
        expect(t['taxCharged'], 18000);
        expect(t['taxCredited'], 900);
        expect(t['netTaxLiability'], 17100);
        expect(t['taxableValue'], 105000);
        expect(t['revenue'], 105000);
        expect(t['collected'], 100000);
        expect('${rep['disclaimer']}', contains('not a tax'));
        final comps = (rep['rows']! as List)
            .map((r) => (r as Map)['component'])
            .toSet();
        expect(comps, containsAll(['CGST', 'SGST', '-', 'credit notes']));
        final csv = await h.call(
          'GET',
          '/finance/reports/tax?from=$day&to=$day&format=csv',
          uid: 'acct',
        );
        expect(csv.statusCode, 200);
        expect(csv.headers['content-type'], contains('text/csv'));
        expect(
          await h.status('GET', '/finance/reports/tax', uid: 'recep'),
          403,
        );
        expect(
          await h.status('GET', '/finance/reports/tax', uid: 'nurse'),
          403,
        );
      },
    );

    test('e-invoicing is disabled: nothing is ever transmitted', () async {
      final inv = await k.finalized();
      final res = await h.call(
        'POST',
        '/billing/invoices/${inv['invoiceId']}/e-invoice',
        uid: 'recep',
      );
      expect(res.statusCode, 409);
      final st = await h.okData(
        h.call(
          'GET',
          '/billing/invoices/${inv['invoiceId']}/e-invoice',
          uid: 'recep',
        ),
      );
      expect(st['submission'], isNull);
      final d = await k.draft(
        lines: [
          {'description': 'x y', 'unitMinor': 1, 'quantity': 1},
        ],
      );
      expect(
        await h.status(
          'POST',
          '/billing/invoices/${d['invoiceId']}/e-invoice',
          uid: 'recep',
        ),
        409,
      );
      expect(
        await h.status(
          'POST',
          '/billing/invoices/${inv['invoiceId']}/e-invoice',
          uid: 'nurse',
        ),
        403,
      );
    });
  });
}
