import 'dart:convert';
import 'dart:math';

import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/ids.dart';
import '../../auth/domain/auth_context.dart';
import '../../platform/audit/audit_service.dart';
import '../../platform/common/paging.dart';
import '../common/clinic_deps.dart';
import '../common/seat_service.dart';
import '../common/tenant_context.dart';
import '../doctors/doctor_service.dart';
import '../staff/staff_service.dart';

final Random _secure = Random.secure();

/// 256-bit random invitation secret (`ecinv_…`). Only its SHA-256 hash is ever
/// stored; the raw value is shown once to the administrator who created it.
String newInvitationToken() =>
    'ecinv_${base64Url.encode(List<int>.generate(32, (_) => _secure.nextInt(256))).replaceAll('=', '')}';

String hashInvitationToken(String token) =>
    sha256.convert(utf8.encode(token)).toString();

const Duration invitationTtl = Duration(days: 7);

/// Single message for every acceptance failure so a caller learns nothing
/// about which part was wrong (expired, revoked, replayed, wrong person).
const ApiException _invalidInvitation = ApiException.badRequest(
  'This invitation is invalid or has expired.',
);

/// Invitation lifecycle for staff logins and doctor-account association.
///
/// Delivery (e-mail / SMS) is **not configured** in Phase 3: the administrator
/// receives the one-time token in the response and shares it themselves; the
/// API reports `delivery.status = "not_configured"` and never claims a message
/// was sent.
class InvitationService {
  InvitationService(this._d, this._staff, this._doctors);

  final ClinicDeps _d;
  final StaffService _staff;
  final DoctorService _doctors;

  static const String collection = 'invitations';
  static const Map<String, Object?> delivery = {
    'status': 'not_configured',
    'note':
        'No e-mail/SMS provider is configured. Share the invitation link with the invitee yourself.',
  };

  Map<String, Object?> _withSecret(Map<String, Object?> inv, String token) => {
    ...present(inv),
    'inviteToken': token,
    'acceptPath': '/accept-invitation?token=$token',
    'delivery': delivery,
  };

  // ---------------------------------------------------------------- staff

