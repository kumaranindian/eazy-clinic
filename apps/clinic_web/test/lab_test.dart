import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:clinic_web/features/laboratory/lab_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

const _base = ['clinic.view', 'branches.view', 'patients.view'];
const _desk = [
  ..._base,
  'lab.tests.view',
  'lab.orders.view',
  'lab.orders.manage',
  'lab.samples.manage',
  'lab.dashboard.view',
];
const _tech = [
  ..._desk,
  'lab.results.enter',
  'lab.results.view',
  'lab.results.verify',
  'lab.reports.publish',
  'lab.reports.view',
  'lab.external.manage',
  'lab.tests.manage',
];

Map<String, Object?> _order(String status, {bool external = false}) => {
  'orderId': 'lo_1',
  'orderNumber': 'LAB-000001',
  'status': status,
  'priority': 'urgent',
  'patientName': 'Asha Patil',
  'patientMrn': 'MRN-000001',
  'branchName': 'Main',
  'doctorName': 'Dr Rao',
  'createdAt': '2026-06-01T05:00:00.000Z',
  'external': external,
  'items': [
    {
      'itemId': 'it1',
      'testId': 'lt_1',
      'code': 'HB',
      'name': 'Haemoglobin',
      'sampleType': 'blood',
      'parameters': [
        {
          'code': 'HGB',
          'name': 'Haemoglobin',
          'valueType': 'numeric',
          'unit': 'g/dL',
        },
      ],
    },
  ],
  'samples': [
    {
      'sampleId': 'ls_1',
      'sampleNumber': 'SMP-000001',
      'sampleType': 'blood',
      'status': status == 'sample_pending' ? 'pending' : 'collected',
    },
  ],
  'history': [
    {'status': 'requested', 'at': '2026-06-01T05:00:00.000Z', 'role': 'doctor'},
  ],
};

class Env {
  Env(this.perms);

  final List<String> perms;
  final List<(String, String, Object?)> sent = [];
  final Map<String, Map<String, Object?>> maps = {};
  final Map<String, List<Map<String, Object?>>> lists = {};
  final Map<String, List<Map<String, Object?>>> rows = {};

  FakeRepo repo() {
    final r = FakeRepo();
    r.on('getMap', (a, n) {
      final path = a[0]! as String;
      if (path.startsWith('/members/current/permissions')) {
        return {
          'tenantId': 'ten_1',
          'role': 'lab_technician',
          'allBranches': true,
          'branches': [
            {'branchId': 'br_1', 'name': 'Main'},
          ],
          'accessLevel': 'full',
          'writesAllowed': true,
          'permissions': perms,
        };
      }
      return maps[path] ?? ownerAccess(path);
    });
    r.on('getList', (a, n) {
      final path = a[0]! as String;
      if (lists.containsKey(path)) return lists[path]!;
      if (path == '/branches') {
        return [
          {'branchId': 'br_1', 'name': 'Main', 'status': 'active'},
        ];
      }
      return <Map<String, Object?>>[];
    });
    r.on('list', (a, n) => listOf(rows[a[0]! as String] ?? []));
    r.on('sendMap', (a, n) {
      sent.add((a[0]! as String, a[1]! as String, a[2]));
      return <String, Object?>{'ok': true};
    });
    r.on('reportBytes', (a, n) => Uint8List.fromList([37, 80, 68, 70]));
    return r;
  }
}

Widget _app(Env e, {List<Override> overrides = const []}) => buildApp(
  repo: e.repo(),
  overrides: overrides,
  session: sessionWith(
    memberships: [
      const MembershipSummaryDto(tenantId: 'ten_1', role: 'lab_technician'),
    ],
  ),
);

