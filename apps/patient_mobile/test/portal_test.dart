import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_mobile/app.dart';
import 'package:patient_mobile/core/config/client_config_provider.dart';
import 'package:patient_mobile/core/routing/app_router.dart';
import 'package:patient_mobile/features/portal/data/portal_repository.dart';
import 'package:patient_mobile/features/portal/push/push_service.dart';
import 'package:utilities/utilities.dart';

import 'support/fake_auth.dart';
import 'support/fake_portal.dart';

const _linked = [
  {
    'clinicId': 'ten_1',
    'clinicName': 'Green Valley Clinic',
    'mrn': 'MRN-000001',
  },
];

Map<String, Object?> _profile({
  List<Map<String, Object?>> linked = const [],
  int completion = 100,
  Object? deletion,
}) => {
  'accountId': 'pa_1',
  'displayName': 'Asha Patil',
  'email': 'asha@example.test',
  'identityVerification': 'email_verified',
  'profileCompletion': completion,
  'profileMissing': <Object?>[],
  'linkedClinics': linked,
  'deletionRequest': ?deletion,
};

Map<String, Object?> _appt({
  String status = 'pending',
  String id = 'apt_1',
  bool cancel = true,
}) => {
  'appointmentId': id,
  'reference': 'APT-1',
  'clinicId': 'ten_1',
  'clinicName': 'Green Valley Clinic',
  'branchId': 'br_1',
  'branchName': 'Main',
  'doctorId': 'dr_1',
  'doctorName': 'Dr Rao',
  'typeId': 'aty_1',
  'typeName': 'General',
  'localDate': '2026-06-02',
  'startTime': '09:00',
  'endTime': '09:30',
  'status': status,
  'canCancel': cancel,
  'createdAt': '2026-06-01T10:00:00Z',
};

class _Setup {
  _Setup(this.handler);
  final Object? Function(String m, String p, Json? b) handler;
  late final FakePortalRepository repo = FakePortalRepository(handler);
}

class _TokenSource implements PushTokenSource {
  @override
  Future<({String deviceId, String token})?> current() async =>
      (deviceId: 'device-0001', token: 'fcm-token-aaaaaaaaaaaaaaaaaaaa');
}

Future<_Setup> _open(
  WidgetTester t,
  Object? Function(String m, String p, Json? b) handler,
  String path, {
  PushTokenSource? push,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(1000, 3200);
  addTearDown(t.view.reset);
  final s = _Setup(handler);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        clientConfigProvider.overrideWithValue(
          ClientConfig.validated(
            appEnv: 'dev',
            apiBaseUrl: 'http://localhost:8080',
          ),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
        authApiProvider.overrideWithValue(FakeAuthApi(sessionWith())),
        appAudienceProvider.overrideWithValue(AppAudience.patient),
        authUiConfigProvider.overrideWithValue(
          const AuthUiConfig(
            appName: 'Test',
            audienceLabel: 'Sign in to test',
            registrationEnabled: true,
          ),
        ),
        portalRepositoryProvider.overrideWithValue(s.repo),
        if (push != null) pushTokenSourceProvider.overrideWithValue(push),
      ],
      child: const EazyClinicApp(),
    ),
  );
  await t.pumpAndSettle();
  ProviderScope.containerOf(
    t.element(find.byType(EazyClinicApp)),
  ).read(appRouterProvider).go(path);
  await t.pumpAndSettle();
  return s;
}

Future<void> _type(WidgetTester t, String label, String text) async {
  final f = find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.labelText ?? '').startsWith(label),
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

extension on FakePortalRepository {
  List<(String, String, Json?)> sent(String method) => [
    for (final c in calls)
      if (c.$1 == method) c,
  ];
}

Object? _base(String m, String p, [Json? body]) {
  if (m == 'GET') {
    if (p.startsWith('/patient/profile')) return _profile(linked: [..._linked]);
    if (p == '/patient/notifications') {
      return {'items': <Object?>[], 'unread': 0};
    }
    return <Object?>[];
  }
  return <String, Object?>{};
}

