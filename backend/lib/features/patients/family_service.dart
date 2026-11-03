import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../auth/domain/auth_context.dart';
import '../clinic/settings/operating_hours.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart' show jsonSafe;
import 'patient_support.dart';

const List<String> relationshipTypes = [
  'parent',
  'child',
  'spouse',
  'guardian',
  'caregiver',
  'other',
];

/// What a relationship may allow. Nothing here grants access to a clinic's
/// medical record: later phases check these scopes before acting.
const List<String> familyScopes = [
  'view_clinic_links',
  'link_clinic_records',
  'manage_appointments',
  'view_records',
  'give_consent',
];

/// Global patient accounts (identity) and the relationships between them.
/// Holds no medical information; clinic records stay inside their tenants.
class PatientAccountService {
  PatientAccountService(this._s);

  final PatientSupport _s;

  DocumentStore get _store => _s.d.store;
  DateTime get _now => _s.d.now;

  // ------------------------------------------------------------- accounts

  Future<Map<String, Object?>> create(
    AuthContext ctx,
    Map<String, Object?> body,
  ) async {
    final r = BodyReader(body)
      ..rejectUnknown({'displayName', 'dateOfBirth', 'phone'});
    final name = r.str('displayName', min: 2, max: 100, required: false);
    final phone = r.phone('phone', required: false);
    String? dob;
    if (r.has('dateOfBirth')) {
      final raw = r.body['dateOfBirth'];
      if (!HoursParser.validDate(raw, minYear: 1900, maxYear: _now.year) ||
          DateTime.parse(raw! as String).isAfter(_now)) {
        r.addIssue(
          'dateOfBirth',
          'invalid_date',
          'Enter a valid date of birth.',
        );
      } else {
        dob = raw as String;
      }
    }
    r.throwIfInvalid();
    final id = 'pa_${newId(length: 14)}';
    final doc = <String, Object?>{
      'accountId': id,
      'uid': ctx.user.uid,
      'kind': 'self',
      'displayName': name ?? ctx.user.displayName,
      'email': ctx.user.email.toLowerCase(),
      'phone': phone,
      'phoneVerified': false,
      'dateOfBirth': dob,
      'status': 'active',
      'createdAt': _now,
      'updatedAt': _now,
    };
    try {
      await _store.commit([
        CreateOp('patient_account_uids/${ctx.user.uid}', {
          'accountId': id,
          'createdAt': _now,
        }),
        CreateOp('patient_accounts/$id', doc),
      ]);
    } on AlreadyExistsException {
      throw const ApiException.conflict('You already have a patient account.');
    }
    return present(doc, ctx);
  }

  /// The caller's own account (never looked up by an id from the request).
  Future<Map<String, Object?>> mine(AuthContext ctx) async {
    final doc = await accountOf(ctx.user.uid);
    if (doc == null) {
      throw const ApiException.notFound('You do not have a patient account.');
    }
    return present(doc, ctx);
  }

  Future<DocData?> accountOf(String uid) async {
    final key = await _store.get('patient_account_uids/$uid');
    if (key == null) return null;
    return _store.get('patient_accounts/${key['accountId']}');
  }

  Future<DocData> requireAccount(AuthContext ctx) async {
    final a = await accountOf(ctx.user.uid);
    if (a == null || a['status'] != 'active') {
      throw const ApiException.forbidden('Create your patient account first.');
    }
    return a;
  }

  Map<String, Object?> present(DocData a, AuthContext? ctx) {
    final out = (jsonSafe(a)! as Map<String, Object?>)..remove('uid');
    final verified = ctx != null && ctx.identity.emailVerified;
    out['identityVerification'] = a['kind'] == 'dependent'
        ? 'managed_by_guardian'
        : verified
        ? 'email_verified'
        : 'unverified';
    return out;
  }

  // -------------------------------------------------------------- family

  /// Effective status (an elapsed validity ends the relationship).
  String effectiveStatus(DocData rel) {
    final until = rel['validUntil'];
    if (rel['status'] == 'active' &&
        until is DateTime &&
        !until.isAfter(_now)) {
      return 'expired';
    }
    return '${rel['status']}';
  }

