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

const _base = ['clinic.view', 'branches.view', 'reports.view'];
const _desk = [..._base, 'appointments.view', 'queue.view', 'patients.view'];
const _admin = [
  ..._desk,
  'reports.export',
  'notifications.manage',
  'finance.reports.view',
];

class Env {
  Env(this.perms);

  final List<String> perms;
  final List<(String, String, Object?)> sent = [];
  final List<String> asked = [];
  final Map<String, Map<String, Object?>> maps = {};
  final Map<String, List<Map<String, Object?>>> lists = {};
  final Map<String, List<Map<String, Object?>>> rows = {};

  FakeRepo repo() {
    final r = FakeRepo();
    r.on('getMap', (a, n) {
      final path = a[0]! as String;
      asked.add(path);
      if (path.startsWith('/members/current/permissions')) {
        return {
          'tenantId': 'ten_1',
          'role': 'clinic_admin',
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
      asked.add(path);
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
      final path = a[1]! as String;
      if (path == '/reports/exports') {
        return {'exportId': 'rx_1', 'status': 'ready'};
      }
      if (path.endsWith('/preview')) {
        return {
          'subject': 'Hi',
          'body': 'Rendered text',
          'note': 'Preview only. Nothing was sent.',
        };
      }
      return <String, Object?>{'ok': true};
    });
    r.on('exportBytes', (a, n) => Uint8List.fromList([1, 2, 3]));
    return r;
  }
}

Widget _app(Env e, {List<Override> overrides = const []}) => buildApp(
  repo: e.repo(),
  overrides: overrides,
  session: sessionWith(
    memberships: [
      const MembershipSummaryDto(tenantId: 'ten_1', role: 'clinic_admin'),
    ],
  ),
);

Map<String, Object?> _dash({bool billing = true}) => {
  'from': '2026-06-01',
  'to': '2026-06-30',
  'timezone': 'Asia/Kolkata',
  'generatedAt': '2026-06-30T10:00:00.000Z',
  'sections': {
    'appointments': {
      'available': true,
      'summary': {
        'total': 12,
        'completed': 8,
        'cancelled': 2,
        'noShowRate': null,
      },
      'truncated': false,
    },
    'queues': {
      'available': true,
      'summary': {'tokens': 9},
      'truncated': false,
    },
    'patients': {
      'available': true,
      'summary': {'registrations': 3, 'activePatients': 40},
      'truncated': false,
    },
    'consultations': {'available': false, 'reason': 'not_permitted'},
    'laboratory': {'available': false, 'reason': 'not_permitted'},
    'billing': billing
        ? {
            'available': true,
            'summary': {
              'grossBilled': 150000,
              'collected': 90000,
              'refunded': 5000,
              'outstandingOnInvoicesInRange': 60000,
            },
            'truncated': false,
          }
        : {'available': false, 'reason': 'not_permitted'},
  },
  'trend': {
    'metric': 'appointments per day',
    'points': [
      {'date': '2026-06-02', 'value': 7},
      {'date': '2026-06-03', 'value': 5},
    ],
  },
};

void main() {
  group('notification center', () {
    testWidgets('lists notifications, shows the unread count and opens one', (
      t,
    ) async {
      final e = Env(_base)
        ..maps['/notifications/unread-count'] = {'unread': 2, 'capped': false}
        ..lists['/notifications'] = [
          {
            'notificationId': 'n1',
            'title': 'A report is ready',
            'body': 'Open the app.',
            'read': false,
            'createdAt': '2026-06-01T05:00:00Z',
            'resourceType': 'lab_report',
            'resourceId': 'lr_1',
          },
          {
            'notificationId': 'n2',
            'title': 'Reminder',
            'body': 'Visit soon.',
            'read': true,
            'createdAt': '2026-06-01T04:00:00Z',
          },
        ];
      await open(t, _app(e), '/clinic/notifications');
      expect(find.text('A report is ready'), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('unread-count'))).data,
        '2 unread',
      );
      await t.tap(find.byKey(const Key('notification-n1')));
      await t.pumpAndSettle();
      expect(e.sent.first.$2, '/notifications/n1/read');
    });

    testWidgets('mark all read and dismiss send the actions', (t) async {
      final e = Env(_base)
        ..maps['/notifications/unread-count'] = {'unread': 1, 'capped': false}
        ..lists['/notifications'] = [
          {
            'notificationId': 'n1',
            'title': 'x',
            'body': 'y',
            'read': false,
            'createdAt': '2026-06-01T05:00:00Z',
          },
        ];
      await open(t, _app(e), '/clinic/notifications');
      await t.tap(find.byKey(const Key('mark-all-read')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('archive-n1')));
      await t.pumpAndSettle();
      expect(e.sent.map((s) => s.$2), [
        '/notifications/read-all',
        '/notifications/n1/archive',
      ]);
    });

    testWidgets('empty state', (t) async {
      final e = Env(_base)
        ..maps['/notifications/unread-count'] = {'unread': 0, 'capped': false};
      await open(t, _app(e), '/clinic/notifications');
      expect(find.text('No notifications'), findsOneWidget);
    });
  });

