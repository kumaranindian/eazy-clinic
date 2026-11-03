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
import '../auth/presentation/auth_routes.dart';
import '../platform/audit/audit_service.dart';
import '../platform/common/paging.dart';
import '../platform/entitlements/entitlement_service.dart';
import 'branches/branch_service.dart';
import 'common/clinic_deps.dart';
import 'common/object_storage.dart';
import 'common/seat_service.dart';
import 'common/tenant_context.dart';
import 'settings/clinic_service.dart';

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
       invites =
           inviteLimiter ??
           RateLimiter(maxRequests: 30, window: const Duration(hours: 1)) {
    clinic = ClinicService(deps, storage);
    branches = BranchService(deps);
  }

  final AuthModule auth;
  final ClinicDeps deps;
  final RateLimiter writes;
  final RateLimiter invites;
  late final ClinicService clinic;
  late final BranchService branches;

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
        if (logo == null)
          throw const ApiException.notFound('No logo has been uploaded.');
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
  }
}

/// Convenience for tests / wiring.
String b64(List<int> bytes) => base64Encode(bytes);
