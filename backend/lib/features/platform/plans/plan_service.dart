import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/ids.dart';
import '../audit/audit_service.dart';
import '../common/body_reader.dart';
import '../common/paging.dart';

/// Validated plan input. Null fields mean "not provided" (PATCH).
class PlanInput {
  const PlanInput({
    this.name,
    this.description,
    this.interval,
    this.priceMinor,
    this.currency,
    this.trialDays,
    this.limits,
    this.features,
  });

  final String? name;
  final String? description;
  final BillingInterval? interval;
  final int? priceMinor;
  final String? currency;
  final int? trialDays;
  final Map<String, int?>? limits;
  final Map<String, bool>? features;

  static const Set<String> fields = {
    'name',
    'description',
    'billingInterval',
    'priceMinor',
    'currency',
    'trialDays',
    'limits',
    'features',
  };

  /// Parses and validates [body]. On create ([partial] false) every field
  /// except `description` is required, including all four limit keys (use
  /// `null` for "unlimited" so a forgotten limit is never unlimited by default).
  static PlanInput parse(Map<String, Object?> body, {required bool partial}) {
    final r = BodyReader(body, partial: partial)..rejectUnknown(fields);
    final name = r.str('name', min: 2, max: 80);
    final description = r.str('description', min: 0, max: 500, required: false);
    final interval = r.enumOf(
      'billingInterval',
      BillingInterval.values,
      (e) => e.wireName,
    );
    final price = r.integer('priceMinor', min: 0, max: 100000000);
    final currency = r.str('currency', min: 3, max: 3);
    if (currency != null && currency != 'INR') {
      r.addIssue('currency', 'unsupported', 'Only INR is supported.');
    }
    final trial = r.integer('trialDays', min: 0, max: 365);

    Map<String, int?>? limits;
    if (body.containsKey('limits')) {
      final raw = body['limits'];
      if (raw is! Map) {
        r.addIssue('limits', 'invalid_type', 'limits must be an object.');
      } else {
        limits = {};
        for (final k in raw.keys) {
          if (!LimitKey.all.contains(k)) {
            r.addIssue('limits.$k', 'not_allowed', 'Unknown limit.');
          }
        }
        for (final k in LimitKey.all) {
          if (!raw.containsKey(k)) {
            if (!partial) {
              r.addIssue(
                'limits.$k',
                'required',
                '$k is required (null = unlimited).',
              );
            }
            continue;
          }
          final v = raw[k];
          if (v == null) {
            limits[k] = null;
          } else if (v is int && v >= 0 && v <= 1000000) {
            limits[k] = v;
          } else {
            r.addIssue(
              'limits.$k',
              'out_of_range',
              '$k must be null or a whole number up to 1000000.',
            );
          }
        }
      }
    } else if (!partial) {
      r.addIssue('limits', 'required', 'limits is required.');
    }

    Map<String, bool>? features;
    if (body.containsKey('features')) {
      final raw = body['features'];
      if (raw is! Map) {
        r.addIssue('features', 'invalid_type', 'features must be an object.');
      } else {
        features = {};
        for (final e in raw.entries) {
          if (!FeatureKey.all.contains(e.key)) {
            r.addIssue('features.${e.key}', 'not_allowed', 'Unknown feature.');
          } else if (e.value is! bool) {
            r.addIssue(
              'features.${e.key}',
              'invalid_type',
              'Must be true or false.',
            );
          } else {
            features[e.key as String] = e.value as bool;
          }
        }
      }
    } else if (!partial) {
      r.addIssue('features', 'required', 'features is required.');
    }
    r.throwIfInvalid();
    return PlanInput(
      name: name,
      description: description,
      interval: interval,
      priceMinor: price,
      currency: currency,
      trialDays: trial,
      limits: limits,
      features: features,
    );
  }
}

