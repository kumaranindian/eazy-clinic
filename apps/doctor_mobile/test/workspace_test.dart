import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:doctor_mobile/app.dart';
import 'package:doctor_mobile/core/config/client_config_provider.dart';
import 'package:doctor_mobile/core/routing/app_router.dart';
import 'package:doctor_mobile/features/workspace/data/clinical_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utilities/utilities.dart';

import 'support/fake_auth.dart';
import 'support/fake_clinical.dart';

Json _consultation({String status = 'draft', int version = 3}) => {
  'consultationId': 'con_1',
  'patientId': 'p1',
  'patientName': 'Asha Rao',
  'patientMrn': 'MRN-1',
  'type': 'general',
  'status': status,
  'version': version,
  'revision': 0,
  'amendmentCount': 0,
  'consultationAt': '2026-01-05T04:30:00Z',
  'chiefComplaint': {
    'reason': 'Fever for two days',
    'symptoms': [
      {'name': 'fever', 'duration': '2 days'},
    ],
  },
  'diagnoses': [
    {
      'diagnosisId': 'dx1',
      'label': 'Viral fever',
      'kind': 'primary',
      'certainty': 'provisional',
    },
  ],
  'prescriptions': [
    {
      'prescriptionId': 'rx1',
      'number': null,
      'status': 'draft',
      'version': 1,
      'medicineCount': 0,
    },
  ],
  'investigations': <Object?>[],
  'followups': <Object?>[],
};

FakeClinicalRepository _repo({String status = 'draft'}) =>
    FakeClinicalRepository((m, p, b) {
      if (m == 'GET') {
        return switch (p) {
          '/doctor/dashboard' => {
            'counts': {'scheduled': 4, 'waiting': 2},
            'upcoming': <Object?>[],
            'queues': <Object?>[],
            'recentConsultations': <Object?>[],
          },
          '/doctor/queue' => [
            {
              'queueId': 'q1',
              'version': 1,
              'branchName': 'Main',
              'waiting': 1,
              'currentToken': null,
              'entries': [
                {
                  'entryId': 'e1',
                  'displayToken': 'A-001',
                  'patientName': 'Asha Rao',
                  'patientId': 'p1',
                  'status': 'waiting',
                  'source': 'scheduled',
                },
              ],
            },
          ],
          '/patients' => [
            {
              'patientId': 'p1',
              'fullName': 'Asha Rao',
              'mrn': 'MRN-1',
              'gender': 'female',
            },
          ],
          '/clinical/patients/p1/overview' => {
            'patient': {
              'patientId': 'p1',
              'fullName': 'Asha Rao',
              'mrn': 'MRN-1',
              'age': 34,
              'gender': 'female',
              'branchId': 'b1',
            },
            'alerts': <Object?>[],
            'allergies': [
              {
                'allergen': 'Penicillin',
                'severity': 'severe',
                'reaction': 'Rash',
              },
            ],
            'medications': null,
            'medicalHistory': <Object?>[],
          },
          '/clinical/patients/p1/history' => {
            'consultations': <Object?>[],
            'laboratory': {'available': false},
          },
          '/clinical/patients/p1/vitals' => <Object?>[],
          '/consultations/con_1' => _consultation(status: status),
          '/prescriptions/rx1' => {
            'prescriptionId': 'rx1',
            'consultationId': 'con_1',
            'status': status == 'draft' ? 'draft' : 'finalized',
            'number': status == 'draft' ? null : 'RX-000001',
            'version': 1,
            'rev': 2,
            'medicines': [
              {
                'name': 'Paracetamol',
                'dosage': '1 tablet',
                'frequency': 'twice daily',
                'durationValue': 3,
                'durationUnit': 'days',
              },
            ],
            'versions': <Object?>[],
            'clinicName': 'Test Clinic',
            'disclaimer': 'Issued by the treating doctor.',
          },
          _ => throw StateError('unexpected GET $p'),
        };
      }
      return const <String, Object?>{};
    });

