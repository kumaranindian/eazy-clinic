import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/seat_service.dart';
import '../clinic/common/tenant_context.dart';
import '../clinic/settings/operating_hours.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'consent_service.dart';
import 'patient_support.dart';

const List<String> patientGenders = ['male', 'female', 'other', 'undisclosed'];
const List<String> bloodGroups = [
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
  'unknown',
];
const List<String> contactMethods = ['phone', 'sms', 'email', 'whatsapp'];
const List<String> patientStatuses = [
  'active',
  'inactive',
  'archived',
  'merged',
];

String normalizeName(String v) => v
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9ऀ-෿ ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String normalizePhone(String v) {
  final d = v.replaceAll(RegExp(r'\D'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

String maskPhone(Object? v) {
  final s = '${v ?? ''}';
  if (s.length < 4) return '';
  return '${'X' * (s.length - 4)}${s.substring(s.length - 4)}';
}

String maskEmail(Object? v) {
  final s = '${v ?? ''}';
  final at = s.indexOf('@');
  if (at < 1) return '';
  return '${s[0]}***${s.substring(at)}';
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [
        cur[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// 0..1 similarity of two names; word order is ignored.
double nameSimilarity(String a, String b) {
  String sorted(String v) => (normalizeName(v).split(' ')..sort()).join(' ');
  double ratio(String x, String y) {
    final longest = x.length > y.length ? x.length : y.length;
    return longest == 0 ? 1 : 1 - _levenshtein(x, y) / longest;
  }

  final plain = ratio(normalizeName(a), normalizeName(b));
  final tokens = ratio(sorted(a), sorted(b));
  return plain > tokens ? plain : tokens;
}

/// Clinic patient records: registration, directory, status, duplicates.
/// A clinic record is independent of any global patient account.
class PatientService {
  PatientService(this._s, this._consents);

  final PatientSupport _s;
  final ConsentService _consents;

  static const String collection = 'patients';

  static const Set<String> _createFields = {
    'branchId',
    'fullName',
    'preferredName',
    'dateOfBirth',
    'gender',
    'bloodGroup',
    'phone',
    'alternatePhone',
    'email',
    'preferredLanguage',
    'preferredContactMethod',
    'address',
    'occupation',
    'restrictedNotes',
    'guardian',
    'emergencyContacts',
    'consent',
    'duplicateReview',
  };
  static const Set<String> _updateFields = {
    'fullName',
    'preferredName',
    'dateOfBirth',
    'gender',
    'bloodGroup',
    'phone',
    'alternatePhone',
    'email',
    'preferredLanguage',
    'preferredContactMethod',
    'address',
    'occupation',
    'restrictedNotes',
    'guardian',
  };

  // ---------------------------------------------------------------- parsing

  /// Parses the demographic fields shared by create and update.
  Map<String, Object?> _demographics(BodyReader r, {required bool partial}) {
    final name = r.str('fullName', min: 2, max: 100);
    final preferred = r.str('preferredName', max: 60, required: false);
    String? dob;
    if (r.has('dateOfBirth')) {
      final raw = r.body['dateOfBirth'];
      final year = _s.d.now.year;
      if (!HoursParser.validDate(raw, minYear: 1900, maxYear: year) ||
          DateTime.parse(raw! as String).isAfter(_s.d.now)) {
        r.addIssue(
          'dateOfBirth',
          'invalid_date',
          'Enter a valid date of birth (YYYY-MM-DD) that is not in the future.',
        );
      } else {
        dob = raw as String;
      }
    } else if (!partial) {
      r.addIssue('dateOfBirth', 'required', 'dateOfBirth is required.');
    }
    final gender = r.enumOf<String>('gender', patientGenders, (v) => v);
    final blood = r.enumOf<String>(
      'bloodGroup',
      bloodGroups,
      (v) => v,
      required: false,
    );
    final phone = r.phone('phone');
    final alt = r.phone('alternatePhone', required: false);
    final email = r.email('email', required: false);
    final language = r.str(
      'preferredLanguage',
      min: 2,
      max: 5,
      required: false,
    );
    final method = r.enumOf<String>(
      'preferredContactMethod',
      contactMethods,
      (v) => v,
      required: false,
    );
    final occupation = r.str('occupation', max: 80, required: false);
    final notes = r.str('restrictedNotes', max: 1000, required: false);
    Map<String, Object?>? address;
    final a = r.object('address');
    if (a != null) {
      a.rejectUnknown({
        'line1',
        'line2',
        'city',
        'state',
        'country',
        'postalCode',
      });
      final country = a.str('country', min: 2, max: 60);
      final postal = a.str('postalCode', min: 3, max: 10);
      if (postal != null &&
          (country ?? 'india').toLowerCase() == 'india' &&
          !RegExp(r'^[1-9][0-9]{5}$').hasMatch(postal)) {
        a.addIssue(
          'postalCode',
          'invalid_postal_code',
          'Enter a valid 6-digit PIN code.',
        );
      }
      address = {
        for (final e in {
          'line1': a.str('line1', min: 3, max: 120),
          'line2': a.str('line2', max: 120, required: false),
          'city': a.str('city', min: 2, max: 60),
          'state': a.str('state', min: 2, max: 60),
          'country': country,
          'postalCode': postal,
        }.entries)
          if (e.value != null) e.key: e.value,
      };
    }
    return {
      'fullName': ?name,
      'preferredName': ?preferred,
      'dateOfBirth': ?dob,
      'gender': ?gender,
      'bloodGroup': ?blood,
      'phone': ?phone,
      'alternatePhone': ?alt,
      'email': ?email,
      'preferredLanguage': ?language,
      'preferredContactMethod': ?method,
      'occupation': ?occupation,
      'restrictedNotes': ?notes,
      'address': ?address,
      if (name != null) 'nameLower': normalizeName(name),
      if (phone != null) 'phoneNorm': normalizePhone(phone),
      if (alt != null) 'alternatePhoneNorm': normalizePhone(alt),
      if (email != null) 'emailNorm': email,
    };
  }

  /// Guardian details of a minor. Verification is a staff attestation made
  /// with an explicit method; it is never inferred from a relationship label.
  Map<String, Object?>? _guardian(
    BodyReader r,
    TenantContext t, {
    Map<String, Object?>? existing,
  }) {
    final g = r.object('guardian', required: false);
    if (g == null) return null;
    g.rejectUnknown({'name', 'relationship', 'phone', 'verificationMethod'});
    final name = g.str('name', min: 2, max: 100);
    final rel = g.str('relationship', min: 2, max: 40);
    final phone = g.phone('phone');
    final method = g.enumOf<String>(
      'verificationMethod',
      const [
        'government_id_sighted',
        'birth_certificate_sighted',
        'court_order_sighted',
        'other_document_sighted',
      ],
      (v) => v,
      required: false,
    );
    if (method != null && !t.can(ClinicPermission.patientsLinkAccount)) {
      g.addIssue(
        'verificationMethod',
        'not_allowed',
        'You are not allowed to verify a guardian.',
      );
    }
    final same =
        existing != null &&
        existing['name'] == name &&
        existing['relationship'] == rel &&
        existing['phone'] == phone;
    final verified = method != null || (same && existing['verified'] == true);
    return {
      'name': ?name,
      'relationship': ?rel,
      'phone': ?phone,
      'verified': verified,
      if (method != null) 'verificationMethod': method,
      if (method != null) 'verifiedBy': t.uid,
      if (method != null) 'verifiedAt': _s.d.now,
      if (method == null && same) ...{
        'verificationMethod': existing['verificationMethod'],
        'verifiedBy': existing['verifiedBy'],
        'verifiedAt': existing['verifiedAt'],
      },
    };
  }

  // ------------------------------------------------------------- duplicates

  Future<List<Map<String, Object?>>> findDuplicates(
    TenantContext t, {
    required String fullName,
    required String dateOfBirth,
    String? phone,
    String? email,
    String? excludePatientId,
  }) async {
    final found = <String, StoredDoc>{};
    Future<void> gather(String field, Object value) async {
      final rows = await _s.d.store.query(
        DocQuery(
          _s.d.path(t, collection),
          filters: [QueryFilter(field, FilterOp.eq, value)],
          limit: 50,
        ),
      );
      for (final r in rows) {
        found[r.id] = r;
      }
    }

    await gather('dateOfBirth', dateOfBirth);
    if (phone != null && phone.isNotEmpty) {
      await gather('phoneNorm', normalizePhone(phone));
    }
    if (email != null && email.isNotEmpty) {
      await gather('emailNorm', email.toLowerCase());
    }
    final out = <Map<String, Object?>>[];
    for (final d in found.values) {
      final p = d.data;
      if (d.id == excludePatientId ||
          p['status'] == 'merged' ||
          !t.scope.allows('${p['branchId']}')) {
        continue;
      }
      final sim = nameSimilarity(fullName, '${p['fullName']}');
      final dobEq = p['dateOfBirth'] == dateOfBirth;
      final phoneEq =
          phone != null &&
          phone.isNotEmpty &&
          (p['phoneNorm'] == normalizePhone(phone) ||
              p['alternatePhoneNorm'] == normalizePhone(phone));
      final emailEq =
          email != null &&
          email.isNotEmpty &&
          p['emailNorm'] == email.toLowerCase();
      final reasons = <String>[
        if (dobEq && sim >= 0.6) 'name_and_birth_date',
        if (phoneEq) 'phone',
        if (emailEq) 'email',
      ];
      String? level;
      if ((dobEq || phoneEq || emailEq) && sim >= 0.85) {
        level = 'high';
      } else if ((dobEq || phoneEq) && sim >= 0.6 || emailEq) {
        level = 'medium';
      } else if (phoneEq) {
        level = 'low';
      }
      if (level == null) continue;
      out.add({
        'patientId': p['patientId'],
        'mrn': p['mrn'],
        'fullName': p['fullName'],
        'dateOfBirth': p['dateOfBirth'],
        'maskedPhone': maskPhone(p['phone']),
        'status': p['status'],
        'branchId': p['branchId'],
        'level': level,
        'reasons': reasons,
      });
    }
    const order = {'high': 0, 'medium': 1, 'low': 2};
    out.sort(
      (a, b) => order['${a['level']}']!.compareTo(order['${b['level']}']!),
    );
    return out.take(10).toList();
  }

  Future<Map<String, Object?>> duplicateCheck(
    TenantContext t,
    Map<String, Object?> body,
  ) async {
    t.require(ClinicPermission.patientsDuplicates);
    final r = BodyReader(body)
      ..rejectUnknown({'fullName', 'dateOfBirth', 'phone', 'email'});
    final name = r.str('fullName', min: 2, max: 100);
    final dob = r.str('dateOfBirth', max: 10);
    if (dob != null &&
        !HoursParser.validDate(dob, minYear: 1900, maxYear: _s.d.now.year)) {
      r.addIssue('dateOfBirth', 'invalid_date', 'Enter a valid date.');
    }
    final phone = r.phone('phone', required: false);
    final email = r.email('email', required: false);
    r.throwIfInvalid();
    final matches = await findDuplicates(
      t,
      fullName: name!,
      dateOfBirth: dob!,
      phone: phone,
      email: email,
    );
    return {
      'matches': matches,
      'requiresReview': matches.any((m) => m['level'] != 'low'),
      'note':
          'Matches are suggestions only. Records are never merged automatically.',
    };
  }

  Future<Map<String, Object?>> possibleDuplicates(
    TenantContext t,
    String id,
  ) async {
    t.require(ClinicPermission.patientsDuplicates);
    final p = await _s.load(t, id);
    final matches = await findDuplicates(
      t,
      fullName: '${p['fullName']}',
      dateOfBirth: '${p['dateOfBirth']}',
      phone: p['phone'] as String?,
      email: p['email'] as String?,
      excludePatientId: id,
    );
    return {'matches': matches};
  }

  // ----------------------------------------------------------------- create

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientsCreate);
    final r = BodyReader(body)..rejectUnknown(_createFields);
    final branchId = r.str('branchId', max: 40);
    final demo = _demographics(r, partial: false);
    final guardian = _guardian(r, t);
    final contacts = r.has('emergencyContacts')
        ? EmergencyContacts.parse(r, 'emergencyContacts')
        : null;
    final c = r.object('consent');
    final ConsentPurpose? purpose = ConsentCatalog.byType(
      ConsentCatalog.dataProcessing,
    );
    String? method;
    String? evidence;
    if (c != null) {
      c.rejectUnknown({
        'granted',
        'textVersion',
        'collectionMethod',
        'evidenceRef',
        'grantedBy',
      });
      if (c.boolean('granted', required: true) != true) {
        c.addIssue(
          'granted',
          'consent_required',
          'A patient cannot be registered without consent to process their data.',
        );
      }
      final v = c.str('textVersion', max: 10);
      if (v != null && v != ConsentCatalog.version) {
        c.addIssue(
          'textVersion',
          'outdated_text',
          'The consent text has changed.',
        );
      }
      method = c.enumOf<String>('collectionMethod', consentMethods, (v) => v);
      evidence = c.str('evidenceRef', max: 120, required: false);
    }
    final dr = r.object('duplicateReview', required: false);
    Set<String> reviewed = {};
    String? reviewReason;
    if (dr != null) {
      dr.rejectUnknown({'decision', 'reason', 'reviewedPatientIds'});
      dr.enumOf<String>('decision', const ['confirmed_distinct'], (v) => v);
      reviewReason = dr.str('reason', min: 5, max: 300);
      final ids = dr.body['reviewedPatientIds'];
      if (ids is! List || ids.any((e) => e is! String) || ids.length > 20) {
        dr.addIssue(
          'reviewedPatientIds',
          'invalid_value',
          'List the patient ids you reviewed.',
        );
      } else {
        reviewed = ids.cast<String>().toSet();
      }
    }
    r.throwIfInvalid();

    // branch must exist, be active and be inside the caller's scope
    t.scope.require(branchId!);
    final branch = await _s.d.store.get(_s.d.path(t, 'branches', branchId));
    if (branch == null || branch['status'] != 'active') {
      throw ApiException.validation([
        FieldIssue(
          field: 'branchId',
          code: 'invalid_branch',
          message: 'Choose an active branch.',
        ),
      ]);
    }
    final dob = demo['dateOfBirth']! as String;
    final minor =
        PatientSupport.ageYears(dob, _s.d.now) < await _s.minorAgeYears(t);
    if (minor) {
      if (guardian == null) {
        throw ApiException.validation([
          FieldIssue(
            field: 'guardian',
            code: 'guardian_required',
            message: 'A guardian is required for a minor.',
          ),
        ]);
      }
    }
    // The decision must come from the patient, or a verified guardian for a minor.
    final grantorReader = BodyReader(c!.body);
    final grantor = _grantorAtRegistration(
      grantorReader,
      minor: minor,
      guardian: guardian,
    );
    grantorReader.throwIfInvalid();

    final matches = await findDuplicates(
      t,
      fullName: demo['fullName']! as String,
      dateOfBirth: dob,
      phone: demo['phone'] as String?,
      email: demo['emailNorm'] as String?,
    );
    final blocking = matches
        .where((m) => m['level'] != 'low')
        .map((m) => m['patientId']! as String)
        .toSet();
    if (blocking.isNotEmpty && !reviewed.containsAll(blocking)) {
      throw ApiException(
        ApiErrorCode.conflict,
        'Possible duplicate patients exist. Review them before registering.',
        issues: [
          FieldIssue(
            field: 'duplicateReview',
            code: 'duplicate_review_required',
            message:
                'Review the possible duplicates and confirm this is a different person.',
          ),
        ],
      );
    }

    final id = 'pt_${newId(length: 12)}';
    final consentId = 'cn_${newId(length: 12)}';
    final now = _s.d.now;
    final counterPath = _s.d.path(t, 'counters', 'patient_mrn');
    return _s.d.seats.withSeat(
      tenantId: t.tenantId,
      kind: SeatKind.patients,
      limit: t.entitlements.limits[LimitKey.maxPatients],
      entityId: id,
      build: (tx, slot) async {
        final counter = await tx.get(counterPath);
        final next = ((counter?['next'] as int?) ?? 0) + 1;
        final mrn = 'MRN-${next.toString().padLeft(6, '0')}';
        final doc = <String, Object?>{
          'patientId': id,
          'tenantId': t.tenantId,
          'branchId': branchId,
          'mrn': mrn,
          ...demo,
          'guardian': guardian,
          'patientAccountId': null,
          'status': 'active',
          'seatSlot': slot,
          'createdAt': now,
          'updatedAt': now,
          'createdBy': t.uid,
          'updatedBy': t.uid,
          'version': 1,
        };
        final reviewId = newId();
        return (
          present(doc, t),
          [
            counter == null
                ? CreateOp(counterPath, {'next': next})
                : UpdateOp(counterPath, {'next': next}),
            CreateOp(_s.d.path(t, 'patient_mrns', mrn), {
              'patientId': id,
              'createdAt': now,
            }),
            CreateOp(_s.patientPath(t, id), doc),
            _consents.decisionOp(
              t.tenantId,
              t.uid,
              consentId: consentId,
              patientId: id,
              type: ConsentCatalog.dataProcessing,
              purpose: purpose!.purpose,
              status: 'granted',
              grantor: grantor,
              method: method!,
              evidenceRef: evidence,
            ),
            if (contacts != null)
              CreateOp(_s.d.path(t, 'patient_emergency_contacts', id), {
                'patientId': id,
                'tenantId': t.tenantId,
                'contacts': contacts,
                'updatedAt': now,
                'updatedBy': t.uid,
              }),
            if (blocking.isNotEmpty)
              CreateOp(_s.d.path(t, 'patient_duplicate_reviews', reviewId), {
                'reviewId': reviewId,
                'patientId': id,
                'decision': 'confirmed_distinct',
                'candidateIds': blocking.toList(),
                'reason': reviewReason,
                'reviewedBy': t.uid,
                'reviewedAt': now,
              }),
            _s.auditOp(
              t,
              id,
              branchId,
              'patient.created',
              after: {
                'mrn': mrn,
                'branchId': branchId,
                if (blocking.isNotEmpty) 'duplicateReviewed': blocking.length,
              },
              requestId: requestId,
            ),
            if (blocking.isNotEmpty)
              _s.auditOp(
                t,
                id,
                branchId,
                'patient.duplicate_reviewed',
                resourceType: 'duplicate_review',
                resourceId: reviewId,
                after: {
                  'decision': 'confirmed_distinct',
                  'candidates': blocking.length,
                },
                reason: reviewReason,
                requestId: requestId,
              ),
          ],
        );
      },
    );
  }

  Grantor _grantorAtRegistration(
    BodyReader consent, {
    required bool minor,
    required Map<String, Object?>? guardian,
  }) {
    final raw = consent.body['grantedBy'];
    if (!minor) {
      if (raw != null && (raw is! Map || raw['type'] != 'patient')) {
        consent.addIssue(
          'grantedBy',
          'invalid_value',
          'An adult patient must give consent personally.',
        );
      }
      return const Grantor('patient');
    }
    if (raw is! Map || raw['type'] != 'guardian') {
      consent.addIssue(
        'grantedBy',
        'guardian_required',
        'A minor needs consent from a guardian.',
      );
      return const Grantor('guardian');
    }
    if (guardian == null || guardian['verified'] != true) {
      consent.addIssue(
        'grantedBy',
        'guardian_unverified',
        'The guardian must be verified before giving consent.',
      );
    }
    return Grantor(
      'guardian',
      name: guardian?['name'] as String?,
      relationship: guardian?['relationship'] as String?,
    );
  }

  // ----------------------------------------------------------------- update

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientsUpdate);
    final r = BodyReader(body, partial: true)..rejectUnknown(_updateFields);
    final changes = _demographics(r, partial: true);
    final guardianCur = (await _s.load(t, id))['guardian'];
    final guardian = _guardian(
      r,
      t,
      existing: guardianCur is Map ? guardianCur.cast<String, Object?>() : null,
    );
    r.throwIfInvalid();
    if (guardian != null) changes['guardian'] = guardian;
    if (changes.isEmpty) {
      throw const ApiException.badRequest('No patient fields to update.');
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final cur = await _s.loadIn(tx, t, id);
      _s.requireOpen(cur);
      final patch = {
        ...changes,
        'updatedAt': now,
        'updatedBy': t.uid,
        'version': ((cur['version'] as int?) ?? 1) + 1,
      };
      tx.write([
        UpdateOp(_s.patientPath(t, id), patch),
        _s.revisionOp(t, id, 'patient', id, {
          for (final k in changes.keys) k: cur[k],
        }),
        _s.auditOp(
          t,
          id,
          cur['branchId'] as String?,
          'patient.updated',
          after: {
            'fields': [
              for (final k in changes.keys)
                if (!k.endsWith('Norm') && k != 'nameLower') k,
            ],
          },
          requestId: requestId,
        ),
      ]);
      return present({...cur, ...patch}, t);
    });
  }

  // ----------------------------------------------------------------- status

  Future<Map<String, Object?>> setStatus(
    TenantContext t,
    String id,
    String to, {
    String? reason,
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientsStatus);
    final needsReason = to == 'archived' || to == 'inactive';
    if (needsReason && (reason == null || reason.trim().length < 5)) {
      throw ApiException.validation([
        FieldIssue(
          field: 'reason',
          code: 'required',
          message: 'Give a reason of at least 5 characters.',
        ),
      ]);
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final cur = await _s.loadIn(tx, t, id);
      final from = cur['status'] as String;
      final allowed = switch (to) {
        'active' => from == 'inactive',
        'inactive' => from == 'active',
        'archived' => from == 'active' || from == 'inactive',
        _ => false,
      };
      if (!allowed) {
        throw ApiException.conflict('A $from patient cannot become $to.');
      }
      final patch = <String, Object?>{
        'status': to,
        'updatedAt': now,
        'updatedBy': t.uid,
        if (to == 'archived') ...{'archivedAt': now, 'archivedBy': t.uid},
      };
      tx.write([
        UpdateOp(_s.patientPath(t, id), patch),
        if (to == 'archived') ...[
          ?_s.d.seats.release(t.tenantId, SeatKind.patients, cur['seatSlot']),
        ],
        _s.auditOp(
          t,
          id,
          cur['branchId'] as String?,
          'patient.$to',
          before: {'status': from},
          after: {'status': to},
          reason: reason?.trim(),
          requestId: requestId,
        ),
      ]);
      return present({...cur, ...patch}, t);
    });
  }

  // ------------------------------------------------------------- read/list

  Future<Map<String, Object?>> detail(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientsView);
    final p = await _s.load(t, id);
    await _s.recordAccess(t, p, 'patient.viewed', requestId: requestId);
    final alerts = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, 'patient_alerts'),
        filters: [
          QueryFilter('patientId', FilterOp.eq, id),
          const QueryFilter('status', FilterOp.eq, 'active'),
        ],
        limit: 20,
      ),
    );
    final canClinical = t.can(ClinicPermission.historyView);
    final allergies = t.can(ClinicPermission.allergiesView)
        ? await _s.d.store.query(
            DocQuery(
              _s.d.path(t, 'patient_allergies'),
              filters: [
                QueryFilter('patientId', FilterOp.eq, id),
                const QueryFilter('status', FilterOp.inList, [
                  'active',
                  'unverified',
                ]),
              ],
              limit: 30,
            ),
          )
        : const <StoredDoc>[];
    return {
      ...present(p, t),
      'alerts': [
        for (final a in alerts)
          if (canClinical ||
              !clinicalAlertCategories.contains(a.data['category']))
            jsonSafe(a.data),
      ],
      if (t.can(ClinicPermission.allergiesView))
        'activeAllergies': [
          for (final a in allergies)
            {
              'allergyId': a.data['allergyId'],
              'allergen': a.data['allergen'],
              'severity': a.data['severity'],
              'status': a.data['status'],
              'verificationStatus': a.data['verificationStatus'],
            },
        ],
    };
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? q,
    String? status,
    String? branchId,
    String? gender,
    String? from,
    String? to,
  }) async {
    t.require(ClinicPermission.patientsView);
    if (status != null && !patientStatuses.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (gender != null && !patientGenders.contains(gender)) {
      throw const ApiException.badRequest('gender has an unsupported value.');
    }
    if (branchId != null) t.scope.require(branchId);
    final DateTime? fromD = from == null ? null : DateTime.tryParse(from);
    final DateTime? toD = to == null ? null : DateTime.tryParse(to);
    if ((from != null && fromD == null) || (to != null && toD == null)) {
      throw const ApiException.badRequest('from/to must be dates.');
    }
    final scoped = !t.scope.allBranches;
    if (scoped && t.scope.branchIds.length > 30) {
      throw const ApiException.forbidden(
        'Your branch access is too broad to list patients; ask for all-branch access.',
      );
    }
    final term = q?.trim();
    // Exact identifier lookups return at most a handful of records: they use
    // one equality filter and the remaining filters are applied afterwards
    // (scope included), so no per-combination index is needed.
    QueryFilter? identifier;
    String? namePrefix;
    if (term != null && term.isNotEmpty) {
      if (term.startsWith('pt_')) {
        identifier = QueryFilter('patientId', FilterOp.eq, term);
      } else if (RegExp(r'^mrn-?\d+$', caseSensitive: false).hasMatch(term)) {
        final digits = term.replaceAll(RegExp(r'\D'), '');
        identifier = QueryFilter(
          'mrn',
          FilterOp.eq,
          'MRN-${digits.padLeft(6, '0')}',
        );
      } else if (term.contains('@')) {
        identifier = QueryFilter('emailNorm', FilterOp.eq, term.toLowerCase());
      } else if (RegExp(r'^[+\d][\d\s\-]{6,}$').hasMatch(term)) {
        identifier = QueryFilter(
          'phoneNorm',
          FilterOp.eq,
          normalizePhone(term),
        );
      } else {
        final n = normalizeName(term);
        if (n.length < 2) {
          throw const ApiException.badRequest('Type at least 2 letters.');
        }
        namePrefix = n;
      }
    }
    bool visible(Map<String, Object?> p) =>
        t.scope.allows('${p['branchId']}') &&
        (status == null || p['status'] == status) &&
        (gender == null || p['gender'] == gender) &&
        (branchId == null || p['branchId'] == branchId);
    if (identifier != null) {
      final page = await runPaged(
        _s.d.store,
        DocQuery(
          _s.d.path(t, collection),
          filters: [identifier],
          orderBy: const OrderBy('createdAt', descending: true),
        ),
        req,
      );
      return Paged(page.docs.where((d) => visible(d.data)).toList(), page.meta);
    }
    final filters = <QueryFilter>[
      if (status != null) QueryFilter('status', FilterOp.eq, status),
      if (gender != null) QueryFilter('gender', FilterOp.eq, gender),
      if (branchId != null)
        QueryFilter('branchId', FilterOp.eq, branchId)
      else if (scoped)
        QueryFilter('branchId', FilterOp.inList, t.scope.branchIds.toList()),
    ];
    var order = const OrderBy('createdAt', descending: true);
    if (namePrefix != null) {
      filters
        ..add(QueryFilter('nameLower', FilterOp.gte, namePrefix))
        ..add(QueryFilter('nameLower', FilterOp.lt, '$namePrefix\uf8ff'));
      order = const OrderBy('nameLower');
    } else {
      if (fromD != null) {
        filters.add(QueryFilter('createdAt', FilterOp.gte, fromD.toUtc()));
      }
      if (toD != null) {
        filters.add(
          QueryFilter(
            'createdAt',
            FilterOp.lt,
            toD.toUtc().add(const Duration(days: 1)),
          ),
        );
      }
    }
    return runPaged(
      _s.d.store,
      DocQuery(_s.d.path(t, collection), filters: filters, orderBy: order),
      req,
    );
  }

  /// List rows: identification and masked contact details only. No clinical
  /// information is ever part of a search result.
  Map<String, Object?> listItem(Map<String, Object?> p) => {
    'patientId': p['patientId'],
    'mrn': p['mrn'],
    'fullName': p['fullName'],
    'preferredName': p['preferredName'],
    'dateOfBirth': p['dateOfBirth'],
    'gender': p['gender'],
    'maskedPhone': maskPhone(p['phone']),
    'maskedEmail': maskEmail(p['email']),
    'status': p['status'],
    'branchId': p['branchId'],
    'linked': p['patientAccountId'] != null,
    'createdAt': jsonSafe(p['createdAt']),
  };

  /// Full record for authorized staff. Internal search keys are removed and
  /// restricted notes need clinical access.
  Map<String, Object?> present(Map<String, Object?> p, TenantContext t) {
    final out = (jsonSafe(p)! as Map<String, Object?>)
      ..remove('seatSlot')
      ..remove('nameLower')
      ..remove('phoneNorm')
      ..remove('alternatePhoneNorm')
      ..remove('emailNorm');
    if (!t.can(ClinicPermission.historyView)) out.remove('restrictedNotes');
    return out;
  }
}

