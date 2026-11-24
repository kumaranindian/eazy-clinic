import 'package:api_contracts/api_contracts.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../platform/audit/audit_service.dart';
import '../../platform/common/body_reader.dart';
import '../../platform/common/paging.dart';
import 'tax_baseline.dart';
import 'tax_policy.dart';

/// Platform-managed, versioned tax policies (`tax_policies/{key}`).
///
/// A policy becomes usable only after a *tax specialist verification*. Any
/// change to rates, mode, rounding, exemptions or components **voids** the
/// verification, so an edited policy can never silently stay "verified".
/// Invoices keep their own snapshot, so editing a policy never rewrites
/// history.
class TaxPolicyService {
  TaxPolicyService(this._store, this._audit, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final DateTime Function() _clock;

  static const String collection = 'tax_policies';

  DateTime get _now => _clock().toUtc();

  Map<String, Object?> present(Map<String, Object?> p) =>
      jsonSafe(p)! as Map<String, Object?>;

  Future<List<Map<String, Object?>>> list({String? countryCode}) async {
    final rows = await _store.query(
      DocQuery(
        collection,
        filters: [
          if (countryCode != null)
            QueryFilter('countryCode', FilterOp.eq, countryCode),
        ],
        limit: 200,
      ),
    );
    return [for (final r in rows) present(r.data)]
      ..sort((a, b) => '${a['key']}'.compareTo('${b['key']}'));
  }

  Future<DocData?> raw(String key) =>
      isPolicyKey(key) ? _store.get('$collection/$key') : Future.value(null);

  /// Policies a clinic may use today: published, verified, same country,
  /// with the exemptions and the rate in force on [date] (no draft data).
  static Future<List<Map<String, Object?>>> usableFor(
    DocumentStore store,
    String tenantId,
    String date,
  ) async {
    final country =
        (await store.get('tenants/$tenantId'))?['countryCode'] as String?;
    if (country == null) return const [];
    final rows = await store.query(
      DocQuery(
        collection,
        filters: [QueryFilter('countryCode', FilterOp.eq, country)],
        limit: 50,
      ),
    );
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final p = r.data;
      if (p['status'] != 'published' ||
          (p['verification'] as Map?)?['status'] != 'verified') {
        continue;
      }
      out.add({
        'key': p['key'],
        'title': p['title'],
        'taxType': p['taxType'],
        'mode': p['mode'],
        'version': p['version'],
        'defaultSupply': p['defaultSupply'],
        'exemptions': [
          for (final e in (p['exemptions'] as List? ?? const []))
            {
              'key': (e as Map)['key'],
              'label': e['label'],
              'treatment': e['treatment'],
            },
        ],
        'components': [
          for (final c in (p['components'] as List? ?? const []))
            {
              'name': (c as Map)['name'],
              'supply': c['supply'],
              'rateBps': rateOn(c.cast<String, Object?>(), date),
            },
        ],
      });
    }
    return out..sort((a, b) => '${a['key']}'.compareTo('${b['key']}'));
  }

  Future<Map<String, Object?>> get(String key) async {
    final d = await raw(key);
    if (d == null) throw const ApiException.notFound('Tax policy not found.');
    return present(d);
  }

  Future<List<Map<String, Object?>>> versions(String key) async {
    if (!isPolicyKey(key)) {
      throw const ApiException.notFound('Tax policy not found.');
    }
    final rows = await _store.query(
      DocQuery('$collection/$key/versions', limit: 200),
    );
    return [for (final r in rows) present(r.data)]
      ..sort((a, b) => (a['version']! as int).compareTo(b['version']! as int));
  }

  List<FieldIssue> _issues(Map<String, Object?> doc) => [
    for (final (f, m) in validatePolicy(doc))
      FieldIssue(field: f, code: 'invalid_value', message: m),
  ];

  Future<List<Map<String, Object?>>> seedBaseline(
    Actor actor, {
    String? requestId,
  }) async {
    final out = <Map<String, Object?>>[];
    for (final base in baselineTaxPolicies()) {
      final key = base['key']! as String;
      final doc = {
        ...base,
        'version': 1,
        'createdAt': _now,
        'updatedAt': _now,
        'updatedBy': actor.uid,
      };
      final issues = _issues(doc);
      if (issues.isNotEmpty) {
        throw StateError('Baseline tax policy $key is invalid.');
      }
      try {
        await _store.commit([
          CreateOp('$collection/$key', doc),
          CreateOp('$collection/$key/versions/1', {
            ...doc,
            'reason': 'baseline_seed',
          }),
          _audit.op(
            AuditEntry(
              actor: actor,
              action: 'tax_policy.seeded',
              targetType: 'tax_policy',
              targetId: key,
              requestId: requestId,
              after: {'version': 1},
            ),
          ),
        ]);
        out.add({'key': key, 'created': true});
      } on AlreadyExistsException {
        out.add({'key': key, 'created': false});
      }
    }
    return out;
  }

