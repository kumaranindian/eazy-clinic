import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../clinical/clinical_support.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import '../portal/portal_support.dart';
import '../scheduling/time_support.dart';
import 'lab_catalogue.dart';
import 'lab_support.dart';

const int reportScanCap = 5000;

/// Laboratory orders, samples and the dashboard.
///
/// A doctor's request (from a consultation) and a staff-entered order both
/// become one `lab_orders` document with its items; the doctor's request
/// records in `investigation_requests` (Phase 6) are kept and linked, never
/// duplicated into a second request store.
class LabOrderService {
  LabOrderService(this._s, this._catalogue, this._clinical);

  final LabSupport _s;
  final LabCatalogueService _catalogue;
  final ClinicalSupport _clinical;

  static const String collection = 'lab_orders';
  static const String samples = 'lab_samples';

  // ----------------------------------------------------------------- load

  Future<DocData> load(TenantContext t, String id, {TxContext? tx}) async {
    final p = _s.path(t, collection, id);
    final o = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (o == null || !t.scope.allows('${o['branchId']}')) {
      throw const ApiException.notFound('Order not found.');
    }
    if (!await _mayRead(t, o)) {
      throw const ApiException.notFound('Order not found.');
    }
    return o;
  }

  /// Staff who manage orders see all in their branches; a doctor who does not
  /// sees only orders they requested.
  Future<bool> _mayRead(TenantContext t, DocData o) async {
    if (t.can(ClinicPermission.labOrdersManage) ||
        t.can(ClinicPermission.labResultsEnter) ||
        t.can(ClinicPermission.labSamplesManage)) {
      return t.can(ClinicPermission.labOrdersView);
    }
    if (!t.can(ClinicPermission.labOrdersView)) return false;
    final own = await _s.sched.ownDoctorId(t);
    return own != null && o['doctorId'] == own;
  }

  Map<String, Object?> presentOrder(DocData o) {
    final out = LabSupport.present(o);
    // snapshots of the test definitions stay on the order, not in lists
    return out;
  }

  // --------------------------------------------------------------- create

