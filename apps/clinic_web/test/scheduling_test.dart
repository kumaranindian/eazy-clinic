import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

const _front = [
  'clinic.view',
  'branches.view',
  'patients.view',
  'appointment_types.view',
  'availability.view',
  'appointments.view',
  'appointments.book',
  'appointments.manage',
  'appointments.check_in',
  'appointments.cancel_checked_in',
  'queue.view',
  'queue.operate',
];
const _admin = [
  ..._front,
  'appointment_types.manage',
  'availability.manage',
  'queue.priority',
];
const _doctor = [
  'clinic.view',
  'branches.view',
  'appointments.view',
  'appointments.consult',
  'queue.view',
  'queue.operate',
  'queue.consult',
  'availability.view',
  'availability.manage_own',
];

Map<String, Object?> _appt({
  String id = 'apt_1',
  String status = 'confirmed',
  bool attention = false,
  String? token,
  String start = '09:00',
  String patient = 'Asha Patil',
}) => {
  'appointmentId': id,
  'reference': 'APT-20260602-AB12',
  'branchId': 'br_1',
  'doctorId': 'dr_1',
  'doctorName': 'Dr Rao',
  'patientId': 'pt_1',
  'patientName': patient,
  'patientMrn': 'MRN-000001',
  'typeId': 'aty_1',
  'typeName': 'General',
  'localDate': '2026-06-02',
  'startTime': start,
  'endTime': '09:30',
  'timezone': 'Asia/Kolkata',
  'durationMinutes': 30,
  'source': 'reception',
  'status': status,
  'needsAttention': attention,
  'tokenDisplay': token,
  'notes': null,
};

class Env {
  Env(this.perms, {this.role = 'receptionist'});

  final List<String> perms;
  final String role;
  List<Map<String, Object?>> appointments = [];
  Map<String, Object?> detail = _appt();
  List<Map<String, Object?>> history = [];
  Map<String, Object?> Function()? queue;
  List<Map<String, Object?>> entries = [];
  List<Map<String, Object?>> schedules = [];
  List<Map<String, Object?>> exceptions = [];
  List<Map<String, Object?>> types = [];
  List<Map<String, Object?>> patients = [];
  List<Map<String, Object?>> slots = [
    {'startTime': '09:00'},
    {'startTime': '09:30'},
  ];
  Object? sendResult = {'ok': true};
  ApiFailure? sendError;
  final sent = <(String, String, Object?, Map<String, String>?)>[];
  final slotRequests = <String>[];
  Map<String, Object?> queryOf(Map<String, String>? q) => q ?? const {};

  FakeRepo repo() {
    final r = FakeRepo();
    r.on('entitlements', (a, n) => entitlementsJson());
    r.on('getMap', (a, n) {
      final path = a[0]! as String;
      final q = (a[1] as Map<String, String>?) ?? const {};
      if (path.startsWith('/members/current/permissions')) {
        return {
          'tenantId': 'ten_1',
          'role': role,
          'allBranches': true,
          'branches': [
            {'branchId': 'br_1', 'name': 'Main'},
          ],
          'accessLevel': 'full',
          'writesAllowed': true,
          'permissions': perms,
        };
      }
      if (path == '/appointments/available-slots') {
        slotRequests.add('${q['date']}|${q['typeId']}');
        return {
          'date': q['date'],
          'day': {
            'closed': false,
            'sessions': [
              {'from': '09:00', 'to': '13:00'},
            ],
            'breaks': <Object?>[],
            'blocked': <Object?>[],
          },
          'slots': slots,
        };
      }
      if (path == '/queues/current') return queue!();
      if (path.startsWith('/appointments/')) {
        return {...detail, 'history': history};
      }
      if (path.startsWith('/patients/')) {
        return {
          'patientId': 'pt_1',
          'fullName': 'Asha Patil',
          'mrn': 'MRN-000001',
          'status': 'active',
        };
      }
      return ownerAccess(path);
    });
    r.on('getList', (a, n) {
      final path = a[0]! as String;
      if (path == '/branches') {
        return [
          {'branchId': 'br_1', 'name': 'Main', 'status': 'active'},
        ];
      }
      if (path == '/doctors') {
        return [
          {'doctorId': 'dr_1', 'fullName': 'Dr Rao', 'status': 'active'},
        ];
      }
      if (path == '/appointment-types') {
        return types.isEmpty
            ? [
                {'typeId': 'aty_1', 'name': 'General', 'durationMinutes': 30},
              ]
            : types;
      }
      if (path == '/appointments' || path.endsWith('/appointments')) {
        return appointments;
      }
      if (path == '/patients') return patients;
      if (path.endsWith('/availability')) return schedules;
      if (path.endsWith('/schedule-exceptions')) return exceptions;
      if (path.endsWith('/entries')) return entries;
      return <Map<String, Object?>>[];
    });
    r.on('list', (a, n) {
      final path = a[0]! as String;
      if (path == '/appointment-types') return listOf(types);
      return listOf([]);
    });
    r.on('sendMap', (a, n) {
      sent.add((
        a[0]! as String,
        a[1]! as String,
        a[2],
        (n['headers'] as Map<String, String>?),
      ));
      if (sendError != null) throw sendError!;
      return sendResult! as Map<String, Object?>;
    });
    r.on('deleteAt', (a, n) {
      sent.add(('DELETE', a[0]! as String, null, null));
      return null;
    });
    return r;
  }
}

