import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/audit/audit_service.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'scheduling_support.dart';

/// Tenant-specific appointment types (duration, buffer, optional fee).
class AppointmentTypeService {
  AppointmentTypeService(this._s);

  final SchedulingSupport _s;

  static const String collection = 'appointment_types';

  static String _key(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Map<String, Object?> _parse(
    Map<String, Object?> body, {
    required bool partial,
  }) {
    final r = BodyReader(body, partial: partial)
      ..rejectUnknown({
        'name',
        'description',
        'durationMinutes',
        'bufferMinutes',
        'defaultFeeMinor',
        'specialities',
      });
    final name = r.str('name', min: 2, max: 60);
    final description = r.str('description', max: 300, required: false);
    final duration = r.integer('durationMinutes', min: 5, max: 240);
    final buffer = r.integer(
      'bufferMinutes',
      min: 0,
      max: 120,
      required: false,
    );
    final fee = r.integer(
      'defaultFeeMinor',
      min: 0,
      max: 100000000,
      required: false,
    );
    List<String>? specialities;
    if (r.has('specialities')) {
      final raw = r.body['specialities'];
      if (raw is! List ||
          raw.length > 10 ||
          raw.any(
            (e) => e is! String || e.trim().length < 2 || e.length > 40,
          )) {
        r.addIssue(
          'specialities',
          'invalid_value',
          'Give up to 10 speciality names (2-40 characters).',
        );
      } else {
        specialities = raw.map((e) => (e as String).trim()).toSet().toList();
      }
    }
    r.throwIfInvalid();
    return {
      'name': ?name,
      'description': ?description,
      'durationMinutes': ?duration,
      'bufferMinutes': ?buffer,
      'defaultFeeMinor': ?fee,
      'specialities': ?specialities,
    };
  }

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.appointmentTypesManage);
    _s.requireFeature(t);
    final input = _parse(body, partial: false);
    final name = input['name']! as String;
    final id = 'aty_${newId(length: 12)}';
    final now = _s.d.now;
    final doc = <String, Object?>{
      'typeId': id,
      'tenantId': t.tenantId,
      'bufferMinutes': 0,
      'specialities': <String>[],
      ...input,
      'status': 'active',
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
    };
    try {
      await _s.d.store.commit([
        CreateOp(_s.d.path(t, 'appointment_type_names', _key(name)), {
          'typeId': id,
        }),
        CreateOp(_s.d.path(t, collection, id), doc),
        _s.d.audit.op(
          AuditEntry(
            actor: _s.d.actorOf(t),
            action: 'appointment_type.created',
            targetType: 'appointment_type',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {'name': name},
          ),
        ),
      ]);
    } on AlreadyExistsException {
      throw const ApiException.conflict(
        'An appointment type with this name already exists.',
      );
    }
    return present(doc);
  }

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.appointmentTypesManage);
    final input = _parse(body, partial: true);
    if (input.isEmpty) {
      throw const ApiException.badRequest('No fields to update.');
    }
    final now = _s.d.now;
    try {
      return await _s.d.store.transaction((tx) async {
        final path = _s.d.path(t, collection, id);
        final cur = await tx.get(path);
        if (cur == null) {
          throw const ApiException.notFound('Appointment type not found.');
        }
        final ops = <WriteOp>[];
        final newName = input['name'] as String?;
        if (newName != null && _key(newName) != _key('${cur['name']}')) {
          ops
            ..add(
              CreateOp(_s.d.path(t, 'appointment_type_names', _key(newName)), {
                'typeId': id,
              }),
            )
            ..add(
              DeleteOp(
                _s.d.path(t, 'appointment_type_names', _key('${cur['name']}')),
              ),
            );
        }
        tx.write([
          UpdateOp(path, {...input, 'updatedAt': now}),
          ...ops,
          _s.d.audit.op(
            AuditEntry(
              actor: _s.d.actorOf(t),
              action: 'appointment_type.updated',
              targetType: 'appointment_type',
              targetId: id,
              tenantId: t.tenantId,
              requestId: requestId,
              after: {'fields': input.keys.toList()},
            ),
          ),
        ]);
        return present({...cur, ...input});
      });
    } on AlreadyExistsException {
      throw const ApiException.conflict(
        'An appointment type with this name already exists.',
      );
    }
  }

  Future<Map<String, Object?>> setStatus(
    TenantContext t,
    String id,
    String status, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.appointmentTypesManage);
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, collection, id);
      final cur = await tx.get(path);
      if (cur == null) {
        throw const ApiException.notFound('Appointment type not found.');
      }
      if (cur['status'] == status) {
        throw ApiException.conflict('The type is already $status.');
      }
      tx.write([
        UpdateOp(path, {'status': status, 'updatedAt': now}),
        _s.d.audit.op(
          AuditEntry(
            actor: _s.d.actorOf(t),
            action: 'appointment_type.$status',
            targetType: 'appointment_type',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
          ),
        ),
      ]);
      return present({...cur, 'status': status});
    });
  }

  Future<Paged> list(TenantContext t, Request req, {String? status}) async {
    t.require(ClinicPermission.appointmentTypesView);
    if (status != null && status != 'active' && status != 'inactive') {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, collection),
        filters: [
          if (status != null) QueryFilter('status', FilterOp.eq, status),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
  }

  /// An active type of this tenant (409 when inactive, 404 when unknown).
  Future<DocData> activeType(TenantContext t, String id) async {
    final d = await _s.d.store.get(_s.d.path(t, collection, id));
    if (d == null) {
      throw const ApiException.notFound('Appointment type not found.');
    }
    if (d['status'] != 'active') {
      throw const ApiException.conflict('This appointment type is not active.');
    }
    return d;
  }

  static Map<String, Object?> present(Map<String, Object?> d) =>
      jsonSafe(d)! as Map<String, Object?>;
}