/// Subscription plan catalogue. Every change creates an immutable version
/// snapshot (`subscription_plans/{id}/versions/{n}`), and subscriptions copy
/// the plan at assignment, so editing a plan never rewrites history.
class PlanService {
  PlanService(this._store, this._audit, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final DateTime Function() _clock;

  static const String collection = 'subscription_plans';
  static const List<String> liveStatuses = [
    'trial',
    'active',
    'past_due',
    'suspended',
  ];

  Future<Map<String, Object?>> create(
    PlanInput input,
    Actor actor, {
    String? requestId,
  }) async {
    final now = _clock().toUtc();
    final id = 'plan_${newId(length: 12)}';
    final doc = <String, Object?>{
      'planId': id,
      'name': input.name,
      'description': input.description ?? '',
      'billingInterval': input.interval!.wireName,
      'priceMinor': input.priceMinor,
      'currency': input.currency,
      'trialDays': input.trialDays,
      'limits': {for (final k in LimitKey.all) k: input.limits![k]},
      'features': {
        for (final k in FeatureKey.all) k: input.features![k] ?? false,
      },
      'status': PlanStatus.inactive.wireName, // activated explicitly
      'version': 1,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': actor.uid,
      'updatedBy': actor.uid,
    };
    await _store.commit([
      CreateOp('$collection/$id', doc),
      CreateOp('$collection/$id/versions/1', {...doc, 'snapshotAt': now}),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: 'plan.created',
          targetType: 'subscription_plan',
          targetId: id,
          requestId: requestId,
          after: {
            'name': input.name,
            'priceMinor': input.priceMinor,
            'version': 1,
          },
        ),
      ),
    ]);
    return doc;
  }

  Future<Map<String, Object?>> update(
    String planId,
    PlanInput input,
    Actor actor, {
    String? requestId,
  }) {
    return _store.transaction((tx) async {
      final plan = await tx.get('$collection/$planId');
      if (plan == null) throw const ApiException.notFound('Plan not found.');
      final changes = <String, Object?>{
        if (input.name != null) 'name': input.name,
        if (input.description != null) 'description': input.description,
        if (input.interval != null) 'billingInterval': input.interval!.wireName,
        if (input.priceMinor != null) 'priceMinor': input.priceMinor,
        if (input.currency != null) 'currency': input.currency,
        if (input.trialDays != null) 'trialDays': input.trialDays,
        if (input.limits != null)
          'limits': {
            ...(plan['limits']! as Map).cast<String, Object?>(),
            ...input.limits!,
          },
        if (input.features != null)
          'features': {
            ...(plan['features']! as Map).cast<String, Object?>(),
            ...input.features!,
          },
      };
      if (changes.isEmpty) {
        throw const ApiException.badRequest('No plan fields to update.');
      }
      final now = _clock().toUtc();
      final version = (plan['version']! as int) + 1;
      final patch = {
        ...changes,
        'version': version,
        'updatedAt': now,
        'updatedBy': actor.uid,
      };
      final next = {...plan, ...patch};
      tx.write([
        UpdateOp('$collection/$planId', patch),
        CreateOp('$collection/$planId/versions/$version', {
          ...next,
          'snapshotAt': now,
        }),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'plan.updated',
            targetType: 'subscription_plan',
            targetId: planId,
            requestId: requestId,
            before: {
              'version': plan['version'],
              'priceMinor': plan['priceMinor'],
            },
            after: {
              'version': version,
              'priceMinor': next['priceMinor'],
              'fields': changes.keys.toList(),
            },
          ),
        ),
      ]);
      return next;
    });
  }

  Future<Map<String, Object?>> setStatus(
    String planId,
    PlanStatus to,
    Actor actor, {
    String? requestId,
  }) {
    return _store.transaction((tx) async {
      final plan = await tx.get('$collection/$planId');
      if (plan == null) throw const ApiException.notFound('Plan not found.');
      if (plan['status'] == to.wireName) {
        throw ApiException.conflict('Plan is already ${to.wireName}.');
      }
      if (to == PlanStatus.inactive) {
        final inUse = await tx.query(
          DocQuery(
            'platform_subscriptions',
            filters: [
              QueryFilter('planId', FilterOp.eq, planId),
              const QueryFilter('status', FilterOp.inList, liveStatuses),
            ],
            limit: 1,
          ),
        );
        if (inUse.isNotEmpty) {
          throw const ApiException.conflict(
            'Plan has live subscriptions. Move those tenants to another plan before deactivating it.',
          );
        }
      }
      final now = _clock().toUtc();
      final patch = {
        'status': to.wireName,
        'updatedAt': now,
        'updatedBy': actor.uid,
      };
      tx.write([
        UpdateOp('$collection/$planId', patch),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: to == PlanStatus.active
                ? 'plan.activated'
                : 'plan.deactivated',
            targetType: 'subscription_plan',
            targetId: planId,
            requestId: requestId,
            before: {'status': plan['status']},
            after: {'status': to.wireName},
          ),
        ),
      ]);
      return {...plan, ...patch};
    });
  }

  Future<Map<String, Object?>?> find(String planId) =>
      _store.get('$collection/$planId');

  Future<Paged> list(Request request, {PlanStatus? status}) => runPaged(
    _store,
    DocQuery(
      collection,
      filters: [
        if (status != null) QueryFilter('status', FilterOp.eq, status.wireName),
      ],
      orderBy: const OrderBy('createdAt', descending: true),
    ),
    request,
  );

  /// Plan plus the tenants currently assigned to it (live subscriptions).
  Future<Map<String, Object?>> detail(String planId) async {
    final plan = await find(planId);
    if (plan == null) throw const ApiException.notFound('Plan not found.');
    final subs = await _store.query(
      DocQuery(
        'platform_subscriptions',
        filters: [
          QueryFilter('planId', FilterOp.eq, planId),
          const QueryFilter('status', FilterOp.inList, liveStatuses),
        ],
        limit: 50,
      ),
    );
    final assigned = <Map<String, Object?>>[];
    for (final s in subs) {
      final tenant = await _store.get('tenants/${s.data['tenantId']}');
      assigned.add({
        'tenantId': s.data['tenantId'],
        'clinicName': tenant?['clinicName'],
        'subscriptionId': s.id,
        'subscriptionStatus': s.data['status'],
      });
    }
    return {...plan, 'assignedTenants': assigned};
  }
}
