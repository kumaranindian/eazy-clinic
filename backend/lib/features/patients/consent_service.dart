import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'patient_support.dart';

/// One consent purpose with the exact text the patient is shown. A decision
/// must name the [version] it was based on, so a changed text can never be
/// attributed to an older agreement.
class ConsentPurpose {
  const ConsentPurpose(this.type, this.purpose, this.text);
  final String type;
  final String purpose;
  final String text;
}

abstract final class ConsentCatalog {
  static const String version = '1.0';

  static const dataProcessing = 'data_processing';
  static const documentProcessing = 'document_processing';
  static const familyAccess = 'family_access';
  static const recordSharing = 'record_sharing';
  static const accountLinking = 'account_linking';
  static const other = 'other';

  static const List<ConsentPurpose> purposes = [
    ConsentPurpose(
      dataProcessing,
      'Collect and process my personal and medical information at this clinic',
      'I agree that this clinic may collect, store and use my personal and medical information to provide my care and manage my records. I can withdraw this consent at any time.',
    ),
    ConsentPurpose(
      'communication_sms',
      'Receive SMS messages from this clinic',
      'I agree to receive SMS messages about my appointments and care from this clinic.',
    ),
    ConsentPurpose(
      'communication_email',
      'Receive e-mail from this clinic',
      'I agree to receive e-mail about my appointments and care from this clinic.',
    ),
    ConsentPurpose(
      'communication_whatsapp',
      'Receive WhatsApp messages from this clinic',
      'I agree to receive WhatsApp messages about my appointments and care from this clinic.',
    ),
    ConsentPurpose(
      familyAccess,
      'Allow a family member or caregiver to access my information',
      'I agree that the family member or caregiver recorded with this consent may access the information described in their permission scope. I can revoke this at any time.',
    ),
    ConsentPurpose(
      recordSharing,
      'Share my records with another clinic',
      'I agree that this clinic may share the records I specify with another clinic I name. Nothing is shared without this consent.',
    ),
    ConsentPurpose(
      documentProcessing,
      'Upload and store my medical documents and photos',
      'I agree that this clinic may upload, store and process documents and photos about my health that I or the clinic provide.',
    ),
    ConsentPurpose(
      accountLinking,
      'Link my patient account to my record at this clinic',
      'I agree that my patient account may be linked to my record at this clinic. The link lets me see my own clinic information in the app. It does not share my records with any other clinic.',
    ),
    ConsentPurpose(
      other,
      'Another purpose described below',
      'I agree to the purpose described in this consent.',
    ),
  ];

  static ConsentPurpose? byType(String type) {
    for (final p in purposes) {
      if (p.type == type) return p;
    }
    return null;
  }
}

const List<String> consentMethods = [
  'in_person_signed',
  'in_person_verbal',
  'digital_form',
  'phone_recorded',
];

/// Who gave a decision. Staff are never a grantor: they only *record* the
/// decision of the patient (adult) or of a verified guardian (minor).
class Grantor {
  const Grantor(this.type, {this.name, this.relationship});
  final String type;
  final String? name;
  final String? relationship;

  Map<String, Object?> toMap() => {
    'type': type,
    'name': ?name,
    'relationship': ?relationship,
  };
}

/// Consent is a backend-controlled service: decisions are append-only records;
/// a revocation updates the original record's status and keeps the evidence.
class ConsentService {
  ConsentService(this._s);

  final PatientSupport _s;

  static const Set<String> _bodyFields = {
    'type',
    'decision',
    'textVersion',
    'grantedBy',
    'collectionMethod',
    'evidenceRef',
    'expiresAt',
    'purpose',
  };

  /// Validates who gave the decision against the patient's situation.
  /// Adults must decide for themselves; minors need a verified guardian.
  Grantor parseGrantor(
    BodyReader r,
    String field, {
    required bool minor,
    required DocData patient,
    bool required = true,
  }) {
    final g = r.object(field, required: required);
    if (g == null) {
      if (minor && !required) {
        r.addIssue(
          field,
          'guardian_required',
          'This patient is a minor: say which verified guardian is asking.',
        );
      }
      return const Grantor('patient');
    }
    g.rejectUnknown({'type', 'name', 'relationship'});
    final type = g.str('type', max: 20);
    if (type != 'patient' && type != 'guardian') {
      r.addIssue(
        '$field.type',
        'invalid_value',
        'Consent can only be given by the patient or, for a minor, a verified guardian.',
      );
      return const Grantor('patient');
    }
    if (type == 'patient' && minor) {
      r.addIssue(
        '$field.type',
        'guardian_required',
        'This patient is a minor: a verified guardian must give consent.',
      );
    }
    if (type == 'guardian') {
      final guardian = patient['guardian'];
      if (!minor) {
        r.addIssue(
          '$field.type',
          'not_a_minor',
          'An adult patient must give consent personally.',
        );
      } else if (guardian is! Map || guardian['verified'] != true) {
        r.addIssue(
          '$field.type',
          'guardian_unverified',
          'The guardian has not been verified for this patient.',
        );
      }
      return Grantor(
        'guardian',
        name: g.str('name', min: 2, max: 100),
        relationship: g.str('relationship', min: 2, max: 40),
      );
    }
    return const Grantor('patient');
  }