  /// Whether [actor] may use [scope] on [subject]'s behalf (optionally inside
  /// one clinic). Requires an active, verified, unexpired relationship; a
  /// pending, rejected, revoked or expired one grants nothing.
  Future<bool> authorize(
    String actorAccountId,
    String subjectAccountId,
    String scope, {
    String? tenantId,
  }) async {
    final allowed = await allowedTenants(
      actorAccountId,
      subjectAccountId,
      scope,
    );
    if (allowed == null) return false;
    return allowed.contains(null) ||
        (tenantId != null && allowed.contains(tenantId));
  }

  /// Clinics in which [scope] is allowed: `null` when it is not allowed at all,
  /// otherwise a set that contains `null` for an unrestricted relationship or
  /// the clinic ids a clinic-verified relationship is limited to.
  Future<Set<String?>?> allowedTenants(
    String actorAccountId,
    String subjectAccountId,
    String scope,
  ) async {
    final rows = await _store.query(
      DocQuery(
        'family_relationships',
        filters: [
          QueryFilter('requesterAccountId', FilterOp.eq, actorAccountId),
          QueryFilter('subjectAccountId', FilterOp.eq, subjectAccountId),
        ],
        limit: 20,
      ),
    );
    Set<String?>? out;
    for (final row in rows) {
      final rel = row.data;
      if (effectiveStatus(rel) != 'active' ||
          rel['verificationStatus'] != 'verified' ||
          !((rel['permissionScope'] as List?) ?? const []).contains(scope)) {
        continue;
      }
      (out ??= {}).add(rel['scopeTenantId'] as String?);
    }
    return out;
  }

  Future<Map<String, Object?>> createRelationship(
    AuthContext ctx,
    Map<String, Object?> body,
  ) async {
    final me = await requireAccount(ctx);
    final r = BodyReader(body)
      ..rejectUnknown({
        'relationshipType',
        'isGuardian',
        'permissionScope',
        'validUntil',
        'subjectAccountId',
        'dependent',
      });
    final type = r.enumOf<String>(
      'relationshipType',
      relationshipTypes,
      (v) => v,
    );
    final guardian = r.boolean('isGuardian') ?? false;
    final scope = _scope(r, r.body['permissionScope']);
    final until = _until(r);
    final subjectId = r.str('subjectAccountId', max: 40, required: false);
    final dep = r.object('dependent', required: false);
    if ((subjectId == null) == (dep == null)) {
      r.addIssue(
        'subjectAccountId',
        'invalid_value',
        'Provide either subjectAccountId or dependent.',
      );
    }
    String? depName;
    String? depDob;
    if (dep != null) {
      dep.rejectUnknown({'displayName', 'dateOfBirth', 'gender'});
      depName = dep.str('displayName', min: 2, max: 100);
      final raw = dep.body['dateOfBirth'];
      if (!HoursParser.validDate(raw, minYear: 1900, maxYear: _now.year) ||
          DateTime.parse(raw! as String).isAfter(_now)) {
        dep.addIssue(
          'dateOfBirth',
          'invalid_date',
          'Enter a valid date of birth.',
        );
      } else {
        depDob = raw as String;
      }
      if (!guardian || (type != 'parent' && type != 'guardian')) {
        r.addIssue(
          'isGuardian',
          'guardian_required',
          'A dependent can only be added by a parent or guardian.',
        );
      }
    } else if (guardian) {
      r.addIssue(
        'isGuardian',
        'not_allowed',
        'Guardianship over another account holder cannot be claimed here.',
      );
    }
    r.throwIfInvalid();

    String subject;
    var subjectAccountDoc = <String, Object?>{};
    final writes = <WriteOp>[];
    final relId = 'fr_${newId(length: 14)}';
    if (dep != null) {
      subject = 'pa_${newId(length: 14)}';
      subjectAccountDoc = {
        'accountId': subject,
        'uid': null,
        'kind': 'dependent',
        'displayName': depName,
        'dateOfBirth': depDob,
        'gender': dep.body['gender'] is String ? dep.body['gender'] : null,
        'managedByAccountId': me['accountId'],
        'status': 'active',
        'createdAt': _now,
        'updatedAt': _now,
      };
      writes.add(CreateOp('patient_accounts/$subject', subjectAccountDoc));
    } else {
      subject = subjectId!;
      final target = await _store.get('patient_accounts/$subject');
      if (target == null ||
          target['kind'] != 'self' ||
          subject == me['accountId']) {
        throw const ApiException.notFound('Patient account not found.');
      }
    }
    // no second open request for the same pair and type
    final existing = await _store.query(
      DocQuery(
        'family_relationships',
        filters: [
          QueryFilter('requesterAccountId', FilterOp.eq, me['accountId']),
          QueryFilter('subjectAccountId', FilterOp.eq, subject),
        ],
        limit: 20,
      ),
    );
    if (existing.any(
      (e) =>
          e.data['relationshipType'] == type &&
          const {'pending', 'active'}.contains(effectiveStatus(e.data)),
    )) {
      throw const ApiException.conflict(
        'This relationship already exists or is waiting for approval.',
      );
    }
    final doc = <String, Object?>{
      'relationshipId': relId,
      'requesterAccountId': me['accountId'],
      'subjectAccountId': subject,
      'relationshipType': type,
      'isGuardian': guardian,
      'isCaregiver': type == 'caregiver',
      'permissionScope': scope,
      'verificationStatus': 'pending',
      'verifiedBy': null,
      'scopeTenantId': null,
      'consentRef': null,
      'validFrom': _now,
      'validUntil': until,
      'status': 'pending',
      'createdAt': _now,
      'updatedAt': _now,
    };
    writes.add(CreateOp('family_relationships/$relId', doc));
    await _store.commit(writes);
    return presentRelationship(doc);
  }

