import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'clinical_support.dart';

/// Vitals are append-only measurements. Values are validated in canonical
/// units, the originally entered value and unit are kept, and BMI is marked
/// as calculated. A wrong entry is corrected by recording a new one that
/// points at it; nothing is overwritten or deleted.
class VitalsService {
  VitalsService(this._s);

  final ClinicalSupport _s;

  static const String collection = 'patient_vitals';

  num? _num(BodyReader r, Object? raw, String field, num min, num max) {
    if (raw is! num || raw.isNaN || raw < min || raw > max) {
      r.addIssue(
        field,
        'out_of_range',
        '$field must be between $min and $max.',
      );
      return null;
    }
    return raw;
  }

  /// `{value, unit}` → canonical value, with the original kept.
  (num canonical, Map<String, Object?> original)? _measure(
    BodyReader r,
    String field,
    Map<String, num Function(num)> toCanonical,
    num min,
    num max,
  ) {
    if (!r.has(field)) return null;
    final raw = r.body[field];
    if (raw is! Map || raw['value'] is! num || raw['unit'] is! String) {
      r.addIssue(field, 'invalid_value', 'Give {value, unit}.');
      return null;
    }
    final unit = raw['unit'] as String;
    final conv = toCanonical[unit];
    if (conv == null) {
      r.addIssue(
        '$field.unit',
        'invalid_unit',
        'Unit must be ${toCanonical.keys.join(' or ')}.',
      );
      return null;
    }
    final canonical = conv(raw['value'] as num);
    if (canonical.isNaN || canonical < min || canonical > max) {
      r.addIssue(
        '$field.value',
        'out_of_range',
        'This value is outside the plausible range.',
      );
      return null;
    }
    return (
      double.parse(canonical.toStringAsFixed(2)),
      {'value': raw['value'], 'unit': unit},
    );
  }

  Future<Map<String, Object?>> record(
    TenantContext t,
    String patientId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.vitalsRecord);
    final patient = await _s.patients.load(t, patientId);
    _s.patients.requireOpen(patient);
    final r = BodyReader(body)
      ..rejectUnknown({
        'consultationId',
        'height',
        'weight',
        'systolic',
        'diastolic',
        'pulse',
        'temperature',
        'respiratoryRate',
        'spo2',
        'glucose',
        'additional',
        'measuredAt',
        'notes',
        'correctsVitalsId',
      });
    final height = _measure(
      r,
      'height',
      {'cm': (v) => v, 'in': (v) => v * 2.54},
      20,
      260,
    );
    final weight = _measure(
      r,
      'weight',
      {'kg': (v) => v, 'lb': (v) => v * 0.45359237},
      0.3,
      500,
    );
    final temp = _measure(
      r,
      'temperature',
      {'C': (v) => v, 'F': (v) => (v - 32) * 5 / 9},
      30,
      45,
    );
    final glucose = _measure(
      r,
      'glucose',
      {'mg/dL': (v) => v, 'mmol/L': (v) => v * 18.0182},
      10,
      1500,
    );
    final sys = r.has('systolic')
        ? _num(r, r.body['systolic'], 'systolic', 40, 300)
        : null;
    final dia = r.has('diastolic')
        ? _num(r, r.body['diastolic'], 'diastolic', 20, 200)
        : null;
    if ((sys == null) != (dia == null) &&
        !r.issues.any((i) => i.field == 'systolic' || i.field == 'diastolic')) {
      r.addIssue(
        'systolic',
        'pair_required',
        'Record systolic and diastolic together.',
      );
    }
    if (sys != null && dia != null && dia >= sys) {
      r.addIssue(
        'diastolic',
        'invalid_value',
        'Diastolic must be lower than systolic.',
      );
    }
    final pulse = r.has('pulse')
        ? _num(r, r.body['pulse'], 'pulse', 20, 300)
        : null;
    final resp = r.has('respiratoryRate')
        ? _num(r, r.body['respiratoryRate'], 'respiratoryRate', 4, 80)
        : null;
    final spo2 = r.has('spo2')
        ? _num(r, r.body['spo2'], 'spo2', 50, 100)
        : null;
    List<Map<String, Object?>>? extra;
    if (r.has('additional')) {
      final raw = r.body['additional'];
      if (raw is! List || raw.length > 10) {
        r.addIssue(
          'additional',
          'invalid_value',
          'Give up to 10 extra observations.',
        );
      } else {
        extra = [];
        for (var i = 0; i < raw.length; i++) {
          final e = raw[i];
          final c = BodyReader(e is Map ? e.cast<String, Object?>() : {})
            ..rejectUnknown({'name', 'value', 'unit'});
          final name = c.str('name', min: 2, max: 60);
          final value = c.str('value', max: 60);
          final unit = c.str('unit', max: 20, required: false);
          for (final x in c.issues) {
            r.addIssue('additional[$i].${x.field}', x.code, x.message);
          }
          extra.add({'name': name, 'value': value, 'unit': ?unit});
        }
      }
    }
    final notes = r.str('notes', max: 300, required: false);
    final consultationId = r.str('consultationId', max: 40, required: false);
    final corrects = r.str('correctsVitalsId', max: 40, required: false);
    final now = _s.d.now;
    var measuredAt = now;
    if (r.has('measuredAt')) {
      final v = r.body['measuredAt'] is String
          ? DateTime.tryParse(r.body['measuredAt']! as String)
          : null;
      if (v == null ||
          v.toUtc().isAfter(now.add(const Duration(minutes: 5))) ||
          v.toUtc().isBefore(now.subtract(const Duration(days: 7)))) {
        r.addIssue(
          'measuredAt',
          'invalid_date',
          'Give a time within the last 7 days, not in the future.',
        );
      } else {
        measuredAt = v.toUtc();
      }
    }
    final any =
        height != null ||
        weight != null ||
        temp != null ||
        glucose != null ||
        sys != null ||
        pulse != null ||
        resp != null ||
        spo2 != null ||
        (extra?.isNotEmpty ?? false);
    if (!any && r.issues.isEmpty) {
      r.addIssue('height', 'required', 'Record at least one measurement.');
    }
    r.throwIfInvalid();

