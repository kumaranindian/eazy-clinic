import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

void main() {
  group('ApplicationStatus', () {
    test('final states allow no transition', () {
      for (final s in [
        ApplicationStatus.approved,
        ApplicationStatus.rejected,
        ApplicationStatus.withdrawn,
      ]) {
        expect(s.isFinal, isTrue);
        for (final t in ApplicationStatus.values) {
          expect(s.canTransitionTo(t), isFalse, reason: '${s.name}->${t.name}');
        }
      }
    });
    test('review paths', () {
      expect(
        ApplicationStatus.submitted.canTransitionTo(ApplicationStatus.approved),
        isTrue,
      );
      expect(
        ApplicationStatus.underReview.canTransitionTo(
          ApplicationStatus.rejected,
        ),
        isTrue,
      );
      expect(
        ApplicationStatus.additionalInformationRequired.canTransitionTo(
          ApplicationStatus.submitted,
        ),
        isTrue,
      );
      expect(
        ApplicationStatus.additionalInformationRequired.canTransitionTo(
          ApplicationStatus.approved,
        ),
        isFalse,
        reason: 'must be re-submitted before approval',
      );
      expect(
        ApplicationStatus.submitted.canTransitionTo(ApplicationStatus.draft),
        isFalse,
      );
    });
    test('open applications block duplicates', () {
      expect(ApplicationStatus.submitted.isOpen, isTrue);
      expect(ApplicationStatus.rejected.isOpen, isFalse);
    });
  });

  group('TenantStatus', () {
    test('lifecycle', () {
      expect(
        TenantStatus.provisioning.canTransitionTo(TenantStatus.active),
        isTrue,
      );
      expect(
        TenantStatus.provisioning.canTransitionTo(TenantStatus.suspended),
        isFalse,
      );
      expect(
        TenantStatus.active.canTransitionTo(TenantStatus.suspended),
        isTrue,
      );
      expect(
        TenantStatus.suspended.canTransitionTo(TenantStatus.active),
        isTrue,
      );
      for (final t in TenantStatus.values) {
        expect(TenantStatus.closed.canTransitionTo(t), isFalse);
      }
    });
  });

  group('SubscriptionStatus', () {
    test('cancelled is terminal; expired can be renewed', () {
      for (final t in SubscriptionStatus.values) {
        expect(SubscriptionStatus.cancelled.canTransitionTo(t), isFalse);
      }
      expect(
        SubscriptionStatus.expired.canTransitionTo(SubscriptionStatus.active),
        isTrue,
      );
      expect(
        SubscriptionStatus.active.canTransitionTo(SubscriptionStatus.trial),
        isFalse,
      );
      expect(
        SubscriptionStatus.active.canTransitionTo(SubscriptionStatus.pastDue),
        isTrue,
      );
    });
  });

  group('BillingInterval.periodEnd', () {
    test('monthly clamps to month end', () {
      expect(
        BillingInterval.monthly.periodEnd(DateTime.utc(2026, 1, 31)),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        BillingInterval.monthly.periodEnd(DateTime.utc(2026, 12, 15)),
        DateTime.utc(2027, 1, 15),
      );
    });
    test('yearly handles leap day', () {
      expect(
        BillingInterval.yearly.periodEnd(DateTime.utc(2028, 2, 29)),
        DateTime.utc(2029, 2, 28),
      );
    });
  });

  group('platform permissions', () {
    test('support admin is read-only and has no audit access', () {
      final p = PermissionPolicy.forPlatformRole(
        PlatformRole.platformSupportAdmin,
      );
      for (final denied in [
        Permission.reviewApplications,
        Permission.manageTenants,
        Permission.managePlans,
        Permission.manageSubscriptions,
        Permission.overrideEntitlements,
        Permission.readAuditLogs,
        Permission.revokeUserSessions,
      ]) {
        expect(p.contains(denied), isFalse, reason: denied);
      }
      expect(p.contains(Permission.readTenants), isTrue);
    });
    test('super admin holds every platform permission', () {
      final p = PermissionPolicy.forPlatformRole(PlatformRole.superAdmin);
      expect(
        p.containsAll([Permission.manageTenants, Permission.readAuditLogs]),
        isTrue,
      );
    });
  });
}