void main() {
  group('navigation follows permissions', () {
    testWidgets('a technician sees the laboratory entries', (t) async {
      await open(t, _app(Env(_tech)), '/clinic');
      for (final l in [
        'Laboratory',
        'Lab orders',
        'Lab tests',
        'External labs',
      ]) {
        expect(find.text(l), findsWidgets, reason: l);
      }
    });

    testWidgets('a receptionist sees none of them', (t) async {
      await open(t, _app(Env(_base)), '/clinic');
      for (final l in [
        'Laboratory',
        'Lab orders',
        'Lab tests',
        'External labs',
      ]) {
        expect(find.text(l), findsNothing, reason: l);
      }
    });
  });

  group('dashboard', () {
    testWidgets('shows the figures the server counted', (t) async {
      final e = Env(_desk)
        ..maps['/laboratory/dashboard'] = {
          'ordersInPeriod': 7,
          'pendingOrders': 4,
          'samplesAwaitingCollection': 2,
          'processing': 1,
          'awaitingVerification': 3,
          'publishedInPeriod': 5,
          'recollections': 1,
          'rejectedSamplesInPeriod': 1,
          'urgentOpen': 2,
          'overdue': 0,
          'truncated': false,
          'definitions': {
            'overdue': 'Open orders older than their turnaround.',
          },
        };
      await open(t, _app(e), '/clinic/laboratory');
      expect(
        t.widget<Text>(find.byKey(const Key('lab-tile-pendingOrders'))).data,
        '4',
      );
      expect(
        t
            .widget<Text>(
              find.byKey(const Key('lab-tile-awaitingVerification')),
            )
            .data,
        '3',
      );
      expect(find.textContaining('turnaround'), findsOneWidget);
    });
  });

  group('orders', () {
    testWidgets('the list shows number, patient, tests and status', (t) async {
      final e = Env(_desk)
        ..rows['/laboratory/orders'] = [
          {
            ..._order('requested'),
            'tests': ['Haemoglobin'],
          },
        ];
      await open(t, _app(e), '/clinic/laboratory/orders');
      expect(find.text('LAB-000001 · Asha Patil'), findsOneWidget);
      expect(find.textContaining('Haemoglobin'), findsOneWidget);
      expect(find.byKey(const Key('new-lab-order')), findsOneWidget);
    });

    testWidgets('the desk accepts a requested order', (t) async {
      final e = Env(_desk)
        ..maps['/laboratory/orders/lo_1'] = _order('requested');
      await open(t, _app(e), '/clinic/laboratory/orders/lo_1');
      await t.tap(find.byKey(const Key('lab-accept')));
      await t.pumpAndSettle();
      expect(e.sent.single.$1, 'POST');
      expect(e.sent.single.$2, '/laboratory/orders/lo_1/accept');
    });

    testWidgets('a role without manage rights gets no actions', (t) async {
      final e = Env(_base + ['lab.orders.view'])
        ..maps['/laboratory/orders/lo_1'] = _order('requested');
      await open(t, _app(e), '/clinic/laboratory/orders/lo_1');
      expect(find.byKey(const Key('lab-accept')), findsNothing);
      expect(find.byKey(const Key('lab-cancel')), findsNothing);
    });

    testWidgets('collecting a sample sends the identity confirmation', (
      t,
    ) async {
      final e = Env(_tech)
        ..maps['/laboratory/orders/lo_1'] = _order('sample_pending');
      await open(t, _app(e), '/clinic/laboratory/orders/lo_1');
      await t.tap(find.byKey(const Key('collect-ls_1')));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Patient number (confirm identity)'),
        'MRN-000001',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Sample label / barcode'),
        'SMP-9001',
      );
      await t.tap(find.text('Record collection'));
      await t.pumpAndSettle();
      final s = e.sent.single;
      expect(s.$2, '/laboratory/samples/ls_1/collect');
      expect((s.$3! as Map)['confirmedMrn'], 'MRN-000001');
      expect((s.$3! as Map)['identifier'], 'SMP-9001');
    });

    testWidgets('results are entered per parameter and saved as a draft', (
      t,
    ) async {
      final e = Env(_tech)
        ..maps['/laboratory/orders/lo_1'] = _order('processing')
        ..maps['/laboratory/orders/lo_1/results'] = {
          'orderId': 'lo_1',
          'status': 'processing',
          'results': <Object?>[],
        };
      await open(t, _app(e), '/clinic/laboratory/orders/lo_1');
      await t.tap(find.byKey(const Key('enter-it1')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('param-HGB')), '10.5');
      await t.tap(find.byKey(const Key('save-results')));
      await t.pumpAndSettle();
      final s = e.sent.single;
      expect(s.$1, 'PUT');
      expect(s.$2, '/laboratory/orders/lo_1/results/it1');
      final obs = ((s.$3! as Map)['observations']! as List).single as Map;
      expect(obs['code'], 'HGB');
      expect(obs['value'], 10.5);
    });

    testWidgets('a non-numeric value is rejected before sending', (t) async {
      final e = Env(_tech)
        ..maps['/laboratory/orders/lo_1'] = _order('processing')
        ..maps['/laboratory/orders/lo_1/results'] = {
          'orderId': 'lo_1',
          'results': <Object?>[],
        };
      await open(t, _app(e), '/clinic/laboratory/orders/lo_1');
      await t.tap(find.byKey(const Key('enter-it1')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('param-HGB')), 'high');
      await t.tap(find.byKey(const Key('save-results')));
      await t.pumpAndSettle();
      expect(find.textContaining('must be a number'), findsOneWidget);
      expect(e.sent, isEmpty);
    });

    testWidgets('verification shows server flags and offers verify/return', (
      t,
    ) async {
      final e = Env(_tech)
        ..maps['/laboratory/orders/lo_1'] = _order('verification_pending')
        ..maps['/laboratory/orders/lo_1/results'] = {
          'orderId': 'lo_1',
          'results': [
            {
              'resultId': 'lo_1__it1',
              'itemId': 'it1',
              'testName': 'Haemoglobin',
              'status': 'submitted',
              'observations': [
                {
                  'code': 'HGB',
                  'name': 'Haemoglobin',
                  'value': 6,
                  'unit': 'g/dL',
                  'flag': 'critical_low',
                  'range': {
                    'low': 12,
                    'high': 15,
                    'unit': 'g/dL',
                    'source': 'Clinic SOP',
                  },
                },
              ],
            },
          ],
        };
      await open(t, _app(e), '/clinic/laboratory/orders/lo_1');
      expect(
        t.widget<Text>(find.byKey(const Key('flag-HGB'))).data,
        'Critical low',
      );
      expect(find.textContaining('Clinic SOP'), findsOneWidget);
      expect(find.byKey(const Key('lab-verify')), findsOneWidget);
      expect(find.byKey(const Key('lab-return')), findsOneWidget);
      await t.tap(find.byKey(const Key('lab-verify')));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/laboratory/orders/lo_1/verify');
    });

    testWidgets('a verified order can be published', (t) async {
      final e = Env(_tech)
        ..maps['/laboratory/orders/lo_1'] = _order('verified')
        ..maps['/laboratory/orders/lo_1/results'] = {'results': <Object?>[]};
      await open(t, _app(e), '/clinic/laboratory/orders/lo_1');
      await t.tap(find.byKey(const Key('lab-publish')));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/laboratory/orders/lo_1/publish');
    });

    testWidgets(
      'an external order takes an uploaded report, labelled external',
      (t) async {
        final e = Env(_tech)
          ..maps['/laboratory/orders/lo_1'] = _order(
            'processing',
            external: true,
          );
        final picked = (
          name: 'ref.pdf',
          bytes: Uint8List.fromList([37, 80, 68, 70, 45]),
        );
        await open(
          t,
          _app(
            e,
            overrides: [
              externalReportPickerProvider.overrideWithValue(
                () async => picked,
              ),
            ],
          ),
          '/clinic/laboratory/orders/lo_1',
        );
        expect(find.byKey(const Key('lab-submit')), findsNothing);
        await t.tap(find.byKey(const Key('lab-upload-external')));
        await t.pumpAndSettle();
        final s = e.sent.single;
        expect(s.$2, '/laboratory/orders/lo_1/external-report');
        expect((s.$3! as Map)['fileName'], 'ref.pdf');
        expect((s.$3! as Map)['contentBase64'], isNotEmpty);
      },
    );

    testWidgets('published reports can be downloaded through the API', (
      t,
    ) async {
      final e = Env(_tech)
        ..maps['/laboratory/orders/lo_1'] = _order('published')
        ..maps['/laboratory/orders/lo_1/results'] = {'results': <Object?>[]}
        ..lists['/laboratory/reports'] = [
          {
            'reportId': 'lr_1',
            'reportNumber': 'RPT-000001',
            'version': 1,
            'status': 'published',
            'label': 'Verified by the laboratory',
            'contentType': 'application/pdf',
          },
        ];
      final saved = <String>[];
      await open(
        t,
        _app(
          e,
          overrides: [
            reportSaverProvider.overrideWithValue(
              (n, b) async => saved.add('$n:${b.length}'),
            ),
          ],
        ),
        '/clinic/laboratory/orders/lo_1',
      );
      await t.tap(find.byKey(const Key('download-lr_1')));
      await t.pumpAndSettle();
      expect(saved, ['RPT-000001.pdf:4']);
    });
  });
}
