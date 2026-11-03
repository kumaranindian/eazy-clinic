import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/ids.dart';
import '../../platform/audit/audit_service.dart';
import '../../platform/common/body_reader.dart';
import '../../platform/common/paging.dart';
import '../branches/branch_service.dart';
import '../common/clinic_deps.dart';
import '../common/seat_service.dart';
import '../common/tenant_context.dart';
import '../settings/operating_hours.dart';

const List<String> genders = ['male', 'female', 'other', 'undisclosed'];

/// Doctor professional profiles and their branch assignments.
///
/// One profile per doctor (`doctors/{id}`); where they work is modelled by
/// `doctor_branch_assignments`, never by copying the profile. A profile can
/// exist without a login; the login is linked only through an invitation
/// (see InvitationService).
class DoctorService {
  DoctorService(this._d, this._branches);

  final ClinicDeps _d;
  final BranchService _branches;

  static const String collection = 'doctors';
  static const String assignments = 'doctor_branch_assignments';

  static const Set<String> fields = {
    'fullName',
    'gender',
    'dateOfBirth',
    'email',
    'phone',
    'designation',
    'qualifications',
    'registrationNumber',
    'registrationCouncil',
    'specialty',
    'subSpecialty',
    'yearsOfExperience',
    'languages',
    'consultationFeeMinor',
    'biography',
  };

  FieldIssue _issue(String f, String c, String m) =>
      FieldIssue(field: f, code: c, message: m);

  static String regKey(String registrationNumber) =>
      registrationNumber.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<bool> _registrationRequired(TenantContext t) async {
    final s = await _d.store.get(_d.path(t, 'clinic_settings', 'operations'));
    return s?['doctorRegistrationRequired'] as bool? ?? true;
  }

  Map<String, Object?> _parse(
    Map<String, Object?> body, {
    required bool partial,
    required bool regRequired,
  }) {
    final r = BodyReader(body, partial: partial)
      ..rejectUnknown({...fields, if (!partial) 'branchIds'});
    final name = r.str('fullName', min: 2, max: 100);
    final gender = r.str('gender', max: 12, required: false);
    if (gender != null && !genders.contains(gender)) {
      r.addIssue(
        'gender',
        'invalid_value',
        'gender must be one of: ${genders.join(', ')}.',
      );
    }
    final dob = r.str('dateOfBirth', max: 10, required: false);
    if (dob != null &&
        (!HoursParser.validDate(
              dob,
              minYear: 1900,
              maxYear: DateTime.now().year,
            ) ||
            dob.compareTo(DateTime.now().toIso8601String().substring(0, 10)) >
                0)) {
      r.addIssue('dateOfBirth', 'invalid_date', 'Use YYYY-MM-DD.');
    }
    final email = r.email('email', required: false);
    final phone = r.phone('phone', required: false);
    final designation = r.str('designation', max: 80, required: false);
    List<String>? list(String f, int maxItems, int maxLen) {
      if (!body.containsKey(f)) return null;
      final raw = body[f];
      if (raw is! List ||
          raw.length > maxItems ||
          raw.any(
            (e) => e is! String || e.trim().isEmpty || e.length > maxLen,
          )) {
        r.addIssue(
          f,
          'invalid_value',
          'Up to $maxItems entries of 1-$maxLen characters.',
        );
        return null;
      }
      return raw.map((e) => (e as String).trim()).toList();
    }

    final qualifications = list('qualifications', 10, 80);
    final languages = list('languages', 10, 40);
    var reg = r.str(
      'registrationNumber',
      min: 3,
      max: 30,
      required: regRequired && !partial,
    );
    if (reg != null && !RegExp(r'^[A-Za-z0-9/\-. ]{3,30}$').hasMatch(reg)) {
      r.addIssue(
        'registrationNumber',
        'invalid_format',
        'Use letters, digits, / - . and spaces.',
      );
      reg = null;
    }
    final council = r.str('registrationCouncil', max: 80, required: false);
    final specialty = r.str('specialty', max: 60, required: false);
    final sub = r.str('subSpecialty', max: 60, required: false);
    final years = r.integer(
      'yearsOfExperience',
      min: 0,
      max: 70,
      required: false,
    );
    final fee = r.integer(
      'consultationFeeMinor',
      min: 0,
      max: 10000000,
      required: false,
    );
    final bio = r.str('biography', min: 0, max: 1000, required: false);
    r.throwIfInvalid();
    return {
      'fullName': ?name,
      if (name != null) 'fullNameLower': name.toLowerCase(),
      'gender': ?gender,
      'dateOfBirth': ?dob,
      'email': ?email,
      'phone': ?phone,
      'designation': ?designation,
      'qualifications': ?qualifications,
      'registrationNumber': ?reg,
      'registrationCouncil': ?council,
      'specialty': ?specialty,
      'subSpecialty': ?sub,
      'yearsOfExperience': ?years,
      'languages': ?languages,
      'consultationFeeMinor': ?fee,
      'biography': ?bio,
    };
  }

