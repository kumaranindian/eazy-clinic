import 'package:api_contracts/api_contracts.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../platform/audit/audit_service.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'compliance_baseline.dart';
import 'compliance_core.dart';

final RegExp _key = RegExp(r'^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$');

/// Platform-managed, versioned register of compliance requirements by
/// country, jurisdiction and authority (`compliance_profiles/{key}`).
///
/// A profile says *what to evidence*; it never says a clinic is compliant.
/// Every version is snapshotted (`versions/{n}`) with its reason and a tenant
/// impact report.
class ComplianceProfileService {
  ComplianceProfileService(
    this._store,
    this._audit, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final DateTime Function() _clock;

  static const String collection = 'compliance_profiles';

  DateTime get _now => _clock().toUtc();

  static bool isWellFormedKey(String? k) => k != null && _key.hasMatch(k);

  Map<String, Object?> present(Map<String, Object?> p) =>
      (jsonSafe(p)! as Map<String, Object?>)..remove('createdBy');

  // ----------------------------------------------------------------- reads

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
    final out = [for (final r in rows) present(r.data)]
      ..sort((a, b) => '${a['key']}'.compareTo('${b['key']}'));
    return out;
  }

  Future<Map<String, Object?>> get(String key) async {
    if (!isWellFormedKey(key)) {
      throw const ApiException.notFound('Profile not found.');
    }
    final doc = await _store.get('$collection/$key');
    if (doc == null) throw const ApiException.notFound('Profile not found.');
    return present(doc);
  }

  Future<DocData?> raw(String key) => isWellFormedKey(key)
      ? _store.get('$collection/$key')
      : Future.value(null);

  // ------------------------------------------------------------ validation

