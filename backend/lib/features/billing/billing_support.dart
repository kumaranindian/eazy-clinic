import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/patient_support.dart';
import '../platform/common/body_reader.dart';
import '../portal/portal_notifier.dart';
import '../scheduling/scheduling_support.dart';
import '../scheduling/time_support.dart';

FieldIssue billingIssue(String f, String code, String m) =>
    FieldIssue(field: f, code: code, message: m);

/// Minor-unit exponent per currency (INR: 2, so 1 rupee = 100 paise).
const Map<String, int> currencyExponent = {'INR': 2, 'AED': 2};

const List<String> paymentMethods = [
  'cash',
  'upi',
  'card',
  'bank_transfer',
  'cheque',
];

/// A request key plus the fingerprint of the request body it belongs to.
class Idem {
  const Idem(this.path, this.fingerprint);
  final String path;
  final String fingerprint;
}

/// Shared rules of the billing services: scope, currency, settings, audit,
/// idempotency and concurrency-safe numbering.
class BillingSupport {
  BillingSupport(this.d, this.patients, this.sched);

  final ClinicDeps d;
  final PatientSupport patients;
  final SchedulingSupport sched;

  /// Set by the clinic module so billing events can reach the patient app.
  PortalNotifier? notifier;

  String path(TenantContext t, String collection, [String? id]) =>
      d.path(t, collection, id);