Future<void> _open(
  WidgetTester tester,
  FakeClinicalRepository repo,
  String path,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 3000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
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
        authApiProvider.overrideWithValue(
          FakeAuthApi(
            sessionWith(
              memberships: [
                const MembershipSummaryDto(tenantId: 't', role: 'doctor'),
              ],
            ),
          ),
        ),
        appAudienceProvider.overrideWithValue(AppAudience.doctor),
        authUiConfigProvider.overrideWithValue(
          const AuthUiConfig(
            appName: 'Test',
            audienceLabel: 'Sign in to test',
            registrationEnabled: false,
          ),
        ),
        clinicalRepositoryProvider.overrideWithValue(repo),
      ],
      child: const EazyClinicApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(EazyClinicApp)),
  );
  container.read(appRouterProvider).go(path);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dashboard shows today\'s counts', (tester) async {
    await _open(tester, _repo(), '/');
    expect(find.byKey(const Key('count-scheduled')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('count-scheduled'))).data,
      '4',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('count-waiting'))).data,
      '2',
    );
  });

  testWidgets('patient search lists results and opens the clinical view', (
    tester,
  ) async {
    await _open(tester, _repo(), '/patients');
    expect(find.text('Asha Rao'), findsOneWidget);
    await tester.tap(find.byKey(const Key('patient-p1')));
    await tester.pumpAndSettle();
    expect(find.text('Penicillin'), findsOneWidget);
    // a role without medication access sees that, not an empty list
    expect(find.text('Not available for your role.'), findsOneWidget);
    expect(
      find.text('Laboratory results are not available yet.'),
      findsOneWidget,
    );
  });

  testWidgets('a draft consultation is editable and saves with its version', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, repo, '/consultations/con_1');
    expect(find.text('Viral fever'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(EcTextField, 'Assessment notes'),
      'Looks viral',
    );
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    final patch = repo.calls.lastWhere((c) => c.$1 == 'PATCH');
    expect(patch.$2, '/consultations/con_1');
    expect(patch.$3!['expectedVersion'], 3);
    expect((patch.$3!['assessment'] as Map)['notes'], 'Looks viral');
    // existing symptom detail is preserved, not rebuilt from the names
    final cc = patch.$3!['chiefComplaint'] as Map;
    expect((cc['symptoms'] as List).first, {
      'name': 'fever',
      'duration': '2 days',
    });
  });

  testWidgets('finalizing asks for confirmation first', (tester) async {
    final repo = _repo();
    await _open(tester, repo, '/consultations/con_1');
    await tester.tap(find.text('Finalize'));
    await tester.pumpAndSettle();
    expect(find.text('Finalize consultation?'), findsOneWidget);
    expect(repo.calls.where((c) => c.$2.endsWith('/finalize')), isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Finalize'));
    await tester.pumpAndSettle();
    expect(
      repo.calls.where(
        (c) => c.$1 == 'POST' && c.$2 == '/consultations/con_1/finalize',
      ),
      hasLength(1),
    );
  });

  testWidgets('a finalized consultation is read-only and offers amend', (
    tester,
  ) async {
    await _open(tester, _repo(status: 'finalized'), '/consultations/con_1');
    expect(find.text('Finalized and read-only.'), findsOneWidget);
    expect(find.text('Save draft'), findsNothing);
    expect(find.text('Finalize'), findsNothing);
    expect(find.text('Add diagnosis'), findsNothing);
    expect(find.text('New prescription'), findsNothing);
    final field = tester.widget<EcTextField>(
      find.widgetWithText(EcTextField, 'Chief complaint'),
    );
    expect(field.enabled, isFalse);
    expect(find.text('Amend'), findsOneWidget);
  });

  testWidgets(
    'a draft prescription cannot be edited into an issued one without authorization',
    (tester) async {
      final repo = _repo();
      await _open(tester, repo, '/prescriptions/rx1');
      expect(find.text('Paracetamol'), findsOneWidget);
      expect(find.text('Add medicine'), findsOneWidget);
      await tester.tap(find.text('Authorize prescription'));
      await tester.pumpAndSettle();
      expect(find.text('Authorize prescription?'), findsOneWidget);
      expect(repo.calls.where((c) => c.$2.endsWith('/finalize')), isEmpty);
    },
  );

  testWidgets('an issued prescription is a read-only preview', (tester) async {
    await _open(tester, _repo(status: 'finalized'), '/prescriptions/rx1');
    expect(find.text('Prescription RX-000001'), findsOneWidget);
    expect(find.text('Add medicine'), findsNothing);
    expect(find.text('Authorize prescription'), findsNothing);
    expect(find.text('Amend'), findsOneWidget);
    expect(find.text('Issued by the treating doctor.'), findsOneWidget);
  });

  testWidgets('the queue lets the doctor call a waiting patient', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, repo, '/queue');
    expect(find.text('A-001'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('waiting-count'))).data,
      'Waiting: 1',
    );
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    expect(
      repo.calls.where(
        (c) => c.$1 == 'POST' && c.$2 == '/doctor/queue/e1/call',
      ),
      hasLength(1),
    );
  });
}