Widget _app(Env e) => buildApp(
  repo: e.repo(),
  session: sessionWith(
    memberships: [
      const MembershipSummaryDto(tenantId: 'ten_1', role: 'receptionist'),
    ],
  ),
);

Future<void> _type(WidgetTester t, String label, String text) async {
  final f = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  expect(f, findsOneWidget, reason: label);
  await t.ensureVisible(f);
  await t.enterText(f, text);
}

Future<void> _pick(WidgetTester t, String label, String item) async {
  final f = find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField && w.decoration.labelText == label,
  );
  expect(f, findsOneWidget, reason: label);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

void main() {
  group('navigation', () {
    testWidgets('sections follow permissions', (t) async {
      await open(t, _app(Env(_front)), '/clinic');
      for (final l in [
        'Appointments',
        'Queue',
        'Availability',
        'Appointment types',
      ]) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      final none = Env(['clinic.view', 'branches.view']);
      await open(t, _app(none), '/clinic');
      for (final l in [
        'Appointments',
        'Queue',
        'Availability',
        'Appointment types',
      ]) {
        expect(find.text(l), findsNothing, reason: l);
      }
    });
  });

  group('appointment types', () {
    testWidgets('list, create with numbers, and permission gating', (t) async {
      final e = Env(_admin)
        ..types = [
          {
            'typeId': 'aty_1',
            'name': 'General',
            'durationMinutes': 30,
            'bufferMinutes': 5,
            'status': 'active',
          },
        ];
      await open(t, _app(e), '/clinic/appointment-types');
      expect(find.text('General'), findsOneWidget);
      expect(find.textContaining('30 min + 5 min buffer'), findsOneWidget);
      await t.tap(find.text('New type'));
      await t.pumpAndSettle();
      await _type(t, 'Name', 'Follow-up');
      await _type(t, 'Duration (minutes)', '15');
      await t.tap(find.text('Create'));
      await t.pumpAndSettle();
      final body = e.sent.single.$3! as Map<String, Object?>;
      expect(e.sent.single.$2, '/appointment-types');
      expect(body, {'name': 'Follow-up', 'durationMinutes': 15});
      final ro = Env(_front)..types = e.types;
      await open(t, _app(ro), '/clinic/appointment-types');
      expect(find.text('New type'), findsNothing);
    });

    testWidgets('empty state', (t) async {
      await open(t, _app(Env(_admin)), '/clinic/appointment-types');
      expect(find.text('No appointment types yet'), findsOneWidget);
    });
  });

  group('availability', () {
    Env env() => Env(_admin)
      ..schedules = [
        {
          'scheduleId': 'sch_1',
          'branchId': 'br_1',
          'status': 'active',
          'effectiveFrom': '2026-01-01',
          'defaultDurationMinutes': 15,
          'bufferMinutes': 0,
          'maxPerSlot': 1,
          'timezone': 'Asia/Kolkata',
          'weeklyHours': {
            '1': {
              'sessions': [
                {'from': '09:00', 'to': '13:00'},
                {'from': '17:00', 'to': '20:00'},
              ],
              'breaks': [
                {'from': '11:00', 'to': '11:15'},
              ],
            },
          },
        },
      ];

    testWidgets('shows weekly sessions and breaks of the chosen doctor', (
      t,
    ) async {
      await open(t, _app(env()), '/clinic/availability');
      expect(find.text('Choose a doctor'), findsOneWidget);
      await _pick(t, 'Doctor', 'Dr Rao');
      expect(
        find.textContaining(
          'Monday: 09:00-13:00, 17:00-20:00 (breaks 11:00-11:15)',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Sunday: closed'), findsOneWidget);
      expect(find.text('New schedule'), findsOneWidget);
    });

    testWidgets('the editor refuses malformed ranges and sends nothing', (
      t,
    ) async {
      final e = env();
      await open(t, _app(e), '/clinic/availability');
      await _pick(t, 'Doctor', 'Dr Rao');
      await t.tap(find.text('New schedule'));
      await t.pumpAndSettle();
      await t.enterText(
        find
            .byWidgetPredicate(
              (w) => w is TextField && w.decoration?.labelText == 'Sessions',
            )
            .first,
        '9am to 1pm',
      );
      await t.tap(find.text('Save schedule'));
      await t.pumpAndSettle();
      expect(find.textContaining('Use 09:00-13:00'), findsWidgets);
      expect(e.sent, isEmpty);
    });

    testWidgets('a valid schedule is sent as sessions and breaks', (t) async {
      final e = env();
      await open(t, _app(e), '/clinic/availability');
      await _pick(t, 'Doctor', 'Dr Rao');
      await t.tap(find.text('New schedule'));
      await t.pumpAndSettle();
      await t.enterText(
        find
            .byWidgetPredicate(
              (w) => w is TextField && w.decoration?.labelText == 'Sessions',
            )
            .first,
        '09:00-13:00, 17:00-20:00',
      );
      await t.enterText(
        find
            .byWidgetPredicate(
              (w) => w is TextField && w.decoration?.labelText == 'Breaks',
            )
            .first,
        '11:00-11:15',
      );
      await t.tap(find.text('Save schedule'));
      await t.pumpAndSettle();
      final body = e.sent.single.$3! as Map<String, Object?>;
      expect(e.sent.single.$2, '/doctors/dr_1/availability');
      final monday = (body['weeklyHours']! as Map)['1']! as Map;
      expect(monday['sessions'], [
        {'from': '09:00', 'to': '13:00'},
        {'from': '17:00', 'to': '20:00'},
      ]);
      expect(monday['breaks'], [
        {'from': '11:00', 'to': '11:15'},
      ]);
      expect((body['weeklyHours']! as Map)['2'], {
        'sessions': <Object?>[],
        'breaks': <Object?>[],
      });
      expect(body['branchId'], 'br_1');
    });

    testWidgets(
      'adding leave lists the appointments that need attention and cancels none',
      (t) async {
        final e = env()
          ..sendResult = {
            'exceptionId': 'exc_1',
            'affectedAppointments': [
              {
                'localDate': '2026-06-02',
                'startTime': '09:00',
                'patientName': 'Asha Patil',
                'reference': 'APT-1',
              },
            ],
          };
        await open(t, _app(e), '/clinic/availability');
        await _pick(t, 'Branch', 'Main');
        await _pick(t, 'Doctor', 'Dr Rao');
        await t.tap(find.text('Add leave'));
        await t.pumpAndSettle();
        await _pick(t, 'Type', 'Doctor leave');
        await _type(t, 'First day (YYYY-MM-DD)', '2026-06-02');
        await _type(t, 'Reason', 'Conference');
        await t.tap(find.text('Add').last);
        await t.pumpAndSettle();
        expect(find.text('1 appointment(s) need attention'), findsOneWidget);
        expect(find.textContaining('Asha Patil'), findsWidgets);
        expect(find.textContaining('not cancelled'), findsNothing);
        final posts = e.sent.where((s) => s.$1 == 'POST').toList();
        expect(posts.single.$2, '/doctors/dr_1/schedule-exceptions');
        expect(e.sent.where((s) => s.$2.contains('cancel')), isEmpty);
      },
    );

    testWidgets('read-only roles see schedules but no edit actions', (t) async {
      final e = Env(_front)..schedules = env().schedules;
      await open(t, _app(e), '/clinic/availability');
      await _pick(t, 'Doctor', 'Dr Rao');
      expect(find.textContaining('Monday: 09:00-13:00'), findsOneWidget);
      expect(find.text('New schedule'), findsNothing);
      expect(find.text('Add leave'), findsNothing);
    });
  });

  group('calendar and list', () {
    testWidgets('day view lists appointments with status, token and warnings', (
      t,
    ) async {
      final e = Env(_front)
        ..appointments = [
          _appt(attention: true),
          _appt(
            id: 'apt_2',
            status: 'checked_in',
            token: 'A001',
            start: '10:00',
            patient: 'Ravi Kulkarni',
          ),
          _appt(
            id: 'apt_3',
            status: 'cancelled',
            start: '11:00',
            patient: 'Meena Rao',
          ),
        ];
      await open(t, _app(e), '/clinic/appointments');
      expect(find.text('Asha Patil · MRN-000001'), findsOneWidget);
      expect(find.textContaining('token A001'), findsOneWidget);
      expect(find.text('Checked in'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(find.text('Book appointment'), findsOneWidget);
      expect(find.text('Walk-in'), findsOneWidget);
    });

    testWidgets('views switch between day, week, month and list', (t) async {
      final e = Env(_front)..appointments = [_appt()];
      await open(t, _app(e), '/clinic/appointments');
      for (final v in ['Week', 'Month', 'List']) {
        await t.tap(find.text(v));
        await t.pumpAndSettle();
      }
      await t.tap(find.text('Month'));
      await t.pumpAndSettle();
      expect(find.textContaining('booked'), findsWidgets);
      await t.tap(find.text('Week'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('calendar-range')), findsOneWidget);
    });

    testWidgets('navigating changes the requested range and filters are sent', (
      t,
    ) async {
      final e = Env(_front);
      final repo = e.repo();
      await open(
        t,
        buildApp(
          repo: repo,
          session: sessionWith(
            memberships: [
              const MembershipSummaryDto(
                tenantId: 'ten_1',
                role: 'receptionist',
              ),
            ],
          ),
        ),
        '/clinic/appointments',
      );
      await _pick(t, 'Doctor', 'Dr Rao');
      await _pick(t, 'Status', 'Confirmed');
      final lists = [
        for (var i = 0; i < repo.calls.length; i++)
          if (repo.calls[i] == 'getList' &&
              repo.callArgs[i][0] == '/appointments')
            repo.callArgs[i][1]! as Map<String, String>,
      ];
      expect(lists.last['doctorId'], 'dr_1');
      expect(lists.last['status'], 'confirmed');
      final before = lists.last['from'];
      await t.tap(find.byTooltip('Next'));
      await t.pumpAndSettle();
      final after = [
        for (var i = 0; i < repo.calls.length; i++)
          if (repo.calls[i] == 'getList' &&
              repo.callArgs[i][0] == '/appointments')
            repo.callArgs[i][1]! as Map<String, String>,
      ].last['from'];
      expect(after, isNot(before));
    });

    testWidgets('empty and error states', (t) async {
      await open(t, _app(Env(_front)), '/clinic/appointments');
      expect(find.text('No appointments'), findsOneWidget);
      final bad = Env(_front);
      final repo = bad.repo()
        ..on('getList', (a, n) {
          if (a[0] == '/appointments') {
            throw const ApiFailure(message: 'Server error');
          }
          return <Map<String, Object?>>[];
        });
      await open(
        t,
        buildApp(
          repo: repo,
          session: sessionWith(
            memberships: [
              const MembershipSummaryDto(
                tenantId: 'ten_1',
                role: 'receptionist',
              ),
            ],
          ),
        ),
        '/clinic/appointments',
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a doctor-specific day shows availability from the backend', (
      t,
    ) async {
      final e = Env(_front);
      await open(t, _app(e), '/clinic/appointments');
      await _pick(t, 'Doctor', 'Dr Rao');
      expect(find.text('Availability'), findsWidgets);
      expect(find.textContaining('Working: 09:00-13:00'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);
    });
  });

  group('booking', () {
    Future<void> fill(WidgetTester t) async {
      await _type(t, 'Find patient (name, MRN or phone)', 'asha');
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Asha Patil · MRN-000001'));
      await t.pumpAndSettle();
      await _pick(t, 'Branch', 'Main');
      await _pick(t, 'Doctor', 'Dr Rao');
      await _pick(t, 'Appointment type', 'General (30 min)');
    }

    Env env() => Env(_front)
      ..patients = [
        {
          'patientId': 'pt_1',
          'fullName': 'Asha Patil',
          'mrn': 'MRN-000001',
          'dateOfBirth': '1990-05-14',
          'maskedPhone': 'XXXXXX0001',
        },
      ];

    testWidgets(
      'slots come from the server; confirming sends an idempotency key and no trusted fields',
      (t) async {
        final e = env()..sendResult = {'appointmentId': 'apt_9'};
        await open(t, _app(e), '/clinic/appointments/new');
        await fill(t);
        expect(find.textContaining('9876'), findsNothing);
        expect(e.slotRequests, isNotEmpty);
        await t.tap(find.text('09:30'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('booking-review')), findsOneWidget);
        await t.ensureVisible(find.text('Confirm booking'));
        await t.tap(find.text('Confirm booking'));
        await t.pumpAndSettle();
        final s = e.sent.single;
        expect(s.$2, '/appointments');
        expect(s.$4!['Idempotency-Key'], matches(RegExp(r'^ui-\d+-\d+$')));
        final body = s.$3! as Map<String, Object?>;
        expect(body['patientId'], 'pt_1');
        expect(body['startTime'], '09:30');
        expect(body['doctorId'], 'dr_1');
        for (final k in [
          'tenantId',
          'status',
          'source',
          'appointmentId',
          'reference',
        ]) {
          expect(body.containsKey(k), isFalse, reason: k);
        }
      },
    );

    testWidgets('confirm stays disabled until a slot is chosen', (t) async {
      final e = env();
      await open(t, _app(e), '/clinic/appointments/new');
      await fill(t);
      await t.ensureVisible(find.text('Confirm booking'));
      await t.tap(find.text('Confirm booking'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(e.sent, isEmpty);
    });

    testWidgets(
      'a conflict is explained, the slot is cleared and a new key is used',
      (t) async {
        final e = env()
          ..sendError = const ApiFailure(
            code: ApiErrorCode.conflict,
            message: 'That time was just taken. Choose another slot.',
          );
        await open(t, _app(e), '/clinic/appointments/new');
        await fill(t);
        await t.tap(find.text('09:00'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Confirm booking'));
        await t.tap(find.text('Confirm booking'));
        await t.pumpAndSettle();
        expect(find.textContaining('just taken'), findsOneWidget);
        expect(find.byKey(const Key('booking-review')), findsNothing);
        e.sendError = null;
        e.sendResult = {'appointmentId': 'apt_9'};
        await t.tap(find.text('09:30'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Confirm booking'));
        await t.tap(find.text('Confirm booking'));
        await t.pumpAndSettle();
        expect(e.sent, hasLength(2));
        expect(
          e.sent[1].$4!['Idempotency-Key'],
          isNot(e.sent[0].$4!['Idempotency-Key']),
        );
      },
    );

    testWidgets('a patient who is not found offers registration', (t) async {
      final e = Env([..._front, 'patients.create']);
      await open(t, _app(e), '/clinic/appointments/new');
      await _type(t, 'Find patient (name, MRN or phone)', 'zzzz');
      await t.pumpAndSettle();
      expect(find.text('Register a new patient'), findsOneWidget);
    });

    testWidgets('walk-in shows the token and adds no date or time', (t) async {
      final e = env()
        ..sendResult = {
          'tokenDisplay': 'A004',
          'startTime': '10:30',
          'doctorName': 'Dr Rao',
        };
      await open(t, _app(e), '/clinic/appointments/walk-in');
      await fill(t);
      await t.ensureVisible(find.text('Add walk-in'));
      await t.tap(find.text('Add walk-in'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('walk-in-token')), findsOneWidget);
      expect(find.text('A004'), findsOneWidget);
      final s = e.sent.single;
      expect(s.$2, '/appointments/walk-in');
      expect((s.$3! as Map).containsKey('date'), isFalse);
      expect((s.$3! as Map).containsKey('startTime'), isFalse);
      expect(s.$4!['Idempotency-Key'], isNotEmpty);
    });
  });

  group('appointment details', () {
    Future<Env> open0(WidgetTester t, Env e) async {
      await open(t, _app(e), '/clinic/appointments/apt_1');
      return e;
    }

    testWidgets(
      'a confirmed appointment offers check-in, reschedule, cancel and no-show',
      (t) async {
        final e = Env(_front)
          ..detail = _appt(attention: true)
          ..history = [
            {
              'action': 'appointment.created',
              'timestamp': '2026-06-01T10:00:00Z',
              'actorRole': 'receptionist',
            },
          ];
        await open0(t, e);
        for (final l in ['Check in', 'Reschedule', 'Cancel', 'Mark no-show']) {
          expect(find.text(l), findsOneWidget, reason: l);
        }
        expect(find.text('Complete'), findsNothing);
        expect(find.textContaining('doctor is unavailable'), findsOneWidget);
        expect(find.text('Appointment created'), findsOneWidget);
      },
    );

    testWidgets('cancelling asks for a reason first', (t) async {
      final e = await open0(t, Env(_front));
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Cancel appointment?'), findsOneWidget);
      await t.tap(find.text('Cancel appointment'));
      await t.pumpAndSettle();
      expect(e.sent, isEmpty);
      await t.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Patient called',
      );
      await t.tap(find.text('Cancel appointment'));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/appointments/apt_1/cancel');
      expect((e.sent.single.$3! as Map)['reason'], 'Patient called');
    });

    testWidgets('check-in posts to the check-in endpoint', (t) async {
      final e = await open0(t, Env(_front));
      await t.tap(find.text('Check in'));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/appointments/apt_1/check-in');
    });

    testWidgets('rescheduling picks a server slot and needs a reason', (
      t,
    ) async {
      final e = await open0(t, Env(_front));
      await t.tap(find.text('Reschedule'));
      await t.pumpAndSettle();
      await t.tap(find.text('09:30'));
      await t.pumpAndSettle();
      final go = find.widgetWithText(FilledButton, 'Reschedule');
      await t.tap(go, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(e.sent, isEmpty);
      await t.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Patient request',
      );
      await t.pumpAndSettle();
      await t.tap(go);
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/appointments/apt_1/reschedule');
      expect((e.sent.single.$3! as Map)['startTime'], '09:30');
    });

    testWidgets(
      'finished appointments offer no actions; only doctors complete visits',
      (t) async {
        final done = Env(_admin)..detail = _appt(status: 'cancelled');
        await open0(t, done);
        for (final l in [
          'Check in',
          'Reschedule',
          'Cancel',
          'Mark no-show',
          'Complete',
        ]) {
          expect(find.text(l), findsNothing, reason: l);
        }
        final prog = Env(_front)..detail = _appt(status: 'in_progress');
        await open0(t, prog);
        expect(find.text('Complete'), findsNothing);
        final doc = Env(_doctor, role: 'doctor')
          ..detail = _appt(status: 'in_progress');
        await open0(t, doc);
        expect(find.text('Complete'), findsOneWidget);
      },
    );
  });

  group('queue', () {
    Map<String, Object?> summary({
      int version = 5,
      Map<String, Object?>? current,
      int waiting = 2,
    }) => {
      'queueId': 'q_1',
      'version': version,
      'scheduledAppointments': 5,
      'checkedIn': 3,
      'waiting': waiting,
      'inConsultation': current == null ? 0 : 1,
      'completed': 1,
      'noShow': 0,
      'currentToken': current,
      'nextToken': {'displayToken': 'A003', 'patientName': 'Meena Rao'},
    };

    Env env() => Env(_front)
      ..queue = (() => summary(
        current: {'displayToken': 'A001', 'patientName': 'Asha Patil'},
      ))
      ..entries = [
        {
          'entryId': 'qe_1',
          'displayToken': 'A001',
          'patientName': 'Asha Patil',
          'status': 'in_progress',
          'source': 'reception',
        },
        {
          'entryId': 'qe_2',
          'displayToken': 'A002',
          'patientName': 'Ravi Kulkarni',
          'status': 'waiting',
          'queuePosition': 1,
          'source': 'walk_in',
          'priority': 'normal',
        },
        {
          'entryId': 'qe_3',
          'displayToken': 'A003',
          'patientName': 'Meena Rao',
          'status': 'skipped',
          'source': 'reception',
        },
      ];

    testWidgets(
      'dashboard shows counts, the current token and the waiting list',
      (t) async {
        await open(t, _app(env()), '/clinic/queue');
        expect(find.text('Choose a doctor'), findsOneWidget);
        await _pick(t, 'Doctor', 'Dr Rao');
        expect(find.text('A001'), findsWidgets);
        expect(
          t.widget<Text>(find.byKey(const Key('current-token'))).data,
          'A001',
        );
        expect(
          t.widget<Text>(find.byKey(const Key('count-waiting'))).data,
          '2',
        );
        expect(find.textContaining('Position 1 · Walk-in'), findsOneWidget);
        expect(find.text('Call next'), findsOneWidget);
      },
    );

    testWidgets('actions depend on each entry\'s state and the role', (
      t,
    ) async {
      final e = env();
      await open(t, _app(e), '/clinic/queue');
      await _pick(t, 'Doctor', 'Dr Rao');
      // front desk: waiting → call/skip, skipped → restore, in progress → nothing (no consult right)
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);
      expect(find.text('Priority'), findsNothing);
      await t.tap(find.text('Call'));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/queue-entries/qe_2/call');
      final admin = env();
      await open(
        t,
        _app(
          Env(_admin)
            ..queue = admin.queue
            ..entries = admin.entries,
        ),
        '/clinic/queue',
      );
      await _pick(t, 'Doctor', 'Dr Rao');
      expect(find.text('Priority'), findsOneWidget);
    });

    testWidgets('a doctor can complete the patient in consultation', (t) async {
      final base = env();
      final e = Env(_doctor, role: 'doctor')
        ..queue = base.queue
        ..entries = base.entries;
      await open(t, _app(e), '/clinic/queue');
      await _pick(t, 'Doctor', 'Dr Rao');
      await t.tap(find.text('Complete'));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/queue-entries/qe_1/complete');
    });

    testWidgets('the screen refreshes by itself and ignores a stale snapshot', (
      t,
    ) async {
      final e = env();
      var n = 0;
      e.queue = () {
        n++;
        return switch (n) {
          1 => summary(version: 5, waiting: 2),
          2 => summary(
            version: 4,
            waiting: 9,
          ), // out of order: older than what is shown
          _ => summary(version: 6, waiting: 1),
        };
      };
      await open(t, _app(e), '/clinic/queue');
      await _pick(t, 'Doctor', 'Dr Rao');
      expect(t.widget<Text>(find.byKey(const Key('count-waiting'))).data, '2');
      await t.pump(const Duration(seconds: 11));
      await t.pump();
      expect(
        t.widget<Text>(find.byKey(const Key('count-waiting'))).data,
        '2',
        reason: 'older snapshot ignored',
      );
      await t.pump(const Duration(seconds: 11));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('count-waiting'))).data, '1');
    });

    testWidgets('an empty queue explains itself', (t) async {
      final e = env()
        ..queue = (() => summary(waiting: 0)
          ..['checkedIn'] = 0
          ..['version'] = 0)
        ..entries = [];
      await open(t, _app(e), '/clinic/queue');
      await _pick(t, 'Doctor', 'Dr Rao');
      expect(find.text('—'), findsWidgets);
    });
  });

  group('patient appointment timeline', () {
    testWidgets('lists visits with status and token, newest first', (t) async {
      final e = Env([..._front, 'patients.view'])
        ..appointments = [
          _appt(status: 'completed', token: 'A002'),
          _appt(id: 'apt_2', status: 'cancelled', start: '10:00'),
        ];
      await open(t, _app(e), '/clinic/patients/pt_1');
      await t.ensureVisible(find.text('Appointments').last);
      await t.tap(find.text('Appointments').last);
      await t.pumpAndSettle();
      expect(find.textContaining('token A002'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
    });
  });
}