  /// The plan must include billing.
  void requireFeature(TenantContext t) {
    if (t.entitlements.features[FeatureKey.billing] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include billing.',
      );
    }
  }

  /// Currency of the clinic (explicit on every record; INR by default).
  Future<String> currency(TenantContext t) async {
    final s = await d.store.get(path(t, 'clinic_settings', 'operations'));
    final c = s?['currency'] as String?;
    return c != null && currencyExponent.containsKey(c) ? c : 'INR';
  }

  Future<ClinicZone> zone(TenantContext t) async {
    final s = await d.store.get(path(t, 'clinic_settings', 'operations'));
    return ClinicZone.resolve(s?['timezone'] as String?);
  }

  static const Map<String, Object?> defaultSettings = {
    'invoiceDueDays': 7,
    'customPaymentMethods': <Object?>[],
    // Highest discount (basis points of the invoice subtotal) a role may give.
    'discountLimitsBps': {
      'clinic_owner': 10000,
      'clinic_admin': 10000,
      'accountant': 1000,
    },
    // Largest expense (minor units) a role may approve; absent = no limit.
    'expenseApprovalLimits': <String, Object?>{},
    'allowSelfApproval': false,
  };

  Future<DocData> settings(TenantContext t, {TxContext? tx}) async {
    final p = path(t, 'billing_settings', 'main');
    final s = tx == null ? await d.store.get(p) : await tx.get(p);
    return {...defaultSettings, ...?s};
  }

  Future<List<String>> allowedMethods(TenantContext t) async {
    final s = await settings(t);
    return [
      ...paymentMethods,
      for (final m in (s['customPaymentMethods'] as List? ?? const [])) '$m',
    ];
  }

  Future<DocData> branch(TenantContext t, String branchId) =>
      sched.branch(t, branchId);

  /// Branch the caller may act in; null (clinic-wide) needs all-branch access.
  void requireBranchOrClinicWide(TenantContext t, String? branchId) {
    if (branchId == null) {
      if (!t.scope.allBranches) {
        throw const ApiException.forbidden(
          'Clinic-wide records need all-branch access.',
        );
      }
    } else {
      t.scope.require(branchId);
    }
  }

  /// Filters that keep a list inside the caller's branches.
  List<QueryFilter> scopeFilters(TenantContext t, String? branchId) {
    if (branchId != null) {
      t.scope.require(branchId);
      return [QueryFilter('branchId', FilterOp.eq, branchId)];
    }
    if (t.scope.allBranches) return const [];
    if (t.scope.branchIds.length > 30) {
      throw const ApiException.forbidden(
        'Your branch access is too broad to list this; ask for all-branch access.',
      );
    }
    return [
      QueryFilter('branchId', FilterOp.inList, t.scope.branchIds.toList()),
    ];
  }

  // ------------------------------------------------------------- audit

  CreateOp audit(
    TenantContext t, {
    required String action,
    required String resourceType,
    required String resourceId,
    String? branchId,
    String? patientId,
    String? invoiceId,
    int? amount,
    String? reason,
    String? requestId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) => CreateOp(path(t, 'financial_audit_logs', newId()), {
    'tenantId': t.tenantId,
    'branchId': branchId,
    'patientId': patientId,
    'invoiceId': invoiceId,
    'action': action,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'amount': amount,
    'actorUid': t.uid,
    'actorRole': t.actorLabel,
    'reason': reason,
    'requestId': requestId,
    'before': before,
    'after': after,
    'timestamp': d.now,
  });

  // ------------------------------------------------------- idempotency

  static final RegExp _keyPattern = RegExp(r'^[A-Za-z0-9_\-]{8,64}$');

  /// Builds the idempotency record location. A missing/invalid header is a
  /// 400: money-moving requests must be repeatable safely.
  Idem idem(
    TenantContext t,
    String scope,
    String? header,
    Map<String, Object?> body,
  ) {
    if (header == null || !_keyPattern.hasMatch(header)) {
      throw const ApiException.badRequest(
        'Send an Idempotency-Key header (8-64 letters, digits, - or _).',
      );
    }
    return Idem(
      path(t, 'billing_idempotency', _hash('${t.uid}:$scope:$header')),
      _hash(jsonEncode(_canon(body))),
    );
  }

  /// The earlier result for this key, or null. A key reused with a different
  /// body is a conflict.
  Future<DocData?> priorIn(TxContext tx, Idem i) async {
    final p = await tx.get(i.path);
    if (p == null) return null;
    if (p['fingerprint'] != i.fingerprint) {
      throw const ApiException.conflict(
        'This Idempotency-Key was already used for a different request.',
      );
    }
    return p;
  }

  CreateOp record(Idem i, String resourceType, String resourceId) =>
      CreateOp(i.path, {
        'fingerprint': i.fingerprint,
        'resourceType': resourceType,
        'resourceId': resourceId,
        'createdAt': d.now,
      });

  Object? _canon(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((e) => '$e').toList()..sort();
      return {for (final k in keys) k: _canon(v[k])};
    }
    if (v is List) return v.map(_canon).toList();
    return v;
  }

  String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  // --------------------------------------------------------- numbering

  /// Next gap-free-per-attempt number (`INV-000001`). The counter and the
  /// uniqueness key are written with the caller's transaction, so concurrent
  /// callers can never receive the same number.
  Future<String> nextNumber(
    TxContext tx,
    TenantContext t,
    List<WriteOp> ops, {
    required String counter,
    required String prefix,
    required String keys,
    required String ownerId,
    String ownerField = 'ownerId',
  }) async {
    final counterPath = path(t, 'counters', counter);
    final c = await tx.get(counterPath);
    final n = ((c?['next'] as int?) ?? 0) + 1;
    final number = '$prefix-${n.toString().padLeft(6, '0')}';
    ops
      ..add(
        c == null
            ? CreateOp(counterPath, {'next': n})
            : UpdateOp(counterPath, {'next': n}),
      )
      ..add(
        CreateOp(path(t, keys, number), {
          ownerField: ownerId,
          'createdAt': d.now,
        }),
      );
    return number;
  }

  // ------------------------------------------------------------ input

  /// A required amount in minor units.
  int amount(
    BodyReader r,
    String field, {
    int min = 1,
    int max = 100000000000,
    bool required = true,
  }) => r.integer(field, min: min, max: max, required: required) ?? 0;

  static Map<String, Object?> present(Map<String, Object?> doc) =>
      (_safe(doc)! as Map).cast<String, Object?>();

  static Object? _safe(Object? v) {
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': _safe(e.value)};
    }
    if (v is List) return v.map(_safe).toList();
    return v;
  }
}
