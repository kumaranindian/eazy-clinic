import 'dart:convert';
import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:crypto/crypto.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/object_storage.dart';
import '../platform/audit/audit_service.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'compliance_core.dart';
import 'compliance_profile_service.dart';

/// Hands an expiry alert to the notification pipeline (wired to the
/// notification hub in the clinic module).
typedef ComplianceNotifier =
    Future<void> Function({
      required String tenantId,
      required String staffUid,
      required String dedupeKey,
      required String title,
      required String body,
    });

const String disclaimer =
    'This checklist organises evidence. It is not legal advice and does not '
    'state that a clinic is compliant, licensed or approved. Requirements are '
    'working drafts until reviewed by qualified counsel.';

/// A clinic's compliance workflow: applicability (set by a platform
/// reviewer), evidence (uploaded by the clinic, reviewed by the platform),
/// credentials, and expiry alerts.
///
/// Safe defaults: nothing applies until a reviewer says so; a requirement is
/// `not_assessed` until evidence is reviewed; an approval stops counting when
/// it expires or when the requirement it approved changes. No field anywhere
/// says "compliant".
class TenantComplianceService {
  TenantComplianceService(
    this._store,
    this._audit,
    this._profiles,
    this._storage, {
    DateTime Function()? clock,
    this.notifier,
  }) : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final ComplianceProfileService _profiles;
  final ObjectStorage _storage;
  final DateTime Function() _clock;
  ComplianceNotifier? notifier;

  DateTime get _now => _clock().toUtc();

  String _p(String tenantId, String collection, [String? id]) =>
      'tenants/$tenantId/$collection${id == null ? '' : '/$id'}';

  static String itemKey(String profileKey, String reqKey) =>
      '${profileKey}__$reqKey';

  FieldIssue _issue(String f, String c, String m) =>
      FieldIssue(field: f, code: c, message: m);

  DateTime? _dateField(BodyReader r, String f, {bool required = false}) {
    final v = r.str(f, min: 10, max: 10, required: required);
    if (v == null) return null;
    final d = DateTime.tryParse(v);
    if (d == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
      r.addIssue(f, 'invalid_date', '$f must be a date like 2027-03-31.');
      return null;
    }
    return DateTime.utc(d.year, d.month, d.day);
  }

  // ---------------------------------------------------------------- tenant

  Future<DocData> _tenant(String tenantId) async {
    final t = await _store.get('tenants/$tenantId');
    if (t == null) throw const ApiException.notFound('Clinic not found.');
    return t;
  }

  // ------------------------------------------------------------- dashboard

  /// The compliance view of one clinic. Used by the clinic and by platform
  /// reviewers. Statuses are *effective* statuses (expiry and changed
  /// requirements applied), so no stale approval can show.
  Future<Map<String, Object?>> dashboard(String tenantId) async {
    final tenant = await _tenant(tenantId);
    final country = tenant['countryCode'] as String?;
    final now = _now;
    if (country == null) {
      return {
        'tenantId': tenantId,
        'countryCode': null,
        'disclaimer': disclaimer,
        'readiness': 'country_not_assigned',
        'profiles': <Object?>[],
        'credentials': await _credentialSummary(tenantId, now),
        'counts': _emptyCounts(),
      };
    }
    final profiles =
        (await _store.query(
            DocQuery(
              ComplianceProfileService.collection,
              filters: [QueryFilter('countryCode', FilterOp.eq, country)],
              limit: 100,
            ),
          )).map((d) => d.data).toList()
          ..sort((a, b) => '${a['key']}'.compareTo('${b['key']}'));
    final applic = {
      for (final d in await _store.query(
        DocQuery(_p(tenantId, 'compliance_applicability'), limit: 200),
      ))
        d.id: d.data,
    };
    final items = {
      for (final d in await _store.query(
        DocQuery(_p(tenantId, 'compliance_items'), limit: 2000),
      ))
        d.id: d.data,
    };

    final counts = _emptyCounts();
    final outProfiles = <Map<String, Object?>>[];
    var anyApplies = false;
    var anyUnvalidated = false;
    var anyOpen = false;
    for (final p in profiles) {
      final key = '${p['key']}';
      final a = applic[key];
      final applicability =
          Applicability.tryParse(a?['status']) ?? Applicability.unknown;
      // retired profiles only matter where they were already confirmed
      if (p['status'] == 'retired' && applicability == Applicability.unknown) {
        continue;
      }
      final summary = <String, int>{
        for (final s in ComplianceStatus.values) s.wireName: 0,
      };
      final reqs = <Map<String, Object?>>[];
      if (applicability == Applicability.applies) {
        anyApplies = true;
        final lr = (p['legalReview'] as Map?)?['status'];
        if (lr != 'reviewed') anyUnvalidated = true;
        for (final r
            in (p['requirements']! as List<Object?>)
                .cast<Map<String, Object?>>()) {
          final item = items[itemKey(key, '${r['key']}')];
          final status = effectiveStatus(item: item, requirement: r, now: now);
          summary[status.wireName] = summary[status.wireName]! + 1;
          counts[status.wireName] = counts[status.wireName]! + 1;
          if (status != ComplianceStatus.approved &&
              status != ComplianceStatus.notApplicable) {
            anyOpen = true;
          }
          reqs.add({
            'key': r['key'],
            'title': r['title'],
            'description': r['description'],
            'category': r['category'],
            'appliesTo': r['appliesTo'],
            'evidence': r['evidence'],
            'goLiveBlocking': r['goLiveBlocking'],
            'source': r['source'],
            'confidence': r['confidence'],
            'status': status.wireName,
            'storedStatus': item?['status'],
            'expiresAt': jsonSafe(item?['expiresAt']),
            'evidenceId': item?['evidenceId'],
            'reviewedBy': item?['reviewedBy'],
            'reviewedAt': jsonSafe(item?['reviewedAt']),
            'note': item?['note'],
            'requirementChanged':
                item != null &&
                item['status'] == 'approved' &&
                item['requirementHash'] != requirementHash(r),
          });
        }
      }
      outProfiles.add({
        'key': key,
        'title': p['title'],
        'authority': p['authority'],
        'jurisdiction': p['jurisdiction'],
        'domain': p['domain'],
        'appliesWhenNote': p['appliesWhenNote'],
        'status': p['status'],
        'version': p['version'],
        'legalReview': jsonSafe(p['legalReview']),
        'applicability': {
          'status': applicability.wireName,
          'reason': a?['reason'],
          'setBy': a?['setBy'],
          'setAt': jsonSafe(a?['setAt']),
        },
        'summary': summary,
        'requirements': reqs,
      });
    }
    final readiness = !anyApplies
        ? 'applicability_unconfirmed'
        : anyUnvalidated
        ? 'awaiting_legal_validation'
        : anyOpen
        ? 'incomplete'
        : 'all_required_evidence_approved';
    return {
      'tenantId': tenantId,
      'countryCode': country,
      'disclaimer': disclaimer,
      'readiness': readiness,
      'profiles': outProfiles,
      'credentials': await _credentialSummary(tenantId, now),
      'counts': counts,
    };
  }