  group('preferences', () {
    testWidgets('a change sends only that choice', (t) async {
      final e = Env(_base)
        ..maps['/notifications/preferences'] = {
          'pushEnabled': true,
          'channels': {'email': true, 'sms': true, 'whatsapp': true},
          'categories': {
            'appointment_reminder': true,
            'clinic_announcement': false,
          },
          'essentialCategories': ['appointment_reminder'],
        };
      await open(t, _app(e), '/clinic/notifications/settings');
      await t.tap(find.byKey(const Key('pref-push')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pref-cat-clinic_announcement')));
      await t.pumpAndSettle();
      expect(e.sent[0].$3, {'pushEnabled': false});
      expect(e.sent[1].$3, {
        'categories': {'clinic_announcement': true},
      });
      expect(find.textContaining('Service message'), findsWidgets);
    });
  });

  group('administration', () {
    testWidgets('the admin entry follows the permission', (t) async {
      await open(t, _app(Env(_desk)), '/clinic');
      expect(find.text('Notification admin'), findsNothing);
      expect(find.text('Notifications'), findsWidgets);
      await open(t, _app(Env(_admin)), '/clinic');
      expect(find.text('Notification admin'), findsWidgets);
    });

    testWidgets('a failed delivery can be retried after confirmation', (
      t,
    ) async {
      final e = Env(_admin)
        ..maps['/admin/notification-health'] = {
          'failed': 1,
          'retryBacklog': 0,
          'configurationRequired': 0,
          'eventsWaiting': 0,
        }
        ..rows['/admin/notification-deliveries'] = [
          {
            'deliveryId': 'dl_1',
            'type': 'appointment_reminder',
            'channel': 'push',
            'status': 'permanently_failed',
            'attempts': 5,
            'error': 'http_403',
            'createdAt': '2026-06-01T05:00:00Z',
          },
        ];
      await open(t, _app(e), '/clinic/notifications/admin');
      expect(t.widget<Text>(find.byKey(const Key('health-failed'))).data, '1');
      expect(
        find.textContaining('does not confirm that the person received it'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('retry-dl_1')));
      await t.pumpAndSettle();
      expect(e.sent, isEmpty, reason: 'nothing happens before confirming');
      await t.tap(find.byKey(const Key('confirm-retry')));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/admin/notification-deliveries/dl_1/retry');
    });

    testWidgets(
      'templates preview without sending; built-ins cannot be edited',
      (t) async {
        final e = Env(_admin)
          ..maps['/admin/notification-health'] = {}
          ..lists['/admin/notification-templates'] = [
            {
              'templateId': 'builtin:appointment_reminder:push',
              'builtin': true,
              'eventType': 'appointment_reminder',
              'channel': 'push',
              'locale': 'en',
              'body': 'You have an upcoming appointment.',
              'version': 1,
            },
            {
              'templateId': 'tpl_1',
              'builtin': false,
              'eventType': 'followup_reminder',
              'channel': 'in_app',
              'locale': 'en',
              'subject': 's',
              'body': 'Follow-up on {{date}}',
              'version': 2,
            },
          ];
        await open(t, _app(e), '/clinic/notifications/admin');
        await t.tap(find.byKey(const Key('admin-tab-templates')));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('edit-builtin:appointment_reminder:push')),
          findsNothing,
        );
        expect(find.byKey(const Key('edit-tpl_1')), findsOneWidget);
        await t.tap(find.byKey(const Key('preview-tpl_1')));
        await t.pumpAndSettle();
        expect(find.text('Rendered text'), findsOneWidget);
        expect(find.textContaining('Nothing was sent'), findsOneWidget);
      },
    );

    testWidgets('channels show configuration honestly and can be paused', (
      t,
    ) async {
      final e = Env(_admin)
        ..maps['/admin/notification-health'] = {}
        ..lists['/admin/notification-channels'] = [
          {'channel': 'in_app', 'configured': true, 'paused': false},
          {'channel': 'push', 'configured': true, 'paused': false},
          {
            'channel': 'email',
            'configured': false,
            'paused': false,
            'status': 'configuration_required',
          },
        ];
      await open(t, _app(e), '/clinic/notifications/admin');
      await t.tap(find.byKey(const Key('admin-tab-channels')));
      await t.pumpAndSettle();
      expect(find.textContaining('Configuration required'), findsOneWidget);
      expect(find.byKey(const Key('toggle-in_app')), findsNothing);
      await t.tap(find.byKey(const Key('toggle-push')));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/admin/notification-channels/push/pause');
    });
  });

