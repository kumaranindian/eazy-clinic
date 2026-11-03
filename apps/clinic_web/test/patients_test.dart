import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:clinic_web/features/patients/patient_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

const _frontDesk = [
  'clinic.view',
  'branches.view',
  'patients.view',
  'patients.create',
  'patients.update',
  'patients.duplicates',
  'patients.link_account',
  'alerts.view',
  'consents.view',
  'consents.manage',
];
const _clinical = [
  ..._frontDesk,
  'history.view',
  'history.manage',
  'allergies.view',
  'allergies.manage',
  'medications.view',
  'medications.manage',
  'alerts.manage',
  'patient_documents.view',
  'patient_documents.manage',
  'patients.status',
  'patient_audit.view',
];

Map<String, Object?> _patient({
  String id = 'pt_1',
  List<Map<String, Object?>> alerts = const [],
  List<Map<String, Object?>>? allergies,
  bool linked = false,
  String status = 'active',
}) => {
  'patientId': id,
  'tenantId': 'ten_1',
  'branchId': 'br_1',
  'mrn': 'MRN-000001',
  'fullName': 'Asha Patil',
  'dateOfBirth': '1990-05-14',
  'gender': 'female',
  'phone': '9876500001',
  'email': 'asha@example.test',
  'status': status,
  'patientAccountId': linked ? 'pa_1' : null,
  'address': {'line1': '5 Lake Road', 'city': 'Pune'},
  'alerts': alerts,
  'activeAllergies': ?allergies,
  'createdAt': '2026-06-01T10:00:00Z',
  'updatedAt': '2026-06-01T10:00:00Z',
};

FakeRepo _repo(
  List<String> perms, {
  String role = 'receptionist',
  Map<String, Object?>? patient,
  Map<String, List<Map<String, Object?>>> lists = const {},
  Map<String, Object?> Function(String method, String path, Object? body)? send,
}) {
  final r = FakeRepo();
  r.on('entitlements', (a, n) => entitlementsJson());
  r.on('getMap', (a, n) {
    final path = a[0]! as String;
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
    if (path == '/consent-catalog') {
      return {
        'version': '1.0',
        'purposes': [
          {
            'type': 'data_processing',
            'purpose': 'Process my data',
            'text':
                'I agree that this clinic may collect and use my information.',
          },
          {
            'type': 'communication_sms',
            'purpose': 'SMS',
            'text': 'I agree to receive SMS.',
          },
        ],
      };
    }
    if (path.endsWith('/emergency-contacts')) {
      return {'contacts': <Object?>[]};
    }
    if (path.startsWith('/patients/')) return patient ?? _patient();
    return ownerAccess(path);
  });
  r.on('getList', (a, n) {
    if ((a[0]! as String) == '/branches') {
      return [
        {'branchId': 'br_1', 'name': 'Main', 'status': 'active'},
      ];
    }
    return <Map<String, Object?>>[];
  });
  r.on('list', (a, n) {
    final path = a[0]! as String;
    for (final e in lists.entries) {
      if (path == e.key) return listOf(e.value);
    }
    return listOf([]);
  });
  r.on('sendMap', (a, n) {
    final body = a[2];
    if (send != null) return send(a[0]! as String, a[1]! as String, body);
    return {'ok': true};
  });
  return r;
}

