import 'package:api_contracts/api_contracts.dart';
import 'package:country_config/country_config.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../applications/application_service.dart';
import '../audit/audit_service.dart';
import '../common/body_reader.dart';
import '../common/paging.dart';
import 'country_directory.dart';

/// Tenant statuses that still hold data and therefore block disabling a
/// country. (`closed` tenants are excluded.)
const List<String> _liveTenantStatuses = [
  'provisioning',
  'active',
  'suspended',
];

/// Platform administration of the country master, the dry-run backfill
/// report and the audited assignment of a legal country to a tenant.
class CountryService {
  CountryService(
    this._store,
    this._audit,
    this.directory, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final CountryDirectory directory;
  final DateTime Function() _clock;

  DateTime get _now => _clock().toUtc();

  static const Set<String> _createFields = {
    'code',
    'name',
    'nativeName',
    'callingCode',
    'defaultCurrency',
    'locales',
    'defaultLocale',
    'suggestedTimezones',
    'adminAreaLabel',
    'postalCode',
    'policy',
    'reviewedOn',
    'sources',
  };

  /// Fields that may change after creation. `code`, `callingCode` and
  /// `defaultCurrency` are fixed: changing them would silently alter the
  /// meaning of existing tenants' data and needs a dedicated migration.
  static const Set<String> _updateFields = {
    'expectedVersion',
    'reason',
    'status',
    'onboardingEnabled',
    'name',
    'nativeName',
    'locales',
    'defaultLocale',
    'suggestedTimezones',
    'adminAreaLabel',
    'postalCode',
    'policy',
    'reviewedOn',
    'sources',
  };

  // ------------------------------------------------------------------ views

  Future<int> activeTenants(String code) => _store.count(
    DocQuery(
      'tenants',
      filters: [
        QueryFilter('countryCode', FilterOp.eq, code),
        const QueryFilter('status', FilterOp.inList, _liveTenantStatuses),
      ],
    ),
  );

  Future<Map<String, Object?>> _present(
    CountryProfile p,
    Map<String, Object?> stored,
  ) async => {
    ...p.toJson(),
    'isOnboardable': p.isOnboardable,
    'completenessWarnings': p.completenessWarnings(),
    'activeTenants': await activeTenants(p.code),
    'updatedAt': jsonSafe(stored['updatedAt']),
    'updatedBy': stored['updatedBy'],
  };

  Future<List<Map<String, Object?>>> list() async {
    final rows = await _store.query(
      const DocQuery(
        CountryDirectory.collection,
        orderBy: OrderBy('code'),
        limit: 300,
      ),
    );
    final out = <Map<String, Object?>>[];
    for (final row in rows) {
      final p = CountryDirectory.parse(row.data);
      if (p == null) {
        // Surface a broken record instead of hiding it.
        out.add({
          'code': row.id,
          'invalid': true,
          'isOnboardable': false,
          'completenessWarnings': ['invalid_profile'],
        });
      } else {
        out.add(await _present(p, row.data));
      }
    }
    return out;
  }

  Future<Map<String, Object?>> get(String code) async {
    if (!CountryDirectory.isWellFormedCode(code)) {
      throw const ApiException.notFound('Country not found.');
    }
    final stored = await _store.get(CountryDirectory.pathOf(code));
    final p = CountryDirectory.parse(stored);
    if (p == null) throw const ApiException.notFound('Country not found.');
    return _present(p, stored!);
  }

  /// Safe list for the onboarding selector: only countries a new clinic may
  /// choose, with client-safe fields.
  Future<List<Map<String, Object?>>> listOnboardable() async {
    final rows = await _store.query(
      const DocQuery(
        CountryDirectory.collection,
        filters: [QueryFilter('onboardingEnabled', FilterOp.eq, true)],
        orderBy: OrderBy('code'),
        limit: 300,
      ),
    );
    return [
      for (final row in rows)
        if (CountryDirectory.parse(row.data) case final p? when p.isOnboardable)
          p.toClientJson(),
    ];
  }

  // ------------------------------------------------------------------ write

  DocData _stored(CountryProfile p, Actor actor) => {
    ...p.toJson(),
    'effectiveFrom': p.effectiveFrom,
    'updatedAt': _now,
    'updatedBy': actor.uid,
  };

  CreateOp _versionOp(CountryProfile p, Actor actor, String? reason) =>
      CreateOp(
        '${CountryDirectory.pathOf(p.code)}/versions/${p.configurationVersion}',
        {..._stored(p, actor), 'reason': reason, 'snapshotAt': _now},
      );

  /// Creates the reviewed India and UAE profiles if absent. Idempotent and
  /// never overwrites an existing (possibly edited) profile.
  Future<List<Map<String, Object?>>> seedBaseline(
    Actor actor, {
    String? requestId,
  }) async {
    final out = <Map<String, Object?>>[];
    for (final p in BaselineCountries.all(effectiveFrom: _now)) {
      try {
        await _store.commit([
          CreateOp(CountryDirectory.pathOf(p.code), _stored(p, actor)),
          _versionOp(p, actor, 'baseline_seed'),
          _audit.op(
            AuditEntry(
              actor: actor,
              action: 'country.seeded',
              targetType: 'country',
              targetId: p.code,
              requestId: requestId,
              after: {'configurationVersion': 1},
            ),
          ),
        ]);
        out.add({'code': p.code, 'created': true});
      } on AlreadyExistsException {
        out.add({'code': p.code, 'created': false});
      }
    }
    directory.invalidate();
    return out;
  }

  Future<Map<String, Object?>> create(
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown(_createFields);
    r.throwIfInvalid();
    final candidate = _candidate({
      ...body,
      'status': CountryStatus.disabled.wireName,
      'onboardingEnabled': false,
      'configurationVersion': 1,
      'effectiveFrom': _now.toIso8601String(),
    }, r);
    final p = candidate;
    try {
      await _store.commit([
        CreateOp(CountryDirectory.pathOf(p.code), _stored(p, actor)),
        _versionOp(p, actor, 'created'),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'country.created',
            targetType: 'country',
            targetId: p.code,
            requestId: requestId,
            after: {'status': 'disabled', 'configurationVersion': 1},
          ),
        ),
      ]);
    } on AlreadyExistsException {
      throw const ApiException.conflict('That country already exists.');
    }
    directory.invalidate(p.code);
    return get(p.code);
  }

  CountryProfile _candidate(Map<String, Object?> json, BodyReader r) {
    final CountryProfile p;
    try {
      p = CountryProfile.fromJson(json);
    } on Object {
      throw ApiException.validation([
        const FieldIssue(
          field: 'body',
          code: 'invalid_value',
          message: 'The country profile is malformed.',
        ),
      ]);
    }
    final problems = p.problems();
    if (problems.isNotEmpty) {
      throw ApiException.validation([
        for (final m in problems)
          FieldIssue(field: 'profile', code: 'invalid_value', message: m),
      ]);
    }
    return p;
  }

  Future<Map<String, Object?>> update(
    String code,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    if (!CountryDirectory.isWellFormedCode(code)) {
      throw const ApiException.notFound('Country not found.');
    }
    final r = BodyReader(body)..rejectUnknown(_updateFields);
    final expected = r.integer('expectedVersion', min: 1, max: 100000);
    final reason = r.str('reason', min: 3, max: 500);
    r.throwIfInvalid();

    // Disabling needs the live-tenant guard; count before the transaction.
    final wantsDisable = body['status'] == CountryStatus.disabled.wireName;
    final live = wantsDisable ? await activeTenants(code) : 0;

    await _store.transaction((tx) async {
      final stored = await tx.get(CountryDirectory.pathOf(code));
      final current = CountryDirectory.parse(stored);
      if (current == null) {
        throw const ApiException.notFound('Country not found.');
      }
      if (current.configurationVersion != expected) {
        throw const ApiException.conflict(
          'The country was changed by someone else. Reload and try again.',
        );
      }
      final merged = {
        ...current.toJson(),
        for (final k in _updateFields)
          if (body.containsKey(k) && k != 'expectedVersion' && k != 'reason')
            k: body[k],
        'configurationVersion': current.configurationVersion + 1,
        'effectiveFrom': _now.toIso8601String(),
      };
      final next = _candidate(merged, r);

      if (next.status == CountryStatus.disabled &&
          current.status != CountryStatus.disabled &&
          live > 0) {
        throw ApiException.conflict(
          'This country has $live active clinic(s). It cannot be disabled '
          'until an approved migration or retention process exists. You can '
          'pause new applications by turning onboarding off instead.',
        );
      }
      if (next.status == CountryStatus.disabled && next.onboardingEnabled) {
        throw ApiException.validation(const [
          FieldIssue(
            field: 'onboardingEnabled',
            code: 'invalid_state',
            message: 'A disabled country cannot accept new applications.',
          ),
        ]);
      }
      if (next.onboardingEnabled &&
          !current.onboardingEnabled &&
          (next.sources.isEmpty || next.reviewedOn == null)) {
        throw ApiException.validation(const [
          FieldIssue(
            field: 'onboardingEnabled',
            code: 'review_evidence_required',
            message:
                'Record the review date and sources before enabling '
                'onboarding for a country.',
          ),
        ]);
      }
      tx.write([
        UpdateOp(CountryDirectory.pathOf(code), _stored(next, actor)),
        _versionOp(next, actor, reason),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'country.updated',
            targetType: 'country',
            targetId: code,
            requestId: requestId,
            reason: reason,
            before: {
              'configurationVersion': current.configurationVersion,
              'status': current.status.wireName,
              'onboardingEnabled': current.onboardingEnabled,
            },
            after: {
              'configurationVersion': next.configurationVersion,
              'status': next.status.wireName,
              'onboardingEnabled': next.onboardingEnabled,
              'fields': [
                for (final k in body.keys)
                  if (k != 'expectedVersion' && k != 'reason') k,
              ],
            },
          ),
        ),
      ]);
    });
    directory.invalidate(code);
    return get(code);
  }

  // --------------------------------------------------------------- backfill

  static String _norm(Object? v) =>
      '$v'.toLowerCase().replaceAll(RegExp(r'[^a-z؀-ۿऀ-ॿ]+'), '');

  /// Legacy free-text aliases seen in pre-Phase-12 applications. Used only to
  /// classify existing tenants in the dry-run report; never at onboarding.
  static const Map<String, String> _legacyAliases = {
    'uae': 'AE',
    'bharat': 'IN',
  };

  /// Read-only classification of tenants that have no legal country yet.
  ///
  /// * **verified** – the applicant's own country entry maps to exactly one
  ///   known country and the application's postal code and phone numbers are
  ///   consistent with it;
  /// * **ambiguous** – a candidate exists but the evidence is inconsistent or
  ///   matches several countries;
  /// * **unmapped** – no usable country evidence.
  ///
  /// Nothing is written. The country is never inferred from IP address,
  /// browser locale or device time zone; phone and postal data are used only
  /// to cross-check what the applicant explicitly entered. Each tenant is
  /// then assigned individually through [assignTenantCountry].
  Future<Map<String, Object?>> backfillReport({int maxTenants = 5000}) async {
    final profiles = <CountryProfile>[
      for (final row in await _store.query(
        const DocQuery(CountryDirectory.collection, limit: 300),
      ))
        if (CountryDirectory.parse(row.data) case final p?) p,
    ];
    final tenants = <StoredDoc>[];
    PageCursor? after;
    var truncated = false;
    while (true) {
      final page = await _store.query(
        DocQuery(
          'tenants',
          orderBy: const OrderBy('createdAt'),
          limit: 200,
          after: after,
        ),
      );
      tenants.addAll(page);
      if (tenants.length >= maxTenants) {
        truncated = page.length == 200;
        break;
      }
      if (page.length < 200) break;
      after = PageCursor(page.last.data['createdAt'], page.last.id);
    }

    var assigned = 0;
    final rows = <Map<String, Object?>>[];
    final counts = {'verified': 0, 'ambiguous': 0, 'unmapped': 0};
    for (final t in tenants) {
      if (t.data['countryCode'] is String) {
        assigned++;
        continue;
      }
      final reasons = <String>[];
      CountryProfile? candidate;
      final appId = t.data['applicationId'];
      final app = appId is String
          ? await _store.get('${ApplicationService.collection}/$appId')
          : null;
      final address = (app?['address'] as Map?)?.cast<String, Object?>();
      final clinic = (app?['clinic'] as Map?)?.cast<String, Object?>();
      final owner = (app?['owner'] as Map?)?.cast<String, Object?>();
      final text = _norm(address?['country']);
      if (app == null) {
        reasons.add('no_application_record');
      } else if (text.isEmpty) {
        reasons.add('no_country_entered');
      } else {
        final alias = _legacyAliases[text];
        final matches = profiles
            .where(
              (p) =>
                  _norm(p.name) == text ||
                  _norm(p.nativeName) == text ||
                  p.code.toLowerCase() == text ||
                  p.code == alias,
            )
            .toList();
        if (matches.isEmpty) {
          reasons.add('country_text_not_recognised');
        } else if (matches.length > 1) {
          reasons.add('country_text_matches_several');
        } else {
          candidate = matches.single;
        }
      }
      var classification = 'unmapped';
      if (candidate != null) {
        final postal = candidate.postalCode.check(
          address?['postalCode'] as String?,
        );
        if (postal != null) reasons.add('postal_code_inconsistent');
        for (final (label, value) in [
          ('clinic_phone', clinic?['phone']),
          ('owner_phone', owner?['phone']),
        ]) {
          if (value is String &&
              !PhoneNumbers.validate(value, candidate.code).isValid) {
            reasons.add('${label}_inconsistent');
          }
        }
        classification = reasons.isEmpty ? 'verified' : 'ambiguous';
      } else if (reasons.contains('country_text_matches_several')) {
        classification = 'ambiguous';
      }
      counts[classification] = counts[classification]! + 1;
      rows.add({
        'tenantId': t.id,
        'clinicName': t.data['clinicName'],
        'status': t.data['status'],
        'classification': classification,
        'candidateCountry': candidate?.code,
        'reasons': reasons,
      });
    }
    return {
      'dryRun': true,
      'generatedAt': _now.toIso8601String(),
      'tenantsScanned': tenants.length,
      'alreadyAssigned': assigned,
      'truncated': truncated,
      'summary': counts,
      'tenants': rows,
    };
  }

  // -------------------------------------------------------------- migration

  /// Privileged, audited assignment (or correction) of a tenant's legal
  /// country. Idempotent for the same value. A correction to a different
  /// country must state the current value being replaced.
  Future<Map<String, Object?>> assignTenantCountry({
    required String tenantId,
    required String countryCode,
    required String reason,
    String? expectedCurrent,
    required Actor actor,
    String? requestId,
  }) async {
    if (!CountryDirectory.isWellFormedCode(countryCode)) {
      throw ApiException.validation(const [
        FieldIssue(
          field: 'countryCode',
          code: 'invalid_value',
          message: 'countryCode must be an ISO 3166-1 alpha-2 code.',
        ),
      ]);
    }
    return _store.transaction((tx) async {
      final tenant = await tx.get('tenants/$tenantId');
      if (tenant == null) {
        throw const ApiException.notFound('Tenant not found.');
      }
      final profile = await CountryDirectory.profileIn(tx, countryCode);
      if (profile == null || profile.status != CountryStatus.supported) {
        throw ApiException.validation(const [
          FieldIssue(
            field: 'countryCode',
            code: 'unsupported_country',
            message: 'That country is not available.',
          ),
        ]);
      }
      final current = tenant['countryCode'] as String?;
      if (current == countryCode) {
        return {
          'tenantId': tenantId,
          'countryCode': countryCode,
          'changed': false,
        };
      }
      if (current != null && expectedCurrent != current) {
        throw const ApiException.conflict(
          'The tenant already has a different country. Send '
          'expectedCurrent with its current value to confirm a correction.',
        );
      }
      final now = _now;
      tx.write([
        UpdateOp('tenants/$tenantId', {
          'countryCode': countryCode,
          'countryConfigVersion': profile.configurationVersion,
          'countrySource': 'migration',
          'countrySetAt': now,
          'countrySetBy': actor.uid,
          'updatedAt': now,
        }),
        CreateOp(
          'tenants/$tenantId/country_history/${now.microsecondsSinceEpoch}',
          {
            'from': current,
            'to': countryCode,
            'configurationVersion': profile.configurationVersion,
            'reason': reason,
            'actorUid': actor.uid,
            'at': now,
          },
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'tenant.country_assigned',
            targetType: 'tenant',
            targetId: tenantId,
            tenantId: tenantId,
            requestId: requestId,
            reason: reason,
            before: {'countryCode': current},
            after: {
              'countryCode': countryCode,
              'configurationVersion': profile.configurationVersion,
            },
          ),
        ),
      ]);
      return {
        'tenantId': tenantId,
        'countryCode': countryCode,
        'changed': true,
        'previousCountryCode': current,
      };
    });
  }
}