  List<String> _scope(BodyReader r, Object? raw) {
    if (raw is! List || raw.isEmpty || raw.any((e) => e is! String)) {
      r.addIssue(
        'permissionScope',
        'invalid_value',
        'List what this relationship allows.',
      );
      return const [];
    }
    final out = raw.cast<String>().toSet().toList();
    if (out.any((e) => !familyScopes.contains(e))) {
      r.addIssue(
        'permissionScope',
        'invalid_value',
        'Unknown permission scope.',
      );
    }
    return out;
  }

  DateTime? _until(BodyReader r) {
    final raw = r.body['validUntil'];
    if (raw == null) return null;
    final v = raw is String ? DateTime.tryParse(raw) : null;
    if (v == null || !v.toUtc().isAfter(_now)) {
      r.addIssue(
        'validUntil',
        'invalid_date',
        'validUntil must be in the future.',
      );
      return null;
    }
    return v.toUtc();
  }

  /// A relationship, if the caller is one of its two parties.
  Future<(DocData rel, DocData me)> _partyOf(AuthContext ctx, String id) async {
    final me = await requireAccount(ctx);
    final rel = await _store.get('family_relationships/$id');
    if (rel == null ||
        (rel['requesterAccountId'] != me['accountId'] &&
            rel['subjectAccountId'] != me['accountId'])) {
      throw const ApiException.notFound('Relationship not found.');
    }
    return (rel, me);
  }

  Future<Map<String, Object?>> getRelationship(
    AuthContext ctx,
    String id,
  ) async {
    final (rel, _) = await _partyOf(ctx, id);
    return presentRelationship(rel);
  }

  Future<List<Map<String, Object?>>> listMine(AuthContext ctx) async {
    final me = await requireAccount(ctx);
    final asRequester = await _store.query(
      DocQuery(
        'family_relationships',
        filters: [
          QueryFilter('requesterAccountId', FilterOp.eq, me['accountId']),
        ],
        limit: 100,
      ),
    );
    final asSubject = await _store.query(
      DocQuery(
        'family_relationships',
        filters: [
          QueryFilter('subjectAccountId', FilterOp.eq, me['accountId']),
        ],
        limit: 100,
      ),
    );
    final seen = <String>{};
    return [
      for (final d in [...asRequester, ...asSubject])
        if (seen.add(d.id)) presentRelationship(d.data),
    ];
  }

