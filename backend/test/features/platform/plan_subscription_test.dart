import 'package:backend/core/errors/api_exception.dart';
import 'package:backend/features/platform/plans/plan_service.dart';
import 'package:backend/features/platform/subscriptions/subscription_logic.dart';
import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/platform_fixtures.dart';

Matcher conflict() => throwsA(
  isA<ApiException>().having((e) => e.code.httpStatus, 'status', 409),
);
Matcher invalid() => throwsA(
  isA<ApiException>().having((e) => e.code.httpStatus, 'status', 422),
);

void main() {
  late PlatformServices s;
  setUp(() => s = PlatformServices());

  group('plan validation', () {
    test('rejects unknown fields, bad limits and unknown features', () {
      expect(
        () => PlanInput.parse({
          ...planBody(),
          'status': 'active',
        }, partial: false),
        invalid(),
      );
      expect(
        () => PlanInput.parse(
          planBody(
            limits: {
              'max_branches': -1,
              'max_doctors': 1,
              'max_staff': 1,
              'max_patients': null,
            },
          ),
          partial: false,
        ),
        invalid(),
      );
      expect(
        () => PlanInput.parse(
          planBody(features: {'time_travel': true}),
          partial: false,
        ),
        invalid(),
      );
      expect(
        () => PlanInput.parse(planBody(price: -5), partial: false),
        invalid(),
      );
    });
    test('a missing limit key is an error (never silently unlimited)', () {
      expect(
        () => PlanInput.parse(
          planBody(limits: {'max_branches': 1}),
          partial: false,
        ),
        invalid(),
      );
    });
    test('only INR', () {
      expect(
        () =>
            PlanInput.parse({...planBody(), 'currency': 'USD'}, partial: false),
        invalid(),
      );
    });
  });

  group('plans', () {
    test('create → inactive, version 1, snapshot + audit written', () async {
      final plan = await s.plans.create(
        PlanInput.parse(planBody(), partial: false),
        admin,
      );
      expect(plan['status'], 'inactive');
      expect(plan['version'], 1);
      final id = plan['planId'] as String;
      expect(s.store.docs['subscription_plans/$id/versions/1'], isNotNull);
      expect(
        s.store.docs.keys.any((k) => k.startsWith('platform_audit_logs/')),
        isTrue,
      );
    });

    test('edit bumps the version and keeps the old snapshot', () async {
      final id = await s.activePlan();
      await s.plans.update(
        id,
        PlanInput.parse({'priceMinor': 149900}, partial: true),
        admin,
      );
      final plan = (await s.plans.find(id))!;
      expect(plan['version'], 2);
      expect(plan['priceMinor'], 149900);
      expect(
        s.store.docs['subscription_plans/$id/versions/1']!['priceMinor'],
        99900,
      );
      expect(
        s.store.docs['subscription_plans/$id/versions/2']!['priceMinor'],
        149900,
      );
    });

    test('partial limits merge instead of wiping other limits', () async {
      final id = await s.activePlan();
      await s.plans.update(
        id,
        PlanInput.parse({
          'limits': {'max_doctors': 9},
        }, partial: true),
        admin,
      );
      final limits = (await s.plans.find(id))!['limits']! as Map;
      expect(limits['max_doctors'], 9);
      expect(limits['max_branches'], 1);
    });

    test('empty update → 400', () async {
      final id = await s.activePlan();
      expect(
        () => s.plans.update(id, const PlanInput(), admin),
        throwsA(isA<ApiException>()),
      );
    });

    test('cannot deactivate a plan with live subscriptions', () async {
      final id = await s.activePlan();
      s.seedTenant('t1');
      await s.subscriptions.assign(
        tenantId: 't1',
        planId: id,
        trial: false,
        actor: admin,
      );
      await expectLater(
        s.plans.setStatus(id, PlanStatus.inactive, admin),
        conflict(),
      );
    });

    test('can deactivate once the subscription is cancelled', () async {
      final id = await s.activePlan();
      s.seedTenant('t1');
      final sub = await s.subscriptions.assign(
        tenantId: 't1',
        planId: id,
        trial: false,
        actor: admin,
      );
      await s.subscriptions.cancel(
        sub['subscriptionId']! as String,
        admin,
        reason: 'closing',
      );
      final plan = await s.plans.setStatus(id, PlanStatus.inactive, admin);
      expect(plan['status'], 'inactive');
    });

    test('detail lists assigned tenants', () async {
      final id = await s.activePlan();
      s.seedTenant('t1', name: 'Alpha');
      await s.subscriptions.assign(
        tenantId: 't1',
        planId: id,
        trial: false,
        actor: admin,
      );
      final d = await s.plans.detail(id);
      expect((d['assignedTenants']! as List).single['clinicName'], 'Alpha');
    });
  });

  group('subscription assignment', () {
    test(
      'assign an active subscription: snapshot, dates, tenant link',
      () async {
        final id = await s.activePlan();
        s.seedTenant('t1');
        final sub = await s.subscriptions.assign(
          tenantId: 't1',
          planId: id,
          trial: false,
          actor: admin,
        );
        expect(sub['status'], 'active');
        expect(sub['priceMinor'], 99900);
        expect(sub['planVersion'], 1);
        expect(sub['endDate'], DateTime.utc(2026, 7, 1, 10));
        expect(
          s.store.docs['tenants/t1']!['subscriptionId'],
          sub['subscriptionId'],
        );
      },
    );

    test('trial uses trialDays', () async {
      final id = await s.activePlan(trialDays: 14);
      s.seedTenant('t1');
      final sub = await s.subscriptions.assign(
        tenantId: 't1',
        planId: id,
        trial: true,
        actor: admin,
      );
      expect(sub['status'], 'trial');
      expect(sub['trialEndDate'], DateTime.utc(2026, 6, 15, 10));
    });

    test('trial on a plan without trial → 409', () async {
      final id = await s.activePlan(trialDays: 0);
      s.seedTenant('t1');
      await expectLater(
        s.subscriptions.assign(
          tenantId: 't1',
          planId: id,
          trial: true,
          actor: admin,
        ),
        conflict(),
      );
    });

    test('inactive plan, unknown tenant, closed tenant', () async {
      final plan = await s.plans.create(
        PlanInput.parse(planBody(), partial: false),
        admin,
      );
      s.seedTenant('t1');
      await expectLater(
        s.subscriptions.assign(
          tenantId: 't1',
          planId: plan['planId']! as String,
          trial: false,
          actor: admin,
        ),
        conflict(),
      );
      final id = await s.activePlan(name: 'Pro');
      await expectLater(
        s.subscriptions.assign(
          tenantId: 'nope',
          planId: id,
          trial: false,
          actor: admin,
        ),
        throwsA(isA<ApiException>()),
      );
      s.seedTenant('t2', status: 'closed');
      await expectLater(
        s.subscriptions.assign(
          tenantId: 't2',
          planId: id,
          trial: false,
          actor: admin,
        ),
        conflict(),
      );
    });

    test('a second live subscription is refused', () async {
      final id = await s.activePlan();
      s.seedTenant('t1');
      await s.subscriptions.assign(
        tenantId: 't1',
        planId: id,
        trial: false,
        actor: admin,
      );
      await expectLater(
        s.subscriptions.assign(
          tenantId: 't1',
          planId: id,
          trial: false,
          actor: admin,
        ),
        conflict(),
      );
    });

    test('start date outside the allowed window → 400', () async {
      final id = await s.activePlan();
      s.seedTenant('t1');
      await expectLater(
        s.subscriptions.assign(
          tenantId: 't1',
          planId: id,
          trial: false,
          startDate: DateTime.utc(2020),
          actor: admin,
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('lifecycle', () {
    late String planId;
    late String subId;
    setUp(() async {
      planId = await s.activePlan();
      s.seedTenant('t1');
      subId =
          (await s.subscriptions.assign(
                tenantId: 't1',
                planId: planId,
                trial: false,
                actor: admin,
              ))['subscriptionId']!
              as String;
    });

    test(
      'active → past_due → active (renew extends from the old end)',
      () async {
        await s.subscriptions.markPastDue(subId, admin);
        final renewed = await s.subscriptions.renew(subId, admin);
        expect(renewed['status'], 'active');
        expect(renewed['endDate'], DateTime.utc(2026, 8, 1, 10));
      },
    );

    test('invalid transitions are refused', () async {
      await expectLater(
        s.subscriptions.extendTrial(subId, 7, admin, reason: 'x'),
        conflict(),
      );
      await s.subscriptions.cancel(subId, admin, reason: 'bye');
      await expectLater(s.subscriptions.renew(subId, admin), conflict());
      await expectLater(
        s.subscriptions.suspend(subId, admin, reason: 'x'),
        conflict(),
      );
    });

    test('suspend → renew reactivates the subscription only', () async {
      await s.subscriptions.suspend(subId, admin, reason: 'abuse');
      expect((await s.subscriptions.find(subId))!['status'], 'suspended');
      expect(
        s.store.docs['tenants/t1']!['status'],
        'active',
        reason: 'tenant status is independent',
      );
    });

    test('renewing an expired subscription starts a new period now', () async {
      s.clock.now = DateTime.utc(2026, 9, 1);
      final renewed = await s.subscriptions.renew(subId, admin);
      // Stored status was still `active` but past its end, so it restarts now.
      expect(renewed['endDate'], DateTime.utc(2026, 10, 1));
    });

    test(
      'trial extension adds days from the later of end/now and needs trial',
      () async {
        s.seedTenant('t2');
        final trial = await s.subscriptions.assign(
          tenantId: 't2',
          planId: planId,
          trial: true,
          actor: admin,
        );
        final ext = await s.subscriptions.extendTrial(
          trial['subscriptionId']! as String,
          7,
          admin,
          reason: 'onboarding delay',
        );
        expect(ext['trialEndDate'], DateTime.utc(2026, 6, 22, 10));
        expect(ext['endDate'], DateTime.utc(2026, 6, 22, 10));
      },
    );

    test('plan change preserves history and old price', () async {
      final other = await s.activePlan(
        name: 'Pro',
        body: planBody(name: 'Pro', price: 299900),
      );
      final changed = await s.subscriptions.changePlan(
        subId,
        other,
        admin,
        reason: 'upgrade',
      );
      expect(changed['planId'], other);
      expect(changed['priceMinor'], 299900);
      expect(changed['previousSubscriptionId'], subId);
      final old = (await s.subscriptions.find(subId))!;
      expect(old['status'], 'cancelled');
      expect(old['priceMinor'], 99900, reason: 'historical price untouched');
      expect(
        s.store.docs['tenants/t1']!['subscriptionId'],
        changed['subscriptionId'],
      );
      await expectLater(
        s.subscriptions.changePlan(
          changed['subscriptionId']! as String,
          other,
          admin,
        ),
        conflict(),
      );
    });

    test('plan edits do not alter existing subscriptions', () async {
      await s.plans.update(
        planId,
        PlanInput.parse({'priceMinor': 500000}, partial: true),
        admin,
      );
      expect((await s.subscriptions.find(subId))!['priceMinor'], 99900);
    });

    test('every change writes history and audit', () async {
      await s.subscriptions.markPastDue(subId, admin, reason: 'unpaid');
      await s.subscriptions.suspend(subId, admin, reason: 'unpaid 30d');
      final d = await s.subscriptions.detail(subId);
      expect((d['history']! as List).length, greaterThanOrEqualTo(3));
      final actions = s.store.docs.entries
          .where((e) => e.key.startsWith('platform_audit_logs/'))
          .map((e) => e.value['action']);
      expect(
        actions,
        containsAll([
          'subscription.assigned',
          'subscription.marked_past_due',
          'subscription.suspended',
        ]),
      );
    });

    test('overrides are stored and audited', () async {
      await s.subscriptions.setOverrides(
        subId,
        {
          'features': {'billing': true},
        },
        admin,
        reason: 'goodwill',
      );
      expect(
        ((await s.subscriptions.find(subId))!['overrides']! as Map)['features'],
        {'billing': true},
      );
    });
  });

  group('effectiveSubscriptionStatus', () {
    test('trial and active expire by date', () {
      final now = DateTime.utc(2026, 6, 10);
      expect(
        effectiveSubscriptionStatus({
          'status': 'trial',
          'trialEndDate': DateTime.utc(2026, 6, 9),
        }, now),
        SubscriptionStatus.expired,
      );
      expect(
        effectiveSubscriptionStatus({
          'status': 'trial',
          'trialEndDate': DateTime.utc(2026, 6, 11),
        }, now),
        SubscriptionStatus.trial,
      );
      expect(
        effectiveSubscriptionStatus({
          'status': 'active',
          'endDate': DateTime.utc(2026, 6, 10),
        }, now),
        SubscriptionStatus.expired,
      );
      expect(
        effectiveSubscriptionStatus({
          'status': 'past_due',
          'endDate': DateTime.utc(2026, 1, 1),
        }, now),
        SubscriptionStatus.pastDue,
      );
    });
  });
}
