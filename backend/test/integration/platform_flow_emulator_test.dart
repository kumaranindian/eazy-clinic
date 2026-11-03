@Tags(['emulator'])
library;

import 'dart:io';

import 'package:backend/core/data/firestore_document_store.dart';
import 'package:backend/features/auth/data/membership_access_resolver.dart';
import 'package:backend/features/auth/domain/platform_user.dart';
import 'package:backend/features/platform/applications/application_service.dart';
import 'package:backend/features/platform/audit/audit_service.dart';
import 'package:backend/features/platform/dashboard/dashboard_service.dart';
import 'package:backend/features/platform/entitlements/entitlement_service.dart';
import 'package:backend/features/platform/plans/plan_service.dart';
import 'package:backend/features/platform/subscriptions/subscription_service.dart';
import 'package:backend/features/platform/tenants/tenant_service.dart';
import 'package:common_models/common_models.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/platform_fixtures.dart';

class _OwnerClient extends http.BaseClient {
  _OwnerClient(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

/// The whole SaaS control-plane flow on the real REST store against the
/// Firestore emulator: transactions, preconditions, filtered/ordered queries,
/// aggregation counts and collection-group queries.
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  group(
    'platform flow on the Firestore emulator',
    () {
      late FirestoreDocumentStore store;
      late AuditService audit;
      late PlanService plans;
      late SubscriptionService subs;
      late ApplicationService apps;
      late TenantService tenants;
      final clock = DateTime.now;

      setUp(() {
        store = FirestoreDocumentStore(
          projectId: 'demo-eazyclinic',
          host: 'http://$host',
          client: _OwnerClient(http.Client()),
        );
        audit = AuditService(store);
        plans = PlanService(store, audit);
        subs = SubscriptionService(store, audit);
        apps = ApplicationService(store, audit);
        tenants = TenantService(store, audit, subs);
      });

      Request req([String q = '']) => Request('GET', Uri.parse('http://x/l$q'));

      test(
        'submit → approve → membership → entitlements → lifecycle',
        () async {
          final suffix = clock().microsecondsSinceEpoch.toString();
          final plan = await plans.create(
            PlanInput.parse(planBody(name: 'Emu $suffix'), partial: false),
            admin,
          );
          final planId = plan['planId']! as String;
          await plans.setStatus(planId, PlanStatus.active, admin);

          final uid = 'emu-owner-$suffix';
          final app = await apps.submit(
            applicantUid: uid,
            applicantEmail: '$uid@example.test',
            input: ApplicationInput.parse(
              applicationBody(
                name: 'Emu Clinic $suffix',
                city: 'Pune $suffix',
                postalCode: '411001',
              ),
              partial: false,
            ),
          );
          final appId = app['applicationId']! as String;

          // listing: status filter, name prefix (range + order), id lookup
          expect(
            (await apps.list(
              req(),
              status: ApplicationStatus.submitted,
            )).docs.any((d) => d.id == appId),
            isTrue,
          );
          expect(
            (await apps.list(
              req(),
              q: 'emu clinic $suffix',
            )).docs.map((d) => d.id),
            [appId],
          );
          expect((await apps.list(req(), q: appId)).docs, hasLength(1));
          expect((await apps.listMine(uid, req())).docs, hasLength(1));

          // duplicate/conflict queries
          await expectLater(
            apps.submit(
              applicantUid: uid,
              applicantEmail: 'x@example.test',
              input: ApplicationInput.parse(
                applicationBody(name: 'Another'),
                partial: false,
              ),
            ),
            throwsA(isA<Object>()),
          );

          // approval with initial trial; repeated approval is idempotent
          final r = await tenants.approve(
            applicationId: appId,
            actor: admin,
            initialPlanId: planId,
            startTrial: true,
          );
          expect(r.completed, isTrue);
          final again = await tenants.approve(
            applicationId: appId,
            actor: admin,
            initialPlanId: planId,
            startTrial: true,
          );
          expect(again.tenantId, r.tenantId);

          // membership resolved through a collection-group query
          final user = PlatformUser(
            uid: uid,
            displayName: 'x',
            email: '$uid@example.test',
            emailVerified: true,
            accountStatus: AccountStatus.active,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          final memberships = await MembershipAccessResolver(
            store,
          ).membershipsFor(user);
          expect(memberships.map((m) => m.tenantId), contains(r.tenantId));
          expect(
            memberships.firstWhere((m) => m.tenantId == r.tenantId).role,
            'clinic_owner',
          );

          // entitlements
          final ent = await EntitlementService(store).forTenant(r.tenantId);
          expect(ent.accessLevel, AccessLevel.full);
          expect(ent.features[FeatureKey.appointments], isTrue);
          expect(ent.subscription!['status'], 'trial');

          // dashboard counts, including the inequality-on-date aggregation
          final dash = await DashboardService(store, audit).build();
          expect((dash['tenants']! as Map)['active'], greaterThanOrEqualTo(1));
          expect(
            (dash['subscriptions']! as Map)['trial'],
            greaterThanOrEqualTo(1),
          );
          expect((dash['recentApplications']! as List), isNotEmpty);

          // tenant lifecycle + subscription change + reactivation rules
          await tenants.suspend(r.tenantId, 'Emulator review', admin);
          expect(
            (await EntitlementService(store).forTenant(r.tenantId)).accessLevel,
            AccessLevel.blocked,
          );
          await tenants.reactivate(r.tenantId, 'Emulator OK', admin);
          final subId =
              (await store.get('tenants/${r.tenantId}'))!['subscriptionId']!
                  as String;
          await subs
              .markPastDue(subId, admin)
              .catchError((Object _) => <String, Object?>{});
          await subs.renew(subId, admin);
          await subs
              .extendTrial(subId, 3, admin, reason: 'x')
              .catchError((Object _) => <String, Object?>{});

          // audit: filtered + ordered + paginated
          final audits = await audit.list(
            req('?limit=3'),
            tenantId: r.tenantId,
          );
          expect(audits.docs, isNotEmpty);
          expect(audits.meta.hasMore, isTrue);
          final next = await audit.list(
            Request(
              'GET',
              Uri.parse('http://x/l?limit=3&cursor=${audits.meta.nextCursor}'),
            ),
            tenantId: r.tenantId,
          );
          expect(
            next.docs
                .map((d) => d.id)
                .toSet()
                .intersection(audits.docs.map((d) => d.id).toSet()),
            isEmpty,
          );

          // tenant list queries
          expect(
            (await tenants.list(
              req(),
              status: TenantStatus.active,
            )).docs.any((d) => d.id == r.tenantId),
            isTrue,
          );
          expect(
            (await tenants.list(
              req(),
              q: 'emu clinic $suffix',
            )).docs.map((d) => d.id),
            [r.tenantId],
          );

          // plan queries
          expect((await plans.detail(planId))['assignedTenants'], isNotEmpty);
          await expectLater(
            plans.setStatus(planId, PlanStatus.inactive, admin),
            throwsA(isA<Object>()),
          );
        },
      );
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : null,
  );
}