    if (consultationId != null) {
      final c = await _s.consultation(t, consultationId);
      if (c['patientId'] != patientId) {
        throw ApiException.validation([
          issue(
            'consultationId',
            'wrong_patient',
            'The consultation belongs to another patient.',
          ),
        ]);
      }
    }
    if (corrects != null) {
      final prev = await _s.d.store.get(_s.path(t, collection, corrects));
      if (prev == null || prev['patientId'] != patientId) {
        throw ApiException.validation([
          issue(
            'correctsVitalsId',
            'invalid_reference',
            'That measurement does not belong to this patient.',
          ),
        ]);
      }
    }
    double? bmi;
    if (height != null && weight != null) {
      final m = height.$1 / 100;
      bmi = double.parse((weight.$1 / (m * m)).toStringAsFixed(1));
    }
    final id = 'vt_${newId(length: 12)}';
    final doc = <String, Object?>{
      'vitalsId': id,
      'tenantId': t.tenantId,
      'branchId': patient['branchId'],
      'patientId': patientId,
      'consultationId': consultationId,
      'correctsVitalsId': corrects,
      'heightCm': height?.$1,
      'weightKg': weight?.$1,
      // calculated, never typed in: shown as such, not a diagnosis
      'bmi': bmi,
      if (bmi != null) 'bmiCalculated': true,
      'systolic': sys,
      'diastolic': dia,
      'pulse': pulse,
      'temperatureC': temp?.$1,
      'respiratoryRate': resp,
      'spo2': spo2,
      'glucoseMgDl': glucose?.$1,
      'original': {
        'height': ?height?.$2,
        'weight': ?weight?.$2,
        'temperature': ?temp?.$2,
        'glucose': ?glucose?.$2,
      },
      'additional': extra ?? <Object?>[],
      'notes': notes,
      'measuredAt': measuredAt,
      'recordedBy': t.uid,
      'recordedByRole': t.role.wireName,
      'recordedAt': now,
    }..removeWhere((k, v) => v == null);
    await _s.d.store.commit([
      CreateOp(_s.path(t, collection, id), doc),
      _s.audit(
        t,
        action: 'vitals.recorded',
        resourceType: 'vitals',
        resourceId: id,
        branchId: '${patient['branchId']}',
        patientId: patientId,
        consultationId: consultationId,
        requestId: requestId,
        after: {'bmiCalculated': bmi != null, 'corrects': corrects},
      ),
    ]);
    return ClinicalSupport.present(doc);
  }

  Future<Paged> list(TenantContext t, String patientId, Request req) async {
    t.require(ClinicPermission.vitalsView);
    await _s.patients.load(t, patientId);
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, collection),
        filters: [QueryFilter('patientId', FilterOp.eq, patientId)],
        orderBy: const OrderBy('measuredAt', descending: true),
      ),
      req,
    );
  }
}

/// Tenant catalogues used for lookup only: diagnoses and medicines. They ship
/// **empty**: the clinic (or a later terminology import such as ICD-10)
/// supplies the entries, and nothing here is invented or implies suitability.
class CatalogueService {
  CatalogueService(this._s);