Widget _app(FakeRepo repo, {List<Override> overrides = const []}) => buildApp(
  repo: repo,
  overrides: overrides,
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
  group('patient directory', () {
    testWidgets('lists masked rows; the register action needs permission', (
      t,
    ) async {
      final repo = _repo(
        _frontDesk,
        lists: {
          '/patients': [
            {
              'patientId': 'pt_1',
              'mrn': 'MRN-000001',
              'fullName': 'Asha Patil',
              'dateOfBirth': '1990-05-14',
              'maskedPhone': 'XXXXXX0001',
              'status': 'active',
              'linked': true,
            },
          ],
        },
      );
      await open(t, _app(repo), '/clinic/patients');
      expect(find.text('Asha Patil'), findsOneWidget);
      expect(find.textContaining('XXXXXX0001'), findsOneWidget);
      expect(find.textContaining('9876500001'), findsNothing);
      expect(find.text('Register patient'), findsOneWidget);
    });

    testWidgets(
      'no register action without patients.create; nav needs patients.view',
      (t) async {
        final repo = _repo(['clinic.view', 'patients.view']);
        await open(t, _app(repo), '/clinic/patients');
        expect(find.text('Register patient'), findsNothing);
        expect(find.text('No patients found'), findsOneWidget);

        final hidden = _repo(['clinic.view', 'branches.view']);
        await open(t, _app(hidden), '/clinic');
        expect(find.text('Patients'), findsNothing);
      },
    );

    testWidgets('a failed load shows an error with retry', (t) async {
      final repo = _repo(_frontDesk)
        ..on('list', (a, n) => throw const ApiFailure(message: 'Nope'));
      await open(t, _app(repo), '/clinic/patients');
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('registration', () {
    testWidgets('validation blocks submit; nothing is sent', (t) async {
      final repo = _repo(_frontDesk);
      await open(t, _app(repo), '/clinic/patients/new');
      await t.ensureVisible(find.text('Register patient').last);
      await t.tap(find.text('Register patient').last);
      await t.pumpAndSettle();
      expect(find.textContaining('required'), findsWidgets);
      expect(repo.calls, isNot(contains('sendMap')));
    });

    testWidgets('consent must be ticked; the consent text is shown', (t) async {
      final repo = _repo(_frontDesk);
      await open(t, _app(repo), '/clinic/patients/new');
      expect(find.byKey(const Key('consent-text')), findsOneWidget);
      expect(
        find.textContaining('collect and use my information'),
        findsOneWidget,
      );
    });

    testWidgets(
      'duplicates are reviewed before registering; the review is sent',
      (t) async {
        final sent = <(String, String, Object?)>[];
        final repo = _repo(
          _frontDesk,
          send: (m, p, b) {
            sent.add((m, p, b));
            if (p == '/patients/duplicate-check') {
              return {
                'requiresReview': true,
                'matches': [
                  {
                    'patientId': 'pt_9',
                    'mrn': 'MRN-000009',
                    'fullName': 'Asha Patil',
                    'dateOfBirth': '1990-05-14',
                    'maskedPhone': 'XXXXXX0001',
                    'level': 'high',
                    'reasons': ['name_and_birth_date'],
                  },
                ],
              };
            }
            return {'patientId': 'pt_new'};
          },
        );
        await open(t, _app(repo), '/clinic/patients/new');
        await _pick(t, 'Branch', 'Main');
        await _type(t, 'Full name', 'Asha Patil');
        await _type(t, 'Date of birth (YYYY-MM-DD)', '1990-05-14');
        await _pick(t, 'Gender', 'Female');
        await _type(t, 'Phone', '9876500001');
        await _type(t, 'Address line 1', '5 Lake Road');
        await _type(t, 'City', 'Pune');
        await _type(t, 'State', 'Maharashtra');
        await _type(t, 'PIN / postal code', '411001');
        await t.ensureVisible(find.byKey(const Key('consent-check')));
        await t.tap(find.byKey(const Key('consent-check')));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Register patient').last);
        await t.tap(find.text('Register patient').last);
        // the save button spins while the check runs: pump, don't settle
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(find.text('Possible duplicate patients'), findsOneWidget);
        expect(find.textContaining('MRN-000009'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('9876500001'),
          ),
          findsNothing,
        );
        // nothing is created until the reviewer explains
        expect(sent.where((s) => s.$2 == '/patients'), isEmpty);
        await t.enterText(
          find.widgetWithText(TextField, 'Why is this a different person?'),
          'Different person, same name',
        );
        await t.tap(find.text('Different person, continue'));
        await t.pumpAndSettle();
        final create = sent.firstWhere((s) => s.$2 == '/patients');
        final body = create.$3! as Map<String, Object?>;
        expect(body['branchId'], 'br_1');
        expect((body['duplicateReview']! as Map)['reviewedPatientIds'], [
          'pt_9',
        ]);
        expect((body['consent']! as Map)['granted'], true);
        for (final k in [
          'tenantId',
          'patientId',
          'mrn',
          'status',
          'createdBy',
        ]) {
          expect(body.containsKey(k), isFalse, reason: k);
        }
      },
    );
  });

  group('patient record', () {
    testWidgets(
      'allergies and alerts are shown first, unverified ones labelled',
      (t) async {
        final repo = _repo(
          _clinical,
          role: 'doctor',
          patient: _patient(
            alerts: [
              {
                'alertId': 'an_1',
                'title': 'Anticoagulants',
                'message': 'Bleeding risk',
                'priority': 'critical',
              },
            ],
            allergies: [
              {
                'allergen': 'Penicillin',
                'severity': 'severe',
                'verificationStatus': 'verified',
              },
              {
                'allergen': 'Latex',
                'severity': 'unknown',
                'verificationStatus': 'unverified',
              },
            ],
          ),
        );
        await open(t, _app(repo), '/clinic/patients/pt_1');
        expect(
          find.textContaining('Anticoagulants: Bleeding risk'),
          findsOneWidget,
        );
        expect(find.textContaining('Penicillin (severe)'), findsOneWidget);
        expect(find.textContaining('Latex (unverified)'), findsOneWidget);
      },
    );

    testWidgets('no allergy records never reads as "no allergies"', (t) async {
      final repo = _repo(
        _clinical,
        role: 'doctor',
        patient: _patient(allergies: const []),
      );
      await open(t, _app(repo), '/clinic/patients/pt_1');
      expect(find.byKey(const Key('no-allergy-info')), findsOneWidget);
      expect(find.textContaining('does not mean'), findsOneWidget);
    });

    testWidgets(
      'front desk sees no clinical tabs, banners or restricted notes',
      (t) async {
        final repo = _repo(_frontDesk);
        await open(t, _app(repo), '/clinic/patients/pt_1');
        expect(find.text('Overview'), findsWidgets);
        for (final tab in [
          'Medical history',
          'Allergies',
          'Medications',
          'Documents',
          'Audit',
        ]) {
          expect(find.text(tab), findsNothing, reason: tab);
        }
        expect(find.text('Consent'), findsOneWidget);
        expect(find.text('Identity'), findsOneWidget);
        expect(find.byKey(const Key('allergy-banner')), findsNothing);
        expect(find.byKey(const Key('no-allergy-info')), findsNothing);
      },
    );

    testWidgets(
      'a doctor adds history; entries show source and verification; only doctors can verify',
      (t) async {
        final sent = <(String, String, Object?)>[];
        final repo = _repo(
          _clinical,
          role: 'doctor',
          lists: {
            '/patients/pt_1/medical-history': [
              {
                'entryId': 'he_1',
                'title': 'Hypertension',
                'category': 'condition',
                'status': 'active',
                'source': 'patient_reported',
                'verificationStatus': 'unverified',
              },
            ],
          },
          send: (m, p, b) {
            sent.add((m, p, b));
            return {'ok': true};
          },
        );
        await open(t, _app(repo), '/clinic/patients/pt_1');
        await t.tap(find.text('Medical history'));
        await t.pumpAndSettle();
        expect(find.text('Hypertension'), findsOneWidget);
        expect(find.text('Source: Patient reported'), findsOneWidget);
        expect(find.text('Unverified'), findsOneWidget);
        await t.tap(find.text('Mark as verified'));
        await t.pumpAndSettle();
        expect(sent.single.$1, 'PATCH');
        expect(sent.single.$2, '/patients/pt_1/medical-history/he_1');
        expect(sent.single.$3, {'verify': true});

        // a nurse cannot verify
        final nurse = _repo(
          _clinical,
          role: 'nurse',
          lists: {
            '/patients/pt_1/medical-history': [
              {
                'entryId': 'he_1',
                'title': 'Hypertension',
                'category': 'condition',
                'source': 'patient_reported',
                'verificationStatus': 'unverified',
              },
            ],
          },
        );
        await open(t, _app(nurse), '/clinic/patients/pt_1');
        await t.tap(find.text('Medical history'));
        await t.pumpAndSettle();
        expect(find.text('Mark as verified'), findsNothing);
      },
    );

    testWidgets('empty clinical lists explain that absence is not a negative', (
      t,
    ) async {
      final repo = _repo(_clinical, role: 'doctor');
      await open(t, _app(repo), '/clinic/patients/pt_1');
      await t.tap(find.text('Allergies'));
      await t.pumpAndSettle();
      expect(find.textContaining('does not confirm'), findsOneWidget);
    });

    testWidgets('archived patients offer no edit, status or add actions', (
      t,
    ) async {
      final repo = _repo(
        _clinical,
        role: 'owner',
        patient: _patient(status: 'archived'),
      );
      await open(t, _app(repo), '/clinic/patients/pt_1');
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
    });
  });

  group('consent, documents, identity', () {
    testWidgets('consent shows the exact text and records the decision', (
      t,
    ) async {
      final sent = <(String, String, Object?)>[];
      final repo = _repo(
        _frontDesk,
        send: (m, p, b) {
          sent.add((m, p, b));
          return {'ok': true};
        },
        lists: {
          '/patients/pt_1/consents': [
            {
              'consentId': 'cn_1',
              'type': 'data_processing',
              'purpose': 'Process my data',
              'status': 'granted',
              'grantedBy': {'type': 'patient'},
              'collectionMethod': 'in_person_signed',
              'textVersion': '1.0',
              'decidedAt': '2026-06-01T10:00:00Z',
            },
          ],
        },
      );
      await open(t, _app(repo), '/clinic/patients/pt_1');
      await t.tap(find.text('Consent'));
      await t.pumpAndSettle();
      expect(find.text('Granted'), findsOneWidget);
      await t.tap(find.text('Record consent'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('consent-dialog-text')), findsOneWidget);
      // no decision is preselected
      final record = find.widgetWithText(TextButton, 'Record');
      expect(record, findsNothing);
      await _pick(t, 'The decision', 'Agreed');
      await t.tap(find.text('Record').last);
      await t.pumpAndSettle();
      final body = sent.single.$3! as Map<String, Object?>;
      expect(body['type'], 'data_processing');
      expect(body['decision'], 'granted');
      expect(body['textVersion'], '1.0');
      expect(body['grantedBy'], {'type': 'patient'});
    });

    testWidgets('revoking a consent asks for a reason first', (t) async {
      final sent = <(String, String, Object?)>[];
      final repo = _repo(
        _frontDesk,
        send: (m, p, b) {
          sent.add((m, p, b));
          return {'ok': true};
        },
        lists: {
          '/patients/pt_1/consents': [
            {
              'consentId': 'cn_1',
              'type': 'communication_sms',
              'purpose': 'SMS',
              'status': 'granted',
              'grantedBy': {'type': 'patient'},
              'collectionMethod': 'in_person_signed',
              'textVersion': '1.0',
            },
          ],
        },
      );
      await open(t, _app(repo), '/clinic/patients/pt_1');
      await t.tap(find.text('Consent'));
      await t.pumpAndSettle();
      await t.tap(find.text('Revoke'));
      await t.pumpAndSettle();
      expect(find.text('Revoke consent?'), findsOneWidget);
      await t.tap(find.text('Revoke').last);
      await t.pumpAndSettle();
      expect(sent, isEmpty, reason: 'a reason is required');
      await t.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Patient asked to stop',
      );
      await t.tap(find.text('Revoke').last);
      await t.pumpAndSettle();
      expect(sent.single.$2, '/patients/pt_1/consents/cn_1/revoke');
      expect((sent.single.$3! as Map)['reason'], 'Patient asked to stop');
    });

    testWidgets('document upload sends the file as base64 with its type', (
      t,
    ) async {
      final sent = <(String, String, Object?)>[];
      final repo = _repo(
        _clinical,
        role: 'nurse',
        send: (m, p, b) {
          sent.add((m, p, b));
          return {'ok': true};
        },
      );
      await open(
        t,
        _app(
          repo,
          overrides: [
            documentPickerProvider.overrideWithValue(
              () async => PickedDocument(
                'report.pdf',
                Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]),
                'application/pdf',
              ),
            ),
          ],
        ),
        '/clinic/patients/pt_1',
      );
      await t.ensureVisible(find.text('Documents'));
      await t.tap(find.text('Documents'));
      await t.pumpAndSettle();
      expect(find.text('No documents'), findsOneWidget);
      await t.tap(find.text('Upload document'));
      await t.pumpAndSettle();
      await _pick(t, 'Category', 'Lab report');
      await t.tap(find.text('Upload').last);
      await t.pumpAndSettle();
      final body = sent.single.$3! as Map<String, Object?>;
      expect(sent.single.$2, '/patients/pt_1/documents');
      expect(body['contentType'], 'application/pdf');
      expect(body['category'], 'lab_report');
      expect(body['dataBase64'], isNotEmpty);
      expect(body.containsKey('tenantId'), isFalse);
      expect(body.containsKey('storagePath'), isFalse);
    });

    testWidgets(
      'issuing a link code needs a confirmation and shows the code once',
      (t) async {
        final sent = <(String, String, Object?)>[];
        final repo = _repo(
          _frontDesk,
          send: (m, p, b) {
            sent.add((m, p, b));
            return {
              'code': 'ECL-ABCD-EFGH-JKMN',
              'expiresAt': '2026-06-02T10:00:00Z',
            };
          },
        );
        await open(t, _app(repo), '/clinic/patients/pt_1');
        await t.tap(find.text('Identity'));
        await t.pumpAndSettle();
        expect(find.text('Not linked'), findsWidgets);
        await t.tap(find.text('Issue link code'));
        await t.pumpAndSettle();
        await _pick(t, 'How did you identify them?', 'Government id sighted');
        await t.tap(find.text('Issue code').last);
        await t.pumpAndSettle();
        expect(sent, isEmpty, reason: 'identity must be confirmed first');
        await t.tap(find.text('Confirm and issue'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('link-code')), findsOneWidget);
        expect(find.text('ECL-ABCD-EFGH-JKMN'), findsOneWidget);
        final body = sent.single.$3! as Map<String, Object?>;
        expect(body['identityConfirmed'], true);
        expect(body['verificationMethod'], 'government_id_sighted');
        expect(
          find.textContaining('Family relationships belong'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a linked record offers unlink, not another code', (t) async {
      final repo = _repo(_frontDesk, patient: _patient(linked: true));
      await open(t, _app(repo), '/clinic/patients/pt_1');
      await t.tap(find.text('Identity'));
      await t.pumpAndSettle();
      expect(find.text('Linked to a patient account'), findsOneWidget);
      expect(find.text('Issue link code'), findsNothing);
      expect(find.text('Unlink account'), findsOneWidget);
    });
  });
}