void main() {
  group('account setup', () {
    testWidgets(
      'a person without a patient account is asked for details and creates one',
      (t) async {
        var created = false;
        final s = await _open(t, (m, p, b) {
          if (m == 'GET' && p.startsWith('/patient/profile')) {
            if (!created) {
              throw const ApiFailure(
                code: ApiErrorCode.forbidden,
                message: 'Create your patient account first.',
              );
            }
            return _profile();
          }
          if (m == 'POST' && p == '/patient-accounts') {
            created = true;
            return {'accountId': 'pa_1'};
          }
          return _base(m, p);
        }, '/');
        expect(find.text('Set up your profile'), findsOneWidget);
        expect(
          find.textContaining('does not give any clinic access'),
          findsOneWidget,
        );
        await t.tap(find.text('Create my profile'));
        await t.pumpAndSettle();
        expect(find.text('Enter your full name.'), findsOneWidget);
        expect(s.repo.sent('POST'), isEmpty);
        await _type(t, 'Full name', 'Asha Patil');
        await t.tap(find.text('Create my profile'));
        await t.pumpAndSettle();
        final call = s.repo.sent('POST').single;
        expect(call.$3, {'displayName': 'Asha Patil'});
        expect(find.text('Set up your profile'), findsNothing);
      },
    );
  });

  group('home', () {
    testWidgets(
      'without a linked clinic the app asks to link one, and shows no records',
      (t) async {
        await _open(
          t,
          (m, p, b) => m == 'GET' && p.startsWith('/patient/profile')
              ? _profile()
              : _base(m, p),
          '/',
        );
        expect(find.text('No clinic linked yet'), findsOneWidget);
        expect(find.text('Next appointment'), findsNothing);
      },
    );

    testWidgets(
      'shows the next appointment, what is due and unread notifications',
      (t) async {
        await _open(t, (m, p, b) {
          if (p.startsWith('/patient/appointments')) return [_appt()];
          if (p.startsWith('/patient/billing-summary')) {
            return [
              {'clinicId': 'ten_1', 'outstanding': 60000, 'creditBalance': 0},
            ];
          }
          if (p == '/patient/notifications') {
            return {'items': <Object?>[], 'unread': 3};
          }
          return _base(m, p);
        }, '/');
        expect(find.byKey(const Key('next-appointment')), findsOneWidget);
        expect(find.textContaining('Dr Rao'), findsOneWidget);
        expect(
          t.widget<Text>(find.byKey(const Key('home-owed'))).data,
          '₹600.00 due',
        );
        expect(find.text('3'), findsWidgets);
      },
    );
  });

  group('clinics', () {
    testWidgets('lists clinics, links with a code and never links by phone', (
      t,
    ) async {
      final s = await _open(t, (m, p, b) {
        if (p.startsWith('/patient/clinics?') || p == '/patient/clinics') {
          return [
            {
              'clinicId': 'ten_2',
              'name': 'Lakeview Clinic',
              'address': {'line1': '5 Lake Road', 'city': 'Pune'},
            },
          ];
        }
        return _base(m, p);
      }, '/clinics');
      expect(find.text('Lakeview Clinic'), findsOneWidget);
      expect(
        find.text('Green Valley Clinic'),
        findsOneWidget,
        reason: 'my clinics',
      );
      await t.tap(find.text('Link with a code'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('phone number or e-mail alone never links'),
        findsOneWidget,
      );
      await _type(t, 'Link code', 'ABCD2345EF');
      await t.tap(find.text('Link').last);
      await t.pumpAndSettle();
      final call = s.repo.sent('POST').single;
      expect(call.$2, '/patient-accounts/me/link-clinic-record');
      expect(call.$3, {'code': 'ABCD2345EF'});
    });

    testWidgets(
      'viewing an unlinked clinic says it gives no access and offers no booking',
      (t) async {
        await _open(t, (m, p, b) {
          if (p == '/patient/clinics/ten_2') {
            return {
              'clinicId': 'ten_2',
              'name': 'Lakeview Clinic',
              'branches': [
                {'branchId': 'br_9', 'name': 'Lake Branch'},
              ],
              'appointmentTypes': <Object?>[],
              'phone': '9876543210',
            };
          }
          if (p.startsWith('/patient/clinics/ten_2/specialities')) {
            return ['General Medicine'];
          }
          if (p.startsWith('/patient/clinics/ten_2/doctors')) {
            return [
              {
                'doctorId': 'dr_1',
                'fullName': 'Dr Rao',
                'specialty': 'General Medicine',
                'consultationFeeMinor': 50000,
              },
            ];
          }
          return _base(m, p);
        }, '/clinics/ten_2');
        expect(
          find.textContaining('does not give access to any record'),
          findsOneWidget,
        );
        expect(find.text('Book appointment'), findsNothing);
        expect(find.text('Dr Rao'), findsOneWidget);
        expect(find.text('₹500.00'), findsOneWidget);
      },
    );
  });

  group('appointments', () {
    testWidgets('filters ask the backend, and an empty list says so', (
      t,
    ) async {
      final s = await _open(t, (m, p, b) {
        if (p.startsWith('/patient/appointments?filter=cancelled')) {
          return <Object?>[];
        }
        if (p.startsWith('/patient/appointments')) return [_appt()];
        return _base(m, p);
      }, '/appointments');
      expect(find.text('Dr Rao · 2 Jun 2026 09:00'), findsOneWidget);
      await t.tap(find.byKey(const Key('filter-cancelled')));
      await t.pumpAndSettle();
      expect(find.text('No cancelled appointments'), findsOneWidget);
      expect(
        s.repo.calls.map((c) => c.$2),
        contains('/patient/appointments?filter=cancelled'),
      );
    });

    testWidgets(
      'detail offers cancel (with confirmation) and never sets a status itself',
      (t) async {
        final s = await _open(t, (m, p, b) {
          if (p.startsWith('/patient/clinics/ten_1/appointments/apt_1')) {
            return _appt();
          }
          return _base(m, p);
        }, '/appointments/ten_1/apt_1');
        expect(find.text('Cancel appointment'), findsOneWidget);
        expect(
          find.text('Check in'),
          findsNothing,
          reason: 'not confirmed yet',
        );
        await t.tap(find.text('Cancel appointment'));
        await t.pumpAndSettle();
        expect(find.text('Cancel this appointment?'), findsOneWidget);
        expect(s.repo.sent('POST'), isEmpty);
        await t.tap(find.byKey(const Key('confirm-cancel')));
        await t.pumpAndSettle();
        final call = s.repo.sent('POST').single;
        expect(call.$2, '/patient/clinics/ten_1/appointments/apt_1/cancel');
        expect((call.$3 ?? const {}).containsKey('status'), isFalse);
      },
    );

    testWidgets(
      'a confirmed visit can be checked in, and the queue shows only token and counts',
      (t) async {
        final s = await _open(t, (m, p, b) {
          if (p.endsWith('/queue')) {
            return {
              'status': 'waiting',
              'token': 'A-003',
              'currentToken': 'A-001',
              'patientsAhead': 1,
              'queuePosition': 2,
              'estimatedWait': null,
              'estimatedWaitNote':
                  'A waiting time is not shown because it cannot be promised reliably.',
            };
          }
          if (p.startsWith('/patient/clinics/ten_1/appointments/apt_1')) {
            return _appt(status: 'checked_in', cancel: false)
              ..['tokenDisplay'] = 'A-003';
          }
          return _base(m, p);
        }, '/appointments/ten_1/apt_1');
        expect(find.text('A-003'), findsWidgets);
        expect(find.text('A-001'), findsOneWidget);
        expect(find.textContaining('cannot be promised'), findsOneWidget);
        expect(find.text('Cancel appointment'), findsNothing);
        await t.tap(find.byKey(const Key('refresh-queue')));
        await t.pumpAndSettle();
        expect(
          s.repo.calls.where((c) => c.$2.endsWith('/queue')).length,
          greaterThanOrEqualTo(2),
        );
      },
    );

    testWidgets('a confirmed visit shows Check in', (t) async {
      final s = await _open(
        t,
        (m, p, b) => p.startsWith('/patient/clinics/ten_1/appointments/apt_1')
            ? _appt(status: 'confirmed')
            : _base(m, p),
        '/appointments/ten_1/apt_1',
      );
      await t.tap(find.text('Check in'));
      await t.pumpAndSettle();
      expect(
        s.repo.sent('POST').single.$2,
        '/patient/clinics/ten_1/appointments/apt_1/check-in',
      );
    });
  });

  group('booking', () {
    Object? handler(String m, String p, Json? b, {int? bookStatus}) {
      if (m == 'GET' && p.startsWith('/patient/profile')) {
        return _profile(linked: [..._linked]);
      }
      if (p == '/patient/clinics/ten_1') {
        return {
          'clinicId': 'ten_1',
          'name': 'Green Valley Clinic',
          'branches': [
            {'branchId': 'br_1', 'name': 'Main'},
          ],
          'appointmentTypes': [
            {'typeId': 'aty_1', 'name': 'General', 'durationMinutes': 30},
          ],
        };
      }
      if (p.startsWith('/patient/clinics/ten_1/doctors')) {
        return [
          {
            'doctorId': 'dr_1',
            'fullName': 'Dr Rao',
            'specialty': 'General Medicine',
          },
        ];
      }
      if (p.startsWith('/patient/clinics/ten_1/availability')) {
        return {
          'slots': [
            {'startTime': '09:00'},
            {'startTime': '09:30'},
          ],
        };
      }
      if (m == 'POST' && p == '/patient/appointments') return _appt();
      return _base(m, p);
    }

    Future<_Setup> fill(
      WidgetTester t,
      Object? Function(String, String, Json?) h,
    ) async {
      final s = await _open(t, h, '/appointments/new');
      await _pick(t, 'Doctor', 'Dr Rao (General Medicine)');
      await _pick(t, 'Appointment type', 'General');
      await t.tap(find.byKey(const Key('pick-date')));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('slot-09:30')));
      await t.pumpAndSettle();
      return s;
    }

    testWidgets(
      'review shows the choices, confirming sends ids only with an idempotency key',
      (t) async {
        final s = await fill(t, handler);
        await t.ensureVisible(find.byKey(const Key('review-booking')));
        await t.tap(find.byKey(const Key('review-booking')));
        await t.pumpAndSettle();
        expect(find.text('Confirm your request'), findsOneWidget);
        expect(find.text('Dr Rao'), findsWidgets);
        await t.tap(find.byKey(const Key('confirm-booking')));
        await t.pumpAndSettle();
        final call = s.repo.sent('POST').single;
        expect(call.$2, '/patient/appointments');
        final body = call.$3!;
        expect(body['clinicId'], 'ten_1');
        expect(body['doctorId'], 'dr_1');
        expect(body['startTime'], '09:30');
        expect(
          body.keys.toSet().difference({
            'clinicId',
            'branchId',
            'doctorId',
            'typeId',
            'date',
            'startTime',
          }),
          isEmpty,
          reason: 'no status, patient or tenant fields',
        );
        expect(find.text('Request received'), findsOneWidget);
        expect(find.textContaining('clinic will confirm'), findsOneWidget);
      },
    );

    testWidgets('a slot conflict is shown honestly, never as success', (
      t,
    ) async {
      final s = await fill(t, (m, p, b) {
        if (m == 'POST' && p == '/patient/appointments') {
          throw const ApiFailure(
            code: ApiErrorCode.conflict,
            message: 'That time was just taken.',
          );
        }
        return handler(m, p, b);
      });
      await t.ensureVisible(find.byKey(const Key('review-booking')));
      await t.tap(find.byKey(const Key('review-booking')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-booking')));
      await t.pumpAndSettle();
      expect(find.textContaining('That time was just taken.'), findsOneWidget);
      expect(find.textContaining('Pick another time'), findsOneWidget);
      expect(find.text('Request received'), findsNothing);
      // the old choice is cleared: booking is disabled until a new time is picked
      final review = t.widget<EcPrimaryButton>(
        find.byKey(const Key('review-booking')),
      );
      expect(review.onPressed, isNull);
      expect(s.repo.sent('POST'), hasLength(1));
    });

    testWidgets('booking needs a linked clinic', (t) async {
      await _open(
        t,
        (m, p, b) => m == 'GET' && p.startsWith('/patient/profile')
            ? _profile()
            : _base(m, p),
        '/appointments/new',
      );
      expect(find.text('No clinic linked yet'), findsOneWidget);
      expect(find.byKey(const Key('review-booking')), findsNothing);
    });
  });

  group('records', () {
    Object? records(String m, String p, Json? b) {
      if (p.startsWith('/patient/medical-records')) {
        return [
          {
            'clinicId': 'ten_1',
            'clinicName': 'Green Valley Clinic',
            'allergies': [
              {
                'allergen': 'Penicillin',
                'severity': 'severe',
                'reaction': 'Rash',
              },
            ],
            'history': [
              {'title': 'Appendectomy', 'category': 'surgery'},
            ],
            'medications': [
              {'name': 'Metformin', 'dosage': '500 mg'},
            ],
          },
        ];
      }
      if (p.startsWith('/patient/consultations')) {
        return [
          {
            'clinicId': 'ten_1',
            'consultationAt': '2026-06-01T10:00:00Z',
            'doctorName': 'Dr Rao',
            'diagnoses': [
              {'label': 'Viral fever', 'certainty': 'provisional'},
            ],
            'advice': {'recommendations': 'Rest and fluids'},
            'followUp': {'recommendedDate': '2026-06-08'},
            'prescriptions': [
              {'number': 'RX-000001'},
            ],
          },
        ];
      }
      if (p.startsWith('/patient/prescriptions')) {
        return [
          {
            'number': 'RX-000001',
            'issuedAt': '2026-06-01T10:00:00Z',
            'doctorName': 'Dr Rao',
            'clinicName': 'Green Valley Clinic',
            'current': true,
            'superseded': false,
            'medicines': [
              {
                'name': 'Paracetamol',
                'strength': '500 mg',
                'dosage': '1 tablet',
                'frequency': 'three times a day',
                'durationValue': 5,
                'durationUnit': 'days',
                'instructions': 'After food',
              },
            ],
            'disclaimer':
                "Issued by your doctor. Follow your doctor's instructions.",
          },
          {
            'number': 'RX-000000',
            'issuedAt': '2026-05-01T10:00:00Z',
            'current': false,
            'superseded': true,
            'medicines': <Object?>[],
            'disclaimer': 'x',
          },
        ];
      }
      if (p == '/patient/lab-reports' ||
          p.startsWith('/patient/lab-reports?')) {
        return [
          {
            'clinicId': 'ten_1',
            'clinicName': 'Green Valley Clinic',
            'reportId': 'lr_1',
            'reportNumber': 'RPT-000001',
            'version': 1,
            'external': false,
            'publishedAt': '2026-06-02T10:00:00Z',
            'tests': ['Haemoglobin'],
          },
          {
            'clinicId': 'ten_1',
            'clinicName': 'Green Valley Clinic',
            'reportId': 'lr_2',
            'reportNumber': 'RPT-000002',
            'version': 1,
            'external': true,
            'verifiedByClinic': false,
            'publishedAt': '2026-06-03T10:00:00Z',
            'tests': ['Send-out marker'],
          },
        ];
      }
      if (p.startsWith('/patient/clinics/ten_1/lab-reports/lr_1')) {
        return {
          'reportId': 'lr_1',
          'tests': [
            {
              'name': 'Haemoglobin',
              'observations': [
                {
                  'name': 'Haemoglobin',
                  'value': 10.2,
                  'unit': 'g/dL',
                  'flag': 'low',
                  'range': {'low': 12, 'high': 15, 'unit': 'g/dL'},
                },
              ],
            },
          ],
          'disclaimer': 'Discuss your results with your doctor.',
        };
      }
      if (p.startsWith('/patient/documents')) {
        return {
          'available': false,
          'note':
              'Documents and laboratory reports are not available in the app yet.',
        };
      }
      if (p.startsWith('/patient/billing-summary')) {
        return [
          {
            'clinicId': 'ten_1',
            'clinicName': 'Green Valley Clinic',
            'outstanding': 60000,
            'creditBalance': 5000,
          },
        ];
      }
      if (p.startsWith('/patient/invoices')) {
        return [
          {
            'invoiceId': 'inv_1',
            'clinicId': 'ten_1',
            'clinicName': 'Green Valley Clinic',
            'invoiceNumber': 'INV-000001',
            'invoiceDate': '2026-06-01',
            'outstanding': 60000,
            'currency': 'INR',
            'status': 'partially_paid',
            'displayStatus': 'partially_paid',
          },
        ];
      }
      if (p.startsWith('/patient/payments')) {
        return [
          {
            'paymentId': 'pay_1',
            'receiptId': 'rct_1',
            'clinicId': 'ten_1',
            'receiptNumber': 'RCT-000001',
            'amount': 40000,
            'currency': 'INR',
            'method': 'upi',
            'receivedAt': '2026-06-01T10:00:00Z',
          },
        ];
      }
      if (p.startsWith('/patient/refunds')) {
        return [
          {
            'refundId': 'rf_1',
            'amount': 1000,
            'currency': 'INR',
            'status': 'requested',
            'requestedAt': '2026-06-01T10:00:00Z',
          },
        ];
      }
      if (p.startsWith('/patient/clinics/ten_1/receipts/rct_1')) {
        return {
          'receiptNumber': 'RCT-000001',
          'amount': 40000,
          'currency': 'INR',
          'method': 'upi',
          'clinic': {'name': 'Green Valley Clinic'},
          'receivedAt': '2026-06-01T10:00:00Z',
          'invoices': [
            {'invoiceNumber': 'INV-000001'},
          ],
        };
      }
      if (p.startsWith('/patient/clinics/ten_1/invoices/inv_1')) {
        return {
          'invoiceNumber': 'INV-000001',
          'clinicName': 'Green Valley Clinic',
          'invoiceDate': '2026-06-01',
          'currency': 'INR',
          'status': 'partially_paid',
          'subtotal': 100000,
          'discountTotal': 0,
          'taxTotal': 0,
          'grandTotal': 100000,
          'adjustedTotal': 100000,
          'amountPaid': 40000,
          'outstanding': 60000,
          'lines': [
            {
              'description': 'Minor procedure',
              'quantity': 1,
              'unitMinor': 100000,
              'total': 100000,
            },
          ],
          'payments': [
            {'amount': 40000, 'createdAt': '2026-06-01T10:00:00Z'},
          ],
          'onlinePayment': {
            'available': false,
            'note': 'Pay at the clinic. Online payment is not available yet.',
          },
        };
      }
      return _base(m, p);
    }

    testWidgets('overview lists what the clinic recorded, per clinic', (
      t,
    ) async {
      await _open(t, records, '/records');
      expect(find.text('Green Valley Clinic'), findsWidgets);
      expect(find.textContaining('Penicillin'), findsOneWidget);
      expect(find.textContaining('Appendectomy'), findsOneWidget);
      expect(find.textContaining('Metformin'), findsOneWidget);
      expect(find.text('Edit'), findsNothing, reason: 'records are read-only');
    });

    testWidgets('visit summaries show only the released summary', (t) async {
      await _open(t, records, '/records?tab=visits');
      expect(find.textContaining('Viral fever'), findsOneWidget);
      expect(find.text('Rest and fluids'), findsOneWidget);
      expect(find.textContaining('RX-000001'), findsOneWidget);
    });

    testWidgets(
      'prescriptions are read-only, current versus history, with the disclaimer',
      (t) async {
        await _open(t, records, '/records?tab=prescriptions');
        expect(find.textContaining('Paracetamol'), findsOneWidget);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Superseded'), findsOneWidget);
        expect(find.textContaining('Follow your doctor'), findsOneWidget);
        expect(find.text('Order'), findsNothing);
        expect(find.text('Refill'), findsNothing);
      },
    );

    testWidgets(
      'bills show what is due, invoices open, receipts preview, and no fake payment',
      (t) async {
        await _open(t, records, '/records?tab=bills');
        expect(
          t.widget<Text>(find.byKey(const Key('due-ten_1'))).data,
          'Due ₹600.00',
        );
        expect(find.text('INV-000001 · 1 Jun 2026'), findsOneWidget);
        expect(find.text('Pay now'), findsNothing);
        await t.tap(find.textContaining('₹400.00 · Upi'));
        await t.pumpAndSettle();
        expect(find.text('Receipt RCT-000001'), findsOneWidget);
        await t.tap(find.text('Close'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('invoice-inv_1')));
        await t.pumpAndSettle();
        expect(find.text('Invoice INV-000001'), findsOneWidget);
        expect(
          find.textContaining('Online payment is not available yet'),
          findsOneWidget,
        );
        expect(find.text('Pay now'), findsNothing);
      },
    );

    testWidgets('lab reports list published reports and open the results', (
      t,
    ) async {
      await _open(t, records, '/records?tab=reports');
      expect(find.textContaining('RPT-000001'), findsOneWidget);
      expect(find.textContaining('Haemoglobin'), findsOneWidget);
      // an outside laboratory's report is labelled as such
      expect(find.textContaining('outside laboratory'), findsOneWidget);
      await t.tap(find.byKey(const Key('open-report-lr_1')));
      await t.pumpAndSettle();
      expect(find.textContaining('Haemoglobin: 10.2 g/dL'), findsOneWidget);
      expect(find.byKey(const Key('flag-Haemoglobin')), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.textContaining('Discuss your results'), findsOneWidget);
    });

    testWidgets('documents are honestly unavailable', (t) async {
      await _open(t, records, '/records?tab=documents');
      expect(find.text('Documents are not available yet'), findsOneWidget);
    });
  });

  group('family and person switching', () {
    Object? family(String m, String p, Json? b) {
      if (p == '/patient/family') {
        return [
          {
            'relationshipId': 'fr_1',
            'otherAccountId': 'pa_child',
            'otherName': 'Mira Patil',
            'otherKind': 'dependent',
            'relationshipType': 'parent',
            'direction': 'i_manage',
            'status': 'active',
            'verificationStatus': 'verified',
            'permissionScope': ['manage_appointments', 'view_records'],
            'canActFor': true,
          },
          {
            'relationshipId': 'fr_2',
            'otherAccountId': 'pa_ravi',
            'otherName': 'Ravi Patil',
            'otherKind': 'self',
            'relationshipType': 'caregiver',
            'direction': 'manages_me',
            'status': 'pending',
            'verificationStatus': 'pending',
            'permissionScope': ['manage_appointments'],
            'canActFor': false,
          },
        ];
      }
      if (p.startsWith('/patient/appointments')) return [_appt()];
      return _base(m, p);
    }

    testWidgets(
      'requests need approval, access can be ended, children can be added',
      (t) async {
        final s = await _open(t, family, '/family');
        expect(find.text('Mira Patil'), findsOneWidget);
        expect(find.text('Ravi Patil'), findsOneWidget);
        await t.tap(find.byKey(const Key('approve-fr_2')));
        await t.pumpAndSettle();
        expect(
          s.repo.sent('POST').last.$2,
          '/family-relationships/fr_2/verify',
        );
        expect(s.repo.sent('POST').last.$3, {'decision': 'approve'});
        await t.tap(find.byKey(const Key('revoke-fr_1')));
        await t.pumpAndSettle();
        expect(find.text('End this access?'), findsOneWidget);
        await t.tap(find.text('End access').last);
        await t.pumpAndSettle();
        expect(
          s.repo.sent('POST').last.$2,
          '/family-relationships/fr_1/revoke',
        );
      },
    );

    testWidgets('adding a child sends a dependent with guardian relationship', (
      t,
    ) async {
      final s = await _open(t, family, '/family');
      await t.tap(find.text('Add a child'));
      await t.pumpAndSettle();
      await _type(t, 'Child', 'Kabir Patil');
      await _type(t, 'Date of birth', '2018-03-04');
      await t.tap(find.text('Add').last);
      await t.pumpAndSettle();
      final body = s.repo.sent('POST').single.$3!;
      expect(body['relationshipType'], 'parent');
      expect(body['isGuardian'], true);
      expect((body['dependent']! as Map)['displayName'], 'Kabir Patil');
      expect(body.containsKey('subjectAccountId'), isFalse);
    });

    testWidgets(
      'choosing a family member adds their id to the requests; Me removes it',
      (t) async {
        final s = await _open(t, family, '/appointments');
        await t.tap(find.byKey(const Key('person-pa_child')));
        await t.pumpAndSettle();
        expect(
          s.repo.calls.map((c) => c.$2),
          anyElement(contains('accountId=pa_child')),
        );
        await t.tap(find.byKey(const Key('person-me')));
        await t.pumpAndSettle();
        expect(s.repo.calls.last.$2, isNot(contains('accountId')));
      },
    );
  });

  group('notifications', () {
    testWidgets('tapping opens the related screen and marks it read', (
      t,
    ) async {
      final s = await _open(t, (m, p, b) {
        if (p == '/patient/notifications') {
          return {
            'items': [
              {
                'notificationId': 'n_1',
                'category': 'prescription_available',
                'title': 'Prescription available',
                'body':
                    'Your doctor issued a prescription. Open the app to view it.',
                'resourceType': 'prescription',
                'resourceId': 'rx_1',
                'clinicId': 'ten_1',
                'read': false,
                'createdAt': '2026-06-01T10:00:00Z',
              },
            ],
            'unread': 1,
          };
        }
        return _base(m, p);
      }, '/notifications');
      expect(find.text('Prescription available'), findsOneWidget);
      await t.tap(find.byKey(const Key('note-n_1')));
      await t.pumpAndSettle();
      expect(s.repo.sent('POST').single.$2, '/patient/notifications/n_1/read');
      expect(find.text('Medical records'), findsOneWidget);
    });

    testWidgets('settings save only the choice made', (t) async {
      final s = await _open(t, (m, p, b) {
        if (p == '/patient/notifications/preferences') {
          return {
            'pushEnabled': true,
            'categories': {
              'appointment_booked': true,
              'clinic_announcement': true,
            },
          };
        }
        return _base(m, p);
      }, '/notifications/settings');
      await t.tap(find.byKey(const Key('push-enabled')));
      await t.pumpAndSettle();
      final put = s.repo.sent('PUT').single;
      expect(put.$2, '/patient/notifications/preferences');
      expect(put.$3, {'pushEnabled': false});
    });

    testWidgets(
      'the device registers when a token exists and is removed on sign-out',
      (t) async {
        final s = await _open(t, _base, '/profile', push: _TokenSource());
        final reg = s.repo
            .sent('POST')
            .where((c) => c.$2 == '/patient/devices')
            .single;
        expect(reg.$3, {
          'deviceId': 'device-0001',
          'token': 'fcm-token-aaaaaaaaaaaaaaaaaaaa',
          'platform': 'android',
        });
        await t.ensureVisible(find.byKey(const Key('sign-out')));
        await t.tap(find.byKey(const Key('sign-out')));
        await t.pumpAndSettle();
        expect(s.repo.sent('DELETE').single.$2, '/patient/devices/device-0001');
      },
    );

    testWidgets('without a push token the app registers nothing', (t) async {
      final s = await _open(t, _base, '/profile');
      expect(
        s.repo.sent('POST').where((c) => c.$2 == '/patient/devices'),
        isEmpty,
      );
    });
  });

  group('profile and privacy', () {
    testWidgets('edit sends only the allowed fields', (t) async {
      final s = await _open(t, _base, '/profile');
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      expect(find.textContaining('need verification'), findsOneWidget);
      await _type(t, 'Address', '12 Main Road');
      await _type(t, 'City', 'Pune');
      await _type(t, 'PIN code', '411001');
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      final call = s.repo.sent('PATCH').single;
      expect(call.$2, '/patient/profile');
      expect(call.$3, {
        'address': {
          'line1': '12 Main Road',
          'city': 'Pune',
          'postalCode': '411001',
        },
      });
    });

    testWidgets('deleting the account is a request that asks first', (t) async {
      final s = await _open(t, _base, '/profile');
      await t.ensureVisible(find.byKey(const Key('request-deletion')));
      await t.tap(find.byKey(const Key('request-deletion')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Nothing is deleted right away'),
        findsOneWidget,
      );
      expect(s.repo.sent('POST'), isEmpty);
      await t.tap(find.text('Send request'));
      await t.pumpAndSettle();
      expect(
        s.repo.sent('POST').single.$2,
        '/patient/account/deletion-request',
      );
    });

    Object? privacy(String m, String p, Json? b) {
      if (p == '/patient/consent-catalog') {
        return {
          'version': '1.0',
          'purposes': [
            {
              'type': 'record_sharing',
              'purpose': 'Record sharing',
              'text': 'Share my record with the clinic team.',
            },
            {
              'type': 'family_access',
              'purpose': 'Family access',
              'text': 'Let a family member help.',
            },
          ],
        };
      }
      if (m == 'GET' && p.startsWith('/patient/clinics/ten_1/consents')) {
        return [
          {
            'consentId': 'cn_1',
            'type': 'family_access',
            'purpose': 'Family access',
            'textVersion': '1.0',
            'status': 'granted',
            'createdAt': '2026-06-01T10:00:00Z',
          },
        ];
      }
      return _base(m, p);
    }

    testWidgets(
      'each purpose is its own choice, recorded with the wording version',
      (t) async {
        final s = await _open(t, privacy, '/profile/privacy/ten_1');
        expect(
          find.text('Share my record with the clinic team.'),
          findsOneWidget,
        );
        await t.tap(find.byKey(const Key('grant-record_sharing')));
        await t.pumpAndSettle();
        final grant = s.repo.sent('POST').single;
        expect(grant.$2, '/patient/consents');
        expect(grant.$3, {
          'clinicId': 'ten_1',
          'type': 'record_sharing',
          'decision': 'granted',
          'textVersion': '1.0',
        });
        await t.tap(find.byKey(const Key('withdraw-family_access')));
        await t.pumpAndSettle();
        expect(
          s.repo.sent('POST').last.$2,
          '/patient/clinics/ten_1/consents/cn_1/revoke',
        );
      },
    );
  });
}
