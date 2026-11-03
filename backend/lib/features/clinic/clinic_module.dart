import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/responses/responses.dart';
import '../../core/security/rate_limiter.dart';
import '../../core/validation/request_validator.dart';
import '../auth/application/auth_context_keys.dart';
import '../auth/domain/auth_context.dart';
import '../auth/presentation/auth_routes.dart';
import '../patients/patient_module.dart';
import '../platform/audit/audit_service.dart';
import '../platform/common/paging.dart';
import '../platform/entitlements/entitlement_service.dart';
import '../scheduling/scheduling_module.dart';
import 'branches/branch_service.dart';
import 'common/clinic_deps.dart';
import 'common/object_storage.dart';
import 'common/seat_service.dart';
import 'common/tenant_context.dart';
import 'doctors/doctor_service.dart';
import 'invitations/invitation_service.dart';
import 'members/member_service.dart';
import 'settings/clinic_service.dart';
import 'staff/staff_service.dart';

final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_\-]{3,64}$');

/// Clinic administration: profile, settings, branches, doctors, staff,
/// invitations, roles and members. Every route sits behind
/// `AuthModule.protect()` and then resolves the caller's tenant context from
/// server-side memberships; permission and branch checks happen in the
/// services (never in the client).
class ClinicModule {
  ClinicModule({
    required this.auth,
    required DocumentStore store,
    required ObjectStorage storage,
    DateTime Function()? clock,
    RateLimiter? writeLimiter,
    RateLimiter? inviteLimiter,
    RateLimiter? acceptLimiter,
    RateLimiter? identityLimiter,
    RateLimiter? familyLimiter,
  }) : deps = ClinicDeps(
         store: store,
         audit: AuditService(store, clock: clock),
         seats: SeatService(store, clock: clock),
         entitlements: EntitlementService(store, clock: clock),
         clock: clock,
       ),
       writes =
           writeLimiter ??
           RateLimiter(maxRequests: 120, window: const Duration(minutes: 1)),
       identityLimits =
           identityLimiter ??
           RateLimiter(maxRequests: 10, window: const Duration(hours: 1)),
       familyLimits =
           familyLimiter ??
           RateLimiter(maxRequests: 60, window: const Duration(hours: 1)),
       accepts =
           acceptLimiter ??
           RateLimiter(maxRequests: 10, window: const Duration(hours: 1)),
       invites =
           inviteLimiter ??
           RateLimiter(maxRequests: 30, window: const Duration(hours: 1)) {
    clinic = ClinicService(deps, storage);
    branches = BranchService(deps);
    doctors = DoctorService(deps, branches);
    staff = StaffService(deps, branches);
    invitations = InvitationService(deps, staff, doctors);
    members = MemberService(deps, staff, branches);
    patients = PatientModule(deps, storage);
    scheduling = SchedulingModule(deps, patients.support);
  }

  final AuthModule auth;
  final ClinicDeps deps;
  final RateLimiter writes;
  final RateLimiter invites;
  final RateLimiter accepts;
  final RateLimiter identityLimits;
  final RateLimiter familyLimits;
  late final PatientModule patients;
  late final SchedulingModule scheduling;
  late final ClinicService clinic;
  late final BranchService branches;
  late final DoctorService doctors;
  late final StaffService staff;
  late final InvitationService invitations;
  late final MemberService members;

  static const String _v1 = apiV1Prefix;

  // --------------------------------------------------------------- plumbing

  /// Wraps [h] `(Request, TenantContext[, String pathParam…])`.
  Handler secured(Function h, {bool write = false, RateLimiter? limiter}) {
    Future<Response> dispatch(Request req) async {
      final authCtx = authContextOf(req);
      final limit = (limiter ?? (write ? writes : null))?.hit(authCtx.user.uid);
      if (limit != null) {
        throw const ApiException(
          ApiErrorCode.rateLimited,
          'Too many requests. Please slow down.',
        );
      }
      final t = await resolveTenantContext(
        auth: authCtx,
        request: req,
        entitlements: deps.entitlements,
        write: write,
      );
      final r = Function.apply(h, [req, t, ...req.params.values]);
      return await r as Response;
    }

    return const Pipeline().addMiddleware(auth.protect()).addHandler(dispatch);
  }

