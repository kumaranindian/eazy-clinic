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

/// Staff profiles (non-doctor and doctor-linked roles are separate: doctors
/// have `doctors/{id}`). A staff profile becomes a login only through an
/// invitation (see InvitationService). Statuses: `inactive` (no seat, not yet
/// invited / deactivated), `invited`, `active`, `suspended`, and the derived
/// `invitation_expired`.
class StaffService {
  StaffService(this._d, this._branches);

  final ClinicDeps _d;
  final BranchService _branches;

  static const String collection = 'staff';
  static const Set<String> profileFields = {
    'fullName',
    'email',
    'phone',
    'designation',
    'department',
    'joiningDate',
  };
  static const Set<String> createFields = {
    ...profileFields,
    'role',
    'allBranches',
    'branchIds',
  };
  static const Set<String> seatHolding = {'invited', 'active', 'suspended'};

  FieldIssue _issue(String f, String c, String m) =>
      FieldIssue(field: f, code: c, message: m);

  static String emailKey(String email) =>
      email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

  // ---------------------------------------------------------------- parsing

  Map<String, Object?> _parseProfile(
    Map<String, Object?> body, {
    required bool partial,
    Set<String>? allowed,
  }) {
    final r = BodyReader(body, partial: partial)
      ..rejectUnknown(allowed ?? profileFields);
    final name = r.str('fullName', min: 2, max: 100);
    final email = r.email('email');
    final phone = r.phone('phone', required: false);
    final designation = r.str('designation', max: 80, required: false);
    final department = r.str('department', max: 80, required: false);
    final joining = r.str('joiningDate', max: 10, required: false);
    if (joining != null && !HoursParser.validDate(joining, minYear: 1980)) {
      r.addIssue('joiningDate', 'invalid_date', 'Use YYYY-MM-DD.');
    }
    r.throwIfInvalid();
    return {
      'fullName': ?name,
      if (name != null) 'fullNameLower': name.toLowerCase(),
      'email': ?email,
      'phone': ?phone,
      'designation': ?designation,
      'department': ?department,
      'joiningDate': ?joining,
    };
  }

  /// Validates role + branch scope against the caller's authority. Returns the
  /// normalised scope fields.
  Future<Map<String, Object?>> validateRoleAndScope(
    TenantContext t, {
    required Object? role,
    required Object? allBranches,
    required Object? branchIds,
    bool requireRole = true,
  }) async {
    final out = <String, Object?>{};
    if (role != null || requireRole) {
      final parsed = role is String ? ClinicRole.tryParse(role) : null;
      if (parsed == null || !ClinicRolePolicy.assignable.contains(parsed)) {
        throw ApiException.validation([
          _issue(
            'role',
            'invalid_value',
            'Choose one of: ${ClinicRolePolicy.assignable.map((e) => e.wireName).join(', ')}.',
          ),
        ]);
      }
      if (!ClinicRolePolicy.canGrant(t.role, parsed)) {
        throw const ApiException.forbidden(
          'You are not allowed to grant that role.',
        );
      }
      out['role'] = parsed.wireName;
    }
    if (allBranches != null || branchIds != null) {
      if (allBranches != null && allBranches is! bool) {
        throw ApiException.validation([
          _issue(
            'allBranches',
            'invalid_type',
            'allBranches must be true or false.',
          ),
        ]);
      }
      final all = allBranches == true;
      final ids = <String>[];
      if (branchIds != null) {
        if (branchIds is! List ||
            branchIds.length > 50 ||
            branchIds.any((e) => e is! String)) {
          throw ApiException.validation([
            _issue(
              'branchIds',
              'invalid_value',
              'Provide up to 50 branch ids.',
            ),
          ]);
        }
        ids.addAll(branchIds.cast<String>().toSet());
      }
      if (all) {
        if (!t.scope.allBranches) {
          throw const ApiException.forbidden(
            'Only users with access to all branches can grant all-branch access.',
          );
        }
        if (ids.isNotEmpty) {
          throw ApiException.validation([
            _issue(
              'branchIds',
              'conflict',
              'Do not send branchIds together with allBranches.',
            ),
          ]);
        }
      } else {
        if (ids.isEmpty) {
          throw ApiException.validation([
            _issue(
              'branchIds',
              'required',
              'Choose at least one branch, or grant all branches.',
            ),
          ]);
        }
        for (final b in ids) {
          t.scope.require(b);
          await _branches.requireActive(t, b);
        }
      }
      out['allBranches'] = all;
      out['branchIds'] = all ? <String>[] : ids;
    } else if (requireRole) {
      throw ApiException.validation([
        _issue(
          'branchIds',
          'required',
          'Choose at least one branch, or grant all branches.',
        ),
      ]);
    }
    return out;
  }

