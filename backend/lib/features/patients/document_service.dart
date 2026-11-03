import 'dart:convert';
import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/object_storage.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'consent_service.dart';
import 'patient_support.dart';

const int maxPatientDocumentBytes = 3 * 1024 * 1024;

const List<String> documentCategories = [
  'previous_report',
  'lab_report',
  'scanned_record',
  'referral',
  'patient_prescription',
  'other',
];

String? sniffDocumentType(Uint8List b) {
  if (b.length >= 5 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46 &&
      b[4] == 0x2D) {
    return 'application/pdf';
  }
  return sniffImageType(b);
}

/// Patient documents: metadata in Firestore, bytes in private object storage
/// under a tenant- and patient-scoped path. There are no public or permanent
/// URLs; downloads go through an authorized, audited endpoint. Documents are
/// retained: "removal" hides a document but keeps the stored object.
class PatientDocumentService {
  PatientDocumentService(this._s, this._storage);

  final PatientSupport _s;
  final ObjectStorage _storage;

  static const String collection = 'patient_documents';

  String objectPath(TenantContext t, String patientId, String docId) =>
      'tenants/${t.tenantId}/patients/$patientId/documents/$docId';

  bool _canSee(TenantContext t, Map<String, Object?> d) =>
      d['classification'] != 'restricted' ||
      t.can(ClinicPermission.historyView);

