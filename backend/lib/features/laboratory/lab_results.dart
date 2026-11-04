import 'dart:convert';
import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/object_storage.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'lab_evaluation.dart';
import 'lab_orders.dart';
import 'lab_pdf.dart';
import 'lab_support.dart';

const int maxExternalReportBytes = 8 * 1024 * 1024;

/// Results, verification, amendment, publication and reports.
///
/// Rules enforced here (not in the UI):
///  * results are entered against the parameters snapshotted on the order;
///  * flags come from the clinic's configured ranges only (see
///    `lab_evaluation.dart`), never from built-in medical values;
///  * the person who entered (or amended) a result cannot verify it;
///  * a published report is stored privately and versioned; an amendment
///    produces a new version and supersedes the old one, never overwrites it;
///  * non-laboratory staff (doctors) see results only once verified.
class LabResultService {
  LabResultService(this._s, this._orders);

  final LabSupport _s;
  final LabOrderService _orders;

  static const String results = 'lab_results';
  static const String reports = 'lab_reports';

  static const Set<String> _enterable = {'sample_collected', 'processing'};

  bool _isStaff(TenantContext t) =>
      t.can(ClinicPermission.labOrdersManage) ||
      t.can(ClinicPermission.labResultsEnter);

  String _rid(String orderId, String itemId) => '${orderId}__$itemId';

  // --------------------------------------------------------- observations

  static const _rangeKeys = [
    'low',
    'high',
    'criticalLow',
    'criticalHigh',
    'unit',
    'source',
    'text',
  ];

