import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/ids.dart';
import '../audit/audit_service.dart';
import '../common/paging.dart';
import 'subscription_logic.dart';

/// Admin-controlled subscription lifecycle. No payment gateway is involved:
/// every change is an explicit, audited admin action.
class SubscriptionService {
  SubscriptionService(this._store, this._audit, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final DateTime Function() _clock;

  static const String collection = 'platform_subscriptions';

  DateTime get _now => _clock().toUtc();

  ApiException _notFound() =>
      const ApiException.notFound('Subscription not found.');

  SubscriptionStatus _status(Map<String, Object?> sub) =>
      SubscriptionStatus.tryParse(sub['status'] as String?) ??
      SubscriptionStatus.cancelled;

  CreateOp _history(
    String subId,
    String type,
    Actor actor, {
    SubscriptionStatus? from,
    SubscriptionStatus? to,
    String? reason,
    Map<String, Object?>? details,
  }) => CreateOp('$collection/$subId/history/${newId()}', {
    'type': type,
    'fromStatus': from?.wireName,
    'toStatus': to?.wireName,
    'reason': reason,
    'actorUid': actor.uid,
    'actorRole': actor.role,
    'details': details,
    'at': _now,
  });

  // ------------------------------------------------------------------ assign

  /// Creates the first (or a replacement, after expiry/cancellation)
  /// subscription for a tenant.
  Future<Map<String, Object?>> assign({
    required String tenantId,
    required String planId,
    required bool trial,
    DateTime? startDate,
    String? reason,
    required Actor actor,
    String? requestId,
  }) {
    return _store.transaction((tx) async {
      final tenant = await tx.get('tenants/$tenantId');
      if (tenant == null) {
        throw const ApiException.notFound('Tenant not found.');
      }
      if (tenant['status'] == TenantStatus.closed.wireName) {
        throw const ApiException.conflict('Tenant is closed.');
      }
      final currentId = tenant['subscriptionId'] as String?;
      if (currentId != null) {
        final current = await tx.get('$collection/$currentId');
        if (current != null && _status(current).isLive) {
          throw const ApiException.conflict(
            'Tenant already has a live subscription. Change its plan instead.',
          );
        }
      }
      final plan = await tx.get('subscription_plans/$planId');
      if (plan == null) throw const ApiException.notFound('Plan not found.');
      if (plan['status'] != PlanStatus.active.wireName) {
        throw const ApiException.conflict('Plan is not active.');
      }
      final trialDays = plan['trialDays']! as int;
      if (trial && trialDays <= 0) {
        throw const ApiException.conflict('This plan has no trial period.');
      }
      final now = _now;
      final start = (startDate ?? now).toUtc();
      if (start.isBefore(now.subtract(const Duration(days: 30))) ||
          start.isAfter(now.add(const Duration(days: 365)))) {
        throw const ApiException.badRequest(
          'startDate must be within 30 days in the past and one year ahead.',
        );
      }
      final interval = BillingInterval.tryParse(
        plan['billingInterval'] as String?,
      )!;
      final trialEnd = trial ? start.add(Duration(days: trialDays)) : null;
      final status = trial
          ? SubscriptionStatus.trial
          : SubscriptionStatus.active;
      final id = 'sub_${newId(length: 14)}';
      final doc = <String, Object?>{
        'subscriptionId': id,
        'tenantId': tenantId,
        'status': status.wireName,
        ...planSnapshot(plan),
        'startDate': start,
        'trialEndDate': trialEnd,
        'endDate': trial ? trialEnd : interval.periodEnd(start),
        'overrides': <String, Object?>{},
        'createdAt': now,
        'updatedAt': now,
        'createdBy': actor.uid,
        'updatedBy': actor.uid,
        'cancellationReason': null,
        'previousSubscriptionId': currentId,
      };
      tx.write([
        CreateOp('$collection/$id', doc),
        UpdateOp('tenants/$tenantId', {'subscriptionId': id, 'updatedAt': now}),
        _history(
          id,
          trial ? 'trial_started' : 'assigned',
          actor,
          to: status,
          reason: reason,
          details: {'planId': planId},
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: trial
                ? 'subscription.trial_started'
                : 'subscription.assigned',
            targetType: 'subscription',
            targetId: id,
            tenantId: tenantId,
            reason: reason,
            requestId: requestId,
            after: {
              'planId': planId,
              'planVersion': plan['version'],
              'status': status.wireName,
            },
          ),
        ),
      ]);
      return doc;
    });
  }

  // -------------------------------------------------------------- change plan

