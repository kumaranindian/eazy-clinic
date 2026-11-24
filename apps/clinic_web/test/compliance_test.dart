import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart' show ApiFailure;
import 'package:clinic_web/features/laboratory/lab_pages.dart'
    show reportSaverProvider;
import 'package:clinic_web/features/patients/patient_providers.dart'
    show PickedDocument, documentPickerProvider;
import 'package:common_models/common_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

Map<String, Object?> req(
  String key,
  String status, {
  bool expiry = false,
  String? evidenceId,
  String? expiresAt,
  String? note,
  bool changed = false,
}) => {
  'key': key,
  'title': 'Requirement $key',
  'description': 'Description of $key',
  'category': 'statutory',
  'appliesTo': 'facility',
  'evidence': {
    'required': true,
    'kinds': ['license', 'policy'],
    'expiryTracked': expiry,
  },
  'goLiveBlocking': key == 'facility-license',
  'status': status,
  'evidenceId': evidenceId,
  'expiresAt': expiresAt,
  'note': note,
  'requirementChanged': changed,
};

Map<String, Object?> profile(
  String key,
  String applicability, {
  bool reviewed = false,
  List<Map<String, Object?>> reqs = const [],
}) => {
  'key': key,
  'title': 'Register $key',
  'authority': {'code': 'DHA', 'name': 'Dubai Health Authority'},
  'jurisdiction': 'dubai',
  'domain': 'facility_licensing',
  'appliesWhenNote': 'Draft assumption: applicability is set per clinic.',
  'status': 'published',
  'version': 1,
  'legalReview': {'status': reviewed ? 'reviewed' : 'pending'},
  'applicability': {'status': applicability},
  'summary': <String, Object?>{},
  'requirements': reqs,
};

Map<String, Object?> dashboard({
  List<Map<String, Object?>>? profiles,
  String readiness = 'awaiting_legal_validation',
  Map<String, Object?>? credentials,
}) => {
  'tenantId': 'ten_1',
  'countryCode': 'AE',
  'disclaimer':
      'This checklist organises evidence. It is not legal advice and does not state that a clinic is compliant.',
  'readiness': readiness,
  'profiles': profiles ?? [profile('ae-dha-dubai', 'unknown')],
  'credentials':
      credentials ??
      {
        'total': 0,
        'valid': 0,
        'expiring': 0,
        'expired': 0,
        'noExpiryRecorded': 0,
        'unverified': 0,
        'attention': <Object?>[],
      },
  'counts': <String, Object?>{},
};

Map<String, Object?> cred(
  String id,
  String name,
  String validity, {
  String verification = 'unverified',
  String? evidenceId,
}) => {
  'credentialId': id,
  'subjectType': 'practitioner',
  'subjectName': name,
  'kind': 'practitioner_license',
  'authorityName': 'Dubai Health Authority',
  'number': 'LIC-1',
  'validTo': '2027-01-31T00:00:00.000Z',
  'validity': validity,
  'verification': {'status': verification},
  'evidenceId': evidenceId,
};

FakeRepo clinicRepo(
  Map<String, Object?> dash, {
  List<String> perms = const [
    'clinic.view',
    'compliance.view',
    'compliance.manage',
  ],
  List<Map<String, Object?>> credentials = const [],
}) {
  final r = FakeRepo();
  r.on('entitlements', (a, n) => entitlementsJson());
  r.on('getMap', (a, n) {
    final path = a[0]! as String;
    if (path.startsWith('/members/current/permissions')) {
      return {
        'tenantId': 'ten_1',
        'role': 'clinic_owner',
        'allBranches': true,
        'branches': <Object?>[],
        'accessLevel': 'full',
        'writesAllowed': true,
        'permissions': perms,
      };
    }
    return ownerAccess(path);
  });
  r.on('list', (a, n) => listOf([]));
  r.on('complianceDashboard', (a, n) => dash);
  r.on('complianceCredentials', (a, n) => credentials);
  return r;
}

