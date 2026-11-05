import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show bigScreen, buildApp, routerOf;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

FakeRepo adminRepo() {
  final r = FakeRepo();
  r.on('dashboard', (a, n) => dashboardJson());
  r.on('list', (a, n) {
    final path = a[0]! as String;
    if (path.endsWith('clinic-applications')) {
      return listOf([applicationJson()]);
    }
    if (path.endsWith('/tenants')) {
      return listOf([
        {
          'tenantId': 'ten_1',
          'clinicName': 'Green Valley Clinic',
          'city': 'Pune',
          'status': 'active',
          'approvedAt': '2026-05-30T09:00:00Z',
        },
      ]);
    }
    if (path.endsWith('subscription-plans')) {
      return listOf([
        {
          'planId': 'plan_1',
          'name': 'Starter',
          'priceMinor': 99900,
          'currency': 'INR',
          'billingInterval': 'monthly',
          'trialDays': 14,
          'version': 2,
          'status': 'active',
        },
      ]);
    }
    if (path.endsWith('subscriptions')) {
      return listOf([
        {
          'subscriptionId': 'sub_1',
          'tenantId': 'ten_1',
          'name': 'Starter',
          'priceMinor': 99900,
          'currency': 'INR',
          'billingInterval': 'monthly',
          'endDate': '2026-07-01T00:00:00Z',
          'status': 'active',
        },
      ]);
    }
    if (path.endsWith('audit-logs')) {
      return listOf([
        {
          'action': 'tenant.suspended',
          'timestamp': '2026-05-30T09:00:00Z',
          'actorRole': 'super_admin',
          'actorUid': 'root',
          'targetType': 'tenant',
          'targetId': 'ten_1',
          'reason': 'Policy review',
        },
      ]);
    }
    return listOf([]);
  });
  return r;
}

Future<void> open(WidgetTester t, Widget app, [String? path]) async {
  bigScreen(t);
  await t.pumpWidget(app);
  await t.pumpAndSettle();
  if (path != null) {
    routerOf(t).go(path);
    await t.pumpAndSettle();
  }
}