  /// Replaces the plan: the old subscription is closed (`cancelled`, reason
  /// `plan_changed`) and a new one with a fresh snapshot continues the same
  /// status and dates, so the old price/limits stay on record.
  Future<Map<String, Object?>> changePlan(
    String subId,
    String planId,
    Actor actor, {
    String? reason,
    String? requestId,
  }) {
    return _store.transaction((tx) async {
      final old = await tx.get('$collection/$subId');
      if (old == null) throw _notFound();
      final oldStatus = _status(old);
      if (!oldStatus.isLive && oldStatus != SubscriptionStatus.expired) {
        throw const ApiException.conflict(
          'A cancelled subscription cannot change plan.',
        );
      }
      if (old['planId'] == planId) {
        throw const ApiException.conflict(
          'Subscription already uses this plan.',
        );
      }
      final plan = await tx.get('subscription_plans/$planId');
      if (plan == null) throw const ApiException.notFound('Plan not found.');
      if (plan['status'] != PlanStatus.active.wireName) {
        throw const ApiException.conflict('Plan is not active.');
      }
      final now = _now;
      final newId_ = 'sub_${newId(length: 14)}';
      final doc = <String, Object?>{
        ...old,
        'subscriptionId': newId_,
        ...planSnapshot(plan),
        'overrides': old['overrides'] ?? <String, Object?>{},
        'createdAt': now,
        'updatedAt': now,
        'createdBy': actor.uid,
        'updatedBy': actor.uid,
        'previousSubscriptionId': subId,
      };
      final tenantId = old['tenantId']! as String;
      tx.write([
        CreateOp('$collection/$newId_', doc),
        UpdateOp('$collection/$subId', {
          'status': SubscriptionStatus.cancelled.wireName,
          'cancellationReason': 'plan_changed',
          'replacedBy': newId_,
          'updatedAt': now,
          'updatedBy': actor.uid,
        }),
        UpdateOp('tenants/$tenantId', {
          'subscriptionId': newId_,
          'updatedAt': now,
        }),
        _history(
          subId,
          'plan_changed_out',
          actor,
          from: oldStatus,
          to: SubscriptionStatus.cancelled,
          reason: reason,
          details: {'replacedBy': newId_},
        ),
        _history(
          newId_,
          'plan_changed_in',
          actor,
          to: oldStatus,
          reason: reason,
          details: {'fromPlanId': old['planId'], 'toPlanId': planId},
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'subscription.plan_changed',
            targetType: 'subscription',
            targetId: newId_,
            tenantId: tenantId,
            reason: reason,
            requestId: requestId,
            before: {
              'subscriptionId': subId,
              'planId': old['planId'],
              'priceMinor': old['priceMinor'],
            },
            after: {
              'planId': planId,
              'planVersion': plan['version'],
              'priceMinor': plan['priceMinor'],
            },
          ),
        ),
      ]);
      return doc;
    });
  }

  // --------------------------------------------------------------- overrides

  /// Replaces the entitlement overrides (an empty map clears them). The
  /// caller must hold `platform.entitlements.override`.
  Future<Map<String, Object?>> setOverrides(
    String subId,
    Map<String, Object?> overrides,
    Actor actor, {
    required String reason,
    String? requestId,
  }) {
    return _store.transaction((tx) async {
      final sub = await tx.get('$collection/$subId');
      if (sub == null) throw _notFound();
      final now = _now;
      tx.write([
        UpdateOp('$collection/$subId', {
          'overrides': overrides,
          'updatedAt': now,
          'updatedBy': actor.uid,
        }),
        _history(
          subId,
          'overrides_set',
          actor,
          reason: reason,
          details: {'overrides': overrides},
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'subscription.entitlements_overridden',
            targetType: 'subscription',
            targetId: subId,
            tenantId: sub['tenantId'] as String?,
            reason: reason,
            requestId: requestId,
            before: {'overrides': sub['overrides']},
            after: {'overrides': overrides},
          ),
        ),
      ]);
      return {...sub, 'overrides': overrides, 'updatedAt': now};
    });
  }

  // --------------------------------------------------------- status changes

  Future<Map<String, Object?>> _change(
    String subId,
    Actor actor, {
    required String type,
    SubscriptionStatus? to,
    String? reason,
    String? requestId,
    required Map<String, Object?> Function(
      Map<String, Object?> sub,
      DateTime now,
    )
    patchFor,
    void Function(Map<String, Object?> sub)? guard,
    bool allowSame = false,
  }) {
    return _store.transaction((tx) async {
      final sub = await tx.get('$collection/$subId');
      if (sub == null) throw _notFound();
      final from = _status(sub);
      guard?.call(sub);
      if (to != null &&
          !(allowSame && from == to) &&
          !from.canTransitionTo(to)) {
        throw ApiException.conflict(
          'A ${from.wireName} subscription cannot become ${to.wireName}.',
        );
      }
      final now = _now;
      final patch = {
        ...patchFor(sub, now),
        if (to != null) 'status': to.wireName,
        'updatedAt': now,
        'updatedBy': actor.uid,
      };
      tx.write([
        UpdateOp('$collection/$subId', patch),
        _history(
          subId,
          type,
          actor,
          from: from,
          to: to ?? from,
          reason: reason,
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'subscription.$type',
            targetType: 'subscription',
            targetId: subId,
            tenantId: sub['tenantId'] as String?,
            reason: reason,
            requestId: requestId,
            before: {'status': from.wireName, 'endDate': sub['endDate']},
            after: {
              'status': (to ?? from).wireName,
              'endDate': patch['endDate'] ?? sub['endDate'],
            },
          ),
        ),
      ]);
      return {...sub, ...patch};
    });
  }

  Future<Map<String, Object?>> extendTrial(
    String subId,
    int days,
    Actor actor, {
    required String reason,
    String? requestId,
  }) => _change(
    subId,
    actor,
    type: 'trial_extended',
    reason: reason,
    requestId: requestId,
    guard: (sub) {
      if (_status(sub) != SubscriptionStatus.trial) {
        throw const ApiException.conflict(
          'Only a trial subscription can be extended.',
        );
      }
    },
    patchFor: (sub, now) {
      final current = (sub['trialEndDate'] ?? sub['endDate']) as DateTime;
      final base = current.isAfter(now) ? current : now;
      final end = base.add(Duration(days: days));
      return {'trialEndDate': end, 'endDate': end};
    },
  );

  Future<Map<String, Object?>> renew(
    String subId,
    Actor actor, {
    String? reason,
    String? requestId,
  }) => _change(
    subId,
    actor,
    type: 'renewed',
    to: SubscriptionStatus.active,
    allowSame: true, // early renewal of a running period
    reason: reason,
    requestId: requestId,
    patchFor: (sub, now) {
      final end = sub['endDate'] as DateTime;
      final from = _status(sub);
      // Renewing a still-running paid period extends it; otherwise start now.
      final start =
          (from == SubscriptionStatus.active ||
                  from == SubscriptionStatus.pastDue) &&
              end.isAfter(now)
          ? end
          : now;
      final interval = BillingInterval.tryParse(
        sub['billingInterval'] as String?,
      )!;
      return {
        'endDate': interval.periodEnd(start),
        if (start == now) 'startDate': now,
      };
    },
  );

  Future<Map<String, Object?>> markPastDue(
    String subId,
    Actor actor, {
    String? reason,
    String? requestId,
  }) => _change(
    subId,
    actor,
    type: 'marked_past_due',
    to: SubscriptionStatus.pastDue,
    reason: reason,
    requestId: requestId,
    patchFor: (_, _) => {},
  );

  Future<Map<String, Object?>> suspend(
    String subId,
    Actor actor, {
    required String reason,
    String? requestId,
  }) => _change(
    subId,
    actor,
    type: 'suspended',
    to: SubscriptionStatus.suspended,
    reason: reason,
    requestId: requestId,
    patchFor: (_, _) => {},
  );

  Future<Map<String, Object?>> cancel(
    String subId,
    Actor actor, {
    required String reason,
    String? requestId,
  }) => _change(
    subId,
    actor,
    type: 'cancelled',
    to: SubscriptionStatus.cancelled,
    reason: reason,
    requestId: requestId,
    patchFor: (_, _) => {'cancellationReason': reason},
  );

  // ------------------------------------------------------------------ reads

  Future<Map<String, Object?>?> find(String subId) =>
      _store.get('$collection/$subId');

  Future<Map<String, Object?>> detail(String subId) async {
    final sub = await find(subId);
    if (sub == null) throw _notFound();
    final history = await _store.query(
      DocQuery(
        '$collection/$subId/history',
        orderBy: const OrderBy('at', descending: true),
        limit: 100,
      ),
    );
    final tenant = await _store.get('tenants/${sub['tenantId']}');
    return {
      ...sub,
      'effectiveStatus': effectiveSubscriptionStatus(sub, _now).wireName,
      'clinicName': tenant?['clinicName'],
      'history': history.map((h) => {'id': h.id, ...h.data}).toList(),
    };
  }

  Future<Paged> list(
    Request request, {
    SubscriptionStatus? status,
    String? tenantId,
    String? planId,
  }) => runPaged(
    _store,
    DocQuery(
      collection,
      filters: [
        if (status != null) QueryFilter('status', FilterOp.eq, status.wireName),
        if (tenantId != null) QueryFilter('tenantId', FilterOp.eq, tenantId),
        if (planId != null) QueryFilter('planId', FilterOp.eq, planId),
      ],
      orderBy: const OrderBy('createdAt', descending: true),
    ),
    request,
  );
}