  /// Validates a full profile document. Returns every problem.
  List<FieldIssue> validate(Map<String, Object?> p) {
    final out = <FieldIssue>[];
    void bad(String f, String m) =>
        out.add(FieldIssue(field: f, code: 'invalid_value', message: m));
    if (!isWellFormedKey(p['key'] as String?)) {
      bad('key', 'key must be lower-case letters, digits and hyphens.');
    }
    final title = p['title'];
    if (title is! String || title.trim().length < 3 || title.length > 140) {
      bad('title', 'title is required (3-140 characters).');
    }
    final cc = p['countryCode'];
    if (cc is! String || !RegExp(r'^[A-Z]{2}$').hasMatch(cc)) {
      bad('countryCode', 'countryCode must be an ISO 3166-1 alpha-2 code.');
    }
    final jur = p['jurisdiction'];
    if (jur is! String || !RegExp(r'^[a-z0-9_]{2,30}$').hasMatch(jur)) {
      bad(
        'jurisdiction',
        'jurisdiction must be a lower-case code such as national, dubai, abu_dhabi.',
      );
    }
    final auth = p['authority'];
    if (auth is! Map ||
        '${auth['code']}'.trim().isEmpty ||
        '${auth['name']}'.trim().isEmpty) {
      bad('authority', 'authority needs a code and a name.');
    }
    if (p['status'] != 'published' && p['status'] != 'retired') {
      bad('status', 'status must be published or retired.');
    }
    final lr = p['legalReview'];
    if (lr is! Map ||
        (lr['status'] != 'pending' && lr['status'] != 'reviewed')) {
      bad('legalReview', 'legalReview.status must be pending or reviewed.');
    } else if (lr['status'] == 'reviewed' &&
        ('${lr['reviewedBy'] ?? ''}'.trim().isEmpty ||
            '${lr['reviewedOn'] ?? ''}'.trim().isEmpty)) {
      bad(
        'legalReview',
        'A reviewed register needs reviewedBy and reviewedOn.',
      );
    }
    final reqs = p['requirements'];
    if (reqs is! List || reqs.isEmpty || reqs.length > 60) {
      bad('requirements', 'Provide 1-60 requirements.');
    } else {
      final seen = <String>{};
      for (var i = 0; i < reqs.length; i++) {
        final r = reqs[i];
        final f = 'requirements[$i]';
        if (r is! Map) {
          bad(f, 'must be an object.');
          continue;
        }
        final k = r['key'];
        if (k is! String || !isWellFormedKey(k)) {
          bad('$f.key', 'key must be lower-case letters, digits and hyphens.');
        } else if (!seen.add(k)) {
          bad('$f.key', 'duplicate requirement key "$k".');
        }
        final t = r['title'];
        if (t is! String || t.trim().length < 3 || t.length > 160) {
          bad('$f.title', 'title is required.');
        }
        if (!requirementCategories.contains(r['category'])) {
          bad(
            '$f.category',
            'category must be one of ${requirementCategories.join(', ')}.',
          );
        }
        if (!requirementSubjects.contains(r['appliesTo'])) {
          bad(
            '$f.appliesTo',
            'appliesTo must be one of ${requirementSubjects.join(', ')}.',
          );
        }
        if (!confidenceLevels.contains(r['confidence'])) {
          bad('$f.confidence', 'confidence must be low, medium or high.');
        }
        final src = r['source'];
        if (src is! Map || '${src['reference'] ?? ''}'.trim().isEmpty) {
          bad('$f.source', 'every requirement needs a source reference.');
        }
        if ('${r['owner'] ?? ''}'.trim().isEmpty) {
          bad('$f.owner', 'every requirement needs an owner.');
        }
        final ev = r['evidence'];
        if (ev is! Map ||
            ev['required'] is! bool ||
            ev['expiryTracked'] is! bool ||
            ev['kinds'] is! List) {
          bad(
            '$f.evidence',
            'evidence needs required, kinds and expiryTracked.',
          );
        } else {
          for (final kind in ev['kinds'] as List) {
            if (!evidenceKinds.contains(kind)) {
              bad('$f.evidence.kinds', 'unknown evidence kind "$kind".');
            }
          }
          if (ev['expiryTracked'] == true && ev['required'] != true) {
            bad('$f.evidence', 'expiryTracked needs required evidence.');
          }
        }
        // A high-confidence requirement must have been reviewed.
        if (r['confidence'] == 'high' && r['reviewedOn'] == null) {
          bad('$f.confidence', 'high confidence needs a reviewedOn date.');
        }
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ seed

  /// Creates the baseline registers if absent. Never overwrites an edited
  /// profile. All baseline content is an unvalidated draft (see
  /// [compliance_baseline.dart]).
  Future<List<Map<String, Object?>>> seedBaseline(
    Actor actor, {
    String? requestId,
  }) async {
    final out = <Map<String, Object?>>[];
    for (final base in baselineProfiles()) {
      final key = base['key']! as String;
      final doc = {
        ...base,
        'version': 1,
        'effectiveFrom': _now,
        'createdAt': _now,
        'updatedAt': _now,
        'updatedBy': actor.uid,
      };
      final problems = validate(doc);
      if (problems.isNotEmpty) {
        throw StateError(
          'Baseline profile $key is invalid: ${problems.first.message}',
        );
      }
      try {
        await _store.commit([
          CreateOp('$collection/$key', doc),
          CreateOp('$collection/$key/versions/1', {
            ...doc,
            'reason': 'baseline_seed',
            'impact': {
              'tenantsAffected': 0,
              'added': <Object?>[],
              'removed': <Object?>[],
              'changed': <Object?>[],
            },
          }),
          _audit.op(
            AuditEntry(
              actor: actor,
              action: 'compliance_profile.seeded',
              targetType: 'compliance_profile',
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

  // ---------------------------------------------------------------- update

  static const Set<String> updatable = {
    'expectedVersion',
    'reason',
    'title',
    'authority',
    'facilityTypes',
    'appliesWhenNote',
    'requirements',
    'legalReview',
    'status',
  };

  /// Publishes a new version. `countryCode`, `jurisdiction` and `key` are
  /// fixed (a different scope is a different profile). Returns the profile
  /// with the impact report of the change.
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
    if (!isWellFormedKey(key)) {
      throw const ApiException.notFound('Profile not found.');
    }

    final impactApplicable = await _applyingTenants(key);
    late Map<String, Object?> saved;
    await _store.transaction((tx) async {
      final cur = await tx.get('$collection/$key');
      if (cur == null) throw const ApiException.notFound('Profile not found.');
      if (cur['version'] != expected) {
        throw const ApiException.conflict(
          'The profile was changed by someone else. Reload and try again.',
        );
      }
      final merged = <String, Object?>{
        ...cur,
        for (final k in updatable)
          if (body.containsKey(k) && k != 'expectedVersion' && k != 'reason')
            k: body[k],
      };
      final version = (cur['version']! as int) + 1;
      merged['version'] = version;
      merged['effectiveFrom'] = _now;
      merged['updatedAt'] = _now;
      merged['updatedBy'] = actor.uid;
      final issues = validate(merged);
      if (issues.isNotEmpty) throw ApiException.validation(issues);

      final impact = {
        ..._diff(
          cur['requirements']! as List<Object?>,
          merged['requirements']! as List<Object?>,
        ),
        'tenantsAffected': impactApplicable.length,
        'generatedAt': _now,
      };
      saved = merged;
      tx.write([
        UpdateOp('$collection/$key', merged),
        CreateOp('$collection/$key/versions/$version', {
          ...merged,
          'reason': reason,
          'impact': impact,
        }),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'compliance_profile.updated',
            targetType: 'compliance_profile',
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
              'tenantsAffected': impactApplicable.length,
            },
          ),
        ),
      ]);
    });
    return present(saved);
  }

  Map<String, Object?> _diff(List<Object?> before, List<Object?> after) {
    Map<String, Map<String, Object?>> byKey(List<Object?> l) => {
      for (final r in l)
        '${(r! as Map<Object?, Object?>)['key']}': (r as Map<Object?, Object?>)
            .cast<String, Object?>(),
    };
    final b = byKey(before);
    final a = byKey(after);
    return {
      'added': [
        for (final k in a.keys)
          if (!b.containsKey(k)) k,
      ],
      'removed': [
        for (final k in b.keys)
          if (!a.containsKey(k)) k,
      ],
      'changed': [
        for (final k in a.keys)
          if (b.containsKey(k) &&
              requirementHash(b[k]!) != requirementHash(a[k]!))
            k,
      ],
    };
  }

  /// Clinics a profile currently applies to (confirmed by a reviewer).
  Future<List<StoredDoc>> _applyingTenants(String key) => _store.query(
    DocQuery(
      'compliance_applicability',
      collectionGroup: true,
      filters: [
        QueryFilter('profileKey', FilterOp.eq, key),
        const QueryFilter('status', FilterOp.eq, 'applies'),
      ],
      limit: 5000,
    ),
  );

  // ---------------------------------------------------------------- impact

  /// Live impact of the *current* version: which clinics it applies to and
  /// what changed from the previous version.
  Future<Map<String, Object?>> impact(String key) async {
    final cur = await raw(key);
    if (cur == null) throw const ApiException.notFound('Profile not found.');
    final version = cur['version']! as int;
    final snap = version > 1
        ? await _store.get('$collection/$key/versions/$version')
        : null;
    final tenants = await _applyingTenants(key);
    return {
      'key': key,
      'version': version,
      'tenantsAffected': tenants.length,
      'tenants': [
        for (final t in tenants)
          {
            'tenantId': t.path.split('/')[1],
            'confirmedAt': jsonSafe(t.data['setAt']),
          },
      ],
      'change': snap == null
          ? null
          : {
              for (final e
                  in (jsonSafe(snap['impact'])! as Map<String, Object?>)
                      .entries)
                if (e.key != 'tenantsAffected') e.key: e.value,
            },
    };
  }

  Future<List<Map<String, Object?>>> versions(String key) async {
    if (!isWellFormedKey(key)) {
      throw const ApiException.notFound('Profile not found.');
    }
    final rows = await _store.query(
      DocQuery('$collection/$key/versions', limit: 200),
    );
    final out = [
      for (final r in rows)
        {
          'version': r.data['version'],
          'effectiveFrom': jsonSafe(r.data['effectiveFrom']),
          'updatedBy': r.data['updatedBy'],
          'reason': r.data['reason'],
          'impact': jsonSafe(r.data['impact']),
          'legalReviewStatus': (r.data['legalReview'] as Map?)?['status'],
          'requirementCount': (r.data['requirements'] as List?)?.length,
        },
    ]..sort((a, b) => (b['version']! as int).compareTo(a['version']! as int));
    return out;
  }
}