  Future<Map<String, Object?>> update(
    AuthContext ctx,
    String id,
    Map<String, Object?> body,
  ) async {
    final (rel, me) = await _partyOf(ctx, id);
    if (rel['requesterAccountId'] != me['accountId']) {
      throw const ApiException.forbidden();
    }
    if (const {'revoked', 'rejected'}.contains(rel['status'])) {
      throw const ApiException.conflict('This relationship has ended.');
    }
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'permissionScope', 'validUntil'});
    final scope = r.has('permissionScope')
        ? _scope(r, r.body['permissionScope'])
        : null;
    final until = r.has('validUntil') ? _until(r) : null;
    r.throwIfInvalid();
    final current = ((rel['permissionScope'] as List?) ?? const [])
        .cast<String>();
    if (scope != null && !scope.every(current.contains)) {
      // widening needs a fresh request that the other side approves
      throw const ApiException.conflict(
        'Access can only be reduced here. Create a new request to widen it.',
      );
    }
    final patch = {
      'permissionScope': ?scope,
      'validUntil': ?until,
      'updatedAt': _now,
    };
    await _store.commit([UpdateOp('family_relationships/$id', patch)]);
    return presentRelationship({...rel, ...patch});
  }

  Future<Map<String, Object?>> verify(
    AuthContext ctx,
    String id,
    Map<String, Object?> body,
  ) async {
    final r = BodyReader(body)..rejectUnknown({'decision'});
    final decision = r.enumOf<String>('decision', const [
      'approve',
      'reject',
    ], (v) => v);
    r.throwIfInvalid();
    final (rel, me) = await _partyOf(ctx, id);
    // Only the person the relationship is about can approve it. A guardian
    // relationship for a dependent is verified by the clinic when the
    // dependent's record is linked; nobody can approve their own request.
    if (rel['subjectAccountId'] != me['accountId']) {
      throw const ApiException.forbidden(
        'Only the person this relationship is about can approve it.',
      );
    }
    if (rel['status'] != 'pending') {
      throw const ApiException.conflict('This request is no longer pending.');
    }
    final approved = decision == 'approve';
    final patch = <String, Object?>{
      'verificationStatus': approved ? 'verified' : 'rejected',
      'status': approved ? 'active' : 'rejected',
      'verifiedBy': {'type': 'subject', 'accountId': me['accountId']},
      'consentRef': {'type': 'subject_approval', 'at': _now},
      'updatedAt': _now,
    };
    await _store.commit([UpdateOp('family_relationships/$id', patch)]);
    return presentRelationship({...rel, ...patch});
  }

  Future<Map<String, Object?>> revoke(
    AuthContext ctx,
    String id,
    Map<String, Object?> body,
  ) async {
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 3, max: 300, required: false);
    r.throwIfInvalid();
    final (rel, me) = await _partyOf(ctx, id);
    if (rel['status'] == 'revoked') {
      throw const ApiException.conflict('Already revoked.');
    }
    final patch = {
      'status': 'revoked',
      'revokedAt': _now,
      'revokedByAccountId': me['accountId'],
      'revokeReason': reason,
      'updatedAt': _now,
    };
    await _store.commit([UpdateOp('family_relationships/$id', patch)]);
    return presentRelationship({...rel, ...patch});
  }

  Map<String, Object?> presentRelationship(DocData rel) => {
    ...(jsonSafe(rel)! as Map<String, Object?>),
    'status': effectiveStatus(rel),
  };

  /// Clinic links of the caller or, with an active scoped relationship, of a
  /// person they manage. Contains no medical information.
  Future<List<Map<String, Object?>>> clinicLinks(
    AuthContext ctx, {
    String? forAccountId,
  }) async {
    final me = await requireAccount(ctx);
    var target = me['accountId']! as String;
    Set<String?>? onlyTenants;
    if (forAccountId != null && forAccountId != target) {
      final allowed = await allowedTenants(
        target,
        forAccountId,
        'view_clinic_links',
      );
      if (allowed == null) {
        throw const ApiException.notFound('Patient account not found.');
      }
      target = forAccountId;
      onlyTenants = allowed.contains(null) ? null : allowed;
    }
    final rows = await _store.query(
      DocQuery(
        'patient_clinic_links',
        filters: [
          QueryFilter('accountId', FilterOp.eq, target),
          const QueryFilter('status', FilterOp.eq, 'linked'),
        ],
        limit: 100,
      ),
    );
    return [
      for (final d in rows)
        if (onlyTenants == null || onlyTenants.contains(d.data['tenantId']))
          jsonSafe(d.data)! as Map<String, Object?>,
    ];
  }
}