  Future<Map<String, Object?>> upload(
    TenantContext t,
    String patientId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientDocumentsManage);
    final patient = await _s.load(t, patientId);
    _s.requireOpen(patient);
    final r = BodyReader(body)
      ..rejectUnknown({
        'name',
        'category',
        'contentType',
        'dataBase64',
        'description',
        'source',
        'classification',
      });
    final name = r.str('name', min: 2, max: 120);
    final category = r.enumOf<String>('category', documentCategories, (v) => v);
    final declared = r.str('contentType', max: 40);
    final data = r.str(
      'dataBase64',
      max: (maxPatientDocumentBytes * 4 ~/ 3) + 16,
    );
    final description = r.str('description', max: 300, required: false);
    final source = r.enumOf<String>(
      'source',
      const ['patient_provided', 'external_clinic', 'clinic_scanned', 'other'],
      (v) => v,
      required: false,
    );
    final classification =
        r.enumOf<String>(
          'classification',
          const ['normal', 'restricted'],
          (v) => v,
          required: false,
        ) ??
        'normal';
    r.throwIfInvalid();
    if (classification == 'restricted' &&
        !t.can(ClinicPermission.historyView)) {
      throw const ApiException.forbidden();
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(data!);
    } on FormatException {
      throw ApiException.validation([
        FieldIssue(
          field: 'dataBase64',
          code: 'invalid_base64',
          message: 'The file data is not valid base64.',
        ),
      ]);
    }
    final real = bytes.isEmpty ? null : sniffDocumentType(bytes);
    if (bytes.isEmpty || bytes.length > maxPatientDocumentBytes) {
      throw ApiException.validation([
        FieldIssue(
          field: 'dataBase64',
          code: 'too_large',
          message: 'The file must be between 1 byte and 3 MB.',
        ),
      ]);
    }
    if (real == null || real != declared) {
      throw ApiException.validation([
        FieldIssue(
          field: 'contentType',
          code: 'invalid_file',
          message: 'Only PDF, PNG, JPEG and WebP files are accepted.',
        ),
      ]);
    }
    final id = 'dc_${newId(length: 12)}';
    final path = objectPath(t, patientId, id);
    final now = _s.d.now;
    final doc = <String, Object?>{
      'documentId': id,
      'patientId': patientId,
      'tenantId': t.tenantId,
      'branchId': patient['branchId'],
      'name': name,
      'category': category,
      'contentType': real,
      'size': bytes.length,
      'storagePath': path,
      'description': description,
      'source': source ?? 'clinic_scanned',
      'verificationStatus': 'unverified',
      'classification': classification,
      'status': 'active',
      'uploadedBy': t.uid,
      'uploadedAt': now,
      'createdAt': now,
    };
    // Consent first (so no object is stored without it), then the object, then
    // the metadata; consent is re-checked in the metadata transaction.
    await _s.requireConsent(t, patientId, ConsentCatalog.dataProcessing);
    await _s.requireConsent(t, patientId, ConsentCatalog.documentProcessing);
    await _storage.put(path, bytes, real);
    await _s.d.store.transaction((tx) async {
      final cur = await _s.loadIn(tx, t, patientId);
      _s.requireOpen(cur);
      await _s.requireConsent(
        t,
        patientId,
        ConsentCatalog.dataProcessing,
        tx: tx,
      );
      await _s.requireConsent(
        t,
        patientId,
        ConsentCatalog.documentProcessing,
        tx: tx,
      );
      tx.write([
        CreateOp(_s.d.path(t, collection, id), doc),
        _s.auditOp(
          t,
          patientId,
          cur['branchId'] as String?,
          'document.uploaded',
          resourceType: 'document',
          resourceId: id,
          after: {
            'category': category,
            'contentType': real,
            'size': bytes.length,
            'classification': classification,
          },
          requestId: requestId,
        ),
      ]);
    });
    return present(doc);
  }

  Future<Paged> list(
    TenantContext t,
    String patientId,
    Request req, {
    String? category,
  }) async {
    t.require(ClinicPermission.patientDocumentsView);
    await _s.load(t, patientId);
    if (category != null && !documentCategories.contains(category)) {
      throw const ApiException.badRequest('category has an unsupported value.');
    }
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, collection),
        filters: [
          QueryFilter('patientId', FilterOp.eq, patientId),
          const QueryFilter('status', FilterOp.eq, 'active'),
          if (category != null) QueryFilter('category', FilterOp.eq, category),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
    return Paged(
      page.docs.where((d) => _canSee(t, d.data)).toList(),
      page.meta,
    );
  }

  Future<Map<String, Object?>> _find(
    TenantContext t,
    String patientId,
    String id,
  ) async {
    final d = await _s.d.store.get(_s.d.path(t, collection, id));
    // the document must belong to this patient of this tenant
    if (d == null || d['patientId'] != patientId || !_canSee(t, d)) {
      throw const ApiException.notFound('Document not found.');
    }
    return d;
  }

  Future<Map<String, Object?>> detail(
    TenantContext t,
    String patientId,
    String id,
  ) async {
    t.require(ClinicPermission.patientDocumentsView);
    await _s.load(t, patientId);
    return present(await _find(t, patientId, id));
  }

  /// Bytes of a document; every download is audited.
  Future<(Uint8List, String, String)> content(
    TenantContext t,
    String patientId,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientDocumentsView);
    final patient = await _s.load(t, patientId);
    final d = await _find(t, patientId, id);
    if (d['status'] != 'active') {
      throw const ApiException.notFound('Document not found.');
    }
    final obj = await _storage.get(d['storagePath']! as String);
    if (obj == null) {
      throw const ApiException.notFound('Document not found.');
    }
    await _s.recordAccess(
      t,
      patient,
      'document.viewed',
      resourceType: 'document',
      resourceId: id,
      requestId: requestId,
    );
    return (obj.$1, obj.$2, '${d['name']}');
  }

  Future<Map<String, Object?>> remove(
    TenantContext t,
    String patientId,
    String id,
    String? reason, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.patientDocumentsManage);
    final patient = await _s.load(t, patientId);
    if (reason == null || reason.trim().length < 5) {
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
      final path = _s.d.path(t, collection, id);
      final cur = await tx.get(path);
      if (cur == null || cur['patientId'] != patientId || !_canSee(t, cur)) {
        throw const ApiException.notFound('Document not found.');
      }
      if (cur['status'] != 'active') {
        throw const ApiException.conflict('The document is already removed.');
      }
      final patch = {
        'status': 'removed',
        'removedAt': now,
        'removedBy': t.uid,
        'removeReason': reason.trim(),
      };
      tx.write([
        UpdateOp(path, patch),
        _s.auditOp(
          t,
          patientId,
          patient['branchId'] as String?,
          'document.removed',
          resourceType: 'document',
          resourceId: id,
          reason: reason.trim(),
          requestId: requestId,
        ),
      ]);
      return present({...cur, ...patch});
    });
  }

  static Map<String, Object?> present(Map<String, Object?> d) =>
      (jsonSafe(d)! as Map<String, Object?>)..remove('storagePath');
}