  Future<Map<String, Object?>> createForStaff(
    TenantContext t,
    String staffId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.staffInvite);
    final head = await _staff.load(t, staffId);
    _staff.manageCheck(t, head);
    final role = ClinicRole.tryParse('${head['role']}')!;
    if (!ClinicRolePolicy.canGrant(t.role, role)) {
      throw const ApiException.forbidden(
        'You are not allowed to grant that role.',
      );
    }
    final invId = 'inv_${newId(length: 12)}';
    final token = newInvitationToken();
    final now = _d.now;
    return _d.seats.withSeat(
      tenantId: t.tenantId,
      kind: SeatKind.staff,
      limit: t.entitlements.limits[LimitKey.maxStaff],
      entityId: staffId,
      build: (tx, slot) async {
        final cur = await tx.get(_d.path(t, 'staff', staffId));
        if (cur == null)
          throw const ApiException.notFound('Staff member not found.');
        if (cur['uid'] != null)
          throw const ApiException.conflict(
            'This person already has an account in this clinic.',
          );
        if (cur['status'] != 'inactive') {
          throw const ApiException.conflict(
            'An invitation already exists. Resend or revoke it instead.',
          );
        }
        final inv = <String, Object?>{
          'invitationId': invId,
          'tenantId': t.tenantId,
          'kind': 'staff',
          'subjectId': staffId,
          'email': '${cur['email']}'.toLowerCase(),
          'role': cur['role'],
          'allBranches': cur['allBranches'] == true,
          'branchIds': cur['branchIds'] ?? <String>[],
          'tokenHash': hashInvitationToken(token),
          'status': 'pending',
          'expiresAt': now.add(invitationTtl),
          'resendCount': 0,
          'createdAt': now,
          'createdBy': t.uid,
        };
        return (
          _withSecret(inv, token),
          [
            CreateOp(_d.path(t, collection, invId), inv),
            UpdateOp(_d.path(t, 'staff', staffId), {
              'status': 'invited',
              'seatSlot': slot,
              'invitationId': invId,
              'invitationExpiresAt': inv['expiresAt'],
              'updatedAt': now,
              'updatedBy': t.uid,
            }),
            _d.audit.op(
              AuditEntry(
                actor: _d.actorOf(t),
                action: 'invitation.created',
                targetType: 'invitation',
                targetId: invId,
                tenantId: t.tenantId,
                requestId: requestId,
                after: {'kind': 'staff', 'role': cur['role']},
              ),
            ),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------- doctor

  Future<Map<String, Object?>> createForDoctor(
    TenantContext t,
    String doctorId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.staffInvite);
    t.require(ClinicPermission.doctorsUpdate);
    if (!ClinicRolePolicy.canGrant(t.role, ClinicRole.doctor)) {
      throw const ApiException.forbidden(
        'You are not allowed to grant that role.',
      );
    }
    await _doctors.loadVisible(t, doctorId);
    final invId = 'inv_${newId(length: 12)}';
    final token = newInvitationToken();
    final now = _d.now;
    return _d.store.transaction((tx) async {
      final doc = await tx.get(_d.path(t, 'doctors', doctorId));
      if (doc == null) throw const ApiException.notFound('Doctor not found.');
      if (doc['status'] != 'active')
        throw const ApiException.conflict(
          'Only an active doctor can be invited.',
        );
      if (doc['uid'] != null)
        throw const ApiException.conflict(
          'This doctor already has a linked account.',
        );
      if (doc['accountStatus'] == 'invited') {
        throw const ApiException.conflict(
          'An invitation already exists. Resend or revoke it instead.',
        );
      }
      // The invitation goes to the e-mail on the profile only; an admin cannot
      // aim it at a different address, so they cannot capture someone else's
      // account.
      final email = '${doc['email'] ?? ''}'.toLowerCase();
      if (email.isEmpty)
        throw const ApiException.conflict(
          'Add an email address to the doctor profile first.',
        );
      final assigned = await tx.query(
        DocQuery(
          _d.path(t, DoctorService.assignments),
          filters: [
            QueryFilter('doctorId', FilterOp.eq, doctorId),
            const QueryFilter('status', FilterOp.eq, 'active'),
          ],
          limit: 100,
        ),
      );
      if (assigned.isEmpty)
        throw const ApiException.conflict(
          'Assign the doctor to at least one branch first.',
        );
      final inv = <String, Object?>{
        'invitationId': invId,
        'tenantId': t.tenantId,
        'kind': 'doctor',
        'subjectId': doctorId,
        'email': email,
        'role': ClinicRole.doctor.wireName,
        'allBranches': false,
        'branchIds': [for (final a in assigned) a.data['branchId']],
        'tokenHash': hashInvitationToken(token),
        'status': 'pending',
        'expiresAt': now.add(invitationTtl),
        'resendCount': 0,
        'createdAt': now,
        'createdBy': t.uid,
      };
      tx.write([
        CreateOp(_d.path(t, collection, invId), inv),
        UpdateOp(_d.path(t, 'doctors', doctorId), {
          'accountStatus': 'invited',
          'invitationId': invId,
          'updatedAt': now,
          'updatedBy': t.uid,
        }),
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'invitation.created',
            targetType: 'invitation',
            targetId: invId,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {'kind': 'doctor'},
          ),
        ),
      ]);
      return _withSecret(inv, token);
    });
  }

  // ------------------------------------------------------ resend / revoke

  Future<Map<String, Object?>> _loadForAdmin(TenantContext t, String id) async {
    t.require(ClinicPermission.staffInvite);
    final inv = await _d.store.get(_d.path(t, collection, id));
    if (inv == null) throw const ApiException.notFound('Invitation not found.');
    if (inv['kind'] == 'staff') {
      final s = await _staff.load(t, '${inv['subjectId']}');
      _staff.manageCheck(t, s);
    } else {
      t.require(ClinicPermission.doctorsUpdate);
      await _doctors.loadVisible(t, '${inv['subjectId']}');
    }
    return inv;
  }

  Future<Map<String, Object?>> resend(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    await _loadForAdmin(t, id);
    final token = newInvitationToken();
    final now = _d.now;
    return _d.store.transaction((tx) async {
      final cur = await tx.get(_d.path(t, collection, id));
      if (cur == null || cur['status'] != 'pending') {
        throw const ApiException.conflict(
          'Only a pending invitation can be resent.',
        );
      }
      final patch = {
        // a new secret replaces the old one: the previous link stops working
        'tokenHash': hashInvitationToken(token),
        'expiresAt': now.add(invitationTtl),
        'resendCount': ((cur['resendCount'] as int?) ?? 0) + 1,
        'lastSentAt': now,
      };
      tx.write([
        UpdateOp(_d.path(t, collection, id), patch),
        if (cur['kind'] == 'staff')
          UpdateOp(_d.path(t, 'staff', '${cur['subjectId']}'), {
            'status': 'invited',
            'invitationExpiresAt': patch['expiresAt'],
            'updatedAt': now,
          }),
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'invitation.resent',
            targetType: 'invitation',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
          ),
        ),
      ]);
      return _withSecret({...cur, ...patch}, token);
    });
  }

  Future<Map<String, Object?>> revoke(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    await _loadForAdmin(t, id);
    final now = _d.now;
    return _d.store.transaction((tx) async {
      final cur = await tx.get(_d.path(t, collection, id));
      if (cur == null || cur['status'] != 'pending') {
        throw const ApiException.conflict(
          'Only a pending invitation can be revoked.',
        );
      }
      final subject = '${cur['subjectId']}';
      final ops = <WriteOp>[];
      if (cur['kind'] == 'staff') {
        final s = await tx.get(_d.path(t, 'staff', subject));
        ops.add(
          UpdateOp(_d.path(t, 'staff', subject), {
            'status': 'inactive',
            'seatSlot': null,
            'invitationId': null,
            'invitationExpiresAt': null,
            'updatedAt': now,
          }),
        );
        final release = _d.seats.release(
          t.tenantId,
          SeatKind.staff,
          s?['seatSlot'],
        );
        if (release != null) ops.add(release);
      } else {
        ops.add(
          UpdateOp(_d.path(t, 'doctors', subject), {
            'accountStatus': 'none',
            'invitationId': null,
            'updatedAt': now,
          }),
        );
      }
      final patch = {
        'status': 'revoked',
        'tokenHash': null,
        'revokedAt': now,
        'revokedBy': t.uid,
      };
      tx.write([
        UpdateOp(_d.path(t, collection, id), patch),
        ...ops,
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'invitation.revoked',
            targetType: 'invitation',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
          ),
        ),
      ]);
      return present({...cur, ...patch});
    });
  }

  // ----------------------------------------------------------------- reads

  /// Never includes the hash or the token.
  Map<String, Object?> present(Map<String, Object?> inv) {
    final m = (jsonSafe(inv)! as Map<String, Object?>)..remove('tokenHash');
    final exp = inv['expiresAt'];
    m['effectiveStatus'] =
        m['status'] == 'pending' && exp is DateTime && !exp.isAfter(_d.now)
        ? 'expired'
        : m['status'];
    return m;
  }

  Future<Paged> list(
    TenantContext t,
    Request request, {
    String? status,
    String? kind,
  }) async {
    t.require(ClinicPermission.staffInvite);
    if (status != null &&
        !const {'pending', 'accepted', 'revoked'}.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (kind != null && kind != 'staff' && kind != 'doctor') {
      throw const ApiException.badRequest('kind has an unsupported value.');
    }
    final page = await runPaged(
      _d.store,
      DocQuery(
        _d.path(t, collection),
        filters: [
          if (status != null) QueryFilter('status', FilterOp.eq, status),
          if (kind != null) QueryFilter('kind', FilterOp.eq, kind),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      request,
    );
    if (t.scope.allBranches) return page;
    // scoped managers only see invitations whose scope is inside theirs
    return Paged(
      page.docs
          .where(
            (d) =>
                d.data['allBranches'] != true &&
                t.scope.containsAll(
                  ((d.data['branchIds'] as List?) ?? const []).cast<String>(),
                ),
          )
          .toList(),
      page.meta,
    );
  }

  // ---------------------------------------------------------------- accept

  /// Accepts an invitation for the authenticated caller. There is no tenant
  /// context yet: the invitation itself carries the tenant, role and branch
  /// scope, and the caller can change none of them.
  Future<Map<String, Object?>> accept(
    AuthContext caller,
    String token, {
    String? requestId,
  }) async {
    if (!token.startsWith('ecinv_') || token.length < 20 || token.length > 120)
      throw _invalidInvitation;
    final hash = hashInvitationToken(token);
    final found = await _d.store.query(
      DocQuery(
        collection,
        collectionGroup: true,
        filters: [QueryFilter('tokenHash', FilterOp.eq, hash)],
        limit: 2,
      ),
    );
    if (found.length != 1) throw _invalidInvitation;
    final segs = found.single.path.split('/');
    if (segs.length != 4 || segs[0] != 'tenants') throw _invalidInvitation;
    final tenantId = segs[1];
    final invId = segs[3];
    final now = _d.now;
    final uid = caller.user.uid;
    final email = (caller.identity.email ?? '').toLowerCase();

    Future<void> denied(String reason) => _d.audit.record(
      AuditEntry(
        actor: Actor(uid, 'invitee'),
        action: 'invitation.accept_denied',
        targetType: 'invitation',
        targetId: invId,
        tenantId: tenantId,
        reason: reason,
        requestId: requestId,
      ),
    );

    try {
      return await _d.store.transaction((tx) async {
        final inv = await tx.get('tenants/$tenantId/$collection/$invId');
        if (inv == null ||
            inv['tokenHash'] != hash ||
            inv['status'] != 'pending') {
          throw const _Denied('not_pending');
        }
        final exp = inv['expiresAt'] as DateTime?;
        if (exp == null || !exp.isAfter(now)) throw const _Denied('expired');
        if (!caller.identity.emailVerified ||
            email.isEmpty ||
            email != '${inv['email']}'.toLowerCase()) {
          throw const _Denied('identity_mismatch');
        }
        final memberPath = 'tenants/$tenantId/members/$uid';
        if (await tx.get(memberPath) != null)
          throw const _Denied('already_member');

        final kind = inv['kind'] as String;
        final subject = '${inv['subjectId']}';
        var branchIds = ((inv['branchIds'] as List?) ?? const [])
            .cast<String>();
        final allBranches = inv['allBranches'] == true;
        final role = inv['role'] as String;
        final ops = <WriteOp>[];
        if (kind == 'staff') {
          final s = await tx.get('tenants/$tenantId/staff/$subject');
          if (s == null ||
              s['status'] != 'invited' ||
              s['invitationId'] != invId ||
              s['uid'] != null) {
            throw const _Denied('profile_changed');
          }
          ops.add(
            UpdateOp('tenants/$tenantId/staff/$subject', {
              'uid': uid,
              'status': 'active',
              'invitationExpiresAt': null,
              'updatedAt': now,
              'updatedBy': uid,
            }),
          );
        } else {
          final doc = await tx.get('tenants/$tenantId/doctors/$subject');
          if (doc == null ||
              doc['status'] != 'active' ||
              doc['invitationId'] != invId ||
              doc['uid'] != null) {
            throw const _Denied('profile_changed');
          }
          // the doctor's branches are whatever they are assigned to right now
          final assigned = await tx.query(
            DocQuery(
              'tenants/$tenantId/${DoctorService.assignments}',
              filters: [
                QueryFilter('doctorId', FilterOp.eq, subject),
                const QueryFilter('status', FilterOp.eq, 'active'),
              ],
              limit: 100,
            ),
          );
          branchIds = [for (final a in assigned) a.data['branchId']! as String];
          if (branchIds.isEmpty) throw const _Denied('no_branches');
          ops.add(
            UpdateOp('tenants/$tenantId/doctors/$subject', {
              'uid': uid,
              'accountStatus': 'linked',
              'invitationId': null,
              'updatedAt': now,
              'updatedBy': uid,
            }),
          );
        }
        tx.write([
          CreateOp(memberPath, {
            'uid': uid,
            'role': role,
            'status': 'active',
            'allBranches': allBranches,
            'branchIds': branchIds,
            'permissionOverrides': <String, Object?>{},
            if (kind == 'staff') 'staffId': subject else 'doctorId': subject,
            'displayName': caller.user.displayName,
            'email': email,
            'source': 'invitation',
            'invitationId': invId,
            'createdAt': now,
            'createdBy': inv['createdBy'],
          }),
          UpdateOp('tenants/$tenantId/$collection/$invId', {
            'status': 'accepted',
            'tokenHash': null,
            'acceptedAt': now,
            'acceptedBy': uid,
          }),
          ...ops,
          _d.audit.op(
            AuditEntry(
              actor: Actor(uid, role),
              action: 'invitation.accepted',
              targetType: 'invitation',
              targetId: invId,
              tenantId: tenantId,
              requestId: requestId,
              after: {'role': role, 'kind': kind},
            ),
          ),
        ]);
        return {
          'tenantId': tenantId,
          'role': role,
          'allBranches': allBranches,
          'branchIds': branchIds,
        };
      });
    } on _Denied catch (e) {
      await denied(e.reason);
      throw _invalidInvitation;
    }
  }
}

class _Denied implements Exception {
  const _Denied(this.reason);
  final String reason;
}