  Future<List<Map<String, Object?>>> _items(
    TenantContext t,
    BodyReader r,
    String branchId, {
    TxContext? tx,
  }) async {
    final raw = r.body['tests'];
    if (raw is! List || raw.isEmpty || raw.length > 30) {
      r.addIssue('tests', 'invalid_value', 'Choose 1 to 30 tests.');
      return const [];
    }
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        r.addIssue('tests[$i]', 'invalid_type', 'Must be an object.');
        continue;
      }
      final c = BodyReader(item.cast<String, Object?>())
        ..rejectUnknown({'testId', 'indication', 'instructions'});
      final testId = c.str('testId', max: 40);
      final indication = c.str('indication', min: 3, max: 300, required: false);
      final instructions = c.str('instructions', max: 300, required: false);
      for (final x in c.issues) {
        r.addIssue('tests[$i].${x.field}', x.code, x.message);
      }
      if (testId == null) continue;
      if (!seen.add(testId)) {
        r.addIssue(
          'tests[$i].testId',
          'duplicate',
          'Each test can be chosen once.',
        );
        continue;
      }
      final test = await _catalogue.load(t, testId, tx: tx);
      if (test['status'] != 'active') {
        throw const ApiException.conflict('That test is not active.');
      }
      final branches = (test['branchIds'] as List?) ?? const [];
      if (branches.isNotEmpty && !branches.contains(branchId)) {
        throw const ApiException.conflict(
          'That test is not offered at this branch.',
        );
      }
      out.add(
        {
          'itemId': 'it${out.length + 1}',
          'testId': testId,
          'testVersion': test['version'],
          'code': test['code'],
          'name': test['name'],
          'category': test['category'],
          'sampleType': test['sampleType'],
          'container': test['container'],
          'designation': test['designation'] ?? 'in_house',
          'externalLabId': test['externalLabId'],
          'turnaroundHours': test['turnaroundHours'],
          'fastingRequired': test['fastingRequired'] == true,
          // the definition at order time: later catalogue edits do not change it
          'parameters': test['parameters'],
          'indication': indication,
          'instructions': instructions,
        }..removeWhere((k, v) => v == null),
      );
    }
    final desig = {for (final i in out) i['designation']};
    if (desig.length > 1) {
      r.addIssue(
        'tests',
        'mixed_designation',
        'Order in-house and external tests separately.',
      );
    }
    return out;
  }

  Future<Map<String, Object?>> _create(
    TenantContext t, {
    required DocData patient,
    required String branchId,
    required Map<String, Object?> body,
    required BodyReader r,
    String? consultationId,
    DocData? consultation,
    String? idemKey,
    String? requestId,
  }) async {
    final priority =
        r.enumOf<String>(
          'priority',
          labPriorities,
          (v) => v,
          required: false,
        ) ??
        'routine';
    r.throwIfInvalid();
    final branch = await _s.sched.branch(t, branchId);
    final now = _s.d.now;
    final id = 'lo_${newId(length: 14)}';
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(_canon(body))))
        .toString();
    final idemPath = idemKey == null
        ? null
        : _s.path(
            t,
            'lab_idempotency',
            sha256.convert(utf8.encode('${t.uid}:$idemKey')).toString(),
          );
    return _s.d.store.transaction((tx) async {
      if (idemPath != null) {
        final prior = await tx.get(idemPath);
        if (prior != null) {
          if (prior['fingerprint'] != fingerprint) {
            throw const ApiException.conflict(
              'This Idempotency-Key was already used for a different request.',
            );
          }
          final o = await tx.get(_s.path(t, collection, '${prior['orderId']}'));
          return {...LabSupport.present(o!), 'idempotentReplay': true};
        }
      }
      final items = await _items(t, r, branchId, tx: tx);
      r.throwIfInvalid();
      final ops = <WriteOp>[];
      if (consultationId != null) {
        for (final i in items) {
          final kp = _s.path(
            t,
            'lab_order_keys',
            '${consultationId}_${i['testId']}',
          );
          final k = await tx.get(kp);
          if (k != null && k['active'] == true) {
            throw ApiException.conflict(
              '${i['name']} is already requested for this consultation (order ${k['orderNumber']}).',
            );
          }
          ops.add(
            k == null
                ? CreateOp(kp, {
                    'orderId': id,
                    'active': true,
                    'createdAt': now,
                  })
                : UpdateOp(kp, {'orderId': id, 'active': true}),
          );
        }
      }
      final number = await _s.nextNumber(
        tx,
        t,
        ops,
        counter: 'lab_order_number',
        prefix: 'LAB',
        keys: 'lab_order_numbers',
        ownerId: id,
      );
      if (consultationId != null) {
        // the key documents learn the order number for friendly conflicts
        for (var k = 0; k < ops.length; k++) {
          final o = ops[k];
          if (o is CreateOp && o.path.contains('/lab_order_keys/')) {
            ops[k] = CreateOp(o.path, {...o.data, 'orderNumber': number});
          } else if (o is UpdateOp && o.path.contains('/lab_order_keys/')) {
            ops[k] = UpdateOp(o.path, {...o.fields, 'orderNumber': number});
          }
        }
      }
      final order = <String, Object?>{
        'orderId': id,
        'orderNumber': number,
        'tenantId': t.tenantId,
        'branchId': branchId,
        'branchName': branch['name'],
        'patientId': patient['patientId'],
        'patientName': patient['fullName'],
        'patientMrn': patient['mrn'],
        'patientSex': patient['gender'],
        'patientDob': patient['dateOfBirth'],
        'consultationId': consultationId,
        'doctorId': consultation?['doctorId'],
        'doctorName': consultation?['doctorName'],
        'source': consultation == null ? 'laboratory' : 'doctor',
        'priority': priority,
        'status': 'requested',
        'external':
            items.isNotEmpty && items.first['designation'] == 'external',
        'externalLabId': items.isEmpty ? null : items.first['externalLabId'],
        'items': items,
        'history': [_s.event(t, 'requested')],
        'createdBy': t.uid,
        'createdAt': now,
        'updatedAt': now,
      }..removeWhere((k, v) => v == null);
      ops.add(CreateOp(_s.path(t, collection, id), order));
      if (consultationId != null) {
        // keep the doctor's request records (Phase 6), linked to the order
        for (final i in items) {
          final rid = 'inv_${newId(length: 12)}';
          ops.add(
            CreateOp(
              _s.path(t, 'investigation_requests', rid),
              {
                'investigationId': rid,
                'consultationId': consultationId,
                'tenantId': t.tenantId,
                'branchId': branchId,
                'patientId': patient['patientId'],
                'doctorId': consultation!['doctorId'],
                'testName': i['name'],
                'code': i['code'],
                'testId': i['testId'],
                'indication': i['indication'],
                'instructions': i['instructions'],
                'priority': priority == 'emergency' ? 'stat' : priority,
                'status': 'ordered',
                'processing': 'laboratory',
                'labOrderId': id,
                'labOrderNumber': number,
                'requestedBy': t.uid,
                'requestedAt': now,
              }..removeWhere((k, v) => v == null),
            ),
          );
        }
      }
      if (idemPath != null) {
        ops.add(
          CreateOp(idemPath, {
            'fingerprint': fingerprint,
            'orderId': id,
            'createdAt': now,
          }),
        );
      }
      ops.add(
        _s.audit(
          t,
          action: 'lab_order.created',
          resourceType: 'lab_order',
          resourceId: id,
          branchId: branchId,
          patientId: '${patient['patientId']}',
          orderId: id,
          requestId: requestId,
          after: {
            'number': number,
            'tests': items.length,
            'priority': priority,
            'source': order['source'],
          },
        ),
      );
      tx.write(ops);
      return presentOrder(order);
    });
  }

  Object? _canon(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((e) => '$e').toList()..sort();
      return {for (final k in keys) k: _canon(v[k])};
    }
    if (v is List) return v.map(_canon).toList();
    return v;
  }

  /// A doctor requests investigations in a consultation.
  Future<Map<String, Object?>> createForConsultation(
    TenantContext t,
    String consultationId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.investigationsRequest);
    final r = BodyReader(body)..rejectUnknown({'tests', 'priority'});
    final c = await _clinical.consultation(t, consultationId);
    await _clinical.requireAuthor(t, c);
    _clinical.requireOpen(c);
    final patient = await _s.patients.load(t, '${c['patientId']}');
    return _create(
      t,
      patient: patient,
      branchId: '${c['branchId']}',
      body: {...body, 'consultationId': consultationId},
      r: r,
      consultationId: consultationId,
      consultation: c,
      requestId: requestId,
    );
  }

  /// Laboratory staff enter an order directly (for example a walk-in).
  Future<Map<String, Object?>> createManual(
    TenantContext t,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    t.require(ClinicPermission.labOrdersManage);
    if (idempotencyKey == null ||
        !RegExp(r'^[A-Za-z0-9_\-]{8,64}$').hasMatch(idempotencyKey)) {
      throw const ApiException.badRequest(
        'Send an Idempotency-Key header (8-64 letters, digits, - or _).',
      );
    }
    final r = BodyReader(body)
      ..rejectUnknown({'patientId', 'branchId', 'tests', 'priority'});
    final patientId = r.str('patientId', max: 40);
    final branchId = r.str('branchId', max: 40);
    r.throwIfInvalid();
    final patient = await _s.patients.load(t, patientId!);
    if (patient['status'] != 'active') {
      throw const ApiException.conflict('The patient record is not active.');
    }
    return _create(
      t,
      patient: patient,
      branchId: branchId!,
      body: body,
      r: r,
      idemKey: idempotencyKey,
      requestId: requestId,
    );
  }

  // ------------------------------------------------------------ transitions

  Future<Map<String, Object?>> _move(
    TenantContext t,
    String id,
    String to, {
    String? reason,
    Map<String, Object?> extra = const {},
    String? requestId,
    bool allowAuthorDoctor = false,
  }) {
    return _s.d.store.transaction((tx) async {
      final o = await load(t, id, tx: tx);
      var allowed = t.can(ClinicPermission.labOrdersManage);
      if (!allowed && allowAuthorDoctor) {
        allowed =
            o['doctorId'] != null &&
            await _s.sched.ownDoctorId(t) == o['doctorId'];
      }
      if (!allowed) throw const ApiException.forbidden();
      final from = '${o['status']}';
      if (from == to) return {...presentOrder(o), 'idempotentReplay': true};
      _s.requireMove(from, to);
      final patch = <String, Object?>{
        'status': to,
        ...extra,
        'history': _s.history(o, _s.event(t, to, reason: reason)),
        'updatedAt': _s.d.now,
      };
      final ops = <WriteOp>[
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'lab_order.$to',
          resourceType: 'lab_order',
          resourceId: id,
          branchId: '${o['branchId']}',
          patientId: '${o['patientId']}',
          orderId: id,
          reason: reason,
          requestId: requestId,
          before: {'status': from},
          after: {'status': to},
        ),
      ];
      if (to == 'rejected' || to == 'cancelled') {
        final cid = o['consultationId'] as String?;
        if (cid != null) {
          for (final i in (o['items'] as List)) {
            ops.add(
              UpdateOp(
                _s.path(t, 'lab_order_keys', '${cid}_${(i as Map)['testId']}'),
                {'active': false},
              ),
            );
          }
          final reqs = await tx.query(
            DocQuery(
              _s.path(t, 'investigation_requests'),
              filters: [QueryFilter('labOrderId', FilterOp.eq, id)],
              limit: 40,
            ),
          );
          for (final q in reqs) {
            ops.add(UpdateOp(q.path, {'status': to}));
          }
        }
        // open samples are closed with the order
        final sm = await tx.query(
          DocQuery(
            _s.path(t, samples),
            filters: [QueryFilter('orderId', FilterOp.eq, id)],
            limit: 40,
          ),
        );
        for (final s in sm) {
          if (s.data['status'] == 'pending') {
            ops.add(
              UpdateOp(s.path, {'status': 'cancelled', 'updatedAt': _s.d.now}),
            );
          }
        }
      }
      tx.write(ops);
      return presentOrder({...o, ...patch});
    });
  }

  Future<Map<String, Object?>> accept(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labOrdersManage);
    final r = BodyReader(body)..rejectUnknown({'assignedTo'});
    final assignee = r.str('assignedTo', max: 128, required: false);
    r.throwIfInvalid();
    if (assignee != null) {
      final m = await _s.d.store.get(_s.path(t, 'members', assignee));
      if (m == null || m['status'] != 'active') {
        throw const ApiException.notFound('Staff member not found.');
      }
    }
    return _move(
      t,
      id,
      'accepted',
      extra: {'assignedTo': ?assignee, 'acceptedBy': t.uid},
      requestId: requestId,
    );
  }

  Future<Map<String, Object?>> reject(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labOrdersManage);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    return _move(
      t,
      id,
      'rejected',
      reason: reason,
      extra: {'rejectReason': reason},
      requestId: requestId,
    );
  }

  Future<Map<String, Object?>> cancel(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    final o = await load(t, id);
    if (const {
      'processing',
      'result_entered',
      'verification_pending',
      'verified',
      'published',
    }.contains(o['status'])) {
      throw const ApiException.conflict(
        'An order with results cannot be cancelled.',
      );
    }
    return _move(
      t,
      id,
      'cancelled',
      reason: reason,
      extra: {'cancelReason': reason},
      requestId: requestId,
      allowAuthorDoctor: true,
    );
  }

  // ---------------------------------------------------------------- reads

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.labOrdersView);
    final o = await load(t, id);
    final sm = await _s.d.store.query(
      DocQuery(
        _s.path(t, samples),
        filters: [QueryFilter('orderId', FilterOp.eq, id)],
        limit: 40,
      ),
    );
    return {
      ...presentOrder(o),
      'samples': [for (final s in sm) LabSupport.present(s.data)],
    };
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? status,
    String? priority,
    String? doctorId,
    String? patientId,
    String? branchId,
    String? from,
    String? to,
    String? q,
  }) async {
    t.require(ClinicPermission.labOrdersView);
    if (status != null && !orderTransitions.containsKey(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (priority != null && !labPriorities.contains(priority)) {
      throw const ApiException.badRequest('priority has an unsupported value.');
    }
    final zone = await _s.zone(t);
    DateTime? lo;
    DateTime? hi;
    if (from != null) {
      if (!Dates.valid(from)) {
        throw const ApiException.badRequest('from must be YYYY-MM-DD.');
      }
      lo = zone.toUtc(from, 0);
    }
    if (to != null) {
      if (!Dates.valid(to)) {
        throw const ApiException.badRequest('to must be YYYY-MM-DD.');
      }
      hi = zone.toUtc(Dates.addDays(to, 1), 0);
    }
    final managesOrders =
        t.can(ClinicPermission.labOrdersManage) ||
        t.can(ClinicPermission.labResultsEnter) ||
        t.can(ClinicPermission.labSamplesManage);
    String? ownDoctor;
    if (!managesOrders) {
      ownDoctor = await _s.sched.ownDoctorId(t);
      if (ownDoctor == null) {
        return Paged(const [], const PageMeta(limit: 1, hasMore: false));
      }
    }
    final term = q?.trim().toUpperCase();
    if (term != null && term.isNotEmpty) {
      final key = await _s.d.store.get(_s.path(t, 'lab_order_numbers', term));
      final o = key == null
          ? null
          : await _s.d.store.get(_s.path(t, collection, '${key['ownerId']}'));
      final ok =
          o != null &&
          t.scope.allows('${o['branchId']}') &&
          (ownDoctor == null || o['doctorId'] == ownDoctor);
      return Paged([
        if (ok) StoredDoc(_s.path(t, collection, '${o['orderId']}'), o),
      ], const PageMeta(limit: 1, hasMore: false));
    }
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, collection),
        filters: [
          ..._s.scopeFilters(t, branchId),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
          if (priority != null) QueryFilter('priority', FilterOp.eq, priority),
          if (doctorId != null || ownDoctor != null)
            QueryFilter('doctorId', FilterOp.eq, ownDoctor ?? doctorId),
          if (patientId != null)
            QueryFilter('patientId', FilterOp.eq, patientId),
          if (lo != null) QueryFilter('createdAt', FilterOp.gte, lo),
          if (hi != null) QueryFilter('createdAt', FilterOp.lt, hi),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
  }

  /// Orders (and their request status) of one consultation, for the doctor.
  Future<List<Map<String, Object?>>> forConsultation(
    TenantContext t,
    String consultationId,
  ) async {
    t.require(ClinicPermission.labOrdersView);
    final c = await _clinical.consultation(t, consultationId);
    final rows = await _s.d.store.query(
      DocQuery(
        _s.path(t, collection),
        filters: [
          QueryFilter('consultationId', FilterOp.eq, '${c['consultationId']}'),
        ],
        limit: 20,
      ),
    );
    return [
      for (final r in rows) {...PortalLike.summary(r.data)},
    ];
  }

  // -------------------------------------------------------------- samples

  Future<DocData> _sample(TenantContext t, String id, {TxContext? tx}) async {
    final p = _s.path(t, samples, id);
    final s = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (s == null || !t.scope.allows('${s['branchId']}')) {
      throw const ApiException.notFound('Sample not found.');
    }
    return s;
  }

  Future<Map<String, Object?>> createSample(
    TenantContext t,
    String orderId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labSamplesManage);
    final r = BodyReader(body)
      ..rejectUnknown({'sampleType', 'itemIds', 'container', 'notes'});
    final type = r.enumOf<String>(
      'sampleType',
      sampleTypes,
      (v) => v,
      required: false,
    );
    final container = r.str('container', max: 60, required: false);
    final notes = r.str('notes', max: 300, required: false);
    List<String>? itemIds;
    if (r.has('itemIds')) {
      final v = r.body['itemIds'];
      if (v is! List || v.isEmpty || v.any((e) => e is! String)) {
        r.addIssue('itemIds', 'invalid_value', 'Give the item ids.');
      } else {
        itemIds = v.cast<String>();
      }
    }
    r.throwIfInvalid();
    final id = 'ls_${newId(length: 12)}';
    return _s.d.store.transaction((tx) async {
      final o = await load(t, orderId, tx: tx);
      final st = '${o['status']}';
      if (st != 'accepted' && st != 'sample_pending') {
        throw ApiException.conflict(
          st == 'requested'
              ? 'Accept the order before adding samples.'
              : 'A $st order takes no new sample here.',
        );
      }
      final items = (o['items'] as List).cast<Map<String, Object?>>();
      final existing = await tx.query(
        DocQuery(
          _s.path(t, samples),
          filters: [QueryFilter('orderId', FilterOp.eq, orderId)],
          limit: 40,
        ),
      );
      final covered = <String>{
        for (final s in existing)
          if (s.data['status'] != 'rejected' && s.data['status'] != 'cancelled')
            ...((s.data['itemIds'] as List).cast<String>()),
      };
      final chosen = [
        for (final i in items)
          if (!covered.contains(i['itemId']) &&
              (itemIds == null
                  ? (type == null || i['sampleType'] == type)
                  : itemIds.contains(i['itemId'])))
            i,
      ];
      if (chosen.isEmpty ||
          (itemIds != null && chosen.length != itemIds.length)) {
        throw const ApiException.conflict(
          'No matching test is waiting for a sample.',
        );
      }
      final sampleType = type ?? '${chosen.first['sampleType']}';
      final ops = <WriteOp>[];
      final number = await _s.nextNumber(
        tx,
        t,
        ops,
        counter: 'lab_sample_number',
        prefix: 'SMP',
        keys: 'lab_sample_numbers',
        ownerId: id,
      );
      final doc = <String, Object?>{
        'sampleId': id,
        'sampleNumber': number,
        'tenantId': t.tenantId,
        'branchId': o['branchId'],
        'orderId': orderId,
        'orderNumber': o['orderNumber'],
        'patientId': o['patientId'],
        'patientName': o['patientName'],
        'patientMrn': o['patientMrn'],
        'sampleType': sampleType,
        'itemIds': [for (final i in chosen) i['itemId']],
        'container': container ?? chosen.first['container'],
        'notes': notes,
        'status': 'pending',
        'history': [_s.event(t, 'pending')],
        'createdBy': t.uid,
        'createdAt': _s.d.now,
        'updatedAt': _s.d.now,
      }..removeWhere((k, v) => v == null);
      ops
        ..add(CreateOp(_s.path(t, samples, id), doc))
        ..add(
          _s.audit(
            t,
            action: 'lab_sample.created',
            resourceType: 'lab_sample',
            resourceId: id,
            branchId: '${o['branchId']}',
            patientId: '${o['patientId']}',
            orderId: orderId,
            requestId: requestId,
          ),
        );
      if (st == 'accepted') {
        ops.add(
          UpdateOp(_s.path(t, collection, orderId), {
            'status': 'sample_pending',
            'history': _s.history(o, _s.event(t, 'sample_pending')),
            'updatedAt': _s.d.now,
          }),
        );
      }
      tx.write(ops);
      return LabSupport.present(doc);
    });
  }

  static const List<String> sampleConditions = [
    'acceptable',
    'hemolyzed',
    'lipemic',
    'clotted',
    'insufficient',
    'other',
  ];

  Future<Map<String, Object?>> collect(
    TenantContext t,
    String sampleId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labSamplesManage);
    final r = BodyReader(body)
      ..rejectUnknown({
        'identifier',
        'confirmedMrn',
        'container',
        'condition',
        'notes',
      });
    final identifier = r.str('identifier', min: 4, max: 40);
    if (identifier != null &&
        !RegExp(r'^[A-Za-z0-9\-_/]+$').hasMatch(identifier)) {
      r.addIssue(
        'identifier',
        'invalid_value',
        'Use letters, digits, - _ or /.',
      );
    }
    final mrn = r.str('confirmedMrn', max: 30);
    final container = r.str('container', max: 60, required: false);
    final condition =
        r.enumOf<String>(
          'condition',
          sampleConditions,
          (v) => v,
          required: false,
        ) ??
        'acceptable';
    final notes = r.str('notes', max: 300, required: false);
    r.throwIfInvalid();
    final key = identifier!.toUpperCase();
    return _s.d.store.transaction((tx) async {
      final s = await _sample(t, sampleId, tx: tx);
      if (s['status'] == 'collected') {
        return {...LabSupport.present(s), 'idempotentReplay': true};
      }
      if (s['status'] != 'pending') {
        throw ApiException.conflict(
          'A ${s['status']} sample cannot be collected.',
        );
      }
      final o = await load(t, '${s['orderId']}', tx: tx);
      if (o['status'] != 'sample_pending') {
        throw ApiException.conflict(
          'The order is ${o['status']}; samples cannot be collected now.',
        );
      }
      if ('${s['patientMrn']}'.toUpperCase() != mrn!.toUpperCase()) {
        throw ApiException.validation([
          labIssue(
            'confirmedMrn',
            'identity_mismatch',
            'The patient number does not match this order. Check the patient\'s identity.',
          ),
        ]);
      }
      final keyPath = _s.path(t, 'lab_sample_ids', key);
      if (await tx.get(keyPath) != null) {
        throw const ApiException.conflict(
          'This sample identifier is already in use.',
        );
      }
      final now = _s.d.now;
      final patch = <String, Object?>{
        'status': 'collected',
        'identifier': identifier,
        'container': container ?? s['container'],
        'condition': condition,
        'identityVerified': true,
        'collectedBy': t.uid,
        'collectedAt': now,
        'notes': notes ?? s['notes'],
        'history': _s.history(s, _s.event(t, 'collected')),
        'updatedAt': now,
      }..removeWhere((k, v) => v == null);
      final others = await tx.query(
        DocQuery(
          _s.path(t, samples),
          filters: [QueryFilter('orderId', FilterOp.eq, '${s['orderId']}')],
          limit: 40,
        ),
      );
      final stillPending = others.where(
        (x) => x.id != sampleId && x.data['status'] == 'pending',
      );
      final ops = <WriteOp>[
        CreateOp(keyPath, {'sampleId': sampleId, 'createdAt': now}),
        UpdateOp(_s.path(t, samples, sampleId), patch),
        _s.audit(
          t,
          action: 'lab_sample.collected',
          resourceType: 'lab_sample',
          resourceId: sampleId,
          branchId: '${s['branchId']}',
          patientId: '${s['patientId']}',
          orderId: '${s['orderId']}',
          requestId: requestId,
          after: {'condition': condition},
        ),
      ];
      if (stillPending.isEmpty) {
        ops.add(
          UpdateOp(_s.path(t, collection, '${s['orderId']}'), {
            'status': 'sample_collected',
            'history': _s.history(o, _s.event(t, 'sample_collected')),
            'updatedAt': now,
          }),
        );
      }
      tx.write(ops);
      return LabSupport.present({...s, ...patch});
    });
  }

  Future<Map<String, Object?>> rejectSample(
    TenantContext t,
    String sampleId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labSamplesManage);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    final out = await _s.d.store.transaction((tx) async {
      final s = await _sample(t, sampleId, tx: tx);
      if (s['status'] == 'rejected') {
        return {...LabSupport.present(s), 'idempotentReplay': true};
      }
      if (s['status'] != 'pending' && s['status'] != 'collected') {
        throw ApiException.conflict(
          'A ${s['status']} sample cannot be rejected.',
        );
      }
      final o = await load(t, '${s['orderId']}', tx: tx);
      if (!const {'sample_pending', 'sample_collected'}.contains(o['status'])) {
        throw ApiException.conflict(
          'The order is ${o['status']}; the sample can no longer be rejected.',
        );
      }
      final now = _s.d.now;
      final patch = <String, Object?>{
        'status': 'rejected',
        'rejectReason': reason,
        'rejectedBy': t.uid,
        'rejectedAt': now,
        'history': _s.history(s, _s.event(t, 'rejected', reason: reason)),
        'updatedAt': now,
      };
      tx.write([
        UpdateOp(_s.path(t, samples, sampleId), patch),
        UpdateOp(_s.path(t, collection, '${s['orderId']}'), {
          'status': 'recollection_required',
          'history': _s.history(
            o,
            _s.event(t, 'recollection_required', reason: reason),
          ),
          'updatedAt': now,
        }),
        _s.audit(
          t,
          action: 'lab_sample.rejected',
          resourceType: 'lab_sample',
          resourceId: sampleId,
          branchId: '${s['branchId']}',
          patientId: '${s['patientId']}',
          orderId: '${s['orderId']}',
          reason: reason,
          requestId: requestId,
        ),
      ]);
      return LabSupport.present({...s, ...patch});
    });
    // tell the requesting doctor; the reason (clinical text) is not sent
    final order = await _s.d.store.get(
      _s.path(t, collection, '${out['orderId']}'),
    );
    if (order != null && order['doctorId'] != null) {
      try {
        await _s.notifier?.notifyDoctor(
          t.tenantId,
          '${order['doctorId']}',
          category: 'lab_sample_rejected',
          title: 'A sample was rejected',
          body:
              'A laboratory sample needs to be collected again. Open the app.',
          dedupeKey: 'sample_rejected:$sampleId',
          resourceType: 'lab_order',
          resourceId: '${out['orderId']}',
        );
      } on Object {
        // notifications never undo a rejection
      }
    }
    return out;
  }

  Future<Map<String, Object?>> recollect(
    TenantContext t,
    String sampleId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.labSamplesManage);
    final id = 'ls_${newId(length: 12)}';
    return _s.d.store.transaction((tx) async {
      final s = await _sample(t, sampleId, tx: tx);
      if (s['status'] != 'rejected') {
        throw const ApiException.conflict(
          'Only a rejected sample can be recollected.',
        );
      }
      if (s['recollectedAs'] != null) {
        throw const ApiException.conflict(
          'This sample was already recollected.',
        );
      }
      final o = await load(t, '${s['orderId']}', tx: tx);
      if (o['status'] != 'recollection_required') {
        throw ApiException.conflict('The order is ${o['status']}.');
      }
      final ops = <WriteOp>[];
      final number = await _s.nextNumber(
        tx,
        t,
        ops,
        counter: 'lab_sample_number',
        prefix: 'SMP',
        keys: 'lab_sample_numbers',
        ownerId: id,
      );
      final now = _s.d.now;
      final doc = <String, Object?>{
        'sampleId': id,
        'sampleNumber': number,
        'tenantId': t.tenantId,
        'branchId': s['branchId'],
        'orderId': s['orderId'],
        'orderNumber': s['orderNumber'],
        'patientId': s['patientId'],
        'patientName': s['patientName'],
        'patientMrn': s['patientMrn'],
        'sampleType': s['sampleType'],
        'itemIds': s['itemIds'],
        'container': s['container'],
        'recollectOf': sampleId,
        'status': 'pending',
        'history': [_s.event(t, 'pending')],
        'createdBy': t.uid,
        'createdAt': now,
        'updatedAt': now,
      }..removeWhere((k, v) => v == null);
      ops
        ..add(CreateOp(_s.path(t, samples, id), doc))
        ..add(
          UpdateOp(_s.path(t, samples, sampleId), {
            'recollectedAs': id,
            'updatedAt': now,
          }),
        )
        ..add(
          UpdateOp(_s.path(t, collection, '${s['orderId']}'), {
            'status': 'sample_pending',
            'history': _s.history(
              o,
              _s.event(t, 'sample_pending', reason: 'recollection'),
            ),
            'updatedAt': now,
          }),
        )
        ..add(
          _s.audit(
            t,
            action: 'lab_sample.recollection_requested',
            resourceType: 'lab_sample',
            resourceId: id,
            branchId: '${s['branchId']}',
            patientId: '${s['patientId']}',
            orderId: '${s['orderId']}',
            requestId: requestId,
          ),
        );
      tx.write(ops);
      return LabSupport.present(doc);
    });
  }

  Future<Paged> listSamples(
    TenantContext t,
    Request req, {
    String? status,
    String? branchId,
    String? orderId,
  }) async {
    t.require(ClinicPermission.labOrdersView);
    if (!t.can(ClinicPermission.labSamplesManage) &&
        !t.can(ClinicPermission.labResultsEnter)) {
      throw const ApiException.forbidden();
    }
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, samples),
        filters: [
          ..._s.scopeFilters(t, branchId),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
          if (orderId != null) QueryFilter('orderId', FilterOp.eq, orderId),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
  }

  // ------------------------------------------------------------ dashboard

  Future<Map<String, Object?>> dashboard(TenantContext t, Request req) async {
    t.require(ClinicPermission.labDashboardView);
    final zone = await _s.zone(t);
    final now = _s.d.now;
    final today = zone.localDate(now);
    final q = req.url.queryParameters;
    final from = q['from'] ?? today;
    final to = q['to'] ?? today;
    if (!Dates.valid(from) || !Dates.valid(to) || to.compareTo(from) < 0) {
      throw const ApiException.badRequest(
        'from and to must be dates with from not after to.',
      );
    }
    if (Dates.daysBetween(from, to) > 92) {
      throw const ApiException.badRequest('Choose a range of at most 92 days.');
    }
    final status = q['status'];
    final priority = q['priority'];
    if (status != null && !orderTransitions.containsKey(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (priority != null && !labPriorities.contains(priority)) {
      throw const ApiException.badRequest('priority has an unsupported value.');
    }
    final branchId = q['branchId'];
    final lo = zone.toUtc(from, 0);
    final hi = zone.toUtc(Dates.addDays(to, 1), 0);
    final scope = _s.scopeFilters(t, branchId);
    final orders = await _s.d.store.query(
      DocQuery(
        _s.path(t, collection),
        filters: [
          ...scope,
          if (priority != null) QueryFilter('priority', FilterOp.eq, priority),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
        ],
        limit: reportScanCap,
      ),
    );
    final smp = await _s.d.store.query(
      DocQuery(_s.path(t, samples), filters: [...scope], limit: reportScanCap),
    );
    bool inRange(Object? at) =>
        at is DateTime && !at.isBefore(lo) && at.isBefore(hi);
    const open = {
      'requested',
      'accepted',
      'sample_pending',
      'recollection_required',
      'sample_collected',
      'processing',
      'result_entered',
      'verification_pending',
    };
    final list = [for (final o in orders) o.data];
    int count(bool Function(DocData) f) => list.where(f).length;
    bool overdue(DocData o) {
      if (!open.contains(o['status'])) return false;
      final hours = [
        for (final i in (o['items'] as List))
          ((i as Map)['turnaroundHours'] as int?) ?? 0,
      ].fold<int>(0, (a, b) => a > b ? a : b);
      final created = o['createdAt'];
      return hours > 0 &&
          created is DateTime &&
          now.isAfter(created.add(Duration(hours: hours)));
    }

    return {
      'from': from,
      'to': to,
      'asOf': PortalLikeTime.iso(now),
      'ordersInPeriod': count((o) => inRange(o['createdAt'])),
      'pendingOrders': count(
        (o) => o['status'] == 'requested' || o['status'] == 'accepted',
      ),
      'samplesAwaitingCollection': smp
          .where((s) => s.data['status'] == 'pending')
          .length,
      'processing': count(
        (o) => o['status'] == 'processing' || o['status'] == 'sample_collected',
      ),
      'awaitingVerification': count(
        (o) => o['status'] == 'verification_pending',
      ),
      'publishedInPeriod': count((o) => inRange(o['publishedAt'])),
      'recollections': count((o) => o['status'] == 'recollection_required'),
      'rejectedSamplesInPeriod': smp
          .where(
            (s) =>
                s.data['status'] == 'rejected' && inRange(s.data['rejectedAt']),
          )
          .length,
      'urgentOpen': count(
        (o) => open.contains(o['status']) && o['priority'] != 'routine',
      ),
      'overdue': count(overdue),
      'byStatus': {
        for (final k in orderTransitions.keys)
          k: count((o) => o['status'] == k),
      },
      'truncated':
          orders.length >= reportScanCap || smp.length >= reportScanCap,
      'definitions': {
        'ordersInPeriod': 'Orders created in the period.',
        'pendingOrders': 'Orders waiting to be accepted or sampled, now.',
        'overdue':
            'Open orders older than the longest turnaround time of their tests.',
        'publishedInPeriod': 'Orders whose report was published in the period.',
      },
    };
  }
}

/// Small helpers kept next to the service that uses them.
abstract final class PortalLike {
  static Map<String, Object?> summary(DocData o) =>
      PortalSupport.pick(o, [
          'orderId',
          'orderNumber',
          'status',
          'priority',
          'createdAt',
          'reportId',
          'external',
          'patientId',
          'patientName',
          'patientMrn',
          'branchName',
          'doctorName',
          'source',
        ])
        ..['tests'] = [
          for (final i in (o['items'] as List? ?? const []))
            '${(i as Map)['name']}',
        ];
}

abstract final class PortalLikeTime {
  static String iso(DateTime d) => d.toUtc().toIso8601String();
}