Widget clinicApp(FakeRepo r, {List<Override> overrides = const []}) => buildApp(
  repo: r,
  session: sessionWith(
    memberships: [
      const MembershipSummaryDto(tenantId: 'ten_1', role: 'clinic_owner'),
    ],
  ),
  overrides: overrides,
);

Widget platformApp(
  FakeRepo r, {
  PlatformRole role = PlatformRole.superAdmin,
  List<Override> overrides = const [],
}) => buildApp(
  repo: r,
  session: sessionWith(platformRole: role),
  overrides: overrides,
);

Map<String, Object?> overview() => {
  'disclaimer': 'This checklist organises evidence. It is not legal advice.',
  'profiles': 8,
  'profilesAwaitingLegalValidation': 8,
  'evidenceAwaitingReview': 2,
  'confirmedApplicabilities': 3,
};

FakeRepo platformRepo({
  Map<String, Object?>? tenant,
  List<Map<String, Object?>> credentials = const [],
}) {
  final r = FakeRepo();
  r.on('dashboard', (a, n) => dashboardJson());
  r.on('complianceOverview', (a, n) => overview());
  r.on(
    'complianceProfiles',
    (a, n) => [
      {
        'key': 'ae-dha-dubai',
        'title': 'UAE (Dubai): DHA licensing',
        'countryCode': 'AE',
        'jurisdiction': 'dubai',
        'version': 2,
        'legalReview': {'status': 'pending'},
        'authority': {'name': 'Dubai Health Authority'},
        'requirements': [<String, Object?>{}, <String, Object?>{}],
      },
    ],
  );
  r.on(
    'complianceReviewQueue',
    (a, n) => [
      {
        'evidenceId': 'ce_1',
        'tenantId': 'ten_9',
        'profileKey': 'ae-dha-dubai',
        'requirementKey': 'facility-license',
        'uploadedAt': '2026-06-01T10:00:00Z',
      },
    ],
  );
  r.on('seedComplianceProfiles', (a, n) => null);
  if (tenant != null) r.on('platformComplianceTenant', (a, n) => tenant);
  r.on('platformComplianceCredentials', (a, n) => credentials);
  r.on('setComplianceApplicability', (a, n) => null);
  r.on('reviewComplianceEvidence', (a, n) => {'ok': true});
  r.on('setComplianceItemStatus', (a, n) => {'ok': true});
  r.on('verifyComplianceCredential', (a, n) => {'ok': true});
  r.on(
    'platformEvidenceBytes',
    (a, n) => Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
  );
  return r;
}