void main() {
  group('role-aware landing and guards (UI only)', () {
    testWidgets(
      'super admin lands on the platform dashboard with live numbers',
      (t) async {
        await open(t, buildApp(repo: adminRepo()));
        expect(find.text('Platform overview'), findsOneWidget);
        expect(find.text('Registered clinics'), findsOneWidget);
        expect(find.text('Green Valley Clinic'), findsWidgets);
        expect(
          find.textContaining('Not available yet'),
          findsOneWidget,
          reason: 'no fake revenue',
        );
        for (final label in [
          'Dashboard',
          'Applications',
          'Tenants',
          'Plans',
          'Subscriptions',
          'Audit log',
        ]) {
          expect(find.text(label), findsWidgets, reason: label);
        }
      },
    );

    testWidgets(
      'support admin sees read-only navigation without the audit log',
      (t) async {
        await open(
          t,
          buildApp(
            repo: adminRepo(),
            session: sessionWith(
              platformRole: PlatformRole.platformSupportAdmin,
            ),
          ),
        );
        expect(find.text('Platform overview'), findsOneWidget);
        expect(find.text('Audit log'), findsNothing);
        expect(find.text('Support admin'), findsOneWidget);
      },
    );

    testWidgets('a user without a platform role cannot open /platform', (
      t,
    ) async {
      final repo = FakeRepo()..on('list', (a, n) => listOf([]));
      await open(
        t,
        buildApp(repo: repo, session: sessionWith()),
        '/platform/tenants',
      );
      expect(find.text('Platform overview'), findsNothing);
      expect(find.text('Tenants'), findsNothing);
      expect(find.text('My clinic applications'), findsOneWidget);
      expect(repo.calls.where((c) => c == 'dashboard'), isEmpty);
    });

    testWidgets('a clinic owner lands on the clinic page', (t) async {
      final repo = FakeRepo()
        ..on('entitlements', (a, n) => entitlementsJson())
        ..on('getMap', (a, n) => ownerAccess(a[0]! as String));
      await open(
        t,
        buildApp(
          repo: repo,
          session: sessionWith(
            memberships: [
              const MembershipSummaryDto(
                tenantId: 'ten_1',
                role: 'clinic_owner',
              ),
            ],
          ),
        ),
      );
      expect(find.text('Test Clinic'), findsWidgets);
      expect(find.text('Your plan'), findsOneWidget);
      expect(find.text('/platform'), findsNothing);
    });

    testWidgets('dashboard shows retry on failure and recovers', (t) async {
      var failures = 1;
      final repo = FakeRepo()
        ..on('dashboard', (a, n) {
          if (failures-- > 0) throw const ApiFailure(isNetwork: true);
          return dashboardJson();
        });
      await open(t, buildApp(repo: repo));
      expect(find.text('Could not load this page'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Platform overview'), findsOneWidget);
    });

    testWidgets('narrow screens use a drawer instead of a side bar', (t) async {
      bigScreen(t, size: const Size(420, 900));
      await t.pumpWidget(buildApp(repo: adminRepo()));
      await t.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      await t.tap(find.byTooltip('Open navigation menu'));
      await t.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Tenants'), findsOneWidget);
    });
  });

  group('applicant', () {
    Future<void> openApply(WidgetTester t, FakeRepo repo) =>
        open(t, buildApp(repo: repo, session: sessionWith()), '/apply');

    testWidgets('empty state invites registration', (t) async {
      final repo = FakeRepo()..on('list', (a, n) => listOf([]));
      await open(t, buildApp(repo: repo, session: sessionWith()));
      expect(find.text('No applications yet'), findsOneWidget);
      expect(find.text('Register a clinic'), findsOneWidget);
    });

    testWidgets('form validates required fields and submits nothing', (
      t,
    ) async {
      final repo = FakeRepo();
      await openApply(t, repo);
      await t.ensureVisible(find.text('Submit application'));
      await t.tap(find.text('Submit application'));
      await t.pumpAndSettle();
      expect(find.text('Clinic name is required.'), findsOneWidget);
      expect(find.text('Email is required.'), findsWidgets);
      expect(repo.calls, isNot(contains('submitApplication')));
    });

    testWidgets('rejects an invalid PIN and phone', (t) async {
      await openApply(t, FakeRepo());
      await t.enterText(find.widgetWithText(TextFormField, 'PIN code'), '12');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Clinic phone'),
        '123',
      );
      await t.ensureVisible(find.text('Submit application'));
      await t.tap(find.text('Submit application'));
      await t.pumpAndSettle();
      expect(find.text('Enter a valid PIN code.'), findsOneWidget);
      expect(find.text('Enter a valid 10-digit mobile number.'), findsWidgets);
    });

    testWidgets('valid submission sends no status, role or tenant fields', (
      t,
    ) async {
      final repo = FakeRepo()
        ..on(
          'submitApplication',
          (a, n) => {'applicationId': 'app_1', 'status': 'submitted'},
        )
        ..on(
          'myApplication',
          (a, n) => {
            ...applicationJson(),
            'history': [
              {
                'status': 'submitted',
                'by': 'you',
                'at': '2026-05-30T08:00:00Z',
              },
            ],
          },
        );
      await openApply(t, repo);
      Future<void> fill(String label, String v) async =>
          t.enterText(find.widgetWithText(TextFormField, label), v);
      await fill('Clinic name', 'Green Valley Clinic');
      await fill('Clinic email', 'info@gv.test');
      await fill('Clinic phone', '9876543210');
      await fill('Address line 1', '12 Main Road');
      await fill('City', 'Pune');
      await fill('State', 'Maharashtra');
      await fill('PIN code', '411001');
      await fill('Full name', 'Dr Asha Rao');
      await fill('Email', 'asha@gv.test');
      await fill('Mobile number', '9876543211');
      await fill('Number of doctors', '3');
      await fill('Number of staff', '8');
      await fill('Patients per month', '600');
      await t.ensureVisible(find.text('Submit application'));
      await t.tap(find.text('Submit application'));
      await t.pumpAndSettle();
      final body =
          repo.callArgs[repo.calls.indexOf('submitApplication')][0]!
              as Map<String, Object?>;
      expect(body.keys.toSet(), {'clinic', 'address', 'owner', 'expectations'});
      // the legal country is the applicant's explicit choice, sent as a code
      expect((body['address']! as Map)['countryCode'], 'IN');
      expect((body['address']! as Map).containsKey('country'), isFalse);
      expect(body.toString(), isNot(contains('status')));
      expect(body.toString(), isNot(contains('tenant')));
      expect(find.text('Green Valley Clinic'), findsWidgets);
    });

    testWidgets('backend refusal is shown to the applicant', (t) async {
      final repo = FakeRepo()
        ..on(
          'submitApplication',
          (a, n) => throw const ApiFailure(
            code: ApiErrorCode.conflict,
            message: 'You already have an application in progress.',
          ),
        );
      await openApply(t, repo);
      for (final e in {
        'Clinic name': 'Clinic X',
        'Clinic email': 'a@b.co',
        'Clinic phone': '9876543210',
        'Address line 1': '12 Main Road',
        'City': 'Pune',
        'State': 'MH',
        'PIN code': '411001',
        'Full name': 'Dr A',
        'Email': 'a@b.co',
        'Mobile number': '9876543211',
        'Number of doctors': '1',
        'Number of staff': '1',
        'Patients per month': '1',
      }.entries) {
        await t.enterText(find.widgetWithText(TextFormField, e.key), e.value);
      }
      await t.ensureVisible(find.text('Submit application'));
      await t.tap(find.text('Submit application'));
      await t.pumpAndSettle();
      expect(
        find.text('You already have an application in progress.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'information request can be answered; rejection reason is visible',
      (t) async {
        final repo = FakeRepo()
          ..on(
            'myApplication',
            (a, n) => {
              ...applicationJson(status: 'additional_information_required'),
              'infoRequest': {'message': 'Upload registration proof'},
              'history': <Object?>[],
            },
          )
          ..on('respond', (a, n) => {});
        await open(
          t,
          buildApp(repo: repo, session: sessionWith()),
          '/applications/app_1',
        );
        expect(
          find.textContaining('Upload registration proof'),
          findsOneWidget,
        );
        await t.tap(find.text('Respond'));
        await t.pumpAndSettle();
        await t.tap(find.text('Send response'));
        await t.pumpAndSettle();
        expect(
          find.textContaining('is required'),
          findsOneWidget,
          reason: 'empty response is refused',
        );
        await t.enterText(
          find.byType(TextFormField).last,
          'Registration number added',
        );
        await t.tap(find.text('Send response'));
        await t.pumpAndSettle();
        expect(repo.calls, contains('respond'));
        expect(
          (repo.callArgs[repo.calls.indexOf('respond')][1]! as Map)['message'],
          'Registration number added',
        );
      },
    );
  });

  group('application review', () {
    FakeRepo repoFor(String status) => adminRepo()
      ..on('application', (a, n) => applicationJson(status: status))
      ..on(
        'approve',
        (a, n) => {'provisioningComplete': true, 'tenantId': 'ten_1'},
      )
      ..on('reject', (a, n) => {})
      ..on('startReview', (a, n) => {})
      ..on('requestInformation', (a, n) => {});

    testWidgets('list shows rows and filters', (t) async {
      final repo = adminRepo();
      await open(t, buildApp(repo: repo), '/platform/applications');
      expect(find.text('Green Valley Clinic'), findsOneWidget);
      expect(find.text('Clinic applications'), findsWidgets);
      final first = repo.callArgs[repo.calls.lastIndexOf('list')];
      expect(first[0], '/platform/clinic-applications');
      await t.tap(find.text('All statuses'));
      await t.pumpAndSettle();
      await t.tap(find.text('Rejected').last);
      await t.pumpAndSettle();
      expect((repo.callArgs.last[1]! as Map)['status'], 'rejected');
    });

    testWidgets(
      'approval shows a confirmation with owner details and calls the backend',
      (t) async {
        final repo = repoFor('submitted');
        repo.on(
          'list',
          (a, n) => listOf([
            {'planId': 'plan_1', 'name': 'Starter', 'status': 'active'},
          ]),
        );
        await open(t, buildApp(repo: repo), '/platform/applications/app_1');
        await t.tap(find.text('Approve…'));
        await t.pumpAndSettle();
        expect(find.text('Approve this clinic?'), findsOneWidget);
        expect(find.text('Dr Asha Rao'), findsWidgets);
        expect(find.textContaining('creates a new clinic'), findsOneWidget);
        await t.tap(find.text('Approve and create clinic'));
        await t.pumpAndSettle();
        expect(repo.calls, contains('approve'));
        expect(repo.callNamed[repo.calls.indexOf('approve')]['planId'], isNull);
      },
    );

    testWidgets('rejection needs a reason', (t) async {
      final repo = repoFor('submitted');
      await open(t, buildApp(repo: repo), '/platform/applications/app_1');
      await t.tap(find.text('Reject'));
      await t.pumpAndSettle();
      await t.tap(find.text('Reject application').last);
      await t.pumpAndSettle();
      expect(repo.calls, isNot(contains('reject')));
      expect(find.textContaining('Reason is required'), findsOneWidget);
      await t.enterText(
        find.byType(TextFormField).last,
        'Could not verify the clinic',
      );
      await t.tap(find.text('Reject application').last);
      await t.pumpAndSettle();
      expect(repo.callArgs[repo.calls.indexOf('reject')], [
        'app_1',
        'Could not verify the clinic',
      ]);
    });

    testWidgets('support admin sees the application but no review actions', (
      t,
    ) async {
      final repo = repoFor('submitted');
      await open(
        t,
        buildApp(
          repo: repo,
          session: sessionWith(platformRole: PlatformRole.platformSupportAdmin),
        ),
        '/platform/applications/app_1',
      );
      expect(find.text('Green Valley Clinic'), findsWidgets);
      expect(find.text('Approve…'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Start review'), findsNothing);
    });

    testWidgets('finished applications offer no actions', (t) async {
      final repo = repoFor('rejected');
      await open(t, buildApp(repo: repo), '/platform/applications/app_1');
      expect(find.text('Approve…'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('a backend refusal is shown, not swallowed', (t) async {
      final repo = repoFor('submitted')
        ..on(
          'approve',
          (a, n) => throw const ApiFailure(
            code: ApiErrorCode.forbidden,
            message: 'You cannot approve your own application.',
          ),
        );
      repo.on('list', (a, n) => listOf([]));
      await open(t, buildApp(repo: repo), '/platform/applications/app_1');
      await t.tap(find.text('Approve…'));
      await t.pumpAndSettle();
      await t.tap(find.text('Approve and create clinic'));
      await t.pumpAndSettle();
      expect(
        find.text('You cannot approve your own application.'),
        findsOneWidget,
      );
    });
  });

  group('tenants', () {
    testWidgets('suspend requires a reason and calls the backend with it', (
      t,
    ) async {
      final repo = adminRepo()
        ..on('tenant', (a, n) => tenantJson())
        ..on('suspendTenant', (a, n) => {});
      await open(t, buildApp(repo: repo), '/platform/tenants/ten_1');
      await t.tap(find.text('Suspend'));
      await t.pumpAndSettle();
      await t.tap(find.text('Suspend clinic').last);
      await t.pumpAndSettle();
      expect(repo.calls, isNot(contains('suspendTenant')));
      await t.enterText(find.byType(TextFormField).last, 'Policy review');
      await t.tap(find.text('Suspend clinic').last);
      await t.pumpAndSettle();
      expect(repo.callArgs[repo.calls.indexOf('suspendTenant')], [
        'ten_1',
        'Policy review',
      ]);
    });

    testWidgets('failed provisioning is explained and can be retried', (
      t,
    ) async {
      final repo = adminRepo()
        ..on(
          'tenant',
          (a, n) => tenantJson(
            status: 'provisioning',
            job: {
              'status': 'failed',
              'lastError': 'StoreException',
              'attempts': 1,
            },
          ),
        )
        ..on('retryProvisioning', (a, n) => {});
      await open(t, buildApp(repo: repo), '/platform/tenants/ten_1');
      expect(find.textContaining('Provisioning failed'), findsOneWidget);
      await t.tap(find.text('Retry provisioning'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('retryProvisioning'));
    });

    testWidgets('closing warns that it is final', (t) async {
      final repo = adminRepo()..on('tenant', (a, n) => tenantJson());
      await open(t, buildApp(repo: repo), '/platform/tenants/ten_1');
      await t.tap(find.text('Close clinic'));
      await t.pumpAndSettle();
      expect(find.textContaining('Closing is final'), findsOneWidget);
    });

    testWidgets('support admin cannot see tenant actions', (t) async {
      final repo = adminRepo()..on('tenant', (a, n) => tenantJson());
      await open(
        t,
        buildApp(
          repo: repo,
          session: sessionWith(platformRole: PlatformRole.platformSupportAdmin),
        ),
        '/platform/tenants/ten_1',
      );
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Close clinic'), findsNothing);
      expect(find.text('Green Valley Clinic'), findsWidgets);
    });

    testWidgets('list pagination loads more with the cursor', (t) async {
      final cursors = <Object?>[];
      final repo = adminRepo()
        ..on('list', (a, n) {
          final q = a[1]! as Map<String, String>;
          cursors.add(q['cursor']);
          return q['cursor'] == null
              ? listOf([
                  {
                    'tenantId': 'ten_1',
                    'clinicName': 'First Clinic',
                    'status': 'active',
                  },
                ], next: 'c1')
              : listOf([
                  {
                    'tenantId': 'ten_2',
                    'clinicName': 'Second Clinic',
                    'status': 'active',
                  },
                ]);
        });
      await open(t, buildApp(repo: repo), '/platform/tenants');
      expect(find.text('First Clinic'), findsOneWidget);
      await t.tap(find.text('Load more'));
      await t.pumpAndSettle();
      expect(find.text('Second Clinic'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(cursors.last, 'c1');
    });

    testWidgets('empty list shows guidance', (t) async {
      final repo = adminRepo()..on('list', (a, n) => listOf([]));
      await open(t, buildApp(repo: repo), '/platform/tenants');
      expect(find.text('No tenants found'), findsOneWidget);
    });
  });

  group('plans and subscriptions', () {
    testWidgets('plan list and detail show limits and unlimited values', (
      t,
    ) async {
      final repo = adminRepo()
        ..on(
          'plan',
          (a, n) => {
            'planId': 'plan_1',
            'name': 'Starter',
            'description': 'For small clinics',
            'status': 'active',
            'version': 2,
            'priceMinor': 99900,
            'currency': 'INR',
            'billingInterval': 'monthly',
            'trialDays': 14,
            'limits': {
              'max_branches': 1,
              'max_doctors': 3,
              'max_staff': 10,
              'max_patients': null,
            },
            'features': {'appointments': true},
            'assignedTenants': [
              {
                'tenantId': 'ten_1',
                'clinicName': 'Green Valley Clinic',
                'subscriptionStatus': 'active',
              },
            ],
          },
        );
      await open(t, buildApp(repo: repo), '/platform/plans');
      expect(find.text('Starter'), findsOneWidget);
      expect(find.textContaining('₹999.00'), findsOneWidget);
      await t.tap(find.text('Starter'));
      await t.pumpAndSettle();
      expect(find.text('Unlimited'), findsOneWidget);
      expect(find.text('Green Valley Clinic'), findsOneWidget);
    });

    testWidgets('plan form validates numbers and sends paise, null limits', (
      t,
    ) async {
      final repo = adminRepo()
        ..on('createPlan', (a, n) => {'planId': 'plan_9'})
        ..on(
          'plan',
          (a, n) => {
            'planId': 'plan_9',
            'name': 'Pro',
            'description': '',
            'status': 'inactive',
            'version': 1,
            'priceMinor': 149900,
            'currency': 'INR',
            'billingInterval': 'yearly',
            'trialDays': 0,
            'limits': {
              'max_branches': 5,
              'max_doctors': null,
              'max_staff': null,
              'max_patients': null,
            },
            'features': <String, Object?>{},
            'assignedTenants': <Object?>[],
          },
        );
      await open(t, buildApp(repo: repo), '/platform/plans/new');
      await t.ensureVisible(find.text('Create plan'));
      await t.tap(find.text('Create plan'));
      await t.pumpAndSettle();
      expect(find.text('Enter a name (2–80 characters).'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextFormField, 'Plan name'), 'Pro');
      await t.enterText(find.widgetWithText(TextFormField, 'Price (₹)'), 'abc');
      await t.ensureVisible(find.text('Create plan'));
      await t.tap(find.text('Create plan'));
      await t.pumpAndSettle();
      expect(find.textContaining('Enter an amount in rupees'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Price (₹)'),
        '1499',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Max branches'),
        '5',
      );
      await t.ensureVisible(find.text('Create plan'));
      await t.tap(find.text('Create plan'));
      await t.pumpAndSettle();
      final body =
          repo.callArgs[repo.calls.indexOf('createPlan')][0]!
              as Map<String, Object?>;
      expect(body['priceMinor'], 149900);
      expect((body['limits']! as Map)['max_branches'], 5);
      expect((body['limits']! as Map)['max_doctors'], isNull);
      expect(body.containsKey('status'), isFalse);
    });

    testWidgets(
      'subscription detail flags an expired-by-date subscription and offers lifecycle actions',
      (t) async {
        final repo = adminRepo()
          ..on(
            'subscription',
            (a, n) => {
              'subscriptionId': 'sub_1',
              'tenantId': 'ten_1',
              'clinicName': 'Green Valley Clinic',
              'name': 'Starter',
              'planVersion': 1,
              'priceMinor': 99900,
              'currency': 'INR',
              'billingInterval': 'monthly',
              'status': 'active',
              'effectiveStatus': 'expired',
              'startDate': '2026-01-01T00:00:00Z',
              'endDate': '2026-02-01T00:00:00Z',
              'overrides': <String, Object?>{},
              'history': [
                {
                  'type': 'assigned',
                  'toStatus': 'active',
                  'at': '2026-01-01T00:00:00Z',
                  'actorRole': 'super_admin',
                },
              ],
            },
          )
          ..on('renew', (a, n) => {});
        await open(t, buildApp(repo: repo), '/platform/subscriptions/sub_1');
        expect(find.textContaining('treated as expired'), findsOneWidget);
        await t.tap(find.text('Renew'));
        await t.pumpAndSettle();
        expect(repo.calls, contains('renew'));
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets('audit log lists entries and filters by tenant', (t) async {
      final repo = adminRepo();
      await open(t, buildApp(repo: repo), '/platform/audit');
      expect(find.text('Tenant suspended'), findsOneWidget);
      expect(find.textContaining('Policy review'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'ten_1');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect((repo.callArgs.last[1]! as Map)['tenantId'], 'ten_1');
    });
  });

  group('clinic home restrictions', () {
    Future<void> clinic(WidgetTester t, Map<String, Object?> ent) => open(
      t,
      buildApp(
        repo: FakeRepo()
          ..on('entitlements', (a, n) => ent)
          ..on('getMap', (a, n) {
            if (ent['accessLevel'] == 'blocked') {
              throw const ApiFailure(
                code: ApiErrorCode.forbidden,
                message: 'blocked',
              );
            }
            return ownerAccess(a[0]! as String, writes: false);
          }),
        session: sessionWith(
          memberships: [
            const MembershipSummaryDto(tenantId: 'ten_1', role: 'clinic_owner'),
          ],
        ),
      ),
    );

    testWidgets('suspended clinic is blocked with an explanation', (t) async {
      await clinic(
        t,
        entitlementsJson(
          level: 'blocked',
          reason: 'tenant_suspended',
          tenantStatus: 'suspended',
        ),
      );
      expect(find.textContaining('Your clinic is suspended'), findsOneWidget);
    });

    testWidgets('expired subscription is blocked', (t) async {
      await clinic(
        t,
        entitlementsJson(level: 'blocked', reason: 'subscription_expired'),
      );
      expect(find.textContaining('subscription has expired'), findsOneWidget);
    });

    testWidgets('past due subscription is read-only', (t) async {
      await clinic(
        t,
        entitlementsJson(level: 'read_only', reason: 'subscription_past_due'),
      );
      expect(find.textContaining('cannot make changes'), findsOneWidget);
    });
  });
}
