import 'dart:convert';
import 'dart:math';

import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../auth/domain/auth_context.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import 'consent_service.dart';
import 'family_service.dart';
import 'patient_support.dart';

const List<String> linkVerificationMethods = [
  'government_id_sighted',
  'other_document_sighted',
  'known_patient_in_person',
];

const Duration linkCodeLifetime = Duration(hours: 24);

/// Links a global patient account to ONE clinic record, only after the clinic
/// has identified the person in person and the account holder (with a verified
/// e-mail) presents the one-time code the clinic issued. Phone or e-mail
/// similarity never links anything, and a link shares no medical data.
class PatientIdentityService {
  PatientIdentityService(this._s, this._accounts, this._consents);

  final PatientSupport _s;
  final PatientAccountService _accounts;
  final ConsentService _consents;

  static const String _alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static final Random _rng = Random.secure();

  DocumentStore get _store => _s.d.store;
  DateTime get _now => _s.d.now;

  static String _hash(String code) => sha256
      .convert(
        utf8.encode(code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '')),
      )
      .toString();

  static String _newCode() {
    String block() => String.fromCharCodes(
      List.generate(
        4,
        (_) => _alphabet.codeUnitAt(_rng.nextInt(_alphabet.length)),
      ),
    );
    return 'ECL-${block()}-${block()}-${block()}';
  }

  // ------------------------------------------------------------ staff side

  Future<Map<String, Object?>> createLinkCode(
    TenantContext t,
    String patientId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientsLinkAccount);
    final r = BodyReader(body)
      ..rejectUnknown({'verificationMethod', 'identityConfirmed'});
    final method = r.enumOf<String>(
      'verificationMethod',
      linkVerificationMethods,
      (v) => v,
    );
    if (r.boolean('identityConfirmed', required: true) != true) {
      r.addIssue(
        'identityConfirmed',
        'required',
        'Confirm that you identified the patient before issuing a code.',
      );
    }
    r.throwIfInvalid();
    final code = _newCode();
    final codeId = 'lc_${newId(length: 12)}';
    final expires = _now.add(linkCodeLifetime);
    await _store.transaction((tx) async {
      final p = await _s.loadIn(tx, t, patientId);
      _s.requireOpen(p);
      if (p['status'] != 'active') {
        throw const ApiException.conflict('The patient must be active.');
      }
      if (p['patientAccountId'] != null) {
        throw const ApiException.conflict(
          'This record is already linked to a patient account.',
        );
      }
      final minor = await _s.isMinor(t, p);
      final guardian = p['guardian'];
      if (minor && (guardian is! Map || guardian['verified'] != true)) {
        throw const ApiException.conflict(
          'Verify the guardian before linking a minor.',
        );
      }
      final old = await tx.query(
        DocQuery(
          _s.d.path(t, 'patient_link_codes'),
          filters: [
            QueryFilter('patientId', FilterOp.eq, patientId),
            const QueryFilter('status', FilterOp.eq, 'pending'),
          ],
          limit: 20,
        ),
      );
      tx.write([
        for (final o in old)
          UpdateOp(o.path, {'status': 'revoked', 'revokedAt': _now}),
        CreateOp(_s.d.path(t, 'patient_link_codes', codeId), {
          'codeId': codeId,
          'tenantId': t.tenantId,
          'patientId': patientId,
          'codeHash': _hash(code),
          'verificationMethod': method,
          'forMinor': minor,
          'guardianVerified': minor,
          'status': 'pending',
          'createdBy': t.uid,
          'createdAt': _now,
          'expiresAt': expires,
        }),
        _s.auditOp(
          t,
          patientId,
          p['branchId'] as String?,
          'patient.link_code_created',
          resourceType: 'identity_link',
          resourceId: codeId,
          after: {'verificationMethod': method, 'forMinor': minor},
          requestId: requestId,
        ),
      ]);
    });
    // The code is shown once; only its hash is stored.
    return {
      'code': code,
      'expiresAt': expires.toUtc().toIso8601String(),
      'patientId': patientId,
    };
  }

  Future<Map<String, Object?>> unlinkByClinic(
    TenantContext t,
    String patientId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientsLinkAccount);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    return _unlink(
      tenantId: t.tenantId,
      patientId: patientId,
      actorUid: t.uid,
      actorRole: t.role.wireName,
      reason: reason!,
      requestId: requestId,
      scope: t,
    );
  }

  Future<Map<String, Object?>> _unlink({
    required String tenantId,
    required String patientId,
    required String actorUid,
    required String actorRole,
    required String reason,
    String? requestId,
    TenantContext? scope,
  }) async {
    final patientPath = 'tenants/$tenantId/patients/$patientId';
    return _store.transaction((tx) async {
      final p = await tx.get(patientPath);
      if (p == null ||
          (scope != null && !scope.scope.allows('${p['branchId']}'))) {
        throw const ApiException.notFound('Patient not found.');
      }
      final accountId = p['patientAccountId'];
      if (accountId == null) {
        throw const ApiException.conflict('This record is not linked.');
      }
      final links = await tx.query(
        DocQuery(
          'tenants/$tenantId/patient_identity_links',
          filters: [
            QueryFilter('patientId', FilterOp.eq, patientId),
            const QueryFilter('status', FilterOp.eq, 'linked'),
          ],
          limit: 5,
        ),
      );
      tx.write([
        UpdateOp(patientPath, {
          'patientAccountId': null,
          'updatedAt': _now,
          'updatedBy': actorUid,
        }),
        for (final l in links)
          UpdateOp(l.path, {
            'status': 'unlinked',
            'unlinkedAt': _now,
            'unlinkedBy': actorUid,
            'unlinkReason': reason,
          }),
        UpdateOp('patient_clinic_links/${tenantId}_$patientId', {
          'status': 'unlinked',
          'unlinkedAt': _now,
        }),
        CreateOp('tenants/$tenantId/patient_audit_logs/${newId()}', {
          'tenantId': tenantId,
          'branchId': p['branchId'],
          'patientId': patientId,
          'action': 'patient.account_unlinked',
          'resourceType': 'identity_link',
          'resourceId': patientId,
          'actorUid': actorUid,
          'actorRole': actorRole,
          'reason': reason,
          'requestId': requestId,
          'before': {'linked': true},
          'after': {'linked': false},
          'timestamp': _now,
        }),
      ]);
      return {'patientId': patientId, 'linked': false};
    });
  }

  // ---------------------------------------------------------- patient side

  Future<Map<String, Object?>> claim(
    AuthContext ctx,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'code', 'forAccountId'});
    final code = r.str('code', min: 8, max: 30);
    final forAccount = r.str('forAccountId', max: 40, required: false);
    r.throwIfInvalid();
    final me = await _accounts.requireAccount(ctx);
    if (!ctx.identity.emailVerified) {
      throw const ApiException.forbidden(
        'Verify your e-mail address before linking a clinic record.',
      );
    }
    // The account the record will be linked to: yourself or a dependent you
    // are the guardian of.
    var target = me;
    if (forAccount != null && forAccount != me['accountId']) {
      final dep = await _store.get('patient_accounts/$forAccount');
      if (dep == null ||
          dep['kind'] != 'dependent' ||
          dep['managedByAccountId'] != me['accountId']) {
        throw const ApiException.notFound('Patient account not found.');
      }
      target = dep;
    }
    const generic = 'This code is not valid or has expired.';
    final found = await _store.query(
      DocQuery(
        'patient_link_codes',
        collectionGroup: true,
        filters: [QueryFilter('codeHash', FilterOp.eq, _hash(code!))],
        limit: 2,
      ),
    );
    if (found.length != 1) throw const ApiException.badRequest(generic);
    final codePath = found.single.path;
    final tenantId = '${found.single.data['tenantId']}';
    final patientId = '${found.single.data['patientId']}';
    final targetId = target['accountId']! as String;
    final isDependent = target['kind'] == 'dependent';
    final tenantDoc = await _store.get('tenants/$tenantId');
    final linkKey = '${tenantId}_$patientId';

    return _store.transaction((tx) async {
      final c = await tx.get(codePath);
      final exp = c?['expiresAt'];
      if (c == null ||
          c['status'] != 'pending' ||
          exp is! DateTime ||
          !exp.isAfter(_now)) {
        throw const ApiException.badRequest(generic);
      }
      // a dependent can only be linked through a clinic-verified guardian
      if (isDependent != (c['forMinor'] == true)) {
        throw const ApiException.badRequest(generic);
      }
      final p = await tx.get('tenants/$tenantId/patients/$patientId');
      if (p == null || p['status'] != 'active') {
        throw const ApiException.badRequest(generic);
      }
      if (p['patientAccountId'] != null) {
        throw const ApiException.conflict(
          'This record is already linked to an account.',
        );
      }
      final mine = await tx.query(
        DocQuery(
          'patient_clinic_links',
          filters: [
            QueryFilter('accountId', FilterOp.eq, targetId),
            QueryFilter('tenantId', FilterOp.eq, tenantId),
            const QueryFilter('status', FilterOp.eq, 'linked'),
          ],
          limit: 2,
        ),
      );
      if (mine.isNotEmpty) {
        throw const ApiException.conflict(
          'This account is already linked to a record at this clinic.',
        );
      }
      final prior = await tx.get('patient_clinic_links/$linkKey');
      final identityLinkId = 'il_${newId(length: 12)}';
      final guardianRel = isDependent
          ? await tx.query(
              DocQuery(
                'family_relationships',
                filters: [
                  QueryFilter(
                    'requesterAccountId',
                    FilterOp.eq,
                    me['accountId'],
                  ),
                  QueryFilter('subjectAccountId', FilterOp.eq, targetId),
                ],
                limit: 5,
              ),
            )
          : const <StoredDoc>[];
      final linkDoc = {
        'linkId': linkKey,
        'accountId': targetId,
        'tenantId': tenantId,
        'patientId': patientId,
        'mrn': p['mrn'],
        'clinicName': tenantDoc?['clinicName'],
        'status': 'linked',
        'linkedAt': _now,
      };
      tx.write([
        UpdateOp(codePath, {
          'status': 'used',
          'usedAt': _now,
          'usedByAccountId': targetId,
        }),
        UpdateOp('tenants/$tenantId/patients/$patientId', {
          'patientAccountId': targetId,
          'updatedAt': _now,
        }),
        CreateOp('tenants/$tenantId/patient_identity_links/$identityLinkId', {
          'linkId': identityLinkId,
          'tenantId': tenantId,
          'patientId': patientId,
          'accountId': targetId,
          'status': 'linked',
          'method': 'clinic_issued_code',
          'verificationMethod': c['verificationMethod'],
          'linkedBy': ctx.user.uid,
          'linkedAt': _now,
        }),
        if (prior == null)
          CreateOp('patient_clinic_links/$linkKey', linkDoc)
        else
          UpdateOp('patient_clinic_links/$linkKey', linkDoc),
        // the account holder's own consent to the link is recorded
        _consents.decisionOp(
          tenantId,
          ctx.user.uid,
          consentId: 'cn_${newId(length: 12)}',
          patientId: patientId,
          type: ConsentCatalog.accountLinking,
          purpose: ConsentCatalog.byType(
            ConsentCatalog.accountLinking,
          )!.purpose,
          status: 'granted',
          grantor: isDependent
              ? Grantor(
                  'guardian',
                  name: '${me['displayName']}',
                  relationship: 'guardian',
                )
              : const Grantor('patient'),
          method: 'digital_form',
          evidenceRef: 'link_code:${c['codeId']}',
          patientAccountId: targetId,
        ),
        // a clinic-verified guardian relationship, valid for this clinic only
        for (final rel in guardianRel)
          if (rel.data['status'] == 'pending')
            UpdateOp(rel.path, {
              'verificationStatus': 'verified',
              'status': 'active',
              'scopeTenantId': tenantId,
              'verifiedBy': {
                'type': 'clinic',
                'tenantId': tenantId,
                'uid': c['createdBy'],
              },
              'updatedAt': _now,
            }),
        CreateOp('tenants/$tenantId/patient_audit_logs/${newId()}', {
          'tenantId': tenantId,
          'branchId': p['branchId'],
          'patientId': patientId,
          'action': 'patient.account_linked',
          'resourceType': 'identity_link',
          'resourceId': identityLinkId,
          'actorUid': ctx.user.uid,
          'actorRole': 'patient',
          'reason': null,
          'requestId': requestId,
          'before': {'linked': false},
          'after': {'linked': true, 'dependent': isDependent},
          'timestamp': _now,
        }),
      ]);
      // no clinical data and no demographics are returned
      return {
        'linkId': linkKey,
        'tenantId': tenantId,
        'patientId': patientId,
        'mrn': p['mrn'],
        'clinicName': tenantDoc?['clinicName'],
        'accountId': targetId,
        'status': 'linked',
      };
    });
  }

  Future<Map<String, Object?>> unlinkByPatient(
    AuthContext ctx,
    String linkId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 3, max: 300, required: false);
    r.throwIfInvalid();
    final me = await _accounts.requireAccount(ctx);
    final link = await _store.get('patient_clinic_links/$linkId');
    // only the linked account (or its guardian) can end its own link
    var owns = link != null && link['accountId'] == me['accountId'];
    if (link != null && !owns) {
      final dep = await _store.get('patient_accounts/${link['accountId']}');
      owns = dep != null && dep['managedByAccountId'] == me['accountId'];
    }
    if (link == null || !owns || link['status'] != 'linked') {
      throw const ApiException.notFound('Link not found.');
    }
    return _unlink(
      tenantId: '${link['tenantId']}',
      patientId: '${link['patientId']}',
      actorUid: ctx.user.uid,
      actorRole: 'patient',
      reason: reason ?? 'Unlinked by the account holder',
      requestId: requestId,
    );
  }
}
