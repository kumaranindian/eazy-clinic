import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show adminRepo, open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

Map<String, Object?> adminCountry(
  String code, {
  bool onboarding = true,
  int tenants = 0,
  List<String> warnings = const [],
  String status = 'supported',
}) => {
  ...countryDto(code),
  'status': status,
  'onboardingEnabled': onboarding,
  'suggestedTimezones': [code == 'AE' ? 'Asia/Dubai' : 'Asia/Kolkata'],
  'activeTenants': tenants,
  'completenessWarnings': warnings,
  'isOnboardable': onboarding && status == 'supported',
};

FakeRepo countriesRepo({List<Map<String, Object?>>? countries}) {
  final r = adminRepo();
  r.on(
    'countries',
    (a, n) =>
        countries ??
        [
          adminCountry('IN', tenants: 2),
          adminCountry('AE', onboarding: false, warnings: ['never_reviewed']),
        ],
  );
  r.on('updateCountry', (a, n) => adminCountry('IN'));
  r.on('seedCountries', (a, n) => null);
  return r;
}

void main() {
  group('clinic registration with a country', () {
    Future<void> openApply(WidgetTester t, FakeRepo repo) =>
        open(t, buildApp(repo: repo, session: sessionWith()), '/apply');

    Future<void> fill(WidgetTester t, String label, String v) async =>
        t.enterText(find.widgetWithText(TextFormField, label), v);

    Future<void> fillCommon(WidgetTester t, {required String phone}) async {
      await fill(t, 'Clinic name', 'Marina Clinic');
      await fill(t, 'Clinic email', 'info@marina.test');
      await fill(t, 'Clinic phone', phone);
      await fill(t, 'Address line 1', 'Marina Walk');
      await fill(t, 'City', 'Dubai');
      await fill(t, 'Full name', 'Dr Layla');
      await fill(t, 'Email', 'layla@marina.test');
      await fill(t, 'Mobile number', phone);
      await fill(t, 'Number of doctors', '2');
      await fill(t, 'Number of staff', '4');
      await fill(t, 'Patients per month', '300');
    }

    testWidgets('the selector lists only the countries the backend offers', (
      t,
    ) async {
      final repo = FakeRepo()
        ..on('onboardableCountries', (a, n) => [countryDto('AE')]);
      await openApply(t, repo);
      expect(find.text('Country'), findsWidgets);
      expect(find.text('United Arab Emirates'), findsOneWidget);
      expect(find.text('India'), findsNothing);
      // labels follow the country master
      expect(find.widgetWithText(TextFormField, 'Emirate'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'PO Box'), findsOneWidget);
    });

    testWidgets('choosing the UAE changes labels, rules and the payload', (
      t,
    ) async {
      final repo = FakeRepo()
        ..on('submitApplication', (a, n) => {'applicationId': 'app_1'})
        ..on(
          'myApplication',
          (a, n) => {...applicationJson(), 'history': <Object?>[]},
        );
      await openApply(t, repo);
      expect(find.widgetWithText(TextFormField, 'PIN code'), findsOneWidget);

      await t.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Country'),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('United Arab Emirates').last);
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Emirate'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'PO Box'), findsOneWidget);

      await fillCommon(t, phone: '+971 50 123 4567');
      await fill(t, 'Emirate', 'Dubai');
      await t.ensureVisible(find.text('Submit application'));
      await t.tap(find.text('Submit application'));
      await t.pumpAndSettle();

      final body =
          repo.callArgs[repo.calls.indexOf('submitApplication')][0]!
              as Map<String, Object?>;
      final address = body['address']! as Map<String, Object?>;
      expect(address['countryCode'], 'AE');
      expect(address.containsKey('country'), isFalse);
      expect(address.containsKey('postalCode'), isFalse, reason: 'optional');
    });

    testWidgets('an Indian PIN is still required and checked for India', (
      t,
    ) async {
      final repo = FakeRepo();
      await openApply(t, repo);
      await fill(t, 'PIN code', '12');
      await t.ensureVisible(find.text('Submit application'));
      await t.tap(find.text('Submit application'));
      await t.pumpAndSettle();
      expect(find.text('Enter a valid PIN code.'), findsOneWidget);
      expect(repo.calls, isNot(contains('submitApplication')));
    });

    testWidgets(
      'if countries cannot load, the form offers a retry and sends nothing',
      (t) async {
        final repo = FakeRepo()
          ..on(
            'onboardableCountries',
            (a, n) => throw const ApiFailure(code: ApiErrorCode.internalError),
          );
        await openApply(t, repo);
        expect(find.text('Could not load countries.'), findsOneWidget);
        expect(find.byTooltip('Retry'), findsOneWidget);
        await t.ensureVisible(find.text('Submit application'));
        await t.tap(find.text('Submit application'));
        await t.pumpAndSettle();
        expect(repo.calls, isNot(contains('submitApplication')));
      },
    );
  });

  group('platform country administration', () {
    testWidgets('lists countries with status, version, clinics and warnings', (
      t,
    ) async {
      await open(t, buildApp(repo: countriesRepo()), '/platform/countries');
      expect(find.text('India (IN)'), findsOneWidget);
      expect(find.text('United Arab Emirates (AE)'), findsOneWidget);
      expect(find.textContaining('2 active clinics'), findsOneWidget);
      expect(find.textContaining('version 1'), findsWidgets);
      expect(find.text('Onboarding open'), findsOneWidget);
      expect(find.text('Onboarding paused'), findsOneWidget);
      expect(find.textContaining('Not reviewed yet'), findsOneWidget);
    });

    testWidgets('a country with active clinics cannot be disabled', (t) async {
      await open(t, buildApp(repo: countriesRepo()), '/platform/countries');
      // India has 2 active clinics: its Disable button is present but inert
      final disable = find.widgetWithText(OutlinedButton, 'Disable');
      expect(disable, findsNWidgets(2)); // India and the UAE
      expect(t.widget<OutlinedButton>(disable.first).onPressed, isNull);
      expect(t.widget<OutlinedButton>(disable.last).onPressed, isNotNull);
    });

    testWidgets('pausing onboarding needs a reason and sends the version', (
      t,
    ) async {
      final repo = countriesRepo();
      await open(t, buildApp(repo: repo), '/platform/countries');
      await t.tap(find.text('Pause onboarding'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(repo.calls, isNot(contains('updateCountry')), reason: 'no reason');

      await t.enterText(find.byType(TextFormField).last, 'Pause for review');
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      final i = repo.calls.indexOf('updateCountry');
      expect(i, isNot(-1));
      expect(repo.callArgs[i][0], 'IN');
      final patch = repo.callArgs[i][1]! as Map<String, Object?>;
      expect(patch['onboardingEnabled'], false);
      expect(patch['expectedVersion'], 1);
      expect(patch['reason'], 'Pause for review');
    });

    testWidgets('a backend refusal is shown to the admin', (t) async {
      final repo = countriesRepo()
        ..on(
          'updateCountry',
          (a, n) => throw const ApiFailure(
            code: ApiErrorCode.validationFailed,
            message: 'Record the review date and sources first.',
          ),
        );
      await open(t, buildApp(repo: repo), '/platform/countries');
      await t.tap(find.text('Open onboarding'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).last, 'Go live now');
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Record the review date and sources first.'),
        findsOneWidget,
      );
    });

    testWidgets('support admin can read but gets no change controls', (
      t,
    ) async {
      await open(
        t,
        buildApp(
          repo: countriesRepo(),
          session: sessionWith(platformRole: PlatformRole.platformSupportAdmin),
        ),
        '/platform/countries',
      );
      expect(find.text('India (IN)'), findsOneWidget);
      expect(find.text('Pause onboarding'), findsNothing);
      expect(find.text('Seed India and UAE'), findsNothing);
    });

    testWidgets('seeding runs the baseline action', (t) async {
      final repo = countriesRepo();
      await open(t, buildApp(repo: repo), '/platform/countries');
      await t.tap(find.text('Seed India and UAE'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('seedCountries'));
    });

    testWidgets('empty master invites seeding', (t) async {
      await open(
        t,
        buildApp(repo: countriesRepo(countries: [])),
        '/platform/countries',
      );
      expect(find.text('No countries yet'), findsOneWidget);
    });

    testWidgets('load failure shows a retry', (t) async {
      final repo = countriesRepo()
        ..on(
          'countries',
          (a, n) => throw const ApiFailure(code: ApiErrorCode.internalError),
        );
      await open(t, buildApp(repo: repo), '/platform/countries');
      expect(find.text('Could not load this page'), findsOneWidget);
    });
  });

  group('country backfill report', () {
    Map<String, Object?> report() => {
      'dryRun': true,
      'alreadyAssigned': 3,
      'summary': {'verified': 1, 'ambiguous': 1, 'unmapped': 1},
      'tenants': [
        {
          'tenantId': 'ten_a',
          'clinicName': 'Verified Clinic',
          'classification': 'verified',
          'candidateCountry': 'IN',
          'reasons': <String>[],
        },
        {
          'tenantId': 'ten_b',
          'clinicName': 'Odd Clinic',
          'classification': 'ambiguous',
          'candidateCountry': 'AE',
          'reasons': ['clinic_phone_inconsistent'],
        },
        {
          'tenantId': 'ten_c',
          'clinicName': 'Mystery Clinic',
          'classification': 'unmapped',
          'candidateCountry': null,
          'reasons': ['no_country_entered'],
        },
      ],
    };

    testWidgets('shows the classification summary and each clinic', (t) async {
      final repo = countriesRepo()..on('backfillReport', (a, n) => report());
      await open(
        t,
        buildApp(repo: repo),
        '/platform/countries/backfill-report',
      );
      expect(find.text('Already assigned: 3'), findsOneWidget);
      expect(find.text('verified: 1'), findsOneWidget);
      expect(find.text('Verified Clinic'), findsOneWidget);
      expect(find.text('Candidate: AE'), findsOneWidget);
      expect(find.textContaining('clinic_phone_inconsistent'), findsOneWidget);
      expect(repo.calls, isNot(contains('assignTenantCountry')));
    });

    testWidgets(
      'assigning needs a country and a reason, then calls the audited action',
      (t) async {
        final repo = countriesRepo()
          ..on('backfillReport', (a, n) => report())
          ..on('assignTenantCountry', (a, n) => {'changed': true});
        await open(
          t,
          buildApp(repo: repo),
          '/platform/countries/backfill-report',
        );
        await t.tap(find.text('Assign country…').first);
        await t.pumpAndSettle();
        await t.tap(find.text('Assign'));
        await t.pumpAndSettle();
        expect(repo.calls, isNot(contains('assignTenantCountry')));
        expect(find.text('Enter at least 3 characters.'), findsOneWidget);

        await t.enterText(
          find.byType(TextFormField).last,
          'Checked registration',
        );
        await t.tap(find.text('Assign'));
        await t.pumpAndSettle();
        final i = repo.calls.indexOf('assignTenantCountry');
        expect(i, isNot(-1));
        expect(repo.callArgs[i][0], 'ten_a');
        expect(repo.callNamed[i]['countryCode'], 'IN'); // preselected candidate
        expect(repo.callNamed[i]['reason'], 'Checked registration');
      },
    );

    testWidgets('support admin cannot assign', (t) async {
      final repo = countriesRepo()..on('backfillReport', (a, n) => report());
      await open(
        t,
        buildApp(
          repo: repo,
          session: sessionWith(platformRole: PlatformRole.platformSupportAdmin),
        ),
        '/platform/countries/backfill-report',
      );
      expect(find.text('Verified Clinic'), findsOneWidget);
      expect(find.text('Assign country…'), findsNothing);
    });

    testWidgets('nothing to migrate shows an empty state', (t) async {
      final repo = countriesRepo()
        ..on(
          'backfillReport',
          (a, n) => {
            'alreadyAssigned': 5,
            'summary': {'verified': 0, 'ambiguous': 0, 'unmapped': 0},
            'tenants': <Object?>[],
          },
        );
      await open(
        t,
        buildApp(repo: repo),
        '/platform/countries/backfill-report',
      );
      expect(find.text('Nothing to migrate'), findsOneWidget);
    });
  });
}
