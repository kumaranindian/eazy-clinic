import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/ids.dart';
import '../applications/application_service.dart';
import '../audit/audit_service.dart';
import '../common/paging.dart';
import '../subscriptions/subscription_logic.dart';
import '../subscriptions/subscription_service.dart';

/// Outcome of an approval / provisioning attempt.
class ProvisioningResult {
  const ProvisioningResult({
    required this.applicationId,
    required this.tenantId,
    required this.tenantStatus,
    required this.completed,
    this.failureCode,
  });

  final String applicationId;
  final String tenantId;
  final TenantStatus tenantStatus;
  final bool completed;
  final String? failureCode;

  Map<String, Object?> toJson() => {
    'applicationId': applicationId,
    'tenantId': tenantId,
    'tenantStatus': tenantStatus.wireName,
    'provisioningComplete': completed,
    if (failureCode != null) 'failureCode': failureCode,
  };
}

const Set<String> _reservedSlugs = {
  'admin',
  'api',
  'app',
  'www',
  'platform',
  'support',
  'login',
  'register',
  'eazyclinic',
  'static',
  'assets',
  'health',
  'null',
  'undefined',
};

String slugify(String name) {
  var s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 40) s = s.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  return s.length < 3 ? 'clinic' : s;
}

/// Tenant provisioning and lifecycle.
///
/// Provisioning is two atomic phases so a crash can never leave a half-built
/// tenant that looks active:
///
/// * **Phase A** (one atomic commit): application → `approved`, tenant created
///   as `provisioning`, slug reserved, provisioning job created, audit.
///   Ids are deterministic from the application id and every document is
///   created with a does-not-exist precondition, so repeated or concurrent
///   approvals cannot create a second tenant.
/// * **Phase B** (idempotent steps): owner membership, optional initial
///   subscription, then tenant → `active` and job → `completed`. A failure is
///   recorded on the job (`failed`) and the tenant stays `provisioning`; an
///   authorized admin retries with [retryProvisioning].
class TenantService {
  TenantService(
    this._store,
    this._audit,
    this._subscriptions, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final SubscriptionService _subscriptions;
  final DateTime Function() _clock;

  static const String collection = 'tenants';
  static const String jobs = 'tenant_provisioning_jobs';

  DateTime get _now => _clock().toUtc();

  /// Deterministic tenant id for an application id (`app_x` → `ten_x`).
  static String tenantIdFor(String applicationId) =>
      'ten_${applicationId.substring(4)}';

  // ---------------------------------------------------------------- approve

  Future<ProvisioningResult> approve({
    required String applicationId,
    required Actor actor,
    String? initialPlanId,
    bool startTrial = false,
    String? note,
    String? requestId,
  }) async {
    if (!applicationId.startsWith('app_') || applicationId.length < 8) {
      throw const ApiException.notFound('Application not found.');
    }
    final tenantId = tenantIdFor(applicationId);
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await _store.transaction((tx) async {
          final app = await tx.get(
            '${ApplicationService.collection}/$applicationId',
          );
          if (app == null) {
            throw const ApiException.notFound('Application not found.');
          }
          final from = ApplicationService.statusOf(app);
          if (from == ApplicationStatus.approved) return; // idempotent repeat
          if (!from.canTransitionTo(ApplicationStatus.approved)) {
            throw ApiException.conflict(
              'A ${from.wireName} application cannot be approved.',
            );
          }
          if (app['applicantUid'] == actor.uid) {
            throw const ApiException.forbidden(
              'You cannot approve your own application.',
            );
          }
          if (initialPlanId != null) {
            final plan = await tx.get('subscription_plans/$initialPlanId');
            if (plan == null || plan['status'] != PlanStatus.active.wireName) {
              throw const ApiException.conflict(
                'The selected plan is not active.',
              );
            }
            if (startTrial && (plan['trialDays']! as int) <= 0) {
              throw const ApiException.conflict(
                'The selected plan has no trial period.',
              );
            }
          }
          final clinic = (app['clinic']! as Map).cast<String, Object?>();
          final slug = await _chooseSlug(
            tx,
            clinic['name']! as String,
            applicationId,
          );
          final now = _now;
          tx.write([
            UpdateOp('${ApplicationService.collection}/$applicationId', {
              'status': ApplicationStatus.approved.wireName,
              'tenantId': tenantId,
              'reviewedBy': actor.uid,
              'reviewedAt': now,
              'decidedAt': now,
              'updatedAt': now,
            }),
            CreateOp('$collection/$tenantId', {
              'tenantId': tenantId,
              'clinicName': clinic['name'],
              'clinicNameLower': '${clinic['name']}'.toLowerCase(),
              'slug': slug,
              'ownerUid': app['applicantUid'],
              'applicationId': applicationId,
              'status': TenantStatus.provisioning.wireName,
              'clinicType': clinic['type'],
              'city': (app['address'] as Map?)?['city'],
              'createdAt': now,
              'updatedAt': now,
              'approvedAt': now,
              'approvedBy': actor.uid,
              'subscriptionId': null,
              'configurationVersion': 1,
              'statusReason': null,
            }),
            CreateOp('tenant_slugs/$slug', {
              'tenantId': tenantId,
              'createdAt': now,
            }),
            CreateOp('$jobs/$tenantId', {
              'tenantId': tenantId,
              'applicationId': applicationId,
              'status': 'pending',
              'attempts': 0,
              'initialPlanId': initialPlanId,
              'startTrial': startTrial,
              'steps': {
                'membership': false,
                'subscription': initialPlanId == null,
              },
              'lastError': null,
              'createdAt': now,
              'updatedAt': now,
              'startedBy': actor.uid,
            }),
            CreateOp(
              '${ApplicationService.collection}/$applicationId/history/${newId()}',
              {
                'fromStatus': from.wireName,
                'toStatus': 'approved',
                'actorUid': actor.uid,
                'actorRole': actor.role,
                'reason': note,
                'at': now,
              },
            ),
            _audit.op(
              AuditEntry(
                actor: actor,
                action: 'application.approved',
                targetType: 'clinic_application',
                targetId: applicationId,
                tenantId: tenantId,
                reason: note,
                requestId: requestId,
                before: {'status': from.wireName},
                after: {'status': 'approved', 'tenantId': tenantId},
              ),
            ),
            _audit.op(
              AuditEntry(
                actor: actor,
                action: 'tenant.created',
                targetType: 'tenant',
                targetId: tenantId,
                tenantId: tenantId,
                requestId: requestId,
                after: {'status': 'provisioning', 'slug': slug},
              ),
            ),
          ]);
        });
        break;
      } on AlreadyExistsException {
        // Lost a race on the slug or tenant id: re-evaluate from fresh state.
        if (attempt == 4) {
          throw const ApiException.conflict(
            'Could not reserve a clinic address. Please retry.',
          );
        }
      }
    }
    return _complete(applicationId, tenantId, actor, requestId: requestId);
  }

  Future<String> _chooseSlug(
    TxContext tx,
    String name,
    String applicationId,
  ) async {
    final base = _reservedSlugs.contains(slugify(name))
        ? 'clinic-${slugify(name)}'
        : slugify(name);
    final tail = applicationId
        .substring(4)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final candidates = [
      base,
      '$base-${tail.substring(0, 4)}',
      '$base-${tail.substring(0, 8)}',
    ];
    for (final c in candidates) {
      if (await tx.get('tenant_slugs/$c') == null) return c;
    }
    throw const ApiException.conflict('Could not reserve a clinic address.');
  }

  // ----------------------------------------------------------- provisioning

  /// Phase B. Safe to call any number of times.
  Future<ProvisioningResult> _complete(
    String applicationId,
    String tenantId,
    Actor actor, {
    String? requestId,
  }) async {
    final tenant = await _store.get('$collection/$tenantId');
    if (tenant == null) throw const ApiException.notFound('Tenant not found.');
    final current = TenantStatus.tryParse(tenant['status'] as String?)!;
    if (current != TenantStatus.provisioning) {
      return ProvisioningResult(
        applicationId: applicationId,
        tenantId: tenantId,
        tenantStatus: current,
        completed: current == TenantStatus.active,
      );
    }
    final job = (await _store.get('$jobs/$tenantId'))!;
    try {
      // 1. Owner membership (trusted, server-created).
      final ownerUid = tenant['ownerUid']! as String;
      final memberPath = '$collection/$tenantId/members/$ownerUid';
      if (await _store.get(memberPath) == null) {
        try {
          await _store.commit([
            CreateOp(memberPath, {
              'uid': ownerUid,
              'role': ClinicRole.clinicOwner.wireName,
              'status': 'active',
              'branchIds': <String>[],
              'permissionOverrides': <String, Object?>{},
              'source': 'application_approval',
              'createdAt': _now,
              'createdBy': actor.uid,
            }),
            _audit.op(
              AuditEntry(
                actor: actor,
                action: 'tenant.owner_membership_created',
                targetType: 'tenant',
                targetId: tenantId,
                tenantId: tenantId,
                requestId: requestId,
                after: {'role': 'clinic_owner'},
              ),
            ),
          ]);
        } on AlreadyExistsException {
          // created by a concurrent attempt
        }
      }
      await _store.commit([
        UpdateOp('$jobs/$tenantId', {
          'steps': {
            ...((job['steps'] as Map?)?.cast<String, Object?>() ?? const {}),
            'membership': true,
          },
          'updatedAt': _now,
        }),
      ]);

      // 2. Optional initial subscription.
      final planId = job['initialPlanId'] as String?;
      if (planId != null && tenant['subscriptionId'] == null) {
        try {
          await _subscriptions.assign(
            tenantId: tenantId,
            planId: planId,
            trial: job['startTrial'] == true,
            reason: 'initial subscription at approval',
            actor: actor,
            requestId: requestId,
          );
        } on ApiException catch (e) {
          // Already assigned by an earlier attempt is fine; anything else fails.
          final fresh = await _store.get('$collection/$tenantId');
          if (fresh?['subscriptionId'] == null) rethrow;
          if (e.code.httpStatus != 409) rethrow;
        }
      }

      // 3. Activate only after every step succeeded.
      final now = _now;
      await _store.transaction((tx) async {
        final t = (await tx.get('$collection/$tenantId'))!;
        if (t['status'] != TenantStatus.provisioning.wireName) return;
        tx.write([
          UpdateOp('$collection/$tenantId', {
            'status': TenantStatus.active.wireName,
            'updatedAt': now,
          }),
          UpdateOp('$jobs/$tenantId', {
            'status': 'completed',
            'lastError': null,
            'updatedAt': now,
          }),
          _audit.op(
            AuditEntry(
              actor: actor,
              action: 'tenant.activated',
              targetType: 'tenant',
              targetId: tenantId,
              tenantId: tenantId,
              requestId: requestId,
              before: {'status': 'provisioning'},
              after: {'status': 'active'},
            ),
          ),
        ]);
      });
      return ProvisioningResult(
        applicationId: applicationId,
        tenantId: tenantId,
        tenantStatus: TenantStatus.active,
        completed: true,
      );
    } on Object catch (e) {
      final code = e is ApiException
          ? e.code.wireName
          : e.runtimeType.toString();
      await _recordFailure(tenantId, job, actor, code, requestId);
      return ProvisioningResult(
        applicationId: applicationId,
        tenantId: tenantId,
        tenantStatus: TenantStatus.provisioning,
        completed: false,
        failureCode: code,
      );
    }
  }

  Future<void> _recordFailure(
    String tenantId,
    Map<String, Object?> job,
    Actor actor,
    String code,
    String? requestId,
  ) async {
    try {
      await _store.commit([
        UpdateOp('$jobs/$tenantId', {
          'status': 'failed',
          'lastError': code,
          'attempts': ((job['attempts'] as int?) ?? 0) + 1,
          'updatedAt': _now,
        }),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'tenant.provisioning_failed',
            targetType: 'tenant',
            targetId: tenantId,
            tenantId: tenantId,
            requestId: requestId,
            reason: code,
          ),
        ),
      ]);
    } on Object {
      // Nothing more can be done; the tenant stays `provisioning`.
    }
  }

  Future<ProvisioningResult> retryProvisioning(
    String tenantId,
    Actor actor, {
    String? requestId,
  }) async {
    final tenant = await _store.get('$collection/$tenantId');
    if (tenant == null) throw const ApiException.notFound('Tenant not found.');
    if (tenant['status'] != TenantStatus.provisioning.wireName) {
      throw const ApiException.conflict(
        'Only a tenant that is still provisioning can be retried.',
      );
    }
    await _audit.record(
      AuditEntry(
        actor: actor,
        action: 'tenant.provisioning_retried',
        targetType: 'tenant',
        targetId: tenantId,
        tenantId: tenantId,
        requestId: requestId,
      ),
    );
    return _complete(
      tenant['applicationId']! as String,
      tenantId,
      actor,
      requestId: requestId,
    );
  }

  // -------------------------------------------------------------- lifecycle

  Future<Map<String, Object?>> _transition(
    String tenantId,
    Actor actor, {
    required TenantStatus to,
    required String reason,
    required String action,
    String? requestId,
    Future<void> Function(
      TxContext tx,
      Map<String, Object?> tenant,
      List<WriteOp> out,
    )?
    extra,
  }) {
    return _store.transaction((tx) async {
      final tenant = await tx.get('$collection/$tenantId');
      if (tenant == null) {
        throw const ApiException.notFound('Tenant not found.');
      }
      final from = TenantStatus.tryParse(tenant['status'] as String?)!;
      if (!from.canTransitionTo(to)) {
        throw ApiException.conflict(
          'A ${from.wireName} tenant cannot become ${to.wireName}.',
        );
      }
      final now = _now;
      final out = <WriteOp>[];
      await extra?.call(tx, tenant, out);
      final patch = {
        'status': to.wireName,
        'statusReason': reason,
        'statusChangedAt': now,
        'statusChangedBy': actor.uid,
        'updatedAt': now,
      };
      tx.write([
        UpdateOp('$collection/$tenantId', patch),
        ...out,
        _audit.op(
          AuditEntry(
            actor: actor,
            action: action,
            targetType: 'tenant',
            targetId: tenantId,
            tenantId: tenantId,
            reason: reason,
            requestId: requestId,
            before: {'status': from.wireName},
            after: {'status': to.wireName},
          ),
        ),
      ]);
      return {...tenant, ...patch};
    });
  }

  Future<Map<String, Object?>> suspend(
    String tenantId,
    String reason,
    Actor actor, {
    String? requestId,
  }) => _transition(
    tenantId,
    actor,
    to: TenantStatus.suspended,
    reason: reason,
    action: 'tenant.suspended',
    requestId: requestId,
  );

  /// Reactivation re-checks eligibility; a subscription change alone never
  /// reactivates a tenant.
  Future<Map<String, Object?>> reactivate(
    String tenantId,
    String reason,
    Actor actor, {
    String? requestId,
  }) => _transition(
    tenantId,
    actor,
    to: TenantStatus.active,
    reason: reason,
    action: 'tenant.reactivated',
    requestId: requestId,
    extra: (tx, tenant, out) async {
      final owner = await tx.get(
        '$collection/$tenantId/members/${tenant['ownerUid']}',
      );
      if (owner == null || owner['status'] != 'active') {
        throw const ApiException.conflict(
          'The tenant has no active owner membership.',
        );
      }
      final subId = tenant['subscriptionId'] as String?;
      final sub = subId == null
          ? null
          : await tx.get('${SubscriptionService.collection}/$subId');
      final eff = sub == null ? null : effectiveSubscriptionStatus(sub, _now);
      const ok = {
        SubscriptionStatus.trial,
        SubscriptionStatus.active,
        SubscriptionStatus.pastDue,
      };
      if (eff == null || !ok.contains(eff)) {
        throw const ApiException.conflict(
          'The tenant needs a valid (trial, active or past due) subscription before it can be reactivated.',
        );
      }
    },
  );

  /// Closes the tenant. Data is preserved (no deletion); any live subscription
  /// is cancelled in the same atomic commit.
  Future<Map<String, Object?>> close(
    String tenantId,
    String reason,
    Actor actor, {
    String? requestId,
  }) => _transition(
    tenantId,
    actor,
    to: TenantStatus.closed,
    reason: reason,
    action: 'tenant.closed',
    requestId: requestId,
    extra: (tx, tenant, out) async {
      final subId = tenant['subscriptionId'] as String?;
      if (subId == null) return;
      final sub = await tx.get('${SubscriptionService.collection}/$subId');
      final status = SubscriptionStatus.tryParse(sub?['status'] as String?);
      if (sub != null &&
          status != null &&
          status.canTransitionTo(SubscriptionStatus.cancelled)) {
        final now = _now;
        out.addAll([
          UpdateOp('${SubscriptionService.collection}/$subId', {
            'status': 'cancelled',
            'cancellationReason': 'tenant_closed',
            'updatedAt': now,
            'updatedBy': actor.uid,
          }),
          CreateOp(
            '${SubscriptionService.collection}/$subId/history/${newId()}',
            {
              'type': 'cancelled',
              'fromStatus': status.wireName,
              'toStatus': 'cancelled',
              'reason': 'tenant_closed',
              'actorUid': actor.uid,
              'actorRole': actor.role,
              'at': now,
            },
          ),
        ]);
      }
    },
  );

  // ------------------------------------------------------------------ reads

  Future<Paged> list(Request request, {TenantStatus? status, String? q}) {
    final query = q?.trim().toLowerCase();
    if (query != null && query.isNotEmpty) {
      return runPaged(
        _store,
        DocQuery(
          collection,
          filters: [
            if (status != null)
              QueryFilter('status', FilterOp.eq, status.wireName),
            QueryFilter('clinicNameLower', FilterOp.gte, query),
            QueryFilter('clinicNameLower', FilterOp.lt, '$query'),
          ],
          orderBy: const OrderBy('clinicNameLower'),
        ),
        request,
      );
    }
    return runPaged(
      _store,
      DocQuery(
        collection,
        filters: [
          if (status != null)
            QueryFilter('status', FilterOp.eq, status.wireName),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      request,
    );
  }

  Future<Map<String, Object?>> detail(String tenantId) async {
    final tenant = await _store.get('$collection/$tenantId');
    if (tenant == null) throw const ApiException.notFound('Tenant not found.');
    final app = await _store.get(
      '${ApplicationService.collection}/${tenant['applicationId']}',
    );
    final subId = tenant['subscriptionId'] as String?;
    final sub = subId == null
        ? null
        : await _store.get('${SubscriptionService.collection}/$subId');
    final job = await _store.get('$jobs/$tenantId');
    return {
      ...jsonSafe(tenant)! as Map<String, Object?>,
      'owner': app == null
          ? null
          : {
              'fullName': (app['owner'] as Map?)?['fullName'],
              'email': (app['owner'] as Map?)?['email'],
              'phone': (app['owner'] as Map?)?['phone'],
            },
      'application': app == null
          ? null
          : {
              'applicationId': app['applicationId'],
              'status': app['status'],
              'submittedAt': jsonSafe(app['submittedAt']),
            },
      'subscription': sub == null
          ? null
          : {
              ...jsonSafe(sub)! as Map<String, Object?>,
              'effectiveStatus': effectiveSubscriptionStatus(
                sub,
                _now,
              ).wireName,
            },
      'provisioning': job == null ? null : jsonSafe(job),
      'auditHistory': await _audit.recent(20, tenantId: tenantId),
    };
  }
}