void main() {
  group('clinic compliance page', () {
    testWidgets(
      'says plainly that it is not legal advice and that nothing is confirmed yet',
      (t) async {
        await open(
          t,
          clinicApp(
            clinicRepo(dashboard(readiness: 'applicability_unconfirmed')),
          ),
          '/clinic/compliance',
        );
        expect(find.text('Compliance'), findsWidgets);
        expect(find.textContaining('not legal advice'), findsOneWidget);
        expect(find.byKey(const Key('readiness-text')), findsOneWidget);
        expect(find.textContaining('Waiting for a reviewer'), findsOneWidget);
        expect(find.text('Not validated by counsel'), findsOneWidget);
        expect(find.text('Applicability not confirmed'), findsOneWidget);
        expect(
          find.textContaining(
            'A reviewer must confirm that this register applies',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Upload evidence'), findsNothing);
        // the product never calls a clinic "compliant"
        expect(find.textContaining('Compliant'), findsNothing);
        expect(find.textContaining('Certified'), findsNothing);
      },
    );

    testWidgets(
      'requirements show their real status, expiry and reviewer notes',
      (t) async {
        final d = dashboard(
          profiles: [
            profile(
              'ae-dha-dubai',
              'applies',
              reqs: [
                req(
                  'facility-license',
                  'under_review',
                  expiry: true,
                  evidenceId: 'ce_1',
                ),
                req(
                  'practitioner-license',
                  'approved',
                  expiry: true,
                  evidenceId: 'ce_2',
                  expiresAt: '2027-03-31T00:00:00Z',
                ),
                req(
                  'privacy',
                  'expired',
                  evidenceId: 'ce_3',
                  expiresAt: '2026-01-31T00:00:00Z',
                ),
                req('breach', 'rejected', note: 'Scan is unreadable'),
                req('retention', 'not_assessed'),
                req('agreements', 'pending_evidence', changed: true),
              ],
            ),
          ],
        );
        await open(t, clinicApp(clinicRepo(d)), '/clinic/compliance');
        Finder chip(String key, String label) => find.descendant(
          of: find.byKey(Key('status-$key')),
          matching: find.text(label),
        );
        expect(chip('facility-license', 'Under review'), findsOneWidget);
        expect(
          chip('practitioner-license', 'Evidence approved'),
          findsOneWidget,
        );
        expect(chip('privacy', 'Expired'), findsOneWidget);
        expect(chip('breach', 'Rejected'), findsOneWidget);
        expect(chip('retention', 'Not assessed'), findsOneWidget);
        expect(chip('agreements', 'Evidence needed'), findsOneWidget);
        expect(find.textContaining('Approval valid until'), findsOneWidget);
        expect(find.textContaining('Expired on'), findsOneWidget);
        expect(
          find.textContaining('Reviewer note: Scan is unreadable'),
          findsOneWidget,
        );
        expect(
          find.textContaining('changed after it was approved'),
          findsOneWidget,
        );
        expect(find.text('Needed before go-live'), findsOneWidget);
      },
    );

    testWidgets(
      'a reviewed register is labelled as such; unreviewed ones are not',
      (t) async {
        final d = dashboard(
          readiness: 'all_required_evidence_approved',
          profiles: [
            profile(
              'ae-dha-dubai',
              'applies',
              reviewed: true,
              reqs: [req('facility-license', 'approved')],
            ),
            profile('ae-doh-abu-dhabi', 'unknown'),
          ],
        );
        await open(t, clinicApp(clinicRepo(d)), '/clinic/compliance');
        expect(find.text('Validated by counsel'), findsOneWidget);
        expect(find.text('Not validated by counsel'), findsOneWidget);
        expect(find.textContaining('not a certification'), findsOneWidget);
      },
    );

    testWidgets(
      'uploading evidence needs a file and, where tracked, an expiry date; it sends the file as base64',
      (t) async {
        final d = dashboard(
          profiles: [
            profile(
              'ae-dha-dubai',
              'applies',
              reqs: [req('facility-license', 'not_assessed', expiry: true)],
            ),
          ],
        );
        final repo = clinicRepo(d)
          ..on('uploadComplianceEvidence', (a, n) => {'evidenceId': 'ce_9'});
        final picked = PickedDocument(
          'licence.pdf',
          Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 1, 2]),
          'application/pdf',
        );
        await open(
          t,
          clinicApp(
            repo,
            overrides: [
              documentPickerProvider.overrideWithValue(() async => picked),
            ],
          ),
          '/clinic/compliance',
        );
        await t.tap(find.byKey(const Key('upload-facility-license')));
        await t.pumpAndSettle();
        await t.tap(find.text('Submit'));
        await t.pumpAndSettle();
        expect(find.text('Enter a title.'), findsOneWidget);
        expect(find.text('Enter the expiry date.'), findsOneWidget);
        expect(find.text('Choose a file.'), findsOneWidget);
        expect(repo.calls, isNot(contains('uploadComplianceEvidence')));

        await t.enterText(
          find.widgetWithText(TextFormField, 'Title'),
          'Facility licence 2026',
        );
        await t.enterText(
          find.widgetWithText(TextFormField, 'Valid until (YYYY-MM-DD)'),
          '31/12/2027',
        );
        await t.tap(find.text('Choose file'));
        await t.pumpAndSettle();
        await t.tap(find.text('Submit'));
        await t.pumpAndSettle();
        expect(find.text('Use the format 2027-03-31.'), findsOneWidget);

        await t.enterText(
          find.widgetWithText(TextFormField, 'Valid until (YYYY-MM-DD)'),
          '2027-12-31',
        );
        await t.tap(find.text('Submit'));
        await t.pumpAndSettle();
        final i = repo.calls.indexOf('uploadComplianceEvidence');
        expect(i, isNot(-1));
        final body = repo.callArgs[i][0]! as Map<String, Object?>;
        expect(body['profileKey'], 'ae-dha-dubai');
        expect(body['requirementKey'], 'facility-license');
        expect(body['validTo'], '2027-12-31');
        expect(body['dataBase64'], isNotEmpty);
        expect(body.keys, isNot(contains('status')));
        expect(body.keys, isNot(contains('tenantId')));
        expect(find.text('Evidence submitted for review.'), findsOneWidget);
      },
    );

    testWidgets('a backend refusal is shown', (t) async {
      final d = dashboard(
        profiles: [
          profile(
            'ae-dha-dubai',
            'applies',
            reqs: [req('privacy', 'not_assessed')],
          ),
        ],
      );
      final repo = clinicRepo(d)
        ..on(
          'uploadComplianceEvidence',
          (a, n) => throw const ApiFailure(
            code: ApiErrorCode.validationFailed,
            message: 'Only PDF, PNG and JPEG files are accepted.',
          ),
        );
      final picked = PickedDocument(
        'x.pdf',
        Uint8List.fromList([1, 2, 3]),
        'application/pdf',
      );
      await open(
        t,
        clinicApp(
          repo,
          overrides: [
            documentPickerProvider.overrideWithValue(() async => picked),
          ],
        ),
        '/clinic/compliance',
      );
      await t.tap(find.byKey(const Key('upload-privacy')));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Privacy policy',
      );
      await t.tap(find.text('Choose file'));
      await t.pumpAndSettle();
      await t.tap(find.text('Submit'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Only PDF, PNG and JPEG files are accepted.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'view-only users see everything but get no upload or edit buttons',
      (t) async {
        final d = dashboard(
          profiles: [
            profile(
              'ae-dha-dubai',
              'applies',
              reqs: [req('privacy', 'under_review', evidenceId: 'ce_1')],
            ),
          ],
          credentials: {
            'total': 1,
            'valid': 1,
            'expiring': 0,
            'expired': 0,
            'noExpiryRecorded': 0,
            'unverified': 1,
            'attention': <Object?>[],
          },
        );
        final repo = clinicRepo(
          d,
          perms: const ['clinic.view', 'compliance.view'],
          credentials: [cred('cr_1', 'Dr Asha Rao', 'valid')],
        );
        await open(t, clinicApp(repo), '/clinic/compliance');
        expect(find.text('Requirement privacy'), findsOneWidget);
        expect(find.byKey(const Key('upload-privacy')), findsNothing);
        expect(find.byKey(const Key('add-credential')), findsNothing);
        expect(find.text('Attach document'), findsNothing);
        expect(
          find.byKey(const Key('view-privacy')),
          findsOneWidget,
        ); // reading the file is allowed
      },
    );

    testWidgets('the file is downloaded through the authenticated API', (
      t,
    ) async {
      final d = dashboard(
        profiles: [
          profile(
            'ae-dha-dubai',
            'applies',
            reqs: [req('privacy', 'under_review', evidenceId: 'ce_1')],
          ),
        ],
      );
      final repo = clinicRepo(
        d,
      )..on('complianceEvidenceBytes', (a, n) => Uint8List.fromList([1, 2, 3]));
      final saved = <String>[];
      await open(
        t,
        clinicApp(
          repo,
          overrides: [
            reportSaverProvider.overrideWithValue(
              (name, bytes) async => saved.add(name),
            ),
          ],
        ),
        '/clinic/compliance',
      );
      await t.tap(find.byKey(const Key('view-privacy')));
      await t.pumpAndSettle();
      expect(repo.callArgs[repo.calls.indexOf('complianceEvidenceBytes')], [
        'ce_1',
      ]);
      expect(saved, [
        'evidence-ce_1',
      ]); // a generic name, never the document title
    });

    testWidgets(
      'credentials show validity and verification, and can be added and archived',
      (t) async {
        final d = dashboard(
          credentials: {
            'total': 3,
            'valid': 1,
            'expiring': 1,
            'expired': 1,
            'noExpiryRecorded': 0,
            'unverified': 2,
            'attention': <Object?>[],
          },
        );
        final repo =
            clinicRepo(
                d,
                credentials: [
                  cred(
                    'cr_1',
                    'Dr Valid',
                    'valid',
                    verification: 'verified',
                    evidenceId: 'ce_1',
                  ),
                  cred('cr_2', 'Dr Soon', 'expiring'),
                  cred('cr_3', 'Dr Late', 'expired'),
                ],
              )
              ..on(
                'createComplianceCredential',
                (a, n) => {'credentialId': 'cr_4'},
              )
              ..on(
                'archiveComplianceCredential',
                (a, n) => {'credentialId': 'cr_2'},
              );
        await open(t, clinicApp(repo), '/clinic/compliance');
        expect(find.text('Valid: 1'), findsOneWidget);
        expect(find.text('Expiring soon: 1'), findsOneWidget);
        expect(find.text('Expired: 1'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('credential-cr_1')),
            matching: find.text('Verified by reviewer'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('credential-cr_2')),
            matching: find.text('Expiring soon'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('credential-cr_3')),
            matching: find.text('Expired'),
          ),
          findsOneWidget,
        );

        await t.tap(find.byKey(const Key('add-credential')));
        await t.pumpAndSettle();
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(find.text('Enter a name.'), findsOneWidget);
        await t.enterText(
          find.widgetWithText(TextFormField, 'Facility name'),
          'Green Valley Clinic',
        );
        await t.enterText(
          find.widgetWithText(TextFormField, 'Authority code (e.g. DHA, NMC)'),
          'DHA',
        );
        await t.enterText(
          find.widgetWithText(TextFormField, 'Issuing authority'),
          'Dubai Health Authority',
        );
        await t.enterText(
          find.widgetWithText(TextFormField, 'Licence or registration number'),
          'FAC-001',
        );
        await t.enterText(
          find.widgetWithText(TextFormField, 'Valid until (YYYY-MM-DD)'),
          '2027-01-31',
        );
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        final body =
            repo.callArgs[repo.calls.indexOf('createComplianceCredential')][0]!
                as Map<String, Object?>;
        expect(body['subjectType'], 'facility');
        expect(body['number'], 'FAC-001');
        expect(body.keys, isNot(contains('verification')));

        await t.tap(find.text('Archive').first);
        await t.pumpAndSettle();
        await t.tap(find.text('Archive').last);
        await t.pumpAndSettle();
        expect(repo.calls, contains('archiveComplianceCredential'));
      },
    );

    testWidgets('a clinic without a country is told so', (t) async {
      final d = dashboard(readiness: 'country_not_assigned', profiles: []);
      await open(t, clinicApp(clinicRepo(d)), '/clinic/compliance');
      expect(find.textContaining('no legal country yet'), findsOneWidget);
      expect(find.text('No registers for your country yet'), findsOneWidget);
    });

    testWidgets('load failures can be retried', (t) async {
      final repo = clinicRepo(dashboard());
      var first = true;
      repo.on('complianceDashboard', (a, n) {
        if (first) {
          first = false;
          throw const ApiFailure(code: ApiErrorCode.internalError);
        }
        return dashboard();
      });
      await open(t, clinicApp(repo), '/clinic/compliance');
      expect(find.text('Could not load this page'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Compliance'), findsWidgets);
    });

    testWidgets('the navigation shows Compliance only with the permission', (
      t,
    ) async {
      await open(t, clinicApp(clinicRepo(dashboard())), '/clinic');
      expect(find.text('Compliance'), findsWidgets);
      await open(
        t,
        clinicApp(clinicRepo(dashboard(), perms: const ['clinic.view'])),
        '/clinic',
      );
      expect(find.text('Compliance'), findsNothing);
    });
  });

  group('platform compliance', () {
    testWidgets('overview, review queue and registers', (t) async {
      await open(t, platformApp(platformRepo()), '/platform/compliance');
      expect(find.text('Compliance registers'), findsOneWidget);
      expect(find.textContaining('not legal advice'), findsOneWidget);
      expect(find.text('Registers: 8'), findsOneWidget);
      expect(find.text('Awaiting legal validation: 8'), findsOneWidget);
      expect(find.text('Evidence awaiting review: 2'), findsOneWidget);
      expect(find.byKey(const Key('queue-ce_1')), findsOneWidget);
      expect(find.byKey(const Key('register-ae-dha-dubai')), findsOneWidget);
      expect(find.text('Not validated by counsel'), findsOneWidget);
      expect(find.text('Seed baseline registers'), findsOneWidget);
    });

    testWidgets(
      'support admins see the registers but no review queue and no seeding',
      (t) async {
        await open(
          t,
          platformApp(platformRepo(), role: PlatformRole.platformSupportAdmin),
          '/platform/compliance',
        );
        expect(find.byKey(const Key('register-ae-dha-dubai')), findsOneWidget);
        expect(find.byKey(const Key('queue-ce_1')), findsNothing);
        expect(find.text('Seed baseline registers'), findsNothing);
      },
    );

    testWidgets('seeding runs the baseline action', (t) async {
      final repo = platformRepo();
      await open(t, platformApp(repo), '/platform/compliance');
      await t.tap(find.text('Seed baseline registers'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('seedComplianceProfiles'));
    });

    testWidgets('the queue opens the clinic\'s review page', (t) async {
      final tenant = dashboard(profiles: [profile('ae-dha-dubai', 'unknown')]);
      await open(
        t,
        platformApp(platformRepo(tenant: tenant)),
        '/platform/compliance',
      );
      await t.tap(find.text('Review'));
      await t.pumpAndSettle();
      expect(find.text('Clinic compliance'), findsOneWidget);
    });

    testWidgets('confirming applicability needs a reason', (t) async {
      final repo = platformRepo(
        tenant: dashboard(profiles: [profile('ae-dha-dubai', 'unknown')]),
      );
      await open(t, platformApp(repo), '/platform/compliance/tenants/ten_1');
      expect(find.text('Not confirmed'), findsOneWidget);
      await t.tap(find.byKey(const Key('apply-ae-dha-dubai')));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(repo.calls, isNot(contains('setComplianceApplicability')));
      await t.enterText(
        find.byType(TextFormField).last,
        'Licensed by DHA, checked on the register',
      );
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      final i = repo.calls.indexOf('setComplianceApplicability');
      expect(repo.callArgs[i], [
        'ten_1',
        'ae-dha-dubai',
        'applies',
        'Licensed by DHA, checked on the register',
      ]);
    });

    testWidgets(
      'approving evidence asks for confirmation; rejecting asks for a reason',
      (t) async {
        final tenant = dashboard(
          profiles: [
            profile(
              'ae-dha-dubai',
              'applies',
              reqs: [
                req(
                  'facility-license',
                  'under_review',
                  evidenceId: 'ce_1',
                  expiry: true,
                ),
              ],
            ),
          ],
        );
        final repo = platformRepo(tenant: tenant);
        await open(t, platformApp(repo), '/platform/compliance/tenants/ten_1');
        await t.tap(find.byKey(const Key('reject-facility-license')));
        await t.pumpAndSettle();
        await t.tap(find.text('Reject').last);
        await t.pumpAndSettle();
        expect(repo.calls, isNot(contains('reviewComplianceEvidence')));
        await t.enterText(
          find.byType(TextFormField).last,
          'The scan is unreadable',
        );
        await t.tap(find.text('Reject').last);
        await t.pumpAndSettle();
        var i = repo.calls.indexOf('reviewComplianceEvidence');
        expect(repo.callArgs[i].sublist(0, 2), ['ten_1', 'ce_1']);
        expect((repo.callArgs[i][2]! as Map)['decision'], 'reject');
        expect((repo.callArgs[i][2]! as Map)['note'], 'The scan is unreadable');

        await t.tap(find.byKey(const Key('accept-facility-license')));
        await t.pumpAndSettle();
        await t.tap(find.text('Approve').last);
        await t.pumpAndSettle();
        i = repo.calls.lastIndexOf('reviewComplianceEvidence');
        expect((repo.callArgs[i][2]! as Map)['decision'], 'accept');
      },
    );

    testWidgets('approve and reject appear only for evidence under review', (
      t,
    ) async {
      final tenant = dashboard(
        profiles: [
          profile(
            'ae-dha-dubai',
            'applies',
            reqs: [
              req('a', 'approved', evidenceId: 'ce_1'),
              req('b', 'not_assessed'),
              req('c', 'not_applicable'),
            ],
          ),
        ],
      );
      await open(
        t,
        platformApp(platformRepo(tenant: tenant)),
        '/platform/compliance/tenants/ten_1',
      );
      expect(find.byKey(const Key('accept-a')), findsNothing);
      expect(find.byKey(const Key('accept-b')), findsNothing);
      expect(find.text('Ask for evidence again'), findsOneWidget);
    });

    testWidgets(
      'support admins on a clinic see statuses but no review controls',
      (t) async {
        final tenant = dashboard(
          profiles: [
            profile(
              'ae-dha-dubai',
              'applies',
              reqs: [
                req('facility-license', 'under_review', evidenceId: 'ce_1'),
              ],
            ),
          ],
        );
        await open(
          t,
          platformApp(
            platformRepo(tenant: tenant),
            role: PlatformRole.platformSupportAdmin,
          ),
          '/platform/compliance/tenants/ten_1',
        );
        expect(find.text('Requirement facility-license'), findsOneWidget);
        expect(find.byKey(const Key('accept-facility-license')), findsNothing);
        expect(
          find.byKey(const Key('download-facility-license')),
          findsNothing,
        );
        expect(find.text('Confirm it applies'), findsNothing);
      },
    );

    testWidgets('reviewers can download the file and verify credentials', (
      t,
    ) async {
      final tenant = dashboard(
        profiles: [
          profile(
            'ae-dha-dubai',
            'applies',
            reqs: [req('facility-license', 'under_review', evidenceId: 'ce_1')],
          ),
        ],
      );
      final repo = platformRepo(
        tenant: tenant,
        credentials: [cred('cr_1', 'Dr Asha Rao', 'valid', evidenceId: 'ce_5')],
      );
      final saved = <String>[];
      await open(
        t,
        platformApp(
          repo,
          overrides: [
            reportSaverProvider.overrideWithValue(
              (name, bytes) async => saved.add(name),
            ),
          ],
        ),
        '/platform/compliance/tenants/ten_1',
      );
      await t.tap(find.byKey(const Key('download-facility-license')));
      await t.pumpAndSettle();
      expect(saved, ['evidence-ce_1']);
      await t.tap(find.text('Verify'));
      await t.pumpAndSettle();
      expect(
        repo.callArgs[repo.calls.indexOf('verifyComplianceCredential')].sublist(
          0,
          2,
        ),
        ['ten_1', 'cr_1'],
      );
    });
  });
}