  /// For callers who may not belong to any clinic yet (accepting an
  /// invitation): authenticated, active account, no tenant context.
  Handler userSecured(
    Future<Response> Function(Request, AuthContext) h, {
    required RateLimiter limiter,
  }) {
    Future<Response> dispatch(Request req) async {
      final ctx = authContextOf(req);
      if (limiter.hit(ctx.user.uid) != null) {
        throw const ApiException(
          ApiErrorCode.rateLimited,
          'Too many attempts. Please try again later.',
        );
      }
      return h(req, ctx);
    }

    return const Pipeline().addMiddleware(auth.protect()).addHandler(dispatch);
  }

  String? rid(Request r) => requestIdOf(r);

  String id(String raw) {
    if (!_idPattern.hasMatch(raw)) throw const ApiException.notFound();
    return raw;
  }

  Future<Map<String, Object?>> body(Request r) => readJsonObject(r);

  Future<Map<String, Object?>> optionalBody(Request r) async =>
      r.contentLength == 0 ? {} : readJsonObject(r);

  String? query(Request r, String name, {int max = 100}) {
    final v = r.url.queryParameters[name]?.trim();
    if (v == null || v.isEmpty) return null;
    if (v.length > max) throw ApiException.badRequest('$name is too long.');
    return v;
  }

  Response list(
    Request request,
    Paged page,
    Map<String, Object?> Function(StoredDoc) map,
  ) => ok(request, page.docs.map(map).toList(), page: page.meta);

  Actor actor(TenantContext t) => deps.actorOf(t);

  // --------------------------------------------------------------- register