  // ----------------------------------------------------------------- access

  /// Whether the caller may act on this staff profile (branch scope + role
  /// authority). Throws 404 when it is outside the caller's scope.
  /// 404 unless the profile is inside the caller's branch scope.
  void scopeCheck(TenantContext t, Map<String, Object?> s) {
    final all = s['allBranches'] == true;
    final ids = ((s['branchIds'] as List?) ?? const []).cast<String>();
    final inScope = t.scope.allBranches || (!all && ids.any(t.scope.allows));
    if (!inScope) throw const ApiException.notFound('Staff member not found.');
  }

  /// 403 unless the caller may manage this person: not themselves, role
  /// authority, and a scoped manager only for people fully inside their scope.
  void manageCheck(TenantContext t, Map<String, Object?> s) {
    if (s['uid'] == t.uid) {
      throw const ApiException.forbidden('You cannot change your own access.');
    }
    final role = ClinicRole.tryParse('${s['role']}');
    if (role == null || !ClinicRolePolicy.canManageMember(t.role, role)) {
      throw const ApiException.forbidden(
        'You are not allowed to manage this member.',
      );
    }
    // a scoped manager can only manage people entirely inside their scope
    final all = s['allBranches'] == true;
    final ids = ((s['branchIds'] as List?) ?? const []).cast<String>();
    if (!t.scope.allBranches && (all || !t.scope.containsAll(ids))) {
      throw const ApiException.forbidden(
        'This member also works outside your branches.',
      );
    }
  }

  Future<Map<String, Object?>> load(TenantContext t, String id) async {
    final s = await _d.store.get(_d.path(t, collection, id));
    if (s == null) throw const ApiException.notFound('Staff member not found.');
    scopeCheck(t, s);
    return s;
  }

