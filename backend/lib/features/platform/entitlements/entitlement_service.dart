import 'package:common_models/common_models.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../subscriptions/subscription_logic.dart';

enum AccessLevel {
  /// Reads and writes allowed (subject to feature/limit checks).
  full('full'),

  /// Existing data may be read; new operations are refused (e.g. past due).
  readOnly('read_only'),

  /// Nothing allowed except reading the entitlement/explanation itself.
  blocked('blocked');

  const AccessLevel(this.wireName);
  final String wireName;
}

class AccessDecision {
  const AccessDecision(this.level, this.reason);
  final AccessLevel level;
  final String? reason;
}

/// The single place that turns tenant + subscription state into an access
/// level. See docs/phase-2/ENTITLEMENT_POLICY.md.
AccessDecision evaluateAccess({
  required TenantStatus tenantStatus,
  required Map<String, Object?>? subscription,
  required DateTime now,
}) {
  switch (tenantStatus) {
    case TenantStatus.provisioning:
      return const AccessDecision(AccessLevel.blocked, 'tenant_provisioning');
    case TenantStatus.suspended:
      return const AccessDecision(AccessLevel.blocked, 'tenant_suspended');
    case TenantStatus.closed:
      return const AccessDecision(AccessLevel.blocked, 'tenant_closed');
    case TenantStatus.active:
      break;
  }
  if (subscription == null) {
    return const AccessDecision(AccessLevel.blocked, 'no_subscription');
  }
  return switch (effectiveSubscriptionStatus(subscription, now)) {
    SubscriptionStatus.trial ||
    SubscriptionStatus.active => const AccessDecision(AccessLevel.full, null),
    SubscriptionStatus.pastDue => const AccessDecision(
      AccessLevel.readOnly,
      'subscription_past_due',
    ),
    SubscriptionStatus.expired => const AccessDecision(
      AccessLevel.blocked,
      'subscription_expired',
    ),
    SubscriptionStatus.cancelled => const AccessDecision(
      AccessLevel.blocked,
      'subscription_cancelled',
    ),
    SubscriptionStatus.suspended => const AccessDecision(
      AccessLevel.blocked,
      'subscription_suspended',
    ),
  };
}

class Entitlements {
  const Entitlements({
    required this.tenantId,
    required this.tenantStatus,
    required this.accessLevel,
    required this.reason,
    required this.features,
    required this.limits,
    this.subscription,
  });

  final String tenantId;
  final TenantStatus tenantStatus;
  final AccessLevel accessLevel;
  final String? reason;
  final Map<String, bool> features;
  final Map<String, int?> limits;
  final Map<String, Object?>? subscription;

  bool get writesAllowed => accessLevel == AccessLevel.full;

  Map<String, Object?> toJson() => {
    'tenantId': tenantId,
    'tenantStatus': tenantStatus.wireName,
    'accessLevel': accessLevel.wireName,
    'writesAllowed': writesAllowed,
    'reason': reason,
    'subscription': subscription,
    'features': features,
    'limits': limits,
  };
}

/// Evaluates what a tenant may use. Every future protected business endpoint
/// must call [assertFeature] (and [assertWithinLimit] when creating records)
/// with the tenant resolved from the caller's membership, never from the client.
class EntitlementService {
  EntitlementService(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final DateTime Function() _clock;

  Future<Entitlements> forTenant(String tenantId) async {
    final tenant = await _store.get('tenants/$tenantId');
    if (tenant == null) {
      throw const ApiException.forbidden(
        'You do not have access to this clinic.',
      );
    }
    final status =
        TenantStatus.tryParse(tenant['status'] as String?) ??
        TenantStatus.closed;
    final subId = tenant['subscriptionId'] as String?;
    final sub = subId == null
        ? null
        : await _store.get('platform_subscriptions/$subId');
    final now = _clock().toUtc();
    final decision = evaluateAccess(
      tenantStatus: status,
      subscription: sub,
      now: now,
    );

    final overrides =
        (sub?['overrides'] as Map?)?.cast<String, Object?>() ?? const {};
    final overrideFeatures =
        (overrides['features'] as Map?)?.cast<String, Object?>() ?? const {};
    final overrideLimits =
        (overrides['limits'] as Map?)?.cast<String, Object?>() ?? const {};
    final planFeatures =
        (sub?['features'] as Map?)?.cast<String, Object?>() ?? const {};
    final planLimits =
        (sub?['limits'] as Map?)?.cast<String, Object?>() ?? const {};

    final blocked = decision.level == AccessLevel.blocked;
    final features = {
      for (final k in FeatureKey.all)
        k: !blocked && ((overrideFeatures[k] ?? planFeatures[k]) == true),
    };
    final limits = {
      for (final k in LimitKey.all)
        k:
            (overrideLimits.containsKey(k) ? overrideLimits[k] : planLimits[k])
                as int?,
    };
    return Entitlements(
      tenantId: tenantId,
      tenantStatus: status,
      accessLevel: decision.level,
      reason: decision.reason,
      features: features,
      limits: limits,
      subscription: sub == null
          ? null
          : {
              'subscriptionId': sub['subscriptionId'],
              'planId': sub['planId'],
              'planName': sub['name'],
              'status': effectiveSubscriptionStatus(sub, now).wireName,
              'endsAt': (sub['endDate'] as DateTime?)
                  ?.toUtc()
                  .toIso8601String(),
              'trialEndsAt': (sub['trialEndDate'] as DateTime?)
                  ?.toUtc()
                  .toIso8601String(),
            },
    );
  }

  /// Throws 403 unless [feature] is enabled and the tenant may perform the
  /// operation ([write] operations need full access).
  Future<Entitlements> assertFeature(
    String tenantId,
    String feature, {
    bool write = false,
  }) async {
    final e = await forTenant(tenantId);
    if (e.accessLevel == AccessLevel.blocked || (write && !e.writesAllowed)) {
      throw ApiException.forbidden(
        'Your clinic account is restricted (${e.reason}).',
      );
    }
    if (e.features[feature] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include this feature.',
      );
    }
    return e;
  }

  /// Throws 403 when creating one more record would exceed [limitKey].
  Future<void> assertWithinLimit(
    String tenantId,
    String limitKey,
    int currentCount,
  ) async {
    final e = await forTenant(tenantId);
    if (e.accessLevel != AccessLevel.full) {
      throw ApiException.forbidden(
        'Your clinic account is restricted (${e.reason}).',
      );
    }
    final limit = e.limits[limitKey];
    if (limit != null && currentCount >= limit) {
      throw const ApiException.forbidden(
        'Your subscription limit has been reached.',
      );
    }
  }
}