  void register(Router r) {
    registerSchedulingRoutes(this, scheduling, r);
    registerPatientRoutes(
      this,
      patients,
      r,
      identityLimiter: identityLimits,
      familyLimiter: familyLimits,
    );
    // Clinic profile, settings, logo
    r.get(
      '$_v1/clinics/current',
      secured((Request req, TenantContext t) async {
        t.require(ClinicPermission.clinicView);
        return ok(req, await clinic.getProfile(t));
      }),
    );
    r.patch(
      '$_v1/clinics/current',
      secured((Request req, TenantContext t) async {
        t.require(ClinicPermission.clinicUpdate);
        return ok(
          req,
          await clinic.updateProfile(
            t,
            await body(req),
            actor(t),
            requestId: rid(req),
          ),
        );
      }, write: true),
    );
    r.get(
      '$_v1/clinics/current/settings',
      secured((Request req, TenantContext t) async {
        t.require(ClinicPermission.clinicView);
        return ok(req, await clinic.getSettings(t));
      }),
    );
    r.patch(
      '$_v1/clinics/current/settings',
      secured((Request req, TenantContext t) async {
        t.require(ClinicPermission.clinicSettingsManage);
        return ok(
          req,
          await clinic.updateSettings(
            t,
            await body(req),
            actor(t),
            requestId: rid(req),
          ),
        );
      }, write: true),
    );
    r.put(
      '$_v1/clinics/current/logo',
      secured((Request req, TenantContext t) async {
        t.require(ClinicPermission.clinicUpdate);
        // base64 of up to 512 KB plus JSON framing
        final payload = await readJsonObject(req, maxBytes: 1024 * 1024);
        return ok(
          req,
          await clinic.putLogo(t, payload, actor(t), requestId: rid(req)),
        );
      }, write: true),
    );
    r.get(
      '$_v1/clinics/current/logo',
      secured((Request req, TenantContext t) async {
        t.require(ClinicPermission.clinicView);
        final logo = await clinic.getLogo(t);
        if (logo == null) {
          throw const ApiException.notFound('No logo has been uploaded.');
        }
        return Response.ok(
          Uint8List.fromList(logo.$1),
          headers: {
            'content-type': logo.$2,
            'cache-control': 'private, no-store',
            'x-content-type-options': 'nosniff',
          },
        );
      }),
    );

    // Branches
    r.get(
      '$_v1/branches',
      secured((Request req, TenantContext t) async {
        final page = await branches.list(
          t,
          req,
          status: query(req, 'status'),
          q: query(req, 'q'),
        );
        return list(req, page, (d) => BranchService.present(d.data));
      }),
    );
    r.post(
      '$_v1/branches',
      secured(
        (Request req, TenantContext t) async => ok(
          req,
          await branches.create(t, await body(req), requestId: rid(req)),
          status: 201,
        ),
        write: true,
      ),
    );
    r.get(
      '$_v1/branches/<id>',
      secured(
        (Request req, TenantContext t, String bid) async =>
            ok(req, await branches.detail(t, id(bid))),
      ),
    );
    r.patch(
      '$_v1/branches/<id>',
      secured(
        (Request req, TenantContext t, String bid) async => ok(
          req,
          await branches.update(
            t,
            id(bid),
            await body(req),
            requestId: rid(req),
          ),
        ),
        write: true,
      ),
    );
    r.post(
      '$_v1/branches/<id>/activate',
      secured(
        (Request req, TenantContext t, String bid) async =>
            ok(req, await branches.activate(t, id(bid), requestId: rid(req))),
        write: true,
      ),
    );
    r.post(
      '$_v1/branches/<id>/deactivate',
      secured(
        (Request req, TenantContext t, String bid) async =>
            ok(req, await branches.deactivate(t, id(bid), requestId: rid(req))),
        write: true,
      ),
    );
    // Doctors
    r.get(
      '$_v1/doctors',
      secured((Request req, TenantContext t) async {
        final page = await doctors.list(
          t,
          req,
          q: query(req, 'q'),
          status: query(req, 'status'),
          specialty: query(req, 'specialty', max: 60),
          branchId: query(req, 'branchId', max: 64),
        );
        return list(req, page, (d) => doctors.present(t, d.data));
      }),
    );
    r.post(
      '$_v1/doctors',
      secured(
        (Request req, TenantContext t) async => ok(
          req,
          await doctors.create(t, await body(req), requestId: rid(req)),
          status: 201,
        ),
        write: true,
      ),
    );
    r.get(
      '$_v1/doctors/<id>',
      secured(
        (Request req, TenantContext t, String did) async =>
            ok(req, await doctors.detail(t, id(did))),
      ),
    );
    r.patch(
      '$_v1/doctors/<id>',
      secured(
        (Request req, TenantContext t, String did) async => ok(
          req,
          await doctors.update(
            t,
            id(did),
            await body(req),
            requestId: rid(req),
          ),
        ),
        write: true,
      ),
    );
    r.post(
      '$_v1/doctors/<id>/activate',
      secured(
        (Request req, TenantContext t, String did) async => ok(
          req,
          await doctors.setActive(
            t,
            id(did),
            active: true,
            requestId: rid(req),
          ),
        ),
        write: true,
      ),
    );
    r.post(
      '$_v1/doctors/<id>/deactivate',
      secured(
        (Request req, TenantContext t, String did) async => ok(
          req,
          await doctors.setActive(
            t,
            id(did),
            active: false,
            requestId: rid(req),
          ),
        ),
        write: true,
      ),
    );
    r.get(
      '$_v1/doctors/<id>/branches',
      secured(
        (Request req, TenantContext t, String did) async => ok(
          req,
          await doctors.listAssignments(
            t,
            id(did),
            status: query(req, 'status'),
          ),
        ),
      ),
    );
    r.post(
      '$_v1/doctors/<id>/branches',
      secured(
        (Request req, TenantContext t, String did) async => ok(
          req,
          await doctors.assign(
            t,
            id(did),
            await body(req),
            requestId: rid(req),
          ),
          status: 201,
        ),
        write: true,
      ),
    );
    r.delete(
      '$_v1/doctors/<id>/branches/<branchId>',
      secured((Request req, TenantContext t, String did, String bid) async {
        await doctors.unassign(t, id(did), id(bid), requestId: rid(req));
        return ok(req, {'ended': true});
      }, write: true),
    );
    // Staff
    r.get(
      '$_v1/staff',
      secured((Request req, TenantContext t) async {
        final page = await staff.list(
          t,
          req,
          q: query(req, 'q'),
          status: query(req, 'status'),
          role: query(req, 'role'),
          branchId: query(req, 'branchId', max: 64),
        );
        return list(req, page, (d) => staff.present(d.data));
      }),
    );
    r.post(
      '$_v1/staff',
      secured((Request req, TenantContext t) async {
        final payload = await body(req);
        final invite = payload['invite'] == true;
        final created = await staff.create(
          t,
          {...payload}..remove('invite'),
          requestId: rid(req),
        );
        if (!invite) return ok(req, created, status: 201);
        final inv = await invitations.createForStaff(
          t,
          created['staffId']! as String,
          requestId: rid(req),
        );
        return ok(req, {
          ...created,
          'status': 'invited',
          'invitation': inv,
        }, status: 201);
      }, write: true),
    );
    r.get(
      '$_v1/staff/<id>',
      secured(
        (Request req, TenantContext t, String sid) async =>
            ok(req, await staff.detail(t, id(sid))),
      ),
    );
    r.patch(
      '$_v1/staff/<id>',
      secured(
        (Request req, TenantContext t, String sid) async => ok(
          req,
          await staff.update(t, id(sid), await body(req), requestId: rid(req)),
        ),
        write: true,
      ),
    );
    r.post(
      '$_v1/staff/<id>/invite',
      secured(
        (Request req, TenantContext t, String sid) async => ok(
          req,
          await invitations.createForStaff(t, id(sid), requestId: rid(req)),
          status: 201,
        ),
        write: true,
        limiter: invites,
      ),
    );
    for (final (path, to) in [
      ('activate', 'active'),
      ('deactivate', 'inactive'),
      ('suspend', 'suspended'),
    ]) {
      r.post(
        '$_v1/staff/<id>/$path',
        secured(
          (Request req, TenantContext t, String sid) async => ok(
            req,
            await staff.setStatus(t, id(sid), to, requestId: rid(req)),
          ),
          write: true,
        ),
      );
    }

    // Invitations
    r.get(
      '$_v1/invitations',
      secured((Request req, TenantContext t) async {
        final page = await invitations.list(
          t,
          req,
          status: query(req, 'status'),
          kind: query(req, 'kind'),
        );
        return list(req, page, (d) => invitations.present(d.data));
      }),
    );
    r.post(
      '$_v1/invitations',
      secured(
        (Request req, TenantContext t) async {
          final payload = await body(req);
          final unknown = payload.keys.where(
            (k) => k != 'staffId' && k != 'doctorId',
          );
          final staffId = payload['staffId'];
          final doctorId = payload['doctorId'];
          if (unknown.isNotEmpty ||
              (staffId == null) == (doctorId == null) ||
              (staffId ?? doctorId) is! String) {
            throw ApiException.validation([
              const FieldIssue(
                field: 'staffId',
                code: 'invalid_value',
                message: 'Send exactly one of staffId or doctorId.',
              ),
            ]);
          }
          final inv = staffId != null
              ? await invitations.createForStaff(
                  t,
                  id(staffId as String),
                  requestId: rid(req),
                )
              : await invitations.createForDoctor(
                  t,
                  id(doctorId! as String),
                  requestId: rid(req),
                );
          return ok(req, inv, status: 201);
        },
        write: true,
        limiter: invites,
      ),
    );
    r.post(
      '$_v1/invitations/accept',
      userSecured((Request req, AuthContext ctx) async {
        final payload = await body(req);
        final token = payload['token'];
        if (payload.keys.any((k) => k != 'token') || token is! String) {
          throw const ApiException.badRequest(
            'This invitation is invalid or has expired.',
          );
        }
        return ok(
          req,
          await invitations.accept(ctx, token, requestId: rid(req)),
        );
      }, limiter: accepts),
    );
    r.post(
      '$_v1/invitations/<id>/resend',
      secured(
        (Request req, TenantContext t, String iid) async =>
            ok(req, await invitations.resend(t, id(iid), requestId: rid(req))),
        write: true,
        limiter: invites,
      ),
    );
    r.post(
      '$_v1/invitations/<id>/revoke',
      secured(
        (Request req, TenantContext t, String iid) async =>
            ok(req, await invitations.revoke(t, id(iid), requestId: rid(req))),
        write: true,
      ),
    );

    // Roles, permissions, members
    r.get(
      '$_v1/roles',
      secured(
        (Request req, TenantContext t) async => ok(req, members.roles(t)),
      ),
    );
    r.get(
      '$_v1/permissions',
      secured(
        (Request req, TenantContext t) async =>
            ok(req, members.permissionCatalog(t)),
      ),
    );
    r.get(
      '$_v1/members/current/permissions',
      secured(
        (Request req, TenantContext t) async =>
            ok(req, await members.currentPermissions(t)),
      ),
    );
    r.get(
      '$_v1/members',
      secured((Request req, TenantContext t) async {
        final page = await members.list(
          t,
          req,
          role: query(req, 'role'),
          status: query(req, 'status'),
        );
        final rows = [
          for (final d in page.docs) await members.present(t, d.data),
        ];
        return ok(req, rows, page: page.meta);
      }),
    );
    r.patch(
      '$_v1/members/<id>/role',
      secured(
        (Request req, TenantContext t, String mid) async => ok(
          req,
          await members.updateRole(
            t,
            id(mid),
            await body(req),
            requestId: rid(req),
          ),
        ),
        write: true,
      ),
    );
    r.patch(
      '$_v1/members/<id>/branches',
      secured(
        (Request req, TenantContext t, String mid) async => ok(
          req,
          await members.updateBranches(
            t,
            id(mid),
            await body(req),
            requestId: rid(req),
          ),
        ),
        write: true,
      ),
    );
  }
}

/// Convenience for tests / wiring.
String b64(List<int> bytes) => base64Encode(bytes);
