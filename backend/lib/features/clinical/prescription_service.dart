import 'package:common_models/common_models.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import 'clinical_support.dart';

/// Prescriptions of a consultation.
///
/// `draft → finalized`. A finalized prescription is never edited: a correction
/// creates a **replacement draft** (`version + 1`, linked by `supersedesId` and
/// `rootId`). When the replacement is finalized the original becomes
/// `amended` in the same commit and stays readable. The system never suggests
/// medicines; the catalogue is only a lookup list.
class PrescriptionService {
  PrescriptionService(this._s);

  final ClinicalSupport _s;

  static const String collection = 'prescriptions';
  static const int maxMedicines = 30;
  static const int maxPerConsultation = 5;

  // ------------------------------------------------------------- parsing

  List<Map<String, Object?>>? _parseMedicines(BodyReader r, Object? raw) {
    if (raw is! List || raw.length > maxMedicines) {
      r.addIssue(
        'medicines',
        'invalid_value',
        'Give up to $maxMedicines medicines.',
      );
      return null;
    }
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        r.addIssue('medicines[$i]', 'invalid_type', 'Must be an object.');
        continue;
      }
      final m = BodyReader(item.cast<String, Object?>())
        ..rejectUnknown({
          'name',
          'genericName',
          'brandName',
          'strength',
          'dosage',
          'route',
          'frequency',
          'durationValue',
          'durationUnit',
          'quantity',
          'instructions',
          'foodRelation',
          'warnings',
          'notes',
          'catalogueId',
        });
      final name = m.str('name', min: 2, max: 120);
      final dosage = m.str('dosage', min: 1, max: 60);
      if (dosage != null && !RegExp(r'[A-Za-z0-9]').hasMatch(dosage)) {
        m.addIssue(
          'dosage',
          'invalid_value',
          'Describe the dose, for example "1 tablet".',
        );
      }
      final frequency = m.str('frequency', min: 1, max: 60);
      final dv = m.integer('durationValue', min: 1, max: 365);
      final du = m.enumOf<String>('durationUnit', const [
        'days',
        'weeks',
        'months',
      ], (v) => v);
      final qty = m.integer('quantity', min: 1, max: 10000, required: false);
      final food = m.enumOf<String>(
        'foodRelation',
        const ['before_food', 'after_food', 'with_food', 'any'],
        (v) => v,
        required: false,
      );
      final row = <String, Object?>{
        'name': name,
        'genericName': m.str('genericName', max: 120, required: false),
        'brandName': m.str('brandName', max: 120, required: false),
        'strength': m.str('strength', max: 40, required: false),
        'dosage': dosage,
        'route': m.str('route', max: 30, required: false),
        'frequency': frequency,
        'durationValue': dv,
        'durationUnit': du,
        'quantity': qty,
        'instructions': m.str('instructions', max: 300, required: false),
        'foodRelation': food,
        'warnings': m.str('warnings', max: 300, required: false),
        'notes': m.str('notes', max: 300, required: false),
        'catalogueId': m.str('catalogueId', max: 40, required: false),
      }..removeWhere((k, v) => v == null);
      for (final x in m.issues) {
        r.addIssue('medicines[$i].${x.field}', x.code, x.message);
      }
      out.add(row);
    }
    return out;
  }

  Future<void> _checkCatalogue(
    TenantContext t,
    List<Map<String, Object?>> meds,
    TxContext tx,
  ) async {
    for (var i = 0; i < meds.length; i++) {
      final cid = meds[i]['catalogueId'] as String?;
      if (cid == null) continue;
      final e = await tx.get(_s.path(t, 'medicine_catalogue', cid));
      if (e == null || e['status'] != 'active') {
        throw ApiException.validation([
          issue(
            'medicines[$i].catalogueId',
            'invalid_catalogue_entry',
            'This catalogue entry does not exist or is inactive.',
          ),
        ]);
      }
    }
  }

  // -------------------------------------------------------------- create

  Future<Map<String, Object?>> create(
    TenantContext t,
    String consultationId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.prescriptionsManage);
    final r = BodyReader(body)..rejectUnknown({'medicines', 'notes'});
    final meds = r.has('medicines')
        ? _parseMedicines(r, r.body['medicines'])
        : <Map<String, Object?>>[];
    final notes = r.str('notes', max: 1000, required: false);
    r.throwIfInvalid();
    final id = 'rx_${newId(length: 14)}';
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final c = await _s.consultation(t, consultationId, tx: tx);
      await _s.requireAuthor(t, c);
      _s.requireOpen(c);
      await _checkCatalogue(t, meds!, tx);
      final existing = await tx.query(
        DocQuery(
          _s.path(t, collection),
          filters: [QueryFilter('consultationId', FilterOp.eq, consultationId)],
          limit: 20,
        ),
      );
      if (existing.where((e) => e.data['status'] != 'amended').length >=
          maxPerConsultation) {
        throw const ApiException.conflict(
          'Too many prescriptions for one consultation.',
        );
      }
      final doc = <String, Object?>{
        'prescriptionId': id,
        'rootId': id,
        'version': 1,
        'supersedesId': null,
        'consultationId': consultationId,
        'tenantId': t.tenantId,
        'branchId': c['branchId'],
        'patientId': c['patientId'],
        'patientName': c['patientName'],
        'patientMrn': c['patientMrn'],
        'doctorId': c['doctorId'],
        'doctorName': c['doctorName'],
        'number': null,
        'status': 'draft',
        'medicines': meds,
        'notes': notes,
        'prescribedAt': now,
        'finalizedAt': null,
        'finalizedBy': null,
        'rev': 1,
        'createdAt': now,
        'updatedAt': now,
        'createdBy': t.uid,
        'updatedBy': t.uid,
      };
      tx.write([
        CreateOp(_s.path(t, collection, id), doc),
        _s.audit(
          t,
          action: 'prescription.created',
          resourceType: 'prescription',
          resourceId: id,
          branchId: '${c['branchId']}',
          patientId: '${c['patientId']}',
          consultationId: consultationId,
          requestId: requestId,
          after: {'medicines': meds.length},
        ),
      ]);
      return ClinicalSupport.present(doc);
    });
  }

  Future<DocData> _load(TenantContext t, String id, {TxContext? tx}) async {
    final p = _s.path(t, collection, id);
    final rx = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (rx == null || !await _s.canSee(t, rx)) {
      throw const ApiException.notFound('Prescription not found.');
    }
    return rx;
  }

  // ---------------------------------------------------------------- read

  Future<Map<String, Object?>> detail(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.prescriptionsView);
    final rx = await _load(t, id);
    final chain = await _s.d.store.query(
      DocQuery(
        _s.path(t, collection),
        filters: [QueryFilter('rootId', FilterOp.eq, rx['rootId'])],
        limit: 20,
      ),
    );
    final tenant = await _s.d.store.get('tenants/${t.tenantId}');
    await _s.d.store.commit([
      _s.audit(
        t,
        action: 'prescription.viewed',
        resourceType: 'prescription',
        resourceId: id,
        branchId: '${rx['branchId']}',
        patientId: '${rx['patientId']}',
        consultationId: '${rx['consultationId']}',
        requestId: requestId,
      ),
    ]);
    final versions =
        [
          for (final v in chain)
            {
              'prescriptionId': v.data['prescriptionId'],
              'version': v.data['version'],
              'status': v.data['status'],
              'finalizedAt': ClinicalSupport.present({
                'x': v.data['finalizedAt'],
              })['x'],
              'amendReason': v.data['amendReason'],
            },
        ]..sort(
          (a, b) => ((a['version'] as int?) ?? 0).compareTo(
            (b['version'] as int?) ?? 0,
          ),
        );
    return {
      ...ClinicalSupport.present(rx),
      'clinicName': tenant?['clinicName'],
      'versions': versions,
      // The prescription is what the doctor wrote: nothing here is suggested or
      // checked for clinical suitability.
      'disclaimer':
          'Issued by the treating doctor. Follow the doctor\'s instructions.',
    };
  }

  // -------------------------------------------------------------- update

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.prescriptionsManage);
    final r = BodyReader(body)
      ..rejectUnknown({'medicines', 'notes', 'expectedRev'});
    final meds = r.has('medicines')
        ? _parseMedicines(r, r.body['medicines'])
        : null;
    final notes = r.str('notes', max: 1000, required: false);
    final expected = r.integer(
      'expectedRev',
      min: 1,
      max: 100000,
      required: false,
    );
    r.throwIfInvalid();
    if (meds == null && notes == null) {
      throw const ApiException.badRequest('Nothing to update.');
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final rx = await _load(t, id, tx: tx);
      await _s.requireAuthor(t, rx);
      if (rx['status'] != 'draft') {
        throw const ApiException.conflict(
          'A finalized prescription cannot be edited. Create an amendment instead.',
        );
      }
      if (expected != null && expected != rx['rev']) {
        throw const ApiException.conflict(
          'The prescription changed. Reload before saving.',
        );
      }
      if (meds != null) await _checkCatalogue(t, meds, tx);
      final patch = {
        'medicines': ?meds,
        'notes': ?notes,
        'updatedAt': now,
        'updatedBy': t.uid,
        'rev': ((rx['rev'] as int?) ?? 1) + 1,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'prescription.updated',
          resourceType: 'prescription',
          resourceId: id,
          branchId: '${rx['branchId']}',
          patientId: '${rx['patientId']}',
          consultationId: '${rx['consultationId']}',
          requestId: requestId,
          after: {
            'medicines': meds?.length ?? (rx['medicines'] as List).length,
          },
        ),
      ]);
      return ClinicalSupport.present({...rx, ...patch});
    });
  }

  // ------------------------------------------------------------ finalize

  Future<Map<String, Object?>> finalize(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.prescriptionsFinalize);
    final head = await _load(t, id);
    await _s.requireAuthor(t, head);
    if (head['status'] == 'finalized' || head['status'] == 'amended') {
      return {...ClinicalSupport.present(head), 'idempotentReplay': true};
    }
    final now = _s.d.now;
    final counterPath = _s.path(t, 'counters', 'prescription_number');
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        return await _s.d.store.transaction((tx) async {
          final rx = await _load(t, id, tx: tx);
          if (rx['status'] != 'draft') {
            return {...ClinicalSupport.present(rx), 'idempotentReplay': true};
          }
          final meds = ((rx['medicines'] as List?) ?? const []);
          if (meds.isEmpty) {
            throw ApiException.validation([
              issue(
                'medicines',
                'required',
                'Add at least one medicine before finalizing.',
              ),
            ]);
          }
          final c = await _s.consultation(t, '${rx['consultationId']}', tx: tx);
          if (c['status'] == 'draft') {
            throw const ApiException.conflict(
              'Start the consultation before finalizing a prescription.',
            );
          }
          final supersedes = rx['supersedesId'] as String?;
          final ops = <WriteOp>[];
          String number;
          if (supersedes != null) {
            final orig = await tx.get(_s.path(t, collection, supersedes));
            if (orig == null || orig['status'] != 'finalized') {
              throw const ApiException.conflict(
                'The prescription being replaced is no longer current.',
              );
            }
            number = '${orig['number']}';
            ops.add(
              UpdateOp(_s.path(t, collection, supersedes), {
                'status': 'amended',
                'amendedAt': now,
                'amendedBy': t.uid,
                'replacedById': id,
                'updatedAt': now,
                'updatedBy': t.uid,
              }),
            );
          } else {
            final counter = await tx.get(counterPath);
            final n = ((counter?['next'] as int?) ?? 0) + 1;
            number = 'RX-${n.toString().padLeft(6, '0')}';
            ops
              ..add(
                counter == null
                    ? CreateOp(counterPath, {'next': n})
                    : UpdateOp(counterPath, {'next': n}),
              )
              ..add(
                CreateOp(_s.path(t, 'prescription_numbers', number), {
                  'prescriptionId': id,
                  'createdAt': now,
                }),
              );
          }
          final patch = {
            'status': 'finalized',
            'number': number,
            'finalizedAt': now,
            'finalizedBy': t.uid,
            'updatedAt': now,
            'updatedBy': t.uid,
            'rev': ((rx['rev'] as int?) ?? 1) + 1,
          };
          tx.write([
            ...ops,
            UpdateOp(_s.path(t, collection, id), patch),
            _s.audit(
              t,
              action: supersedes == null
                  ? 'prescription.finalized'
                  : 'prescription.amended',
              resourceType: 'prescription',
              resourceId: id,
              branchId: '${rx['branchId']}',
              patientId: '${rx['patientId']}',
              consultationId: '${rx['consultationId']}',
              reason: rx['amendReason'] as String?,
              requestId: requestId,
              before: {'status': 'draft'},
              after: {
                'status': 'finalized',
                'number': number,
                'version': rx['version'],
                'medicines': meds.length,
                'replaces': supersedes,
              },
            ),
          ]);
          return ClinicalSupport.present({...rx, ...patch});
        });
      } on AlreadyExistsException {
        continue; // number collision: take the next one
      }
    }
    throw const ApiException.conflict(
      'The prescription number is busy. Try again.',
    );
  }

  // --------------------------------------------------------------- amend

  Future<Map<String, Object?>> amend(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.prescriptionsManage);
    final r = BodyReader(body)..rejectUnknown({'reason', 'medicines', 'notes'});
    final reason = r.str('reason', min: 5, max: 300);
    final meds = r.has('medicines')
        ? _parseMedicines(r, r.body['medicines'])
        : null;
    final notes = r.str('notes', max: 1000, required: false);
    r.throwIfInvalid();
    final newId0 = 'rx_${newId(length: 14)}';
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final rx = await _load(t, id, tx: tx);
      await _s.requireAuthor(t, rx);
      if (rx['status'] != 'finalized') {
        throw const ApiException.conflict(
          'Only the current finalized version of a prescription can be amended.',
        );
      }
      final open = await tx.query(
        DocQuery(
          _s.path(t, collection),
          filters: [
            QueryFilter('supersedesId', FilterOp.eq, id),
            const QueryFilter('status', FilterOp.eq, 'draft'),
          ],
          limit: 2,
        ),
      );
      if (open.isNotEmpty) {
        throw const ApiException.conflict(
          'An amendment of this prescription is already in progress.',
        );
      }
      if (meds != null) await _checkCatalogue(t, meds, tx);
      final doc = <String, Object?>{
        ...rx,
        'prescriptionId': newId0,
        'version': ((rx['version'] as int?) ?? 1) + 1,
        'supersedesId': id,
        'status': 'draft',
        'medicines': meds ?? rx['medicines'],
        'notes': notes ?? rx['notes'],
        'amendReason': reason,
        'finalizedAt': null,
        'finalizedBy': null,
        'rev': 1,
        'prescribedAt': now,
        'createdAt': now,
        'updatedAt': now,
        'createdBy': t.uid,
        'updatedBy': t.uid,
      }..remove('replacedById');
      tx.write([
        CreateOp(_s.path(t, collection, newId0), doc),
        _s.audit(
          t,
          action: 'prescription.amendment_started',
          resourceType: 'prescription',
          resourceId: newId0,
          branchId: '${rx['branchId']}',
          patientId: '${rx['patientId']}',
          consultationId: '${rx['consultationId']}',
          reason: reason,
          requestId: requestId,
          after: {'replaces': id, 'version': doc['version']},
        ),
      ]);
      return ClinicalSupport.present(doc);
    });
  }
}