  final ClinicalSupport _s;

  static String _lower(String v) =>
      v.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<Paged> search(
    TenantContext t,
    Request req,
    String collection, {
    required String permission,
    String? q,
    String? status,
  }) async {
    if (!t.can(permission) &&
        !t.can(ClinicPermission.clinicalCatalogueManage)) {
      throw const ApiException.forbidden();
    }
    final term = q == null ? null : _lower(q);
    if (term != null && term.isNotEmpty && term.length < 2) {
      throw const ApiException.badRequest('Type at least 2 letters.');
    }
    final st = status ?? 'active';
    if (st != 'active' && st != 'inactive') {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, collection),
        filters: [
          QueryFilter('status', FilterOp.eq, st),
          if (term != null && term.isNotEmpty) ...[
            QueryFilter('nameLower', FilterOp.gte, term),
            QueryFilter('nameLower', FilterOp.lt, '$term'),
          ],
        ],
        orderBy: const OrderBy('nameLower'),
      ),
      req,
    );
  }

  Future<Map<String, Object?>> createDiagnosis(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) => _create(
    t,
    body,
    'diagnosis_catalogue',
    'dc_',
    'diagnosis_catalogue',
    requestId,
    {'name', 'code', 'codeSystem', 'description'},
  );

  Future<Map<String, Object?>> createMedicine(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) => _create(
    t,
    body,
    'medicine_catalogue',
    'md_',
    'medicine_catalogue',
    requestId,
    {'name', 'genericName', 'brandName', 'strength', 'form', 'description'},
  );

  Future<Map<String, Object?>> _create(
    TenantContext t,
    Map<String, Object?> body,
    String collection,
    String prefix,
    String resource,
    String? requestId,
    Set<String> allowed,
  ) async {
    t.require(ClinicPermission.clinicalCatalogueManage);
    final fields = _parse(body, allowed, partial: false);
    final id = '$prefix${newId(length: 12)}';
    final now = _s.d.now;
    final doc = {
      'entryId': id,
      'tenantId': t.tenantId,
      ...fields,
      'nameLower': _lower('${fields['name']}'),
      'status': 'active',
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
    };
    await _s.d.store.commit([
      CreateOp(_s.path(t, collection, id), doc),
      _s.audit(
        t,
        action: '$resource.added',
        resourceType: resource,
        resourceId: id,
        requestId: requestId,
        after: {'name': fields['name']},
      ),
    ]);
    return _pres(doc);
  }

  Map<String, Object?> _parse(
    Map<String, Object?> body,
    Set<String> allowed, {
    required bool partial,
  }) {
    final r = BodyReader(body, partial: partial)
      ..rejectUnknown({...allowed, if (partial) 'status'});
    final out = <String, Object?>{};
    final name = r.str('name', min: 2, max: 200);
    if (name != null) out['name'] = name;
    for (final k in allowed.where((k) => k != 'name')) {
      final v = r.str(k, max: k == 'description' ? 500 : 120, required: false);
      if (v != null) out[k] = v;
    }
    if (allowed.contains('code') &&
        (out['code'] == null) != (out['codeSystem'] == null) &&
        !partial) {
      r.addIssue(
        'codeSystem',
        'code_system_required',
        'Give a code together with the code system it comes from.',
      );
    }
    final st = r.enumOf<String>(
      'status',
      const ['active', 'inactive'],
      (v) => v,
      required: false,
    );
    if (st != null) out['status'] = st;
    r.throwIfInvalid();
    return out;
  }

  Future<Map<String, Object?>> update(
    TenantContext t,
    String collection,
    String id,
    Map<String, Object?> body,
    Set<String> allowed, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.clinicalCatalogueManage);
    final fields = _parse(body, allowed, partial: true);
    if (fields.isEmpty) {
      throw const ApiException.badRequest('Nothing to update.');
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.path(t, collection, id);
      final cur = await tx.get(path);
      if (cur == null) throw const ApiException.notFound('Entry not found.');
      final patch = {
        ...fields,
        if (fields.containsKey('name'))
          'nameLower': _lower('${fields['name']}'),
        'updatedAt': now,
      };
      tx.write([
        UpdateOp(path, patch),
        _s.audit(
          t,
          action: '$collection.updated',
          resourceType: collection,
          resourceId: id,
          requestId: requestId,
          after: {'fields': fields.keys.toList()},
        ),
      ]);
      return _pres({...cur, ...patch});
    });
  }

  static Map<String, Object?> _pres(Map<String, Object?> d) =>
      ClinicalSupport.present(d)..remove('nameLower');

  static Map<String, Object?> present(Map<String, Object?> d) => _pres(d);
}