  // ----------------------------------------------------------- visibility

  Future<List<Map<String, Object?>>> _activeAssignments(
    TenantContext t,
    String doctorId,
  ) async => (await _d.store.query(
    DocQuery(
      _d.path(t, assignments),
      filters: [
        QueryFilter('doctorId', FilterOp.eq, doctorId),
        const QueryFilter('status', FilterOp.eq, 'active'),
      ],
      limit: 100,
    ),
  )).map((e) => e.data).toList();

  /// Loads a doctor the caller may see. All-branch callers see every doctor;
  /// scoped callers only doctors assigned to at least one of their branches.
  /// Anything else answers 404.
  Future<Map<String, Object?>> loadVisible(
    TenantContext t,
    String doctorId,
  ) async {
    final doc = await _d.store.get(_d.path(t, collection, doctorId));
    if (doc == null) throw const ApiException.notFound('Doctor not found.');
    if (!t.scope.allBranches) {
      final a = await _activeAssignments(t, doctorId);
      if (!a.any((x) => t.scope.allows(x['branchId']! as String))) {
        throw const ApiException.notFound('Doctor not found.');
      }
    }
    return doc;
  }

  // ----------------------------------------------------------------- create

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.doctorsCreate);
    final input = _parse(
      body,
      partial: false,
      regRequired: await _registrationRequired(t),
    );
    final branchIds = ((body['branchIds'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
    if (body['branchIds'] != null &&
        (body['branchIds'] is! List || branchIds.length > 20)) {
      throw ApiException.validation([
        _issue('branchIds', 'invalid_value', 'Provide up to 20 branch ids.'),
      ]);
    }
    if (!t.scope.allBranches && branchIds.isEmpty) {
      throw ApiException.validation([
        _issue(
          'branchIds',
          'required',
          'Choose at least one of your branches.',
        ),
      ]);
    }
    for (final b in branchIds) {
      t.scope.require(b); // 404 for branches outside the caller's scope
      await _branches.requireActive(t, b);
    }
    if (branchIds.isNotEmpty) t.require(ClinicPermission.doctorsAssignBranch);
    final reg = input['registrationNumber'] as String?;
    if (reg != null &&
        await _d.store.get(_d.path(t, 'doctor_regs', regKey(reg))) != null) {
      throw const ApiException.conflict(
        'A doctor with this registration number already exists.',
      );
    }
    final id = 'doc_${newId(length: 12)}';
    final now = _d.now;
    final doc = <String, Object?>{
      'doctorId': id,
      'tenantId': t.tenantId,
      ...input,
      'status': 'active',
      'uid': null,
      'accountStatus': 'none',
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
      'updatedBy': t.uid,
    };
    return _d.seats.withSeat(
      tenantId: t.tenantId,
      kind: SeatKind.doctors,
      limit: t.entitlements.limits[LimitKey.maxDoctors],
      entityId: id,
      build: (tx, slot) async => (
        present(t, doc),
        [
          CreateOp(_d.path(t, collection, id), {...doc, 'seatSlot': slot}),
          if (reg != null)
            CreateOp(_d.path(t, 'doctor_regs', regKey(reg)), {
              'doctorId': id,
              'createdAt': now,
            }),
          for (final b in branchIds)
            ..._assignOps(t, id, b, now: now, fee: null, from: null, to: null),
          _d.audit.op(
            AuditEntry(
              actor: _d.actorOf(t),
              action: 'doctor.created',
              targetType: 'doctor',
              targetId: id,
              tenantId: t.tenantId,
              requestId: requestId,
              after: {'branches': branchIds.length},
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- update

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.doctorsUpdate);
    final input = _parse(body, partial: true, regRequired: false);
    if (input.isEmpty) {
      throw const ApiException.badRequest('No doctor fields to update.');
    }
    await loadVisible(t, id);
    final newReg = input['registrationNumber'] as String?;
    final now = _d.now;
    return _d.store.transaction((tx) async {
      final cur = await tx.get(_d.path(t, collection, id));
      if (cur == null) throw const ApiException.notFound('Doctor not found.');
      final ops = <WriteOp>[];
      if (newReg != null &&
          regKey(newReg) != regKey('${cur['registrationNumber'] ?? ''}')) {
        final taken = await tx.get(_d.path(t, 'doctor_regs', regKey(newReg)));
        if (taken != null) {
          throw const ApiException.conflict(
            'A doctor with this registration number already exists.',
          );
        }
        ops.add(
          CreateOp(_d.path(t, 'doctor_regs', regKey(newReg)), {
            'doctorId': id,
            'createdAt': now,
          }),
        );
        final old = cur['registrationNumber'] as String?;
        if (old != null && old.isNotEmpty) {
          ops.add(DeleteOp(_d.path(t, 'doctor_regs', regKey(old))));
        }
      }
      final patch = {...input, 'updatedAt': now, 'updatedBy': t.uid};
      tx.write([
        UpdateOp(_d.path(t, collection, id), patch),
        ...ops,
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'doctor.updated',
            targetType: 'doctor',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {
              'fields': input.keys.where((k) => k != 'fullNameLower').toList(),
            },
          ),
        ),
      ]);
      return present(t, {...cur, ...patch});
    });
  }

  // ------------------------------------------------------------ activation

  Future<Map<String, Object?>> setActive(
    TenantContext t,
    String id, {
    required bool active,
    String? requestId,
  }) async {
    t.require(ClinicPermission.doctorsActivate);
    await loadVisible(t, id);
    final now = _d.now;
    Future<(Map<String, Object?>, List<WriteOp>)> build(
      TxContext tx,
      int? slot,
    ) async {
      final cur = await tx.get(_d.path(t, collection, id));
      if (cur == null) throw const ApiException.notFound('Doctor not found.');
      final want = active ? 'inactive' : 'active';
      if (cur['status'] != want) {
        throw ApiException.conflict(
          'Doctor is already ${active ? 'active' : 'inactive'}.',
        );
      }
      final patch = {
        'status': active ? 'active' : 'inactive',
        'seatSlot': active ? slot : null,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      final release = active
          ? null
          : _d.seats.release(t.tenantId, SeatKind.doctors, cur['seatSlot']);
      return (
        present(t, {...cur, ...patch}),
        [
          UpdateOp(_d.path(t, collection, id), patch),
          ?release,
          _d.audit.op(
            AuditEntry(
              actor: _d.actorOf(t),
              action: active ? 'doctor.activated' : 'doctor.deactivated',
              targetType: 'doctor',
              targetId: id,
              tenantId: t.tenantId,
              requestId: requestId,
              before: {'status': want},
              after: {'status': patch['status']},
            ),
          ),
        ],
      );
    }

    if (active) {
      return _d.seats.withSeat(
        tenantId: t.tenantId,
        kind: SeatKind.doctors,
        limit: t.entitlements.limits[LimitKey.maxDoctors],
        entityId: id,
        build: build,
      );
    }
    return _d.store.transaction((tx) async {
      final (result, ops) = await build(tx, null);
      tx.write(ops);
      return result;
    });
  }

  // ------------------------------------------------------------ assignments

  List<WriteOp> _assignOps(
    TenantContext t,
    String doctorId,
    String branchId, {
    required DateTime now,
    required int? fee,
    required String? from,
    required String? to,
  }) {
    final id = 'asg_${newId(length: 12)}';
    return [
      CreateOp(_d.path(t, assignments, id), {
        'assignmentId': id,
        'tenantId': t.tenantId,
        'doctorId': doctorId,
        'branchId': branchId,
        'status': 'active',
        'consultationFeeMinor': fee,
        'effectiveFrom': from ?? now.toIso8601String().substring(0, 10),
        'effectiveTo': to,
        'createdAt': now,
        'createdBy': t.uid,
      }),
      // uniqueness key: only one active assignment per doctor+branch
      CreateOp(_d.path(t, 'doctor_branch_active', '${doctorId}_$branchId'), {
        'assignmentId': id,
        'createdAt': now,
      }),
    ];
  }

  Future<Map<String, Object?>> assign(
    TenantContext t,
    String doctorId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.doctorsAssignBranch);
    final r = BodyReader(body)
      ..rejectUnknown({
        'branchId',
        'consultationFeeMinor',
        'effectiveFrom',
        'effectiveTo',
      });
    final branchId = r.str('branchId', min: 3, max: 64);
    final fee = r.integer(
      'consultationFeeMinor',
      min: 0,
      max: 10000000,
      required: false,
    );
    final from = r.str('effectiveFrom', max: 10, required: false);
    final to = r.str('effectiveTo', max: 10, required: false);
    if (from != null && !HoursParser.validDate(from)) {
      r.addIssue('effectiveFrom', 'invalid_date', 'Use YYYY-MM-DD.');
    }
    if (to != null && !HoursParser.validDate(to)) {
      r.addIssue('effectiveTo', 'invalid_date', 'Use YYYY-MM-DD.');
    }
    if (from != null && to != null && to.compareTo(from) < 0) {
      r.addIssue(
        'effectiveTo',
        'invalid_period',
        'effectiveTo must not be before effectiveFrom.',
      );
    }
    r.throwIfInvalid();
    t.scope.require(branchId!);
    await _branches.requireActive(t, branchId);
    final doc = await _visibleForAssign(t, doctorId);
    if (doc['status'] != 'active') {
      throw const ApiException.conflict(
        'Only an active doctor can be assigned.',
      );
    }
    final now = _d.now;
    final ops = _assignOps(
      t,
      doctorId,
      branchId,
      now: now,
      fee: fee,
      from: from,
      to: to,
    );
    try {
      await _d.store.transaction((tx) async {
        // keep the linked login's branch scope in step with the assignments
        final extra = <WriteOp>[];
        final uid = doc['uid'] as String?;
        if (uid != null) {
          final m = await tx.get(_d.path(t, 'members', uid));
          if (m != null) {
            final ids = {
              ...((m['branchIds'] as List?) ?? const []).cast<String>(),
              branchId,
            };
            extra.add(
              UpdateOp(_d.path(t, 'members', uid), {
                'branchIds': ids.toList(),
                'updatedAt': now,
              }),
            );
          }
        }
        tx.write([
          ...ops,
          ...extra,
          _d.audit.op(
            AuditEntry(
              actor: _d.actorOf(t),
              action: 'doctor.branch_assigned',
              targetType: 'doctor',
              targetId: doctorId,
              tenantId: t.tenantId,
              requestId: requestId,
              after: {'branchId': branchId},
            ),
          ),
        ]);
      });
    } on AlreadyExistsException {
      throw const ApiException.conflict(
        'The doctor is already assigned to this branch.',
      );
    }
    return jsonSafe((ops.first as CreateOp).data)! as Map<String, Object?>;
  }

  /// For assignment the caller needs the doctor to exist; a scoped caller may
  /// assign an unassigned doctor created by them or visible to them.
  Future<Map<String, Object?>> _visibleForAssign(
    TenantContext t,
    String doctorId,
  ) async {
    final doc = await _d.store.get(_d.path(t, collection, doctorId));
    if (doc == null) throw const ApiException.notFound('Doctor not found.');
    if (!t.scope.allBranches) {
      final a = await _activeAssignments(t, doctorId);
      final unassigned = a.isEmpty;
      if (!unassigned &&
          !a.any((x) => t.scope.allows(x['branchId']! as String))) {
        throw const ApiException.notFound('Doctor not found.');
      }
      if (unassigned && doc['createdBy'] != t.uid) {
        throw const ApiException.notFound('Doctor not found.');
      }
    }
    return doc;
  }

  Future<void> unassign(
    TenantContext t,
    String doctorId,
    String branchId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.doctorsAssignBranch);
    t.scope.require(branchId);
    await loadVisible(t, doctorId);
    final now = _d.now;
    await _d.store.transaction((tx) async {
      final key = await tx.get(
        _d.path(t, 'doctor_branch_active', '${doctorId}_$branchId'),
      );
      if (key == null) {
        throw const ApiException.notFound('Assignment not found.');
      }
      final aid = key['assignmentId']! as String;
      final doctor = await tx.get(_d.path(t, collection, doctorId));
      final uid = doctor?['uid'] as String?;
      final member = uid == null
          ? null
          : await tx.get(_d.path(t, 'members', uid));
      tx.write([
        if (member != null)
          UpdateOp(_d.path(t, 'members', uid!), {
            'branchIds': [
              for (final b
                  in ((member['branchIds'] as List?) ?? const [])
                      .cast<String>())
                if (b != branchId) b,
            ],
            'updatedAt': now,
          }),
        UpdateOp(_d.path(t, assignments, aid), {
          'status': 'ended',
          'endedAt': now,
          'endedBy': t.uid,
        }),
        DeleteOp(_d.path(t, 'doctor_branch_active', '${doctorId}_$branchId')),
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'doctor.branch_unassigned',
            targetType: 'doctor',
            targetId: doctorId,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {'branchId': branchId},
          ),
        ),
      ]);
    });
  }

  Future<List<Map<String, Object?>>> listAssignments(
    TenantContext t,
    String doctorId, {
    String? status,
  }) async {
    t.require(ClinicPermission.doctorsView);
    await loadVisible(t, doctorId);
    final rows = await _d.store.query(
      DocQuery(
        _d.path(t, assignments),
        filters: [
          QueryFilter('doctorId', FilterOp.eq, doctorId),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
        ],
        limit: 200,
      ),
    );
    final out = <Map<String, Object?>>[];
    for (final a in rows) {
      final branchId = a.data['branchId']! as String;
      if (!t.scope.allows(branchId)) {
        continue; // never reveal out-of-scope branches
      }
      final b = await _branches.find(t, branchId);
      out.add({
        ...jsonSafe(a.data)! as Map<String, Object?>,
        'branchName': b?['name'],
      });
    }
    out.sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    return out;
  }

  // ------------------------------------------------------------------ reads

  Map<String, Object?> present(TenantContext t, Map<String, Object?> d) {
    final m = (jsonSafe(d)! as Map<String, Object?>)
      ..remove('seatSlot')
      ..remove('fullNameLower');
    // date of birth is personal data: only people who maintain profiles see it
    if (!t.can(ClinicPermission.doctorsUpdate)) m.remove('dateOfBirth');
    return m;
  }

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.doctorsView);
    final doc = await loadVisible(t, id);
    return {
      ...present(t, doc),
      'branches': await listAssignments(t, id, status: 'active'),
    };
  }

  Future<Paged> list(
    TenantContext t,
    Request request, {
    String? q,
    String? status,
    String? specialty,
    String? branchId,
  }) async {
    t.require(ClinicPermission.doctorsView);
    final query = q?.trim().toLowerCase();
    if (status != null && status != 'active' && status != 'inactive') {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (branchId != null) t.scope.require(branchId);
    if (t.scope.allBranches && branchId == null) {
      return runPaged(
        _d.store,
        DocQuery(
          _d.path(t, collection),
          filters: [
            if (status != null) QueryFilter('status', FilterOp.eq, status),
            if (specialty != null)
              QueryFilter('specialty', FilterOp.eq, specialty),
            if (query != null && query.isNotEmpty) ...[
              QueryFilter('fullNameLower', FilterOp.gte, query),
              QueryFilter('fullNameLower', FilterOp.lt, '$query'),
            ],
          ],
          orderBy: const OrderBy('fullNameLower'),
        ),
        request,
      );
    }
    // branch-scoped listing: doctors actively assigned to the (allowed) branches
    final branches = branchId != null
        ? [branchId]
        : t.scope.branchIds.take(50).toList();
    final ids = <String>{};
    for (final b in branches) {
      final rows = await _d.store.query(
        DocQuery(
          _d.path(t, assignments),
          filters: [
            QueryFilter('branchId', FilterOp.eq, b),
            const QueryFilter('status', FilterOp.eq, 'active'),
          ],
          limit: 200,
        ),
      );
      ids.addAll(rows.map((r) => r.data['doctorId']! as String));
    }
    final docs = <StoredDoc>[];
    for (final id in ids) {
      final d = await _d.store.get(_d.path(t, collection, id));
      if (d == null) continue;
      if (status != null && d['status'] != status) continue;
      if (specialty != null && d['specialty'] != specialty) continue;
      if (query != null &&
          query.isNotEmpty &&
          !'${d['fullNameLower']}'.startsWith(query)) {
        continue;
      }
      docs.add(StoredDoc(_d.path(t, collection, id), d));
    }
    docs.sort(
      (a, b) =>
          '${a.data['fullNameLower']}'.compareTo('${b.data['fullNameLower']}'),
    );
    return Paged(docs, const PageMeta(limit: 200, hasMore: false));
  }
}
