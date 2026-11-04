import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'lab_support.dart';

/// The laboratory test catalogue and the external-laboratory directory.
///
/// Reference ranges are the clinic's own configuration: each carries its
/// unit and source, and may depend on sex and age. The product ships none.
class LabCatalogueService {
  LabCatalogueService(this._s);

  final LabSupport _s;

  static const String collection = 'lab_tests';

  static String _lower(String v) =>
      v.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  // ---------------------------------------------------------- parameters

  List<Map<String, Object?>>? _parameters(BodyReader r) {
    if (!r.has('parameters')) {
      if (!r.partial) {
        r.addIssue('parameters', 'required', 'parameters is required.');
      }
      return null;
    }
    final raw = r.body['parameters'];
    if (raw is! List || raw.isEmpty || raw.length > 40) {
      r.addIssue('parameters', 'invalid_value', 'Give 1 to 40 parameters.');
      return null;
    }
    final out = <Map<String, Object?>>[];
    final codes = <String>{};
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        r.addIssue('parameters[$i]', 'invalid_type', 'Must be an object.');
        continue;
      }
      final p = BodyReader(item.cast<String, Object?>())
        ..rejectUnknown({
          'code',
          'name',
          'valueType',
          'unit',
          'qualitativeOptions',
          'referenceRanges',
        });
      final code = p.str('code', min: 1, max: 20);
      final name = p.str('name', min: 2, max: 80);
      final type = p.enumOf<String>('valueType', const [
        'numeric',
        'text',
        'qualitative',
      ], (v) => v);
      final unit = p.str('unit', max: 20, required: false);
      if (code != null && !codes.add(code.toLowerCase())) {
        p.addIssue(
          'code',
          'duplicate',
          'Parameter codes must be unique in a test.',
        );
      }
      List<Map<String, Object?>>? options;
      if (type == 'qualitative') {
        final o = p.body['qualitativeOptions'];
        if (o is! List || o.isEmpty || o.length > 20) {
          p.addIssue(
            'qualitativeOptions',
            'required',
            'Give the allowed results (up to 20).',
          );
        } else {
          options = [];
          for (var k = 0; k < o.length; k++) {
            final e = o[k];
            if (e is! Map ||
                e['value'] is! String ||
                (e['value'] as String).trim().isEmpty) {
              p.addIssue(
                'qualitativeOptions[$k]',
                'invalid_value',
                'Each option needs a value.',
              );
              continue;
            }
            options.add({
              'value': (e['value'] as String).trim(),
              if (e['abnormal'] == true) 'abnormal': true,
              if (e['critical'] == true) 'critical': true,
            });
          }
        }
      } else if (p.has('qualitativeOptions')) {
        p.addIssue(
          'qualitativeOptions',
          'not_allowed',
          'Only qualitative parameters have options.',
        );
      }
      List<Map<String, Object?>>? ranges;
      if (p.has('referenceRanges')) {
        if (type != 'numeric') {
          p.addIssue(
            'referenceRanges',
            'not_allowed',
            'Only numeric parameters have reference ranges.',
          );
        } else {
          ranges = _ranges(p, unit);
        }
      }
      for (final x in p.issues) {
        r.addIssue('parameters[$i].${x.field}', x.code, x.message);
      }
      out.add(
        {
          'code': code,
          'name': name,
          'valueType': type,
          'unit': unit,
          'qualitativeOptions': options,
          'referenceRanges': ranges ?? const <Object?>[],
        }..removeWhere((k, v) => v == null),
      );
    }
    return out;
  }

  List<Map<String, Object?>>? _ranges(BodyReader p, String? paramUnit) {
    final raw = p.body['referenceRanges'];
    if (raw is! List || raw.length > 10) {
      p.addIssue('referenceRanges', 'invalid_value', 'Give up to 10 ranges.');
      return null;
    }
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        p.addIssue('referenceRanges[$i]', 'invalid_type', 'Must be an object.');
        continue;
      }
      final m = item.cast<String, Object?>();
      final rr = BodyReader(m)
        ..rejectUnknown({
          'sex',
          'ageMinYears',
          'ageMaxYears',
          'low',
          'high',
          'criticalLow',
          'criticalHigh',
          'unit',
          'source',
          'note',
        });
      final sex =
          rr.enumOf<String>(
            'sex',
            const ['any', 'male', 'female'],
            (v) => v,
            required: false,
          ) ??
          'any';
      final source = rr.str('source', min: 3, max: 120);
      final unit = rr.str('unit', max: 20, required: false) ?? paramUnit;
      final note = rr.str('note', max: 200, required: false);
      num? n(String f) {
        final v = m[f];
        if (v == null) return null;
        if (v is! num || v.isNaN || v.isInfinite) {
          rr.addIssue(f, 'invalid_value', '$f must be a number.');
          return null;
        }
        return v;
      }

      final lo = n('low');
      final hi = n('high');
      final cl = n('criticalLow');
      final ch = n('criticalHigh');
      final amin = n('ageMinYears');
      final amax = n('ageMaxYears');
      if (lo == null && hi == null && cl == null && ch == null) {
        rr.addIssue('low', 'required', 'Give at least one limit.');
      }
      if (lo != null && hi != null && lo > hi) {
        rr.addIssue('low', 'invalid_range', 'low is above high.');
      }
      if (cl != null && lo != null && cl > lo) {
        rr.addIssue(
          'criticalLow',
          'invalid_range',
          'criticalLow must not be above low.',
        );
      }
      if (ch != null && hi != null && ch < hi) {
        rr.addIssue(
          'criticalHigh',
          'invalid_range',
          'criticalHigh must not be below high.',
        );
      }
      if (amin != null && amax != null && amin > amax) {
        rr.addIssue(
          'ageMinYears',
          'invalid_range',
          'ageMinYears is above ageMaxYears.',
        );
      }
      for (final x in rr.issues) {
        p.addIssue('referenceRanges[$i].${x.field}', x.code, x.message);
      }
      out.add(
        {
          'sex': sex,
          'ageMinYears': amin,
          'ageMaxYears': amax,
          'low': lo,
          'high': hi,
          'criticalLow': cl,
          'criticalHigh': ch,
          'unit': unit,
          'source': source,
          'note': note,
        }..removeWhere((k, v) => v == null),
      );
    }
    return out;
  }

  // -------------------------------------------------------------- create

  static const Set<String> _fields = {
    'code',
    'name',
    'category',
    'description',
    'sampleType',
    'container',
    'collectionInstructions',
    'fastingRequired',
    'fastingHours',
    'turnaroundHours',
    'priceMinor',
    'branchIds',
    'designation',
    'externalLabId',
    'parameters',
  };

  Future<Map<String, Object?>> _parse(TenantContext t, BodyReader r) async {
    final code = r.str('code', min: 2, max: 20, required: !r.partial);
    final name = r.str('name', min: 2, max: 120, required: !r.partial);
    final category = r.enumOf<String>(
      'category',
      labCategories,
      (v) => v,
      required: !r.partial,
    );
    final description = r.str('description', max: 500, required: false);
    final sample = r.enumOf<String>(
      'sampleType',
      sampleTypes,
      (v) => v,
      required: !r.partial,
    );
    final container = r.str('container', max: 60, required: false);
    final instr = r.str('collectionInstructions', max: 500, required: false);
    final fasting = r.boolean('fastingRequired');
    final fastingHours = r.integer(
      'fastingHours',
      min: 1,
      max: 24,
      required: false,
    );
    final tat = r.integer(
      'turnaroundHours',
      min: 1,
      max: 720,
      required: !r.partial,
    );
    final price = r.integer(
      'priceMinor',
      min: 0,
      max: 1000000000,
      required: false,
    );
    final designation = r.enumOf<String>(
      'designation',
      const ['in_house', 'external'],
      (v) => v,
      required: false,
    );
    final labId = r.str('externalLabId', max: 40, required: false);
    List<String>? branches;
    if (r.has('branchIds')) {
      final b = r.body['branchIds'];
      if (b is! List ||
          b.length > 50 ||
          b.any((e) => e is! String || e.isEmpty)) {
        r.addIssue('branchIds', 'invalid_value', 'Give up to 50 branch ids.');
      } else {
        branches = b.cast<String>();
      }
    }
    final params = _parameters(r);
    r.throwIfInvalid();
    for (final b in branches ?? const <String>[]) {
      t.scope.require(b);
      if (await _s.d.store.get(_s.path(t, 'branches', b)) == null) {
        throw const ApiException.notFound('Branch not found.');
      }
    }
    if (labId != null) {
      final lab = await _s.d.store.get(
        _s.path(t, 'external_laboratories', labId),
      );
      if (lab == null || lab['status'] != 'active') {
        throw const ApiException.notFound('External laboratory not found.');
      }
    }
    if ((designation == 'external') != (labId != null) &&
        (designation != null || labId != null)) {
      throw ApiException.validation([
        labIssue(
          'externalLabId',
          'invalid_value',
          'An external test names its laboratory; an in-house test does not.',
        ),
      ]);
    }
    return {
      'code': ?code,
      'name': ?name,
      if (name != null) 'nameLower': _lower(name),
      'category': ?category,
      'description': ?description,
      'sampleType': ?sample,
      'container': ?container,
      'collectionInstructions': ?instr,
      'fastingRequired': ?fasting,
      'fastingHours': ?fastingHours,
      'turnaroundHours': ?tat,
      'priceMinor': ?price,
      'branchIds': ?branches,
      'designation': ?designation,
      if (r.has('externalLabId')) 'externalLabId': labId,
      'parameters': ?params,
    };
  }

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labTestsManage);
    final r = BodyReader(body)..rejectUnknown(_fields);
    final f = await _parse(t, r);
    final id = 'lt_${newId(length: 12)}';
    final now = _s.d.now;
    final codeKey = '${f['code']}'.toLowerCase();
    final doc = <String, Object?>{
      'testId': id,
      'tenantId': t.tenantId,
      'fastingRequired': false,
      'designation': 'in_house',
      'branchIds': <String>[],
      ...f,
      'currency': 'INR',
      'priceMinor': f['priceMinor'] ?? 0,
      'status': 'active',
      'version': 1,
      'createdAt': now,
      'createdBy': t.uid,
      'updatedAt': now,
      'updatedBy': t.uid,
    };
    try {
      await _s.d.store.commit([
        CreateOp(_s.path(t, collection, id), doc),
        CreateOp(_s.path(t, 'lab_test_codes', codeKey), {
          'testId': id,
          'createdAt': now,
        }),
        _s.audit(
          t,
          action: 'lab_test.created',
          resourceType: 'lab_test',
          resourceId: id,
          requestId: requestId,
          after: {'code': f['code'], 'category': f['category']},
        ),
      ]);
    } on AlreadyExistsException {
      throw const ApiException.conflict(
        'A test with this code already exists.',
      );
    }
    return LabSupport.present(doc);
  }

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labTestsManage);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({..._fields, 'status', 'reason'});
    final status = r.enumOf<String>(
      'status',
      const ['active', 'inactive'],
      (v) => v,
      required: false,
    );
    final reason = r.str('reason', max: 300, required: false);
    final f = await _parse(t, r);
    final p = _s.path(t, collection, id);
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final cur = await tx.get(p);
      if (cur == null) throw const ApiException.notFound('Test not found.');
      final ops = <WriteOp>[];
      if (f['code'] != null &&
          '${f['code']}'.toLowerCase() != '${cur['code']}'.toLowerCase()) {
        final key = _s.path(t, 'lab_test_codes', '${f['code']}'.toLowerCase());
        if (await tx.get(key) != null) {
          throw const ApiException.conflict(
            'A test with this code already exists.',
          );
        }
        ops.add(CreateOp(key, {'testId': id, 'createdAt': now}));
      }
      final patch = <String, Object?>{
        ...f,
        'status': ?status,
        'version': ((cur['version'] as int?) ?? 1) + 1,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      ops
        ..add(UpdateOp(p, patch))
        ..add(
          _s.audit(
            t,
            action: 'lab_test.updated',
            resourceType: 'lab_test',
            resourceId: id,
            requestId: requestId,
            reason: reason,
            before: {'version': cur['version'], 'status': cur['status']},
            after: {
              'version': patch['version'],
              'status': status ?? cur['status'],
            },
          ),
        );
      tx.write(ops);
      return LabSupport.present({...cur, ...patch});
    });
  }

  Future<DocData> load(TenantContext t, String id, {TxContext? tx}) async {
    final p = _s.path(t, collection, id);
    final doc = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (doc == null) throw const ApiException.notFound('Test not found.');
    return doc;
  }

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.labTestsView);
    return LabSupport.present(await load(t, id));
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? q,
    String? category,
    String? status,
    String? branchId,
  }) async {
    t.require(ClinicPermission.labTestsView);
    if (category != null && !labCategories.contains(category)) {
      throw const ApiException.badRequest('category has an unsupported value.');
    }
    if (status != null && status != 'active' && status != 'inactive') {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    final term = q == null ? null : _lower(q);
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, collection),
        filters: [
          if (category != null) QueryFilter('category', FilterOp.eq, category),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
          if (term != null && term.isNotEmpty) ...[
            QueryFilter('nameLower', FilterOp.gte, term),
            QueryFilter('nameLower', FilterOp.lt, '$term'),
          ],
        ],
        orderBy: const OrderBy('nameLower'),
      ),
      req,
    );
    if (branchId == null) return page;
    t.scope.require(branchId);
    return Paged([
      for (final d in page.docs)
        if (((d.data['branchIds'] as List?) ?? const []).isEmpty ||
            ((d.data['branchIds'] as List).contains(branchId)))
          d,
    ], page.meta);
  }

  List<String> categories() => labCategories;

  // ------------------------------------------------- external laboratories

  Future<List<Map<String, Object?>>> externalLabs(TenantContext t) async {
    t.require(ClinicPermission.labTestsView);
    final rows = await _s.d.store.query(
      DocQuery(_s.path(t, 'external_laboratories'), limit: 200),
    );
    return [for (final r in rows) LabSupport.present(r.data)]..sort(
      (a, b) =>
          '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()),
    );
  }

  Future<Map<String, Object?>> createExternalLab(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labExternalManage);
    final r = BodyReader(body)
      ..rejectUnknown({
        'name',
        'contactPerson',
        'phone',
        'email',
        'address',
        'notes',
      });
    final name = r.str('name', min: 2, max: 120);
    final contact = r.str('contactPerson', max: 100, required: false);
    final phone = r.phone('phone', required: false);
    final email = r.email('email', required: false);
    final address = r.str('address', max: 300, required: false);
    final notes = r.str('notes', max: 300, required: false);
    r.throwIfInvalid();
    final id = 'xl_${newId(length: 10)}';
    final now = _s.d.now;
    final doc = <String, Object?>{
      'labId': id,
      'tenantId': t.tenantId,
      'name': name,
      'contactPerson': contact,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'status': 'active',
      'createdAt': now,
      'createdBy': t.uid,
    }..removeWhere((k, v) => v == null);
    await _s.d.store.commit([
      CreateOp(_s.path(t, 'external_laboratories', id), doc),
      _s.audit(
        t,
        action: 'external_lab.created',
        resourceType: 'external_lab',
        resourceId: id,
        requestId: requestId,
      ),
    ]);
    return LabSupport.present(doc);
  }
}