  Map<String, int> _emptyCounts() => {
    for (final s in ComplianceStatus.values) s.wireName: 0,
  };

  // ----------------------------------------------------------- applicability

  /// Platform reviewer: confirm that a profile applies, does not apply, or
  /// reset it to unknown. The profile must belong to the clinic's country.
  Future<Map<String, Object?>> setApplicability(
    String tenantId,
    String profileKey,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'status', 'reason'});
    final status = r.enumOf<Applicability>(
      'status',
      Applicability.values,
      (e) => e.wireName,
    );
    final reason = r.str('reason', min: 3, max: 500);
    r.throwIfInvalid();
    final tenant = await _tenant(tenantId);
    final profile = await _profiles.raw(profileKey);
    if (profile == null) {
      throw const ApiException.notFound('Profile not found.');
    }
    if (profile['countryCode'] != tenant['countryCode']) {
      throw const ApiException.conflict(
        'That profile belongs to a different country than the clinic.',
      );
    }
    final path = _p(tenantId, 'compliance_applicability', profileKey);
    final existing = await _store.get(path);
    final now = _now;
    final doc = {
      'profileKey': profileKey,
      'status': status!.wireName,
      'reason': reason,
      'setBy': actor.uid,
      'setAt': now,
      'profileVersionAtSet': profile['version'],
    };
    await _store.commit([
      if (existing == null) CreateOp(path, doc) else UpdateOp(path, doc),
      _history(
        tenantId,
        'applicability_set',
        actor,
        profileKey: profileKey,
        detail: status.wireName,
      ),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: 'compliance.applicability_set',
          targetType: 'compliance_profile',
          targetId: profileKey,
          tenantId: tenantId,
          requestId: requestId,
          reason: reason,
          before: {'status': existing?['status'] ?? 'unknown'},
          after: {'status': status.wireName},
        ),
      ),
    ]);
    return {'profileKey': profileKey, 'status': status.wireName};
  }

  CreateOp _history(
    String tenantId,
    String type,
    Actor actor, {
    String? profileKey,
    String? requirementKey,
    String? evidenceId,
    String? credentialId,
    String? detail,
  }) => CreateOp(_p(tenantId, 'compliance_history', newId()), {
    'type': type,
    'actorUid': actor.uid,
    'actorRole': actor.role,
    'profileKey': ?profileKey,
    'requirementKey': ?requirementKey,
    'evidenceId': ?evidenceId,
    'credentialId': ?credentialId,
    'detail': ?detail,
    'at': _now,
  });

  Future<List<Map<String, Object?>>> history(
    String tenantId, {
    int limit = 100,
  }) async {
    final rows = await _store.query(
      DocQuery(
        _p(tenantId, 'compliance_history'),
        orderBy: const OrderBy('at', descending: true),
        limit: limit,
      ),
    );
    return [for (final r in rows) jsonSafe(r.data)! as Map<String, Object?>];
  }

  // ---------------------------------------------------------------- evidence

  Map<String, Object?> presentEvidence(Map<String, Object?> e) =>
      (jsonSafe(e)! as Map<String, Object?>)
        ..remove('storagePath')
        ..remove('sha256');

  Future<List<Map<String, Object?>>> listEvidence(
    String tenantId, {
    String? status,
  }) async {
    final rows = await _store.query(
      DocQuery(
        _p(tenantId, 'compliance_evidence'),
        filters: [
          if (status != null) QueryFilter('status', FilterOp.eq, status),
        ],
        limit: 500,
      ),
    );
    return [for (final r in rows) presentEvidence(r.data)]
      ..sort((a, b) => '${b['uploadedAt']}'.compareTo('${a['uploadedAt']}'));
  }

  (Uint8List, String) _decode(BodyReader r, String declaredField) {
    final data = r.str('dataBase64', max: (maxEvidenceBytes * 4 ~/ 3) + 16);
    r.throwIfInvalid();
    final Uint8List bytes;
    try {
      bytes = base64Decode(data!);
    } on FormatException {
      throw ApiException.validation([
        _issue(
          'dataBase64',
          'invalid_base64',
          'The file data is not valid base64.',
        ),
      ]);
    }
    if (bytes.isEmpty || bytes.length > maxEvidenceBytes) {
      throw ApiException.validation([
        _issue(
          'dataBase64',
          'too_large',
          'The file must be between 1 byte and 3 MB.',
        ),
      ]);
    }
    final mime = detectEvidenceMime(bytes);
    if (mime == null) {
      throw ApiException.validation([
        _issue(
          'dataBase64',
          'unsupported_file',
          'Only PDF, PNG and JPEG files are accepted.',
        ),
      ]);
    }
    return (bytes, mime);
  }

  /// Clinic: upload evidence for one requirement. The requirement moves to
  /// `under_review`; only a platform reviewer can approve it.
  Future<Map<String, Object?>> uploadEvidence(
    String tenantId,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)
      ..rejectUnknown({
        'profileKey',
        'requirementKey',
        'kind',
        'title',
        'documentNumber',
        'issuerName',
        'validFrom',
        'validTo',
        'contentType',
        'dataBase64',
      });
    final profileKey = r.str('profileKey', min: 3, max: 60);
    final reqKey = r.str('requirementKey', min: 3, max: 60);
    final kind = r.enumOf<String>('kind', evidenceKinds, (v) => v);
    final title = r.str('title', min: 3, max: 120);
    final number = r.str('documentNumber', min: 1, max: 60, required: false);
    final issuer = r.str('issuerName', min: 2, max: 120, required: false);
    final validFrom = _dateField(r, 'validFrom');
    final validTo = _dateField(r, 'validTo');
    r.str('contentType', max: 60, required: false); // declared type is ignored
    r.throwIfInvalid();
    if (validFrom != null && validTo != null && validTo.isBefore(validFrom)) {
      throw ApiException.validation([
        _issue(
          'validTo',
          'invalid_range',
          'validTo must not be before validFrom.',
        ),
      ]);
    }
    final (bytes, mime) = _decode(r, 'dataBase64');

    final profile = await _profiles.raw(profileKey!);
    if (profile == null) {
      throw const ApiException.notFound('Profile not found.');
    }
    final req = (profile['requirements']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((e) => e['key'] == reqKey)
        .firstOrNull;
    if (req == null) {
      throw const ApiException.notFound('Requirement not found.');
    }
    final ev = req['evidence']! as Map<String, Object?>;
    if (ev['expiryTracked'] == true) {
      if (validTo == null) {
        throw ApiException.validation([
          _issue(
            'validTo',
            'required',
            'This requirement tracks expiry: enter the date the document stops being valid.',
          ),
        ]);
      }
      if (!validTo.isAfter(_now)) {
        throw ApiException.validation([
          _issue('validTo', 'expired', 'The document has already expired.'),
        ]);
      }
    }

    final id = 'ce_${newId(length: 16)}';
    final path = 'tenants/$tenantId/compliance/$id';
    final key = itemKey(profileKey, reqKey!);
    await _store.transaction((tx) async {
      final ap = await tx.get(
        _p(tenantId, 'compliance_applicability', profileKey),
      );
      if (ap?['status'] != 'applies') {
        throw const ApiException.conflict(
          'This requirement is not active for your clinic yet. A reviewer must confirm that the profile applies.',
        );
      }
      final item = await tx.get(_p(tenantId, 'compliance_items', key));
      final from =
          ComplianceStatus.tryParse(item?['status']) ??
          ComplianceStatus.notAssessed;
      if (from == ComplianceStatus.notApplicable) {
        throw const ApiException.conflict(
          'This requirement was marked not applicable by a reviewer.',
        );
      }
      final now = _now;
      final previous = item?['evidenceId'] as String?;
      // only a file that is still "live" is superseded; a rejected file keeps
      // its status as part of the record
      final previousDoc = previous == null
          ? null
          : await tx.get(_p(tenantId, 'compliance_evidence', previous));
      final supersede =
          previousDoc != null &&
          (previousDoc['status'] == 'submitted' ||
              previousDoc['status'] == 'accepted');
      tx.write([
        CreateOp(
          _p(tenantId, 'compliance_evidence', id),
          {
            'evidenceId': id,
            'tenantId': tenantId,
            'profileKey': profileKey,
            'requirementKey': reqKey,
            'kind': kind,
            'title': title,
            'documentNumber': number,
            'issuerName': issuer,
            'validFrom': validFrom,
            'validTo': validTo,
            'mime': mime,
            'sizeBytes': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
            'storagePath': path,
            'status': 'submitted',
            'uploadedBy': actor.uid,
            'uploadedAt': now,
          }..removeWhere((k, v) => v == null),
        ),
        if (supersede)
          UpdateOp(_p(tenantId, 'compliance_evidence', previous!), {
            'status': 'superseded',
          }),
        _itemWrite(item, tenantId, key, {
          'profileKey': profileKey,
          'requirementKey': reqKey,
          'status': ComplianceStatus.underReview.wireName,
          'evidenceId': id,
          'expiresAt': null,
          'profileVersion': profile['version'],
          'requirementHash': requirementHash(req),
          'updatedAt': now,
        }),
        _history(
          tenantId,
          'evidence_submitted',
          actor,
          profileKey: profileKey,
          requirementKey: reqKey,
          evidenceId: id,
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'compliance.evidence_submitted',
            targetType: 'compliance_evidence',
            targetId: id,
            tenantId: tenantId,
            requestId: requestId,
            after: {
              'profileKey': profileKey,
              'requirementKey': reqKey,
              'status': 'under_review',
            },
          ),
        ),
      ]);
    });
    // The file is stored after the records commit so a failed commit never
    // leaves a record without a file; a failed store leaves a record that a
    // reviewer will not be able to open (and the clinic can upload again).
    await _storage.put(path, bytes, mime);
    return presentEvidence(
      (await _store.get(_p(tenantId, 'compliance_evidence', id)))!,
    );
  }

  WriteOp _itemWrite(
    DocData? existing,
    String tenantId,
    String key,
    Map<String, Object?> fields,
  ) => existing == null
      ? CreateOp(_p(tenantId, 'compliance_items', key), {
          ...fields,
          'createdAt': _now,
        })
      : UpdateOp(_p(tenantId, 'compliance_items', key), fields);

  /// Reads an evidence file. Every read is recorded in the clinic's
  /// compliance history.
  Future<({Uint8List bytes, String mime, String filename})> downloadEvidence(
    String tenantId,
    String evidenceId,
    Actor actor, {
    String? requestId,
  }) async {
    final e = await _store.get(_p(tenantId, 'compliance_evidence', evidenceId));
    final path = e?['storagePath'] as String?;
    if (e == null ||
        path == null ||
        !path.startsWith('tenants/$tenantId/compliance/')) {
      throw const ApiException.notFound('Evidence not found.');
    }
    final file = await _storage.get(path);
    if (file == null) {
      throw const ApiException.notFound('The file is not available.');
    }
    await _store.commit([
      _history(tenantId, 'evidence_viewed', actor, evidenceId: evidenceId),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: 'compliance.evidence_viewed',
          targetType: 'compliance_evidence',
          targetId: evidenceId,
          tenantId: tenantId,
          requestId: requestId,
        ),
      ),
    ]);
    // A generic file name: titles and document numbers never go into names.
    return (
      bytes: file.$1,
      mime: file.$2,
      filename: 'evidence-$evidenceId.${extensionForMime(file.$2)}',
    );
  }

  /// Platform reviewer: accept or reject submitted evidence. Accepting sets
  /// the requirement to `approved` and starts its expiry clock.
  Future<Map<String, Object?>> reviewEvidence(
    String tenantId,
    String evidenceId,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'decision', 'note'});
    final decision = r.enumOf<String>('decision', const [
      'accept',
      'reject',
    ], (v) => v);
    final note = r.str('note', min: 3, max: 500, required: false);
    if (decision == 'reject' && (note == null || note.trim().length < 3)) {
      r.addIssue('note', 'required', 'Say why the evidence is rejected.');
    }
    r.throwIfInvalid();
    late Map<String, Object?> result;
    await _store.transaction((tx) async {
      final e = await tx.get(_p(tenantId, 'compliance_evidence', evidenceId));
      if (e == null) throw const ApiException.notFound('Evidence not found.');
      if (e['status'] != 'submitted') {
        throw const ApiException.conflict(
          'Only submitted evidence can be reviewed.',
        );
      }
      final profileKey = e['profileKey'] as String?;
      final reqKey = e['requirementKey'] as String?;
      final now = _now;
      if (profileKey == null || reqKey == null) {
        throw const ApiException.conflict(
          'This file belongs to a credential: use the credential verification.',
        );
      }
      final key = itemKey(profileKey, reqKey);
      final item = await tx.get(_p(tenantId, 'compliance_items', key));
      if (item == null ||
          item['evidenceId'] != evidenceId ||
          item['status'] != 'under_review') {
        throw const ApiException.conflict(
          'This evidence is no longer the one under review.',
        );
      }
      final profile = await tx.get(
        '${ComplianceProfileService.collection}/$profileKey',
      );
      final req = (profile?['requirements'] as List?)
          ?.cast<Map<String, Object?>>()
          .where((x) => x['key'] == reqKey)
          .firstOrNull;
      if (req == null) {
        throw const ApiException.conflict('The requirement no longer exists.');
      }
      final accept = decision == 'accept';
      final tracked =
          (req['evidence']! as Map<String, Object?>)['expiryTracked'] == true;
      DateTime? expires;
      if (accept && tracked) {
        expires = e['validTo'] as DateTime?;
        if (expires == null || !expires.isAfter(now)) {
          throw const ApiException.conflict(
            'The document has no future expiry date, so it cannot be approved.',
          );
        }
      }
      tx.write([
        UpdateOp(_p(tenantId, 'compliance_evidence', evidenceId), {
          'status': accept ? 'accepted' : 'rejected',
          'reviewedBy': actor.uid,
          'reviewedAt': now,
          'reviewNote': note,
        }),
        UpdateOp(_p(tenantId, 'compliance_items', key), {
          'status': accept ? 'approved' : 'rejected',
          'expiresAt': expires,
          'reviewedBy': actor.uid,
          'reviewedAt': now,
          'note': note,
          'profileVersion': profile!['version'],
          'requirementHash': requirementHash(req),
          'updatedAt': now,
        }),
        _history(
          tenantId,
          accept ? 'evidence_accepted' : 'evidence_rejected',
          actor,
          profileKey: profileKey,
          requirementKey: reqKey,
          evidenceId: evidenceId,
          detail: note,
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: accept
                ? 'compliance.evidence_accepted'
                : 'compliance.evidence_rejected',
            targetType: 'compliance_evidence',
            targetId: evidenceId,
            tenantId: tenantId,
            requestId: requestId,
            reason: note,
            after: {
              'requirement': '$profileKey/$reqKey',
              'status': accept ? 'approved' : 'rejected',
            },
          ),
        ),
      ]);
      result = {
        'evidenceId': evidenceId,
        'decision': decision,
        'requirementStatus': accept ? 'approved' : 'rejected',
      };
    });
    return result;
  }

  /// Platform reviewer: mark a requirement not applicable (with a reason), or
  /// ask for evidence again (`pending_evidence`).
  Future<Map<String, Object?>> setItemStatus(
    String tenantId,
    String profileKey,
    String reqKey,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'status', 'reason'});
    final status = r.enumOf<String>('status', const [
      'not_applicable',
      'pending_evidence',
    ], (v) => v);
    final reason = r.str('reason', min: 3, max: 500);
    r.throwIfInvalid();
    final profile = await _profiles.raw(profileKey);
    final req = (profile?['requirements'] as List?)
        ?.cast<Map<String, Object?>>()
        .where((x) => x['key'] == reqKey)
        .firstOrNull;
    if (profile == null || req == null) {
      throw const ApiException.notFound('Requirement not found.');
    }
    final to = ComplianceStatus.tryParse(status)!;
    final key = itemKey(profileKey, reqKey);
    await _store.transaction((tx) async {
      final item = await tx.get(_p(tenantId, 'compliance_items', key));
      final from = effectiveStatus(item: item, requirement: req, now: _now);
      if (!canTransition(from, to)) {
        throw ApiException.conflict(
          'A requirement that is ${from.wireName} cannot move to ${to.wireName}.',
        );
      }
      tx.write([
        _itemWrite(item, tenantId, key, {
          'profileKey': profileKey,
          'requirementKey': reqKey,
          'status': to.wireName,
          'expiresAt': null,
          'reviewedBy': actor.uid,
          'reviewedAt': _now,
          'note': reason,
          'profileVersion': profile['version'],
          'requirementHash': requirementHash(req),
          'updatedAt': _now,
        }),
        _history(
          tenantId,
          'item_status_set',
          actor,
          profileKey: profileKey,
          requirementKey: reqKey,
          detail: '${to.wireName}: $reason',
        ),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'compliance.item_status_set',
            targetType: 'compliance_item',
            targetId: key,
            tenantId: tenantId,
            requestId: requestId,
            reason: reason,
            before: {'status': from.wireName},
            after: {'status': to.wireName},
          ),
        ),
      ]);
    });
    return {
      'profileKey': profileKey,
      'requirementKey': reqKey,
      'status': to.wireName,
    };
  }

  // -------------------------------------------------------------- credentials

  static const List<String> credentialKinds = [
    'facility_license',
    'facility_registration',
    'practitioner_registration',
    'practitioner_license',
    'other',
  ];

  Map<String, Object?> presentCredential(Map<String, Object?> c, DateTime now) {
    final validTo = c['validTo'] as DateTime?;
    final validity = credentialValidity(validTo, now);
    final verified = (c['verification'] as Map?)?['status'] == 'verified';
    return {
      ...(jsonSafe(c)! as Map<String, Object?>),
      'validity': validity.name,
      'daysToExpiry': validTo?.difference(now).inDays,
      // verified only counts while the credential is still valid
      'verifiedAndValid':
          verified &&
          validity != CredentialValidity.expired &&
          validity != CredentialValidity.noExpiry,
    };
  }

  Future<List<Map<String, Object?>>> listCredentials(
    String tenantId, {
    bool includeArchived = false,
  }) async {
    final now = _now;
    final rows = await _store.query(
      DocQuery(_p(tenantId, 'compliance_credentials'), limit: 500),
    );
    return [
      for (final r in rows)
        if (includeArchived || r.data['status'] != 'archived')
          presentCredential(r.data, now),
    ]..sort(
      (a, b) =>
          '${a['validTo'] ?? '9999'}'.compareTo('${b['validTo'] ?? '9999'}'),
    );
  }

  Future<Map<String, Object?>> _credentialSummary(
    String tenantId,
    DateTime now,
  ) async {
    final all = await listCredentials(tenantId);
    int count(bool Function(Map<String, Object?>) f) => all.where(f).length;
    return {
      'total': all.length,
      'valid': count((c) => c['validity'] == 'valid'),
      'expiring': count((c) => c['validity'] == 'expiring'),
      'expired': count((c) => c['validity'] == 'expired'),
      'noExpiryRecorded': count((c) => c['validity'] == 'noExpiry'),
      'unverified': count(
        (c) => (c['verification'] as Map?)?['status'] != 'verified',
      ),
      'attention': [
        for (final c in all)
          if (c['validity'] == 'expiring' || c['validity'] == 'expired')
            {
              'credentialId': c['credentialId'],
              'subjectName': c['subjectName'],
              'kind': c['kind'],
              'validTo': c['validTo'],
              'validity': c['validity'],
              'daysToExpiry': c['daysToExpiry'],
            },
      ].take(20).toList(),
    };
  }

  Map<String, Object?> _credentialFields(
    BodyReader r, {
    required bool partial,
  }) {
    final kind = r.enumOf<String>(
      'kind',
      credentialKinds,
      (v) => v,
      required: !partial,
    );
    final authCode = r.str(
      'authorityCode',
      min: 2,
      max: 20,
      required: !partial,
    );
    final authName = r.str(
      'authorityName',
      min: 2,
      max: 120,
      required: !partial,
    );
    final jurisdiction = r.str(
      'jurisdiction',
      min: 2,
      max: 60,
      required: false,
    );
    final number = r.str('number', min: 1, max: 40, required: !partial);
    if (number != null &&
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9 /._\-]{0,39}$').hasMatch(number)) {
      r.addIssue(
        'number',
        'invalid_format',
        'Use letters, digits and - / . _ only.',
      );
    }
    final issuedOn = _dateField(r, 'issuedOn');
    final validFrom = _dateField(r, 'validFrom');
    final validTo = _dateField(r, 'validTo');
    final notes = r.str('notes', min: 0, max: 500, required: false);
    if (validFrom != null && validTo != null && validTo.isBefore(validFrom)) {
      r.addIssue(
        'validTo',
        'invalid_range',
        'validTo must not be before validFrom.',
      );
    }
    return {
      'kind': ?kind,
      'authorityCode': ?authCode,
      'authorityName': ?authName,
      'jurisdiction': ?jurisdiction,
      'number': ?number,
      'issuedOn': ?issuedOn,
      'validFrom': ?validFrom,
      'validTo': ?validTo,
      'notes': ?notes,
    };
  }

  Future<Map<String, Object?>> createCredential(
    String tenantId,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)
      ..rejectUnknown({
        'subjectType',
        'subjectName',
        'doctorId',
        'kind',
        'authorityCode',
        'authorityName',
        'jurisdiction',
        'number',
        'issuedOn',
        'validFrom',
        'validTo',
        'notes',
      });
    final type = r.enumOf<String>('subjectType', const [
      'facility',
      'practitioner',
    ], (v) => v);
    final subjectName = r.str('subjectName', min: 2, max: 120);
    final doctorId = r.str('doctorId', min: 3, max: 64, required: false);
    final fields = _credentialFields(r, partial: false);
    r.throwIfInvalid();
    if (type == 'facility' && doctorId != null) {
      throw ApiException.validation([
        _issue(
          'doctorId',
          'not_allowed',
          'A facility credential has no practitioner.',
        ),
      ]);
    }
    if (doctorId != null &&
        await _store.get(_p(tenantId, 'doctors', doctorId)) == null) {
      throw ApiException.validation([
        _issue(
          'doctorId',
          'not_found',
          'That practitioner does not exist in this clinic.',
        ),
      ]);
    }
    final id = 'cr_${newId(length: 16)}';
    final now = _now;
    final doc = {
      'credentialId': id,
      'tenantId': tenantId,
      'subjectType': type,
      'subjectName': subjectName,
      'doctorId': ?doctorId,
      ...fields,
      'verification': {'status': 'unverified'},
      'status': 'active',
      'createdBy': actor.uid,
      'createdAt': now,
      'updatedAt': now,
    };
    await _store.commit([
      CreateOp(_p(tenantId, 'compliance_credentials', id), doc),
      _history(tenantId, 'credential_created', actor, credentialId: id),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: 'compliance.credential_created',
          targetType: 'compliance_credential',
          targetId: id,
          tenantId: tenantId,
          requestId: requestId,
          after: {'kind': fields['kind'], 'subjectType': type},
        ),
      ),
    ]);
    return presentCredential(doc, now);
  }

  Future<DocData> _credential(String tenantId, String id) async {
    final c = await _store.get(_p(tenantId, 'compliance_credentials', id));
    if (c == null) throw const ApiException.notFound('Credential not found.');
    return c;
  }

  Future<Map<String, Object?>> updateCredential(
    String tenantId,
    String id,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({
        'subjectName',
        'kind',
        'authorityCode',
        'authorityName',
        'jurisdiction',
        'number',
        'issuedOn',
        'validFrom',
        'validTo',
        'notes',
      });
    final name = r.str('subjectName', min: 2, max: 120, required: false);
    final fields = _credentialFields(r, partial: true);
    r.throwIfInvalid();
    final changes = {'subjectName': ?name, ...fields};
    if (changes.isEmpty) {
      throw const ApiException.badRequest('No credential fields to update.');
    }
    final cur = await _credential(tenantId, id);
    if (cur['status'] == 'archived') {
      throw const ApiException.conflict(
        'An archived credential cannot be edited.',
      );
    }
    // Anything that changes what was verified voids the verification.
    final material = {
      'kind',
      'authorityCode',
      'number',
      'validFrom',
      'validTo',
      'jurisdiction',
    };
    final voids = changes.keys.any(
      (k) => material.contains(k) && changes[k] != cur[k],
    );
    final now = _now;
    final patch = {
      ...changes,
      if (voids && (cur['verification'] as Map?)?['status'] == 'verified')
        'verification': {'status': 'unverified', 'voidedAt': now},
      'updatedAt': now,
    };
    await _store.commit([
      UpdateOp(_p(tenantId, 'compliance_credentials', id), patch),
      _history(
        tenantId,
        'credential_updated',
        actor,
        credentialId: id,
        detail: changes.keys.join(','),
      ),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: 'compliance.credential_updated',
          targetType: 'compliance_credential',
          targetId: id,
          tenantId: tenantId,
          requestId: requestId,
          after: {'fields': changes.keys.toList(), 'verificationVoided': voids},
        ),
      ),
    ]);
    return presentCredential({...cur, ...patch}, now);
  }

  Future<Map<String, Object?>> archiveCredential(
    String tenantId,
    String id,
    Actor actor, {
    String? requestId,
  }) async {
    final cur = await _credential(tenantId, id);
    final now = _now;
    await _store.commit([
      UpdateOp(_p(tenantId, 'compliance_credentials', id), {
        'status': 'archived',
        'updatedAt': now,
      }),
      _history(tenantId, 'credential_archived', actor, credentialId: id),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: 'compliance.credential_archived',
          targetType: 'compliance_credential',
          targetId: id,
          tenantId: tenantId,
          requestId: requestId,
        ),
      ),
    ]);
    return presentCredential({...cur, 'status': 'archived'}, now);
  }

  /// Clinic: attach the document for a credential. The credential becomes
  /// `unverified` until a reviewer verifies this file.
  Future<Map<String, Object?>> attachCredentialEvidence(
    String tenantId,
    String id,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'contentType', 'dataBase64'});
    r.str('contentType', max: 60, required: false);
    final (bytes, mime) = _decode(r, 'dataBase64');
    final cur = await _credential(tenantId, id);
    if (cur['status'] == 'archived') {
      throw const ApiException.conflict(
        'An archived credential cannot take new files.',
      );
    }
    final evId = 'ce_${newId(length: 16)}';
    final path = 'tenants/$tenantId/compliance/$evId';
    final now = _now;
    final previous = cur['evidenceId'] as String?;
    final previousDoc = previous == null
        ? null
        : await _store.get(_p(tenantId, 'compliance_evidence', previous));
    final supersede =
        previousDoc != null &&
        (previousDoc['status'] == 'submitted' ||
            previousDoc['status'] == 'accepted');
    await _store.commit([
      CreateOp(_p(tenantId, 'compliance_evidence', evId), {
        'evidenceId': evId,
        'tenantId': tenantId,
        'credentialId': id,
        'kind': '${cur['kind']}'.contains('registration')
            ? 'registration'
            : 'license',
        'title': 'Credential document',
        'mime': mime,
        'sizeBytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'storagePath': path,
        'status': 'submitted',
        'uploadedBy': actor.uid,
        'uploadedAt': now,
      }),
      if (supersede)
        UpdateOp(_p(tenantId, 'compliance_evidence', previous!), {
          'status': 'superseded',
        }),
      UpdateOp(_p(tenantId, 'compliance_credentials', id), {
        'evidenceId': evId,
        'verification': {'status': 'unverified'},
        'updatedAt': now,
      }),
      _history(
        tenantId,
        'credential_document_submitted',
        actor,
        credentialId: id,
        evidenceId: evId,
      ),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: 'compliance.credential_document_submitted',
          targetType: 'compliance_credential',
          targetId: id,
          tenantId: tenantId,
          requestId: requestId,
        ),
      ),
    ]);
    await _storage.put(path, bytes, mime);
    return presentCredential({
      ...cur,
      'evidenceId': evId,
      'verification': {'status': 'unverified'},
    }, now);
  }

  /// Platform reviewer: verify or reject a credential's document.
  Future<Map<String, Object?>> verifyCredential(
    String tenantId,
    String id,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'decision', 'note'});
    final decision = r.enumOf<String>('decision', const [
      'verify',
      'reject',
    ], (v) => v);
    final note = r.str('note', min: 3, max: 500, required: false);
    if (decision == 'reject' && (note == null || note.trim().length < 3)) {
      r.addIssue('note', 'required', 'Say why the credential is rejected.');
    }
    r.throwIfInvalid();
    final cur = await _credential(tenantId, id);
    final evId = cur['evidenceId'] as String?;
    final ev = evId == null
        ? null
        : await _store.get(_p(tenantId, 'compliance_evidence', evId));
    if (ev == null || ev['status'] != 'submitted') {
      throw const ApiException.conflict(
        'There is no submitted document to review for this credential.',
      );
    }
    final ok = decision == 'verify';
    if (ok && cur['validTo'] == null) {
      throw const ApiException.conflict(
        'Record the validity end date before verifying a credential.',
      );
    }
    final now = _now;
    await _store.commit([
      UpdateOp(_p(tenantId, 'compliance_evidence', evId!), {
        'status': ok ? 'accepted' : 'rejected',
        'reviewedBy': actor.uid,
        'reviewedAt': now,
        'reviewNote': note,
      }),
      UpdateOp(_p(tenantId, 'compliance_credentials', id), {
        'verification': {
          'status': ok ? 'verified' : 'rejected',
          'by': actor.uid,
          'at': now,
          'note': note,
        },
        'updatedAt': now,
      }),
      _history(
        tenantId,
        ok ? 'credential_verified' : 'credential_rejected',
        actor,
        credentialId: id,
        evidenceId: evId,
        detail: note,
      ),
      _audit.op(
        AuditEntry(
          actor: actor,
          action: ok
              ? 'compliance.credential_verified'
              : 'compliance.credential_rejected',
          targetType: 'compliance_credential',
          targetId: id,
          tenantId: tenantId,
          requestId: requestId,
          reason: note,
        ),
      ),
    ]);
    return presentCredential({
      ...cur,
      'verification': {
        'status': ok ? 'verified' : 'rejected',
        'by': actor.uid,
        'at': now,
      },
    }, now);
  }

  // --------------------------------------------------------- expiry alerts

  /// One pass for one clinic (called by the notification worker). Idempotent:
  /// alerts are deduplicated per credential/requirement, threshold and expiry
  /// date, and statuses are only written when they actually change.
  /// Returns the number of alerts handed to the notifier.
  Future<int> scanExpiries(String tenantId) async {
    final now = _now;
    final notify = notifier;
    var sent = 0;
    final recipients = notify == null
        ? const <String>[]
        : [
            for (final m in await _store.query(
              DocQuery(
                _p(tenantId, 'members'),
                filters: const [
                  QueryFilter('role', FilterOp.inList, [
                    'clinic_owner',
                    'clinic_admin',
                  ]),
                  QueryFilter('status', FilterOp.eq, 'active'),
                ],
                limit: 20,
              ),
            ))
              m.id,
          ];

    Future<void> alert(
      String key,
      DateTime validTo,
      int threshold,
      String what,
    ) async {
      if (notify == null) return;
      final expired = threshold == 0;
      for (final uid in recipients) {
        await notify(
          tenantId: tenantId,
          staffUid: uid,
          dedupeKey: 'compliance:$key:$threshold:${dateOnly(validTo)}:$uid',
          title: expired
              ? 'A compliance document has expired'
              : 'A compliance document expires soon',
          body:
              'A $what ${expired ? 'has expired' : 'expires within $threshold days'}. Open Compliance to review.',
        );
        sent++;
      }
    }

    for (final c in await _store.query(
      DocQuery(_p(tenantId, 'compliance_credentials'), limit: 500),
    )) {
      if (c.data['status'] == 'archived') continue;
      final validTo = c.data['validTo'] as DateTime?;
      if (validTo == null) continue;
      final t = reachedAlertThreshold(validTo, now);
      if (t != null) await alert('cred:${c.id}', validTo, t, 'credential');
    }

    for (final d in await _store.query(
      DocQuery(_p(tenantId, 'compliance_items'), limit: 2000),
    )) {
      final expires = d.data['expiresAt'] as DateTime?;
      if (d.data['status'] != 'approved' || expires == null) continue;
      final t = reachedAlertThreshold(expires, now);
      if (t == null) continue;
      if (t == 0) {
        // persist the expiry so lists and reports agree with the dashboard
        await _store.commit([
          UpdateOp(d.path, {'status': 'expired', 'updatedAt': now}),
          _history(
            tenantId,
            'requirement_expired',
            const Actor('system', 'system'),
            profileKey: d.data['profileKey'] as String?,
            requirementKey: d.data['requirementKey'] as String?,
          ),
        ]);
      }
      await alert('item:${d.id}', expires, t, 'requirement approval');
    }
    return sent;
  }

  // -------------------------------------------------------------- platform

  /// Evidence waiting for a reviewer, oldest first, across all clinics.
  Future<List<Map<String, Object?>>> reviewQueue({int limit = 100}) async {
    final rows = await _store.query(
      DocQuery(
        'compliance_evidence',
        collectionGroup: true,
        filters: const [QueryFilter('status', FilterOp.eq, 'submitted')],
        orderBy: const OrderBy('uploadedAt'),
        limit: limit,
      ),
    );
    return [
      for (final r in rows)
        {...presentEvidence(r.data), 'tenantId': r.path.split('/')[1]},
    ];
  }

  Future<Map<String, Object?>> overview() async {
    final waiting = await _store.count(
      const DocQuery(
        'compliance_evidence',
        collectionGroup: true,
        filters: [QueryFilter('status', FilterOp.eq, 'submitted')],
      ),
    );
    final confirmations = await _store.count(
      const DocQuery(
        'compliance_applicability',
        collectionGroup: true,
        filters: [QueryFilter('status', FilterOp.eq, 'applies')],
      ),
    );
    final profiles = await _profiles.list();
    return {
      'disclaimer': disclaimer,
      'profiles': profiles.length,
      'profilesAwaitingLegalValidation': profiles
          .where((p) => (p['legalReview'] as Map?)?['status'] != 'reviewed')
          .length,
      'evidenceAwaitingReview': waiting,
      'confirmedApplicabilities': confirmations,
    };
  }
}