  List<Map<String, Object?>> _observations(
    BodyReader r,
    DocData order,
    Map<String, Object?> item,
    List<Object?> existing,
  ) {
    final params = (item['parameters'] as List).cast<Map<String, Object?>>();
    final byCode = {for (final p in params) '${p['code']}': p};
    final merged = <String, Map<String, Object?>>{
      for (final o in existing)
        '${(o as Map)['code']}': (o).cast<String, Object?>(),
    };
    final raw = r.body['observations'];
    if (raw is! List || raw.isEmpty || raw.length > 60) {
      r.addIssue('observations', 'invalid_value', 'Give 1 to 60 observations.');
      return const [];
    }
    final dob = order['patientDob'];
    final age = ageInYears(
      dob == null ? null : '$dob'.substring(0, '$dob'.length.clamp(0, 10)),
      _s.d.now,
    );
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is! Map) {
        r.addIssue('observations[$i]', 'invalid_type', 'Must be an object.');
        continue;
      }
      final c = BodyReader(e.cast<String, Object?>())
        ..rejectUnknown({'code', 'value', 'unit', 'comment'});
      final code = c.str('code', max: 20);
      final unit = c.str('unit', max: 20, required: false);
      final comment = c.str('comment', max: 300, required: false);
      Object? value = c.body['value'];
      final p = code == null ? null : byCode[code];
      if (code != null && p == null) {
        c.addIssue(
          'code',
          'unknown_parameter',
          'Not a parameter of this test.',
        );
      }
      if (p != null) {
        switch (p['valueType']) {
          case 'numeric':
            if (value is! num || value.isNaN || value.isInfinite) {
              c.addIssue('value', 'invalid_type', 'Enter a number.');
            } else if (value.abs() > 1e9) {
              c.addIssue(
                'value',
                'invalid_value',
                'The number is out of range.',
              );
            }
          case 'qualitative':
            final opts = (p['qualitativeOptions'] as List? ?? const []).map(
              (x) => (x as Map)['value'],
            );
            if (value is! String || !opts.contains(value)) {
              c.addIssue(
                'value',
                'invalid_value',
                'Choose one of the configured results.',
              );
            }
          default:
            if (value is! String ||
                value.trim().isEmpty ||
                value.length > 500) {
              c.addIssue('value', 'invalid_value', 'Enter 1-500 characters.');
            } else {
              value = value.trim();
            }
        }
      }
      for (final x in c.issues) {
        r.addIssue('observations[$i].${x.field}', x.code, x.message);
      }
      if (c.issues.isNotEmpty || p == null) continue;
      final used = unit ?? p['unit'] as String?;
      final ev = evaluate(
        p,
        value: value,
        unit: used,
        sex: order['patientSex'] as String?,
        ageYears: age,
      );
      merged['$code'] = {
        'code': code,
        'name': p['name'],
        'valueType': p['valueType'],
        'value': value,
        'unit': used,
        'flag': ev.flag,
        if (ev.range != null)
          'range': {
            for (final k in _rangeKeys)
              if (ev.range![k] != null) k: ev.range![k],
          },
        'comment': comment,
      }..removeWhere((k, v) => v == null);
    }
    // keep the test's own parameter order
    return [
      for (final p in params)
        if (merged['${p['code']}'] != null) merged['${p['code']}']!,
    ];
  }

  Map<String, Object?> _present(DocData res, {required bool staff}) {
    final out = LabSupport.present(res);
    if (!staff) {
      out
        ..remove('internalComment')
        ..remove('revisions')
        ..remove('history')
        ..remove('enteredBy');
    }
    return out;
  }

  // ------------------------------------------------------------- entering

  Future<Map<String, Object?>> save(
    TenantContext t,
    String orderId,
    String itemId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labResultsEnter);
    final r = BodyReader(body)
      ..rejectUnknown({'observations', 'internalComment'});
    final internal = r.str('internalComment', max: 500, required: false);
    return _s.d.store.transaction((tx) async {
      final o = await _orders.load(t, orderId, tx: tx);
      if (o['external'] == true) {
        throw const ApiException.conflict(
          'External tests take an uploaded report, not entered results.',
        );
      }
      final st = '${o['status']}';
      if (!_enterable.contains(st)) {
        throw ApiException.conflict(
          'Results cannot be entered on a $st order.',
        );
      }
      final item = (o['items'] as List).cast<Map<String, Object?>>().where(
        (i) => i['itemId'] == itemId,
      );
      if (item.isEmpty) throw const ApiException.notFound('Test not found.');
      final path = _s.path(t, results, _rid(orderId, itemId));
      final cur = await tx.get(path);
      if (cur != null &&
          cur['status'] != 'draft' &&
          cur['status'] != 'returned') {
        throw ApiException.conflict(
          'These results are ${cur['status']}; they can no longer be edited.',
        );
      }
      final obs = _observations(
        r,
        o,
        item.first,
        (cur?['observations'] as List?) ?? const [],
      );
      r.throwIfInvalid();
      final now = _s.d.now;
      final doc = <String, Object?>{
        'resultId': _rid(orderId, itemId),
        'orderId': orderId,
        'itemId': itemId,
        'tenantId': t.tenantId,
        'branchId': o['branchId'],
        'patientId': o['patientId'],
        'testId': item.first['testId'],
        'testName': item.first['name'],
        'status': cur?['status'] == 'returned' ? 'returned' : 'draft',
        'observations': obs,
        'internalComment': internal ?? cur?['internalComment'],
        'revision': cur?['revision'] ?? 1,
        'enteredBy': t.uid,
        'enteredAt': cur?['enteredAt'] ?? now,
        'updatedAt': now,
        'revisions': cur?['revisions'] ?? const <Object?>[],
        'history': cur == null
            ? [_s.event(t, 'draft')]
            : _s.history(cur, _s.event(t, 'edited')),
      }..removeWhere((k, v) => v == null);
      final ops = <WriteOp>[
        cur == null ? CreateOp(path, doc) : UpdateOp(path, doc),
        _s.audit(
          t,
          action: 'lab_result.saved',
          resourceType: 'lab_result',
          resourceId: _rid(orderId, itemId),
          branchId: '${o['branchId']}',
          patientId: '${o['patientId']}',
          orderId: orderId,
          requestId: requestId,
          after: {'parameters': obs.length},
        ),
      ];
      if (st == 'sample_collected') {
        ops.add(
          UpdateOp(_s.path(t, LabOrderService.collection, orderId), {
            'status': 'processing',
            'history': _s.history(o, _s.event(t, 'processing')),
            'updatedAt': now,
          }),
        );
      }
      tx.write(ops);
      return _present(doc, staff: true);
    });
  }

  Future<List<DocData>> _itemResults(
    TxContext tx,
    TenantContext t,
    DocData o,
  ) async {
    final out = <DocData>[];
    for (final i in (o['items'] as List).cast<Map<String, Object?>>()) {
      final d = await tx.get(
        _s.path(t, results, _rid('${o['orderId']}', '${i['itemId']}')),
      );
      if (d != null) out.add(d);
    }
    return out;
  }

  Future<Map<String, Object?>> submit(
    TenantContext t,
    String orderId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labResultsEnter);
    return _s.d.store.transaction((tx) async {
      final o = await _orders.load(t, orderId, tx: tx);
      if (o['status'] == 'verification_pending') {
        return {..._orders.presentOrder(o), 'idempotentReplay': true};
      }
      if (o['status'] != 'processing') {
        throw ApiException.conflict(
          'Results cannot be submitted for a ${o['status']} order.',
        );
      }
      final items = (o['items'] as List).cast<Map<String, Object?>>();
      final docs = await _itemResults(tx, t, o);
      final problems = <FieldIssue>[];
      for (final i in items) {
        final d = docs.where((x) => x['itemId'] == i['itemId']);
        if (d.isEmpty) {
          problems.add(
            labIssue('${i['name']}', 'missing', 'No results entered.'),
          );
          continue;
        }
        final have = {
          for (final x in (d.first['observations'] as List))
            '${(x as Map)['code']}',
        };
        for (final p
            in (i['parameters'] as List).cast<Map<String, Object?>>()) {
          if (!have.contains('${p['code']}')) {
            problems.add(
              labIssue(
                '${i['name']}.${p['code']}',
                'missing',
                '${p['name']} has no value.',
              ),
            );
          }
        }
      }
      if (problems.isNotEmpty) throw ApiException.validation(problems);
      final now = _s.d.now;
      final ops = <WriteOp>[
        for (final d in docs)
          UpdateOp(_s.path(t, results, '${d['resultId']}'), {
            'status': 'submitted',
            'submittedBy': t.uid,
            'submittedAt': now,
            'history': _s.history(d, _s.event(t, 'submitted')),
            'updatedAt': now,
          }),
        UpdateOp(_s.path(t, LabOrderService.collection, orderId), {
          'status': 'verification_pending',
          'history': [
            ...(o['history'] as List),
            _s.event(t, 'result_entered'),
            _s.event(t, 'verification_pending'),
          ],
          'updatedAt': now,
        }),
        _s.audit(
          t,
          action: 'lab_result.submitted',
          resourceType: 'lab_order',
          resourceId: orderId,
          branchId: '${o['branchId']}',
          patientId: '${o['patientId']}',
          orderId: orderId,
          requestId: requestId,
        ),
      ];
      tx.write(ops);
      return _orders.presentOrder({...o, 'status': 'verification_pending'});
    });
  }

  // --------------------------------------------------------- verification

  Future<Map<String, Object?>> verify(
    TenantContext t,
    String orderId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labResultsVerify);
    return _s.d.store.transaction((tx) async {
      final o = await _orders.load(t, orderId, tx: tx);
      if (o['status'] == 'verified') {
        return {..._orders.presentOrder(o), 'idempotentReplay': true};
      }
      if (o['status'] != 'verification_pending') {
        throw ApiException.conflict(
          'A ${o['status']} order is not waiting for verification.',
        );
      }
      final now = _s.d.now;
      final ops = <WriteOp>[];
      if (o['external'] == true) {
        final rep = await tx.get(
          _s.path(t, reports, '${o['externalReportId']}'),
        );
        if (rep == null) {
          throw const ApiException.conflict('No external report was uploaded.');
        }
        if (rep['createdBy'] == t.uid) {
          throw const ApiException.conflict(
            'The person who uploaded the report cannot verify it.',
          );
        }
        ops.add(
          UpdateOp(_s.path(t, reports, '${rep['reportId']}'), {
            'verifiedByClinic': true,
            'verifiedBy': t.uid,
            'verifiedAt': now,
          }),
        );
      } else {
        final docs = await _itemResults(tx, t, o);
        if (docs.length != (o['items'] as List).length ||
            docs.any((d) => d['status'] != 'submitted')) {
          throw const ApiException.conflict(
            'Every test needs submitted results before verification.',
          );
        }
        if (docs.any(
          (d) => d['enteredBy'] == t.uid || d['submittedBy'] == t.uid,
        )) {
          throw const ApiException.conflict(
            'Results must be verified by someone other than the person who entered them.',
          );
        }
        for (final d in docs) {
          ops.add(
            UpdateOp(_s.path(t, results, '${d['resultId']}'), {
              'status': 'verified',
              'verifiedBy': t.uid,
              'verifiedAt': now,
              'history': _s.history(d, _s.event(t, 'verified')),
              'updatedAt': now,
            }),
          );
        }
      }
      ops
        ..add(
          UpdateOp(_s.path(t, LabOrderService.collection, orderId), {
            'status': 'verified',
            'verifiedBy': t.uid,
            'verifiedAt': now,
            'history': _s.history(o, _s.event(t, 'verified')),
            'updatedAt': now,
          }),
        )
        ..add(
          _s.audit(
            t,
            action: 'lab_result.verified',
            resourceType: 'lab_order',
            resourceId: orderId,
            branchId: '${o['branchId']}',
            patientId: '${o['patientId']}',
            orderId: orderId,
            requestId: requestId,
          ),
        );
      tx.write(ops);
      return _orders.presentOrder({...o, 'status': 'verified'});
    });
  }

  Future<Map<String, Object?>> returnForCorrection(
    TenantContext t,
    String orderId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labResultsVerify);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    return _s.d.store.transaction((tx) async {
      final o = await _orders.load(t, orderId, tx: tx);
      if (o['status'] != 'verification_pending') {
        throw ApiException.conflict(
          'A ${o['status']} order cannot be returned.',
        );
      }
      final now = _s.d.now;
      final ops = <WriteOp>[];
      if (o['external'] != true) {
        for (final d in await _itemResults(tx, t, o)) {
          ops.add(
            UpdateOp(_s.path(t, results, '${d['resultId']}'), {
              'status': 'returned',
              'returnReason': reason,
              'history': _s.history(d, _s.event(t, 'returned', reason: reason)),
              'updatedAt': now,
            }),
          );
        }
      }
      ops
        ..add(
          UpdateOp(_s.path(t, LabOrderService.collection, orderId), {
            'status': 'processing',
            'returnReason': reason,
            'history': _s.history(o, _s.event(t, 'processing', reason: reason)),
            'updatedAt': now,
          }),
        )
        ..add(
          _s.audit(
            t,
            action: 'lab_result.returned',
            resourceType: 'lab_order',
            resourceId: orderId,
            branchId: '${o['branchId']}',
            patientId: '${o['patientId']}',
            orderId: orderId,
            reason: reason,
            requestId: requestId,
          ),
        );
      tx.write(ops);
      return _orders.presentOrder({...o, 'status': 'processing'});
    });
  }

  /// Corrects verified or published results. The previous values are kept in
  /// `revisions`; the order goes back to verification and, once verified and
  /// republished, the report becomes a new version.
  Future<Map<String, Object?>> amend(
    TenantContext t,
    String orderId,
    String itemId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labResultsEnter);
    final r = BodyReader(body)
      ..rejectUnknown({'observations', 'reason', 'internalComment'});
    final reason = r.str('reason', min: 5, max: 300);
    final internal = r.str('internalComment', max: 500, required: false);
    return _s.d.store.transaction((tx) async {
      final o = await _orders.load(t, orderId, tx: tx);
      if (o['status'] != 'verified' && o['status'] != 'published') {
        throw ApiException.conflict(
          'Only verified or published results can be amended (order is ${o['status']}).',
        );
      }
      final item = (o['items'] as List).cast<Map<String, Object?>>().where(
        (i) => i['itemId'] == itemId,
      );
      if (item.isEmpty) throw const ApiException.notFound('Test not found.');
      final cur = await tx.get(_s.path(t, results, _rid(orderId, itemId)));
      if (cur == null) throw const ApiException.notFound('Result not found.');
      final obs = _observations(
        r,
        o,
        item.first,
        (cur['observations'] as List?) ?? const [],
      );
      r.throwIfInvalid();
      final now = _s.d.now;
      final rev = (cur['revision'] as int? ?? 1);
      final patch = <String, Object?>{
        'status': 'submitted',
        'observations': obs,
        'internalComment': internal ?? cur['internalComment'],
        'revision': rev + 1,
        'enteredBy': t.uid,
        'submittedBy': t.uid,
        'amendReason': reason,
        'revisions': [
          ...((cur['revisions'] as List?) ?? const []),
          {
            'revision': rev,
            'observations': cur['observations'],
            'verifiedBy': cur['verifiedBy'],
            'verifiedAt': cur['verifiedAt'],
            'amendedBy': t.uid,
            'amendedAt': now,
            'reason': reason,
          },
        ],
        'history': _s.history(cur, _s.event(t, 'amended', reason: reason)),
        'updatedAt': now,
      }..removeWhere((k, v) => v == null);
      tx.write([
        UpdateOp(_s.path(t, results, _rid(orderId, itemId)), patch),
        UpdateOp(_s.path(t, LabOrderService.collection, orderId), {
          'status': 'verification_pending',
          'amendmentPending': true,
          'history': _s.history(
            o,
            _s.event(t, 'verification_pending', reason: 'amendment: $reason'),
          ),
          'updatedAt': now,
        }),
        _s.audit(
          t,
          action: 'lab_result.amended',
          resourceType: 'lab_result',
          resourceId: _rid(orderId, itemId),
          branchId: '${o['branchId']}',
          patientId: '${o['patientId']}',
          orderId: orderId,
          reason: reason,
          requestId: requestId,
          before: {'revision': rev},
          after: {'revision': rev + 1},
        ),
      ]);
      return _present({...cur, ...patch}, staff: true);
    });
  }

  // ---------------------------------------------------------------- reads

  Future<Map<String, Object?>> forOrder(TenantContext t, String orderId) async {
    t.require(ClinicPermission.labResultsView);
    final o = await _orders.load(t, orderId);
    final staff = _isStaff(t);
    if (!staff && o['status'] != 'verified' && o['status'] != 'published') {
      return {'orderId': orderId, 'status': o['status'], 'results': const []};
    }
    final rows = await _s.d.store.query(
      DocQuery(
        _s.path(t, results),
        filters: [QueryFilter('orderId', FilterOp.eq, orderId)],
        limit: 40,
      ),
    );
    return {
      'orderId': orderId,
      'status': o['status'],
      'results': [for (final d in rows) _present(d.data, staff: staff)],
    };
  }

  // ---------------------------------------------------------- publication

  String _flagText(String? f) => switch (f) {
    'low' => 'LOW',
    'high' => 'HIGH',
    'abnormal' => 'ABNORMAL',
    'critical_low' => 'CRITICAL LOW',
    'critical_high' => 'CRITICAL HIGH',
    'critical' => 'CRITICAL',
    'unit_mismatch' => 'UNIT MISMATCH',
    'not_assessed' => 'no reference range',
    _ => '',
  };

  String _rangeText(Map<String, Object?>? range) {
    if (range == null) return '';
    final lo = range['low'];
    final hi = range['high'];
    final u = range['unit'] == null ? '' : ' ${range['unit']}';
    final src = range['source'] == null ? '' : ' (${range['source']})';
    if (lo != null && hi != null) return '$lo - $hi$u$src';
    if (hi != null) return 'up to $hi$u$src';
    if (lo != null) return 'from $lo$u$src';
    return '';
  }

  Uint8List _renderPdf(
    DocData order,
    List<DocData> docs,
    String number,
    int version,
    DateTime at,
    String branchName,
  ) {
    final lines = <PdfLine>[
      PdfLine('Laboratory Report', size: 18, bold: true),
      PdfLine(branchName, size: 11),
      PdfLine('Report $number  -  version $version', size: 10, gap: 6),
      PdfLine('Order ${order['orderNumber']}'),
      PdfLine(
        'Patient: ${order['patientName']}   (${order['patientMrn']})',
        size: 11,
        bold: true,
        gap: 10,
      ),
      if (order['patientSex'] != null || order['patientDob'] != null)
        PdfLine(
          'Sex: ${order['patientSex'] ?? '-'}   Date of birth: ${order['patientDob'] ?? '-'}',
        ),
      if (order['doctorName'] != null)
        PdfLine('Requested by: ${order['doctorName']}'),
      PdfLine('Published: ${at.toUtc().toIso8601String()}'),
    ];
    for (final i in (order['items'] as List).cast<Map<String, Object?>>()) {
      final d = docs.where((x) => x['itemId'] == i['itemId']);
      if (d.isEmpty) continue;
      lines.add(PdfLine('${i['name']}', size: 12, bold: true, gap: 14));
      for (final o
          in (d.first['observations'] as List).cast<Map<String, Object?>>()) {
        final flag = _flagText(o['flag'] as String?);
        final unit = o['unit'] == null ? '' : ' ${o['unit']}';
        final ref = _rangeText(o['range'] as Map<String, Object?>?);
        lines.add(
          PdfLine(
            '${o['name']}: ${o['value']}$unit${flag.isEmpty ? '' : '   [$flag]'}'
            '${ref.isEmpty ? '' : '   Ref: $ref'}',
            bold: flag.contains('CRITICAL') || flag == 'HIGH' || flag == 'LOW',
          ),
        );
        if (o['comment'] != null) {
          lines.add(PdfLine('  Note: ${o['comment']}', size: 9));
        }
      }
    }
    lines
      ..add(
        PdfLine(
          'Reference ranges are those configured by this laboratory. Flags support, '
          'and do not replace, clinical judgement.',
          size: 8,
          gap: 18,
        ),
      )
      ..add(PdfLine('Verified by the laboratory before publication.', size: 8));
    return buildPdf(lines, title: 'Laboratory Report $number');
  }

  Future<Map<String, Object?>> publish(
    TenantContext t,
    String orderId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labReportsPublish);
    String? notifyPatient;
    String? notifyNumber;
    String? notifyId;
    late final Map<String, Object?> out;
    Uint8List? bytes;
    String? storagePath;
    String? sha;
    out = await _s.d.store.transaction((tx) async {
      final o = await _orders.load(t, orderId, tx: tx);
      final prior = await tx.query(
        DocQuery(
          _s.path(t, reports),
          filters: [
            QueryFilter('orderId', FilterOp.eq, orderId),
            QueryFilter('status', FilterOp.eq, 'published'),
          ],
          limit: 20,
        ),
      );
      if (o['status'] == 'published' &&
          prior.isNotEmpty &&
          o['amendmentPending'] != true) {
        return {
          ...LabSupport.present(prior.first.data),
          'idempotentReplay': true,
        };
      }
      if (o['status'] != 'verified') {
        throw ApiException.conflict(
          'Only a verified order can be published (order is ${o['status']}).',
        );
      }
      final id = 'lr_${newId(length: 14)}';
      final version = prior.length + 1;
      final now = _s.d.now;
      final ops = <WriteOp>[];
      final number = await _s.nextNumber(
        tx,
        t,
        ops,
        counter: 'lab_report_number',
        prefix: 'RPT',
        keys: 'lab_report_numbers',
        ownerId: id,
      );
      Map<String, Object?> doc;
      if (o['external'] == true) {
        final ext = await tx.get(
          _s.path(t, reports, '${o['externalReportId']}'),
        );
        if (ext == null || ext['verifiedByClinic'] != true) {
          throw const ApiException.conflict(
            'The external report must be reviewed by the clinic before publishing.',
          );
        }
        ops.add(
          UpdateOp(_s.path(t, reports, '${ext['reportId']}'), {
            'status': 'published',
            'current': true,
            'publishedBy': t.uid,
            'publishedAt': now,
          }),
        );
        doc = {...ext, 'status': 'published', 'current': true};
      } else {
        final docs = await _itemResults(tx, t, o);
        bytes = _renderPdf(o, docs, number, version, now, '${o['branchName']}');
        sha = sha256.convert(bytes!).toString();
        storagePath = '${t.tenantId}/lab_reports/$id.pdf';
        doc = {
          'reportId': id,
          'reportNumber': number,
          'tenantId': t.tenantId,
          'branchId': o['branchId'],
          'orderId': orderId,
          'orderNumber': o['orderNumber'],
          'patientId': o['patientId'],
          'doctorId': o['doctorId'],
          'consultationId': o['consultationId'],
          'version': version,
          'status': 'published',
          'current': true,
          'external': false,
          'source': 'eazyclinic',
          'label': 'Verified by the laboratory',
          'storagePath': storagePath,
          'contentType': 'application/pdf',
          'sizeBytes': bytes!.length,
          'sha256': sha,
          'createdBy': t.uid,
          'publishedBy': t.uid,
          'publishedAt': now,
          'createdAt': now,
        }..removeWhere((k, v) => v == null);
        ops.add(CreateOp(_s.path(t, reports, id), doc));
      }
      for (final p in prior) {
        ops.add(
          UpdateOp(p.path, {
            'status': 'superseded',
            'current': false,
            'supersededAt': now,
          }),
        );
      }
      ops
        ..add(
          UpdateOp(_s.path(t, LabOrderService.collection, orderId), {
            'status': 'published',
            'reportId': doc['reportId'],
            'amendmentPending': false,
            'publishedAt': now,
            'history': _s.history(o, _s.event(t, 'published')),
            'updatedAt': now,
          }),
        )
        ..add(
          _s.audit(
            t,
            action: 'lab_report.published',
            resourceType: 'lab_report',
            resourceId: '${doc['reportId']}',
            branchId: '${o['branchId']}',
            patientId: '${o['patientId']}',
            orderId: orderId,
            requestId: requestId,
            after: {
              'version': doc['version'],
              'external': o['external'] == true,
            },
          ),
        );
      // the bytes are stored before the commit so a published report always
      // has its file; an orphan file after a failed commit is harmless
      if (bytes != null) {
        await _s.storage.put(storagePath!, bytes!, 'application/pdf');
      }
      tx.write(ops);
      notifyPatient = '${o['patientId']}';
      notifyNumber = '${o['orderNumber']}';
      notifyId = '${doc['reportId']}';
      return LabSupport.present(doc);
    });
    if (notifyPatient != null && out['idempotentReplay'] != true) {
      try {
        await _s.notifier?.publishForPatient(
          t.tenantId,
          notifyPatient!,
          category: 'lab_report_available',
          title: 'Your laboratory report is ready',
          body: 'Report for order $notifyNumber is available.',
          dedupeKey: 'lab_report:$notifyId',
          resourceType: 'lab_report',
          resourceId: notifyId,
        );
      } on Object {
        // a failed notification never undoes a published report
      }
    }
    return out;
  }

  // --------------------------------------------------------- external lab

  Future<Map<String, Object?>> uploadExternal(
    TenantContext t,
    String orderId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labExternalManage);
    final r = BodyReader(body)
      ..rejectUnknown({'contentBase64', 'fileName', 'externalReference'});
    final name = r.str('fileName', max: 120);
    final ref = r.str('externalReference', max: 80, required: false);
    final b64 = r.str('contentBase64', max: 12 * 1024 * 1024);
    r.throwIfInvalid();
    Uint8List data;
    try {
      data = base64.decode(b64!);
    } on FormatException {
      throw ApiException.validation([
        labIssue('contentBase64', 'invalid_value', 'Not valid base64.'),
      ]);
    }
    if (data.isEmpty || data.length > maxExternalReportBytes) {
      throw ApiException.validation([
        labIssue(
          'contentBase64',
          'invalid_value',
          'The file must be 1 byte to 8 MB.',
        ),
      ]);
    }
    final isPdf =
        data.length > 5 &&
        ascii.decode(data.sublist(0, 5), allowInvalid: true) == '%PDF-';
    final type = isPdf ? 'application/pdf' : sniffImageType(data);
    if (type == null) {
      throw ApiException.validation([
        labIssue(
          'contentBase64',
          'unsupported_type',
          'Upload a PDF, PNG, JPEG or WebP file.',
        ),
      ]);
    }
    final id = 'lr_${newId(length: 14)}';
    final path = '${t.tenantId}/lab_reports/$id';
    final sum = sha256.convert(data).toString();
    final out = await _s.d.store.transaction((tx) async {
      final o = await _orders.load(t, orderId, tx: tx);
      if (o['external'] != true) {
        throw const ApiException.conflict(
          'Only external tests take an uploaded report.',
        );
      }
      final st = '${o['status']}';
      if (st != 'sample_collected' && st != 'processing') {
        throw ApiException.conflict('Cannot upload a report on a $st order.');
      }
      if (o['externalReportId'] != null) {
        throw const ApiException.conflict(
          'A report was already uploaded for this order.',
        );
      }
      final now = _s.d.now;
      final ops = <WriteOp>[];
      final number = await _s.nextNumber(
        tx,
        t,
        ops,
        counter: 'lab_report_number',
        prefix: 'RPT',
        keys: 'lab_report_numbers',
        ownerId: id,
      );
      final doc = <String, Object?>{
        'reportId': id,
        'reportNumber': number,
        'tenantId': t.tenantId,
        'branchId': o['branchId'],
        'orderId': orderId,
        'orderNumber': o['orderNumber'],
        'patientId': o['patientId'],
        'doctorId': o['doctorId'],
        'consultationId': o['consultationId'],
        'version': 1,
        'status': 'uploaded',
        'current': false,
        'external': true,
        'source': 'external_laboratory',
        'label': 'External laboratory report - uploaded by the clinic',
        'verifiedByClinic': false,
        'externalLabId': o['externalLabId'],
        'externalReference': ref,
        'fileName': name,
        'storagePath': path,
        'contentType': type,
        'sizeBytes': data.length,
        'sha256': sum,
        'createdBy': t.uid,
        'createdAt': now,
      }..removeWhere((k, v) => v == null);
      ops
        ..add(CreateOp(_s.path(t, reports, id), doc))
        ..add(
          UpdateOp(_s.path(t, LabOrderService.collection, orderId), {
            'status': 'verification_pending',
            'externalReportId': id,
            'history': [
              ...(o['history'] as List),
              if (st == 'sample_collected') _s.event(t, 'processing'),
              _s.event(t, 'result_entered'),
              _s.event(t, 'verification_pending'),
            ],
            'updatedAt': now,
          }),
        )
        ..add(
          _s.audit(
            t,
            action: 'lab_report.external_uploaded',
            resourceType: 'lab_report',
            resourceId: id,
            branchId: '${o['branchId']}',
            patientId: '${o['patientId']}',
            orderId: orderId,
            requestId: requestId,
            after: {'sizeBytes': data.length, 'contentType': type},
          ),
        );
      await _s.storage.put(path, data, type);
      tx.write(ops);
      return LabSupport.present(doc);
    });
    return out;
  }

  // -------------------------------------------------------------- reports

  Future<DocData> _report(TenantContext t, String id) async {
    final d = await _s.d.store.get(_s.path(t, reports, id));
    if (d == null || !t.scope.allows('${d['branchId']}')) {
      throw const ApiException.notFound('Report not found.');
    }
    if (_isStaff(t)) return d;
    if (d['status'] != 'published' && d['status'] != 'superseded') {
      throw const ApiException.notFound('Report not found.');
    }
    final own = await _s.sched.ownDoctorId(t);
    if (own == null || d['doctorId'] != own) {
      throw const ApiException.notFound('Report not found.');
    }
    return d;
  }

  Future<Paged> listReports(
    TenantContext t,
    Request req, {
    String? orderId,
    String? patientId,
    String? branchId,
    String? status,
  }) async {
    t.require(ClinicPermission.labReportsView);
    String? own;
    if (!_isStaff(t)) {
      own = await _s.sched.ownDoctorId(t);
      if (own == null) {
        return Paged(const [], const PageMeta(limit: 1, hasMore: false));
      }
    }
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, reports),
        filters: [
          ..._s.scopeFilters(t, branchId),
          if (orderId != null) QueryFilter('orderId', FilterOp.eq, orderId),
          if (patientId != null)
            QueryFilter('patientId', FilterOp.eq, patientId),
          if (own != null) QueryFilter('doctorId', FilterOp.eq, own),
          if (own != null)
            QueryFilter('status', FilterOp.eq, status ?? 'published')
          else if (status != null)
            QueryFilter('status', FilterOp.eq, status),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
  }

  Future<Map<String, Object?>> reportDetail(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labReportsView);
    final d = await _report(t, id);
    await _s.d.store.transaction((tx) async {
      tx.write([
        _s.audit(
          t,
          action: 'lab_report.viewed',
          resourceType: 'lab_report',
          resourceId: id,
          branchId: '${d['branchId']}',
          patientId: '${d['patientId']}',
          orderId: '${d['orderId']}',
          requestId: requestId,
        ),
      ]);
    });
    final out = LabSupport.present(d)..remove('storagePath');
    return out;
  }

  /// Bytes of a report, streamed to an authenticated caller; there is no
  /// permanent or public link to the file.
  Future<Response> download(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labReportsView);
    final d = await _report(t, id);
    if (d['status'] == 'uploaded' && !_isStaff(t)) {
      throw const ApiException.notFound('Report not found.');
    }
    final obj = await _s.storage.get('${d['storagePath']}');
    if (obj == null) {
      throw const ApiException.notFound('Report file not found.');
    }
    await _s.d.store.transaction((tx) async {
      tx.write([
        _s.audit(
          t,
          action: 'lab_report.downloaded',
          resourceType: 'lab_report',
          resourceId: id,
          branchId: '${d['branchId']}',
          patientId: '${d['patientId']}',
          orderId: '${d['orderId']}',
          requestId: requestId,
        ),
      ]);
    });
    return Response.ok(
      obj.$1,
      headers: {
        'content-type': '${d['contentType']}',
        'content-disposition':
            'attachment; filename="${d['reportNumber']}.${d['contentType'] == 'application/pdf' ? 'pdf' : 'bin'}"',
        'cache-control': 'private, no-store',
        'x-content-type-options': 'nosniff',
      },
    );
  }

  Future<Paged> auditLogs(
    TenantContext t,
    Request req, {
    String? orderId,
    String? patientId,
    String? action,
  }) async {
    t.require(ClinicPermission.labAuditView);
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, 'lab_audit_logs'),
        filters: [
          ..._s.scopeFilters(t, null),
          if (orderId != null) QueryFilter('orderId', FilterOp.eq, orderId),
          if (patientId != null)
            QueryFilter('patientId', FilterOp.eq, patientId),
          if (action != null) QueryFilter('action', FilterOp.eq, action),
        ],
        orderBy: const OrderBy('timestamp', descending: true),
      ),
      req,
    );
  }
}