  // ----------------------------------------------------------------- create

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.staffCreate);
    final profile = _parseProfile(
      body,
      partial: false,
      allowed: {...createFields, 'invite'},
    );
    final scope = await validateRoleAndScope(
      t,
      role: body['role'],
      allBranches: body['allBranches'],
      branchIds: body['branchIds'],
    );
    final email = profile['email']! as String;
    if (await _d.store.get(_d.path(t, 'staff_emails', emailKey(email))) !=
        null) {
      throw const ApiException.conflict(
        'A staff member with this email already exists.',
      );
    }
    final id = 'stf_${newId(length: 12)}';
    final now = _d.now;
    final doc = <String, Object?>{
      'staffId': id,
      'tenantId': t.tenantId,
      ...profile,
      ...scope,
      'status': 'inactive',
      'uid': null,
      'seatSlot': null,
      'invitationId': null,
      'invitationExpiresAt': null,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
      'updatedBy': t.uid,
    };
    await _d.store.commit([
      CreateOp(_d.path(t, collection, id), doc),
      CreateOp(_d.path(t, 'staff_emails', emailKey(email)), {
        'staffId': id,
        'createdAt': now,
      }),
      _d.audit.op(
        AuditEntry(
          actor: _d.actorOf(t),
          action: 'staff.created',
          targetType: 'staff',
          targetId: id,
          tenantId: t.tenantId,
          requestId: requestId,
          after: {'role': scope['role']},
        ),
      ),
    ]);
    return present(doc);
  }

  // ----------------------------------------------------------------- update

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.staffUpdate);
    final head = await load(t, id);
    manageCheck(t, head);
    final preInvite = head['status'] == 'inactive' && head['uid'] == null;
    final allowed = {
      ...profileFields,
      if (preInvite) ...{'role', 'allBranches', 'branchIds'},
    };
    final profile = _parseProfile(body, partial: true, allowed: allowed);
    var scope = <String, Object?>{};
    if (preInvite &&
        (body.containsKey('role') ||
            body.containsKey('allBranches') ||
            body.containsKey('branchIds'))) {
      scope = await validateRoleAndScope(
        t,
        role: body['role'],
        allBranches: body['allBranches'],
        branchIds: body['branchIds'],
        requireRole: false,
      );
    }
    if (body.containsKey('email') && head['uid'] != null) {
      throw ApiException.validation([
        _issue(
          'email',
          'immutable',
          'The email of an activated account cannot be changed.',
        ),
      ]);
    }
    final changes = {...profile, ...scope};
    if (changes.isEmpty) {
      throw const ApiException.badRequest('No staff fields to update.');
    }
    final newEmail = profile['email'] as String?;
    final now = _d.now;
    return _d.store.transaction((tx) async {
      final cur = await tx.get(_d.path(t, collection, id));
      if (cur == null) {
        throw const ApiException.notFound('Staff member not found.');
      }
      final ops = <WriteOp>[];
      if (newEmail != null &&
          emailKey(newEmail) != emailKey('${cur['email']}')) {
        if (await tx.get(_d.path(t, 'staff_emails', emailKey(newEmail))) !=
            null) {
          throw const ApiException.conflict(
            'A staff member with this email already exists.',
          );
        }
        ops.addAll([
          CreateOp(_d.path(t, 'staff_emails', emailKey(newEmail)), {
            'staffId': id,
            'createdAt': now,
          }),
          DeleteOp(_d.path(t, 'staff_emails', emailKey('${cur['email']}'))),
        ]);
      }
      final patch = {...changes, 'updatedAt': now, 'updatedBy': t.uid};
      tx.write([
        UpdateOp(_d.path(t, collection, id), patch),
        ...ops,
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'staff.updated',
            targetType: 'staff',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {
              'fields': changes.keys
                  .where((k) => k != 'fullNameLower')
                  .toList(),
            },
          ),
        ),
      ]);
      return present({...cur, ...patch});
    });
  }

  // ------------------------------------------------------ status lifecycle

  /// activate / deactivate / suspend. The linked membership follows the
  /// profile in the same atomic commit; the Firebase account is never touched.
  Future<Map<String, Object?>> setStatus(
    TenantContext t,
    String id,
    String to, {
    String? requestId,
  }) async {
    t.require(switch (to) {
      'active' => ClinicPermission.staffActivate,
      _ => ClinicPermission.staffDeactivate,
    });
    final head = await load(t, id);
    manageCheck(t, head);
    final now = _d.now;
    Future<(Map<String, Object?>, List<WriteOp>)> build(
      TxContext tx,
      int? slot,
    ) async {
      final cur = await tx.get(_d.path(t, collection, id));
      if (cur == null) {
        throw const ApiException.notFound('Staff member not found.');
      }
      final from = '${cur['status']}';
      final allowed = switch (to) {
        'active' => from == 'inactive' || from == 'suspended',
        'inactive' => from == 'active' || from == 'suspended',
        'suspended' => from == 'active',
        _ => false,
      };
      if (!allowed) {
        throw ApiException.conflict('A $from staff member cannot become $to.');
      }
      final uid = cur['uid'] as String?;
      if (to == 'active' && uid == null) {
        throw const ApiException.conflict(
          'This person has not accepted an invitation yet. Send an invitation instead.',
        );
      }
      final holdsSeat = seatHolding.contains(from);
      final needsSeat = to != 'inactive' && !holdsSeat;
      final patch = <String, Object?>{
        'status': to,
        if (needsSeat) 'seatSlot': slot,
        if (to == 'inactive') 'seatSlot': null,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      final memberStatus = switch (to) {
        'active' => 'active',
        'suspended' => 'suspended',
        _ => 'deactivated',
      };
      return (
        present({...cur, ...patch}),
        [
          UpdateOp(_d.path(t, collection, id), patch),
          if (uid != null)
            UpdateOp(_d.path(t, 'members', uid), {
              'status': memberStatus,
              'updatedAt': now,
              'updatedBy': t.uid,
            }),
          if (to == 'inactive')
            ?_d.seats.release(t.tenantId, SeatKind.staff, cur['seatSlot']),
          _d.audit.op(
            AuditEntry(
              actor: _d.actorOf(t),
              action: 'staff.$to',
              targetType: 'staff',
              targetId: id,
              tenantId: t.tenantId,
              requestId: requestId,
              before: {'status': from},
              after: {'status': to},
            ),
          ),
        ],
      );
    }

    final needsClaim =
        to == 'active' && !seatHolding.contains('${head['status']}');
    if (needsClaim) {
      return _d.seats.withSeat(
        tenantId: t.tenantId,
        kind: SeatKind.staff,
        limit: t.entitlements.limits[LimitKey.maxStaff],
        entityId: id,
        build: build,
      );
    }
    return _d.store.transaction((tx) async {
      final (r, ops) = await build(tx, null);
      tx.write(ops);
      return r;
    });
  }

  // ------------------------------------------------------------------ reads

  Map<String, Object?> present(Map<String, Object?> s) {
    final m = (jsonSafe(s)! as Map<String, Object?>)
      ..remove('seatSlot')
      ..remove('fullNameLower');
    final exp = s['invitationExpiresAt'];
    if (m['status'] == 'invited' && exp is DateTime && !exp.isAfter(_d.now)) {
      m['status'] = 'invitation_expired';
    }
    return m;
  }

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.staffView);
    return present(await load(t, id));
  }

  Future<Paged> list(
    TenantContext t,
    Request request, {
    String? q,
    String? status,
    String? role,
    String? branchId,
  }) async {
    t.require(ClinicPermission.staffView);
    final query = q?.trim().toLowerCase();
    if (status != null &&
        !const {
          'inactive',
          'invited',
          'active',
          'suspended',
        }.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (role != null && ClinicRole.tryParse(role) == null) {
      throw const ApiException.badRequest('role has an unsupported value.');
    }
    if (branchId != null) t.scope.require(branchId);
    if (t.scope.allBranches && branchId == null) {
      return runPaged(
        _d.store,
        DocQuery(
          _d.path(t, collection),
          filters: [
            if (status != null) QueryFilter('status', FilterOp.eq, status),
            if (role != null) QueryFilter('role', FilterOp.eq, role),
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
    final branches = branchId != null
        ? [branchId]
        : t.scope.branchIds.take(50).toList();
    final seen = <String, StoredDoc>{};
    for (final b in branches) {
      final rows = await _d.store.query(
        DocQuery(
          _d.path(t, collection),
          filters: [QueryFilter('branchIds', FilterOp.arrayContains, b)],
          limit: 200,
        ),
      );
      for (final r in rows) {
        seen[r.id] = r;
      }
    }
    if (branchId != null && t.scope.allBranches) {
      for (final r in await _d.store.query(
        DocQuery(
          _d.path(t, collection),
          filters: const [QueryFilter('allBranches', FilterOp.eq, true)],
          limit: 200,
        ),
      )) {
        seen[r.id] = r;
      }
    }
    final docs =
        seen.values.where((d) {
          final s = d.data;
          if (status != null && s['status'] != status) return false;
          if (role != null && s['role'] != role) return false;
          if (query != null &&
              query.isNotEmpty &&
              !'${s['fullNameLower']}'.startsWith(query)) {
            return false;
          }
          return true;
        }).toList()..sort(
          (a, b) => '${a.data['fullNameLower']}'.compareTo(
            '${b.data['fullNameLower']}',
          ),
        );
    return Paged(docs, const PageMeta(limit: 200, hasMore: false));
  }
}