  /// Fields whose change voids a verification.
  static const Set<String> _material = {
    'mode',
    'rounding',
    'defaultSupply',
    'components',
    'exemptions',
    'taxType',
    'status',
  };

  static const Set<String> updatable = {
    'expectedVersion',
    'reason',
    'title',
    'mode',
    'rounding',
    'defaultSupply',
    'components',
    'exemptions',
    'invoiceRequirements',
    'source',
    'status',
    'taxType',
  };

  Future<Map<String, Object?>> update(
    String key,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown(updatable);
    final expected = r.integer('expectedVersion', min: 1, max: 100000);
    final reason = r.str('reason', min: 3, max: 500);
    r.throwIfInvalid();
    if (!isPolicyKey(key)) {
      throw const ApiException.notFound('Tax policy not found.');
    }
    late Map<String, Object?> saved;
    await _store.transaction((tx) async {
      final cur = await tx.get('$collection/$key');
      if (cur == null) {
        throw const ApiException.notFound('Tax policy not found.');
      }
      if (cur['version'] != expected) {
        throw const ApiException.conflict(
          'The tax policy was changed by someone else. Reload and try again.',
        );
      }
      final merged = <String, Object?>{
        ...cur,
        for (final k in updatable)
          if (body.containsKey(k) && k != 'expectedVersion' && k != 'reason')
            k: body[k],
      };
      final changedMaterial = [
        for (final k in _material)
          if (body.containsKey(k) && '${body[k]}' != '${cur[k]}') k,
      ];
      final version = (cur['version']! as int) + 1;
      merged
        ..['version'] = version
        ..['updatedAt'] = _now
        ..['updatedBy'] = actor.uid;
      if (changedMaterial.isNotEmpty) {
        merged['verification'] = {
          'status': 'unverified',
          'by': null,
          'at': null,
          'reviewerNote':
              'Voided by a change to: ${changedMaterial.join(', ')}',
        };
      }
      final issues = _issues(merged);
      if (issues.isNotEmpty) throw ApiException.validation(issues);
      saved = merged;
      tx.write([
        UpdateOp('$collection/$key', merged),
        CreateOp('$collection/$key/versions/$version', {
          ...merged,
          'reason': reason,
        }),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'tax_policy.updated',
            targetType: 'tax_policy',
            targetId: key,
            requestId: requestId,
            reason: reason,
            before: {'version': cur['version']},
            after: {
              'version': version,
              'fields': [
                for (final k in body.keys)
                  if (k != 'expectedVersion' && k != 'reason') k,
              ],
              'verificationVoided': changedMaterial.isNotEmpty,
            },
          ),
        ),
      ]);
    });
    return present(saved);
  }

  /// Records (or withdraws) a tax specialist's verification of the *current*
  /// version. Needs at least one rate; `expectedVersion` stops a stale
  /// verification being applied to a newer edit.
  Future<Map<String, Object?>> verify(
    String key,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)
      ..rejectUnknown({'expectedVersion', 'decision', 'note'});
    final expected = r.integer('expectedVersion', min: 1, max: 100000);
    final decision = r.enumOf<String>('decision', const [
      'verify',
      'withdraw',
    ], (v) => v);
    final note = r.str('note', min: 5, max: 500);
    r.throwIfInvalid();
    if (!isPolicyKey(key)) {
      throw const ApiException.notFound('Tax policy not found.');
    }
    late Map<String, Object?> saved;
    await _store.transaction((tx) async {
      final cur = await tx.get('$collection/$key');
      if (cur == null) {
        throw const ApiException.notFound('Tax policy not found.');
      }
      if (cur['version'] != expected) {
        throw const ApiException.conflict(
          'The tax policy changed since you reviewed it. Reload and review again.',
        );
      }
      if (decision == 'verify' && !hasAnyRate(cur)) {
        throw const ApiException.conflict(
          'A policy with no rates cannot be verified.',
        );
      }
      final v = {
        'status': decision == 'verify' ? 'verified' : 'unverified',
        'by': decision == 'verify' ? actor.uid : null,
        'at': decision == 'verify' ? _now : null,
        'reviewerNote': note,
        'verifiedVersion': decision == 'verify' ? expected : null,
      };
      final patch = {'verification': v, 'updatedAt': _now};
      saved = {...cur, ...patch};
      tx.write([
        UpdateOp('$collection/$key', patch),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'tax_policy.$decision',
            targetType: 'tax_policy',
            targetId: key,
            requestId: requestId,
            reason: note,
            after: {'version': expected},
          ),
        ),
      ]);
    });
    return present(saved);
  }
}