  group('reports', () {
    testWidgets(
      'dashboard shows figures, freshness, unavailable sections and empty rates',
      (t) async {
        final e = Env(_desk)
          ..maps['/reports/dashboard'] = _dash(billing: false);
        await open(t, _app(e), '/clinic/reports');
        expect(
          t.widget<Text>(find.byKey(const Key('kpi-appointments-total'))).data,
          '12',
        );
        expect(
          t
              .widget<Text>(
                find.byKey(const Key('kpi-appointments-noShowRate')),
              )
              .data,
          'Not enough data',
        );
        expect(find.byKey(const Key('unavailable-billing')), findsOneWidget);
        expect(find.byKey(const Key('unavailable-laboratory')), findsOneWidget);
        expect(find.byKey(const Key('freshness')), findsOneWidget);
        expect(find.textContaining('Last updated'), findsOneWidget);
      },
    );

    testWidgets('money is shown per measure, never as profit', (t) async {
      final e = Env(_admin)..maps['/reports/dashboard'] = _dash();
      await open(t, _app(e), '/clinic/reports');
      expect(
        t.widget<Text>(find.byKey(const Key('kpi-billing-grossBilled'))).data,
        '₹1,500.00',
      );
      expect(
        t.widget<Text>(find.byKey(const Key('kpi-billing-collected'))).data,
        '₹900.00',
      );
      expect(find.textContaining('rofit'), findsNothing);
    });

    testWidgets('an invalid date is refused before any request', (t) async {
      final e = Env(_desk)..maps['/reports/dashboard'] = _dash();
      await open(t, _app(e), '/clinic/reports');
      final before = e.asked.where((p) => p == '/reports/dashboard').length;
      await t.enterText(
        find.widgetWithText(TextField, 'From (YYYY-MM-DD)'),
        '06/01/2026',
      );
      await t.tap(find.byKey(const Key('apply-range')));
      await t.pumpAndSettle();
      expect(find.text('Use dates like 2026-06-01.'), findsOneWidget);
      expect(e.asked.where((p) => p == '/reports/dashboard').length, before);
    });

    Map<String, Object?> detail() => {
      'report': 'appointments',
      'generatedAt': '2026-06-30T10:00:00.000Z',
      'truncated': false,
      'notes': <Object?>[],
      'columns': ['date', 'total'],
      'rows': [
        {'date': '2026-06-02', 'total': 3},
      ],
      'summary': {'total': 3, 'noShowRate': 0.25},
      'definitions': {'total': 'Appointments with a visit date in the range.'},
    };

    testWidgets('a report shows its table and definitions', (t) async {
      final e = Env(_desk)..maps['/reports/appointments'] = detail();
      await open(t, _app(e), '/clinic/reports/appointments');
      expect(find.text('2026-06-02'), findsOneWidget);
      expect(find.textContaining('25.0%'), findsOneWidget);
      expect(
        find.textContaining('Appointments with a visit date'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('export-csv')),
        findsNothing,
        reason: 'no export permission',
      );
    });

    testWidgets('an incomplete report is flagged', (t) async {
      final e = Env(_desk)
        ..maps['/reports/appointments'] = {
          ...detail(),
          'truncated': true,
          'notes': ['More than 5000 records match; figures are incomplete.'],
        };
      await open(t, _app(e), '/clinic/reports/appointments');
      expect(find.textContaining('incomplete'), findsOneWidget);
    });

    testWidgets('an empty period says so', (t) async {
      final e = Env(_desk)
        ..maps['/reports/appointments'] = {...detail(), 'rows': <Object?>[]};
      await open(t, _app(e), '/clinic/reports/appointments');
      expect(find.byKey(const Key('no-rows')), findsOneWidget);
    });

    testWidgets(
      'export is requested from the server and downloaded through the API',
      (t) async {
        final e = Env(_admin)..maps['/reports/appointments'] = detail();
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
          '/clinic/reports/appointments?from=2026-06-01&to=2026-06-30',
        );
        await t.tap(find.byKey(const Key('export-csv')));
        await t.pumpAndSettle();
        final s = e.sent.single;
        expect(s.$2, '/reports/exports');
        expect((s.$3! as Map)['report'], 'appointments');
        expect((s.$3! as Map)['format'], 'csv');
        expect((s.$3! as Map)['from'], '2026-06-01');
        expect(saved, ['appointments-2026-06-01-2026-06-30.csv:3']);
      },
    );

    testWidgets(
      'export history offers downloads only for ready, unexpired files',
      (t) async {
        final e = Env(_admin)
          ..maps['/reports/appointments'] = detail()
          ..lists['/reports/exports'] = [
            {
              'exportId': 'rx_1',
              'report': 'appointments',
              'format': 'csv',
              'status': 'ready',
              'expired': false,
              'rows': 2,
              'requestedAt': '2026-06-01T05:00:00Z',
            },
            {
              'exportId': 'rx_2',
              'report': 'billing',
              'format': 'pdf',
              'status': 'ready',
              'expired': true,
              'rows': 2,
              'requestedAt': '2026-05-01T05:00:00Z',
            },
          ];
        await open(t, _app(e), '/clinic/reports/appointments');
        expect(find.byKey(const Key('download-export-rx_1')), findsOneWidget);
        expect(find.byKey(const Key('download-export-rx_2')), findsNothing);
      },
    );
  });
}