const Set<String> clinicalAlertCategories = {'medical', 'allergy'};

/// Emergency contact list shared by registration and the contacts endpoint.
abstract final class EmergencyContacts {
  static List<Map<String, Object?>>? parse(BodyReader r, String field) {
    final raw = r.body[field];
    if (raw is! List || raw.isEmpty || raw.length > 5) {
      r.addIssue(field, 'invalid_value', 'Provide 1 to 5 emergency contacts.');
      return null;
    }
    final out = <Map<String, Object?>>[];
    var preferred = 0;
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        r.addIssue('$field[$i]', 'invalid_type', 'Must be an object.');
        return null;
      }
      final c = BodyReader(item.cast<String, Object?>())
        ..rejectUnknown({
          'name',
          'relationship',
          'phone',
          'alternatePhone',
          'address',
          'preferred',
        });
      final name = c.str('name', min: 2, max: 100);
      final rel = c.str('relationship', min: 2, max: 40);
      final phone = c.phone('phone');
      final alt = c.phone('alternatePhone', required: false);
      final address = c.str('address', max: 200, required: false);
      final pref = c.boolean('preferred') ?? false;
      if (pref) preferred++;
      for (final issue in c.issues) {
        r.addIssue('$field[$i].${issue.field}', issue.code, issue.message);
      }
      out.add({
        'name': name,
        'relationship': rel,
        'phone': phone,
        'alternatePhone': alt,
        'address': address,
        'preferred': pref,
      });
    }
    if (preferred > 1) {
      r.addIssue(field, 'invalid_value', 'Only one contact can be preferred.');
    }
    return out;
  }
}