  /// The write that stores a decision; shared with patient registration.
  CreateOp decisionOp(
    String tenantId,
    String actorUid, {
    required String consentId,
    required String patientId,
    required String type,
    required String purpose,
    required String status,
    required Grantor grantor,
    required String method,
    String? evidenceRef,
    DateTime? expiresAt,
    String? patientAccountId,
  }) {
    final now = _s.d.now;
    return CreateOp('tenants/$tenantId/patient_consents/$consentId', {
      'consentId': consentId,
      'tenantId': tenantId,
      'patientId': patientId,
      'patientAccountId': patientAccountId,
      'type': type,
      'purpose': purpose,
      'textVersion': ConsentCatalog.version,
      'status': status,
      'grantedBy': grantor.toMap(),
      'collectionMethod': method,
      'evidenceRef': evidenceRef,
      'decidedAt': now,
      'expiresAt': expiresAt,
      'revokedAt': null,
      'createdAt': now,
      'createdBy': actorUid,
    });
  }

  Map<String, Object?> catalog() => {
    'version': ConsentCatalog.version,
    'methods': consentMethods,
    'purposes': [
      for (final p in ConsentCatalog.purposes)
        {'type': p.type, 'purpose': p.purpose, 'text': p.text},
    ],
  };

  Future<Paged> list(TenantContext t, String patientId, Request req) async {
    t.require(ClinicPermission.consentsView);
    await _s.load(t, patientId);
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, 'patient_consents'),
        filters: [QueryFilter('patientId', FilterOp.eq, patientId)],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
  }

  Future<Map<String, Object?>> record(
    TenantContext t,
    String patientId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consentsManage);
    final patient = await _s.load(t, patientId);
    _s.requireOpen(patient);
    final minor = await _s.isMinor(t, patient);
    final r = BodyReader(body)..rejectUnknown(_bodyFields);
    final type = r.str('type', max: 40);
    final purposeDef = type == null ? null : ConsentCatalog.byType(type);
    if (type != null && purposeDef == null) {
      r.addIssue('type', 'invalid_value', 'Unknown consent type.');
    }
    final decision = r.enumOf<String>('decision', const [
      'granted',
      'rejected',
    ], (v) => v);
    final version = r.str('textVersion', max: 10);
    if (version != null && version != ConsentCatalog.version) {
      r.addIssue(
        'textVersion',
        'outdated_text',
        'The consent text has changed. Show the current text and ask again.',
      );
    }
    final method = r.enumOf<String>(
      'collectionMethod',
      consentMethods,
      (v) => v,
    );
    final evidence = r.str('evidenceRef', max: 120, required: false);
    final custom = r.str(
      'purpose',
      min: 5,
      max: 200,
      required: type == 'other',
    );
    final expires = _expiry(r, body);
    final grantor = parseGrantor(
      r,
      'grantedBy',
      minor: minor,
      patient: patient,
    );
    r.throwIfInvalid();

    final id = 'cn_${newId(length: 12)}';
    final op = decisionOp(
      t.tenantId,
      t.uid,
      consentId: id,
      patientId: patientId,
      type: type!,
      purpose: custom ?? purposeDef!.purpose,
      status: decision!,
      grantor: grantor,
      method: method!,
      evidenceRef: evidence,
      expiresAt: expires,
      patientAccountId: patient['patientAccountId'] as String?,
    );
    await _s.d.store.transaction((tx) async {
      if (decision == 'granted' &&
          await _s.hasConsent(t, patientId, type, tx: tx)) {
        throw const ApiException.conflict(
          'This consent has already been granted.',
        );
      }
      tx.write([
        op,
        _s.auditOp(
          t,
          patientId,
          patient['branchId'] as String?,
          'consent.$decision',
          resourceType: 'consent',
          resourceId: id,
          after: {'type': type, 'grantor': grantor.type},
          requestId: requestId,
        ),
      ]);
    });
    return present({...op.data});
  }

  DateTime? _expiry(BodyReader r, Map<String, Object?> body) {
    final raw = body['expiresAt'];
    if (raw == null) return null;
    final v = raw is String ? DateTime.tryParse(raw) : null;
    if (v == null || !v.toUtc().isAfter(_s.d.now)) {
      r.addIssue(
        'expiresAt',
        'invalid_date',
        'expiresAt must be a future date-time.',
      );
      return null;
    }
    return v.toUtc();
  }

  Future<Map<String, Object?>> revoke(
    TenantContext t,
    String patientId,
    String consentId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consentsManage);
    final patient = await _s.load(t, patientId);
    final minor = await _s.isMinor(t, patient);
    final r = BodyReader(body)..rejectUnknown({'reason', 'requestedBy'});
    final reason = r.str('reason', min: 3, max: 300);
    final by = parseGrantor(
      r,
      'requestedBy',
      minor: minor,
      patient: patient,
      required: false,
    );
    r.throwIfInvalid();
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, 'patient_consents', consentId);
      final cur = await tx.get(path);
      if (cur == null || cur['patientId'] != patientId) {
        throw const ApiException.notFound('Consent not found.');
      }
      if (cur['status'] != 'granted') {
        throw const ApiException.conflict(
          'Only a granted consent can be revoked.',
        );
      }
      final patch = {
        'status': 'revoked',
        'revokedAt': now,
        'revokedBy': t.uid,
        'revokedByType': by.type,
        'revokeReason': reason,
      };
      tx.write([
        UpdateOp(path, patch),
        _s.auditOp(
          t,
          patientId,
          patient['branchId'] as String?,
          'consent.revoked',
          resourceType: 'consent',
          resourceId: consentId,
          before: {'status': 'granted'},
          after: {'status': 'revoked', 'type': cur['type']},
          reason: reason,
          requestId: requestId,
        ),
      ]);
      return present({...cur, ...patch});
    });
  }

  static Map<String, Object?> present(Map<String, Object?> c) =>
      jsonSafe(c)! as Map<String, Object?>;
}
