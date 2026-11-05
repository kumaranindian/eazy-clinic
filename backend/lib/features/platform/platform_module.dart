import 'dart:async';

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
import '../auth/application/security_event_recorder.dart';
import '../auth/presentation/auth_routes.dart';
import 'applications/application_service.dart';
import 'audit/audit_service.dart';
import 'common/body_reader.dart';
import 'common/paging.dart';
import 'countries/country_directory.dart';
import 'countries/country_service.dart';
import 'dashboard/dashboard_service.dart';
import 'entitlements/entitlement_service.dart';
import 'plans/plan_service.dart';
import 'subscriptions/subscription_service.dart';
import 'tenants/tenant_service.dart';

final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_\-]{3,64}$');

/// SaaS control plane: clinic applications, tenants, plans, subscriptions,
/// entitlements, dashboard and audit. Every route sits behind
/// `AuthModule.protect()`; platform routes additionally need a platform
/// permission that comes from the server-side `platformRole`.
class PlatformModule {
  PlatformModule({
    required this.auth,
    required DocumentStore store,
    DateTime Function()? clock,
    RateLimiter? adminWriteLimiter,
    RateLimiter? submitLimiter,
  }) : audit = AuditService(store, clock: clock),
       adminWrites =
           adminWriteLimiter ??
           RateLimiter(maxRequests: 120, window: const Duration(minutes: 1)),
       submits =
           submitLimiter ??
           RateLimiter(maxRequests: 5, window: const Duration(hours: 1)) {
    plans = PlanService(store, audit, clock: clock);
    subscriptions = SubscriptionService(store, audit, clock: clock);
    applications = ApplicationService(store, audit, clock: clock);
    tenants = TenantService(store, audit, subscriptions, clock: clock);
    entitlements = EntitlementService(store, clock: clock);
    dashboard = DashboardService(store, audit, clock: clock);
    countryDirectory = CountryDirectory(store, clock: clock);
    countries = CountryService(store, audit, countryDirectory, clock: clock);
  }

  final AuthModule auth;
  final AuditService audit;
  final RateLimiter adminWrites;
  final RateLimiter submits;
  late final PlanService plans;
  late final SubscriptionService subscriptions;
  late final ApplicationService applications;
  late final TenantService tenants;
  late final EntitlementService entitlements;
  late final DashboardService dashboard;
  late final CountryDirectory countryDirectory;
  late final CountryService countries;

  static const String _p = '$apiV1Prefix/platform';

  // --------------------------------------------------------------- plumbing

  /// Wraps [h] (either `(Request)` or `(Request, String pathParam)`) with
  /// authentication, account-status gating and the permission guard. Route
  /// params are forwarded positionally, in path order.
  Handler _secured(Function h, {String? permission, bool write = false}) {
    FutureOr<Response> dispatch(Request req) => h is Handler
        ? h(req)
        : Function.apply(h, [req, ...req.params.values]) as FutureOr<Response>;
    return const Pipeline()
        .addMiddleware(auth.protect())
        .addMiddleware(_guard(permission, write))
        .addHandler(dispatch);
  }

  Middleware _guard(String? permission, bool write) =>
      (inner) => (request) async {
        final ctx = authContextOf(request);
        if (permission != null &&
            !PermissionPolicy.platformRoleHas(
              ctx.user.platformRole,
              permission,
            )) {
          await auth.events.record(
            SecurityEvent.accessDenied,
            uid: ctx.user.uid,
            requestId: requestIdOf(request),
            outcome: 'denied',
            reason: 'missing_permission',
            persist: false,
          );
          throw const ApiException.forbidden();
        }
        if (write && adminWrites.hit(ctx.user.uid) != null) {
          throw const ApiException(
            ApiErrorCode.rateLimited,
            'Too many requests. Please slow down.',
          );
        }
        return inner(request);
      };

  Actor _actor(Request r) {
    final u = authContextOf(r).user;
    return Actor(u.uid, u.platformRole?.wireName ?? 'user');
  }

  String? _rid(Request r) => requestIdOf(r);

  String _id(String raw) {
    if (!_idPattern.hasMatch(raw)) throw const ApiException.notFound();
    return raw;
  }

  Future<Map<String, Object?>> _body(Request r) => readJsonObject(r);

  Future<Map<String, Object?>> _optionalBody(Request r) async =>
      r.contentLength == 0 ? {} : readJsonObject(r);

  String? _query(Request r, String name, {int max = 100}) {
    final v = r.url.queryParameters[name]?.trim();
    if (v == null || v.isEmpty) return null;
    if (v.length > max) throw ApiException.badRequest('$name is too long.');
    return v;
  }

  T? _enumQuery<T>(
    Request r,
    String name,
    List<T> values,
    String Function(T) wire,
  ) {
    final v = _query(r, name);
    if (v == null) return null;
    for (final e in values) {
      if (wire(e) == v) return e;
    }
    throw ApiException.badRequest('$name has an unsupported value.');
  }

  String _reason(
    Map<String, Object?> body, {
    String field = 'reason',
    bool required = true,
  }) {
    final r = BodyReader(body)..rejectUnknown({field, 'confirm', 'note'});
    final v = r.str(field, min: 3, max: 500, required: required);
    r.throwIfInvalid();
    return v ?? '';
  }

  Response _list(
    Request request,
    Paged page,
    Map<String, Object?> Function(StoredDoc) map,
  ) => ok(request, page.docs.map(map).toList(), page: page.meta);

  Map<String, Object?> _row(StoredDoc d) =>
      (jsonSafe(d.data)! as Map<String, Object?>)
        ..remove('dupKey')
        ..remove('clinicNameLower');

  // -------------------------------------------------------------- register

  void register(Router r) {
    // Dashboard
    r.get(
      '$_p/dashboard',
      _secured(
        (Request req) async => ok(req, await dashboard.build()),
        permission: Permission.readDashboard,
      ),
    );

    // Countries (Phase 12). Literal paths first so they win over `<code>`.
    r.get(
      '$apiV1Prefix/countries',
      _secured(
        (Request req) async =>
            ok(req, {'items': await countries.listOnboardable()}),
      ),
    );
    r.get(
      '$_p/countries',
      _secured(
        (Request req) async => ok(req, {'items': await countries.list()}),
        permission: Permission.readCountries,
      ),
    );
    r.get(
      '$_p/countries/backfill-report',
      _secured(
        (Request req) async => ok(req, await countries.backfillReport()),
        permission: Permission.readCountries,
      ),
    );
    r.post(
      '$_p/countries/seed-baseline',
      _secured(
        (Request req) async => ok(req, {
          'items': await countries.seedBaseline(
            _actor(req),
            requestId: _rid(req),
          ),
        }),
        permission: Permission.manageCountries,
        write: true,
      ),
    );
    r.post(
      '$_p/countries',
      _secured(
        (Request req) async => ok(
          req,
          await countries.create(
            await _body(req),
            _actor(req),
            requestId: _rid(req),
          ),
          status: 201,
        ),
        permission: Permission.manageCountries,
        write: true,
      ),
    );
    r.get(
      '$_p/countries/<code>',
      _secured(
        (Request req, String code) async => ok(req, await countries.get(code)),
        permission: Permission.readCountries,
      ),
    );
    r.patch(
      '$_p/countries/<code>',
      _secured(
        (Request req, String code) async => ok(
          req,
          await countries.update(
            code,
            await _body(req),
            _actor(req),
            requestId: _rid(req),
          ),
        ),
        permission: Permission.manageCountries,
        write: true,
      ),
    );
    r.post(
      '$_p/tenants/<id>/country',
      _secured(
        _assignTenantCountry,
        permission: Permission.migrateTenantCountry,
        write: true,
      ),
    );

    // Applicant side
    r.post('$apiV1Prefix/clinic-applications', _secured(_submitApplication));
    r.get('$apiV1Prefix/clinic-applications/my', _secured(_myApplications));
    r.get(
      '$apiV1Prefix/clinic-applications/<id>',
      _secured(
        (Request req, String id) async => ok(
          req,
          await applications.getMine(_id(id), authContextOf(req).user.uid),
        ),
      ),
    );
    r.post('$apiV1Prefix/clinic-applications/<id>/respond', _secured(_respond));
    r.post(
      '$apiV1Prefix/clinic-applications/<id>/withdraw',
      _secured(
        (Request req, String id) async => ok(
          req,
          await applications.withdraw(
            _id(id),
            authContextOf(req).user.uid,
            requestId: _rid(req),
          ),
        ),
      ),
    );

    // Platform: applications
    r.get(
      '$_p/clinic-applications',
      _secured(_listApplications, permission: Permission.readApplications),
    );
    r.get(
      '$_p/clinic-applications/<id>',
      _secured(
        (Request req, String id) async =>
            ok(req, await applications.detail(_id(id))),
        permission: Permission.readApplications,
      ),
    );
    r.post(
      '$_p/clinic-applications/<id>/start-review',
      _secured(
        (Request req, String id) async => ok(
          req,
          await applications.startReview(
            _id(id),
            _actor(req),
            requestId: _rid(req),
          ),
        ),
        permission: Permission.reviewApplications,
        write: true,
      ),
    );
    r.post(
      '$_p/clinic-applications/<id>/request-information',
      _secured(
        _requestInformation,
        permission: Permission.reviewApplications,
        write: true,
      ),
    );
    r.post(
      '$_p/clinic-applications/<id>/approve',
      _secured(
        _approve,
        permission: Permission.reviewApplications,
        write: true,
      ),
    );
    r.post(
      '$_p/clinic-applications/<id>/reject',
      _secured(_reject, permission: Permission.reviewApplications, write: true),
    );
    r.post(
      '$_p/clinic-applications/<id>/notes',
      _secured(
        _addNote,
        permission: Permission.reviewApplications,
        write: true,
      ),
    );

    // Platform: tenants
    r.get(
      '$_p/tenants',
      _secured(_listTenants, permission: Permission.readTenants),
    );
    r.get(
      '$_p/tenants/<id>',
      _secured(
        (Request req, String id) async =>
            ok(req, await tenants.detail(_id(id))),
        permission: Permission.readTenants,
      ),
    );
    r.post(
      '$_p/tenants/<id>/suspend',
      _secured(
        (Request req, String id) async {
          final reason = _reason(await _body(req));
          return ok(
            req,
            jsonSafe(
              await tenants.suspend(
                _id(id),
                reason,
                _actor(req),
                requestId: _rid(req),
              ),
            ),
          );
        },
        permission: Permission.manageTenants,
        write: true,
      ),
    );
    r.post(
      '$_p/tenants/<id>/reactivate',
      _secured(
        (Request req, String id) async {
          final reason = _reason(await _body(req));
          return ok(
            req,
            jsonSafe(
              await tenants.reactivate(
                _id(id),
                reason,
                _actor(req),
                requestId: _rid(req),
              ),
            ),
          );
        },
        permission: Permission.manageTenants,
        write: true,
      ),
    );
    r.post(
      '$_p/tenants/<id>/close',
      _secured(_closeTenant, permission: Permission.manageTenants, write: true),
    );
    r.post(
      '$_p/tenants/<id>/retry-provisioning',
      _secured(
        (Request req, String id) async {
          final result = await tenants.retryProvisioning(
            _id(id),
            _actor(req),
            requestId: _rid(req),
          );
          return ok(req, result.toJson());
        },
        permission: Permission.manageTenants,
        write: true,
      ),
    );

    // Platform: plans
    r.get(
      '$_p/subscription-plans',
      _secured(_listPlans, permission: Permission.readPlans),
    );
    r.post(
      '$_p/subscription-plans',
      _secured(
        (Request req) async {
          final input = PlanInput.parse(await _body(req), partial: false);
          return ok(
            req,
            jsonSafe(
              await plans.create(input, _actor(req), requestId: _rid(req)),
            ),
            status: 201,
          );
        },
        permission: Permission.managePlans,
        write: true,
      ),
    );
    r.get(
      '$_p/subscription-plans/<id>',
      _secured(
        (Request req, String id) async =>
            ok(req, jsonSafe(await plans.detail(_id(id)))),
        permission: Permission.readPlans,
      ),
    );
    r.patch(
      '$_p/subscription-plans/<id>',
      _secured(
        (Request req, String id) async {
          final input = PlanInput.parse(await _body(req), partial: true);
          return ok(
            req,
            jsonSafe(
              await plans.update(
                _id(id),
                input,
                _actor(req),
                requestId: _rid(req),
              ),
            ),
          );
        },
        permission: Permission.managePlans,
        write: true,
      ),
    );
    r.post(
      '$_p/subscription-plans/<id>/activate',
      _secured(
        (Request req, String id) async => ok(
          req,
          jsonSafe(
            await plans.setStatus(
              _id(id),
              PlanStatus.active,
              _actor(req),
              requestId: _rid(req),
            ),
          ),
        ),
        permission: Permission.managePlans,
        write: true,
      ),
    );
    r.post(
      '$_p/subscription-plans/<id>/deactivate',
      _secured(
        (Request req, String id) async => ok(
          req,
          jsonSafe(
            await plans.setStatus(
              _id(id),
              PlanStatus.inactive,
              _actor(req),
              requestId: _rid(req),
            ),
          ),
        ),
        permission: Permission.managePlans,
        write: true,
      ),
    );

    // Platform: subscriptions
    r.get(
      '$_p/subscriptions',
      _secured(_listSubscriptions, permission: Permission.readSubscriptions),
    );
    r.get(
      '$_p/subscriptions/<id>',
      _secured(
        (Request req, String id) async =>
            ok(req, jsonSafe(await subscriptions.detail(_id(id)))),
        permission: Permission.readSubscriptions,
      ),
    );
    r.post(
      '$_p/subscriptions',
      _secured(
        _assignSubscription,
        permission: Permission.manageSubscriptions,
        write: true,
      ),
    );
    r.patch(
      '$_p/subscriptions/<id>',
      _secured(
        _patchSubscription,
        permission: Permission.manageSubscriptions,
        write: true,
      ),
    );
    r.post(
      '$_p/subscriptions/<id>/extend-trial',
      _secured(
        _extendTrial,
        permission: Permission.manageSubscriptions,
        write: true,
      ),
    );
    r.post(
      '$_p/subscriptions/<id>/renew',
      _secured(
        (Request req, String id) async {
          final body = await _optionalBody(req);
          final reason = body.isEmpty ? null : _reason(body, required: false);
          return ok(
            req,
            jsonSafe(
              await subscriptions.renew(
                _id(id),
                _actor(req),
                reason: reason,
                requestId: _rid(req),
              ),
            ),
          );
        },
        permission: Permission.manageSubscriptions,
        write: true,
      ),
    );
    r.post(
      '$_p/subscriptions/<id>/mark-past-due',
      _secured(
        (Request req, String id) async {
          final body = await _optionalBody(req);
          final reason = body.isEmpty ? null : _reason(body, required: false);
          return ok(
            req,
            jsonSafe(
              await subscriptions.markPastDue(
                _id(id),
                _actor(req),
                reason: reason,
                requestId: _rid(req),
              ),
            ),
          );
        },
        permission: Permission.manageSubscriptions,
        write: true,
      ),
    );
    r.post(
      '$_p/subscriptions/<id>/suspend',
      _secured(
        (Request req, String id) async => ok(
          req,
          jsonSafe(
            await subscriptions.suspend(
              _id(id),
              _actor(req),
              reason: _reason(await _body(req)),
              requestId: _rid(req),
            ),
          ),
        ),
        permission: Permission.manageSubscriptions,
        write: true,
      ),
    );
    r.post(
      '$_p/subscriptions/<id>/cancel',
      _secured(
        (Request req, String id) async => ok(
          req,
          jsonSafe(
            await subscriptions.cancel(
              _id(id),
              _actor(req),
              reason: _reason(await _body(req)),
              requestId: _rid(req),
            ),
          ),
        ),
        permission: Permission.manageSubscriptions,
        write: true,
      ),
    );

    // Platform: audit
    r.get(
      '$_p/audit-logs',
      _secured((Request req) async {
        final used = [
          'tenantId',
          'action',
          'targetType',
          'actorUid',
        ].where((f) => _query(req, f) != null).length;
        if (used > 1) {
          throw const ApiException.badRequest(
            'Use at most one audit filter at a time.',
          );
        }
        final page = await audit.list(
          req,
          tenantId: _query(req, 'tenantId'),
          action: _query(req, 'action'),
          targetType: _query(req, 'targetType'),
          actorUid: _query(req, 'actorUid'),
        );
        return _list(req, page, AuditService.present);
      }, permission: Permission.readAuditLogs),
    );

    // Tenant: entitlements of the caller's own clinic
    r.get(
      '$apiV1Prefix/tenants/current/entitlements',
      _secured(_currentEntitlements),
    );
  }

  // -------------------------------------------------------------- handlers

  Future<Response> _submitApplication(Request req) async {
    final ctx = authContextOf(req);
    if (submits.hit(ctx.user.uid) != null) {
      throw const ApiException(
        ApiErrorCode.rateLimited,
        'Too many submissions. Please try again later.',
      );
    }
    final input = ApplicationInput.parse(await _body(req), partial: false);
    final app = await applications.submit(
      applicantUid: ctx.user.uid,
      applicantEmail: ctx.user.email,
      input: input,
      requestId: _rid(req),
    );
    return ok(
      req,
      ApplicationService.presentForApplicant(app, const []),
      status: 201,
    );
  }

  Future<Response> _myApplications(Request req) async {
    final page = await applications.listMine(authContextOf(req).user.uid, req);
    return ok(
      req,
      page.docs
          .map(
            (d) =>
                ApplicationService.presentForApplicant(d.data, const [])
                  ..remove('history'),
          )
          .toList(),
      page: page.meta,
    );
  }

  Future<Response> _respond(Request req, String id) async {
    final body = await _body(req);
    final reader = BodyReader(body)
      ..rejectUnknown({'message', ...ApplicationInput.fields});
    final message = reader.str('message', min: 3, max: 2000);
    reader.throwIfInvalid();
    final updates = ApplicationInput.parse(
      {...body}..remove('message'),
      partial: true,
    );
    return ok(
      req,
      await applications.respond(
        id: _id(id),
        uid: authContextOf(req).user.uid,
        message: message!,
        updates: updates,
        requestId: _rid(req),
      ),
    );
  }

  Future<Response> _listApplications(Request req) async {
    final page = await applications.list(
      req,
      status: _enumQuery(
        req,
        'status',
        ApplicationStatus.values,
        (e) => e.wireName,
      ),
      q: _query(req, 'q'),
    );
    return _list(
      req,
      page,
      (d) => ApplicationService.presentForPlatform(d.data),
    );
  }

  Future<Response> _requestInformation(Request req, String id) async {
    final r = BodyReader(await _body(req));
    r.rejectUnknown({'message'});
    final message = r.str('message', min: 5, max: 2000);
    r.throwIfInvalid();
    return ok(
      req,
      await applications.requestInformation(
        _id(id),
        message!,
        _actor(req),
        requestId: _rid(req),
      ),
    );
  }

  Future<Response> _reject(Request req, String id) async {
    final reason = _reason(await _body(req));
    return ok(
      req,
      await applications.reject(
        _id(id),
        reason,
        _actor(req),
        requestId: _rid(req),
      ),
    );
  }

  Future<Response> _addNote(Request req, String id) async {
    final r = BodyReader(await _body(req));
    r.rejectUnknown({'note'});
    final note = r.str('note', min: 2, max: 2000);
    r.throwIfInvalid();
    await applications.addNote(
      _id(id),
      note!,
      _actor(req),
      requestId: _rid(req),
    );
    return ok(req, {'added': true}, status: 201);
  }

  Future<Response> _approve(Request req, String id) async {
    final r = BodyReader(await _body(req));
    r.rejectUnknown({'confirm', 'planId', 'startTrial', 'note', 'countryCode'});
    final confirm = r.boolean('confirm', required: true);
    final planId = r.str('planId', min: 5, max: 40, required: false);
    final trial = r.boolean('startTrial') ?? false;
    final note = r.str('note', min: 0, max: 500, required: false);
    final countryCode = r.str('countryCode', min: 2, max: 2, required: false);
    if (countryCode != null &&
        !CountryDirectory.isWellFormedCode(countryCode)) {
      r.addIssue(
        'countryCode',
        'invalid_value',
        'countryCode must be an ISO 3166-1 alpha-2 code.',
      );
    }
    if (confirm != true) {
      r.addIssue(
        'confirm',
        'confirmation_required',
        'Approval must be confirmed (confirm: true).',
      );
    }
    if (trial && planId == null) {
      r.addIssue('startTrial', 'plan_required', 'A trial needs a planId.');
    }
    r.throwIfInvalid();
    final result = await tenants.approve(
      applicationId: _id(id),
      actor: _actor(req),
      initialPlanId: planId,
      startTrial: trial,
      note: note,
      countryCode: countryCode,
      requestId: _rid(req),
    );
    return ok(req, result.toJson());
  }

  Future<Response> _assignTenantCountry(Request req, String id) async {
    final r = BodyReader(await _body(req))
      ..rejectUnknown({'countryCode', 'reason', 'expectedCurrent', 'confirm'});
    final code = r.str('countryCode', min: 2, max: 2);
    final reason = r.str('reason', min: 3, max: 500);
    final expected = r.str('expectedCurrent', min: 2, max: 2, required: false);
    final confirm = r.boolean('confirm', required: true);
    if (confirm != true) {
      r.addIssue(
        'confirm',
        'confirmation_required',
        'Assigning a country must be confirmed (confirm: true).',
      );
    }
    r.throwIfInvalid();
    return ok(
      req,
      await countries.assignTenantCountry(
        tenantId: _id(id),
        countryCode: code!,
        reason: reason!,
        expectedCurrent: expected,
        actor: _actor(req),
        requestId: _rid(req),
      ),
    );
  }

  Future<Response> _listTenants(Request req) async {
    final page = await tenants.list(
      req,
      status: _enumQuery(req, 'status', TenantStatus.values, (e) => e.wireName),
      q: _query(req, 'q'),
    );
    return _list(req, page, (d) => _row(d)..remove('configurationVersion'));
  }

  Future<Response> _closeTenant(Request req, String id) async {
    final body = await _body(req);
    final reason = _reason(body);
    if (body['confirm'] != true) {
      throw ApiException.validation([
        const FieldIssue(
          field: 'confirm',
          code: 'confirmation_required',
          message: 'Closing a clinic must be confirmed (confirm: true).',
        ),
      ]);
    }
    return ok(
      req,
      jsonSafe(
        await tenants.close(_id(id), reason, _actor(req), requestId: _rid(req)),
      ),
    );
  }

  Future<Response> _listPlans(Request req) async {
    final page = await plans.list(
      req,
      status: _enumQuery(req, 'status', PlanStatus.values, (e) => e.wireName),
    );
    return _list(req, page, _row);
  }

  Future<Response> _listSubscriptions(Request req) async {
    final page = await subscriptions.list(
      req,
      status: _enumQuery(
        req,
        'status',
        SubscriptionStatus.values,
        (e) => e.wireName,
      ),
      tenantId: _query(req, 'tenantId'),
      planId: _query(req, 'planId'),
    );
    return _list(req, page, _row);
  }

  Future<Response> _assignSubscription(Request req) async {
    final body = await _body(req);
    final r = BodyReader(body)
      ..rejectUnknown({'tenantId', 'planId', 'trial', 'startDate', 'reason'});
    final tenantId = r.str('tenantId', min: 3, max: 64);
    final planId = r.str('planId', min: 3, max: 64);
    final trial = r.boolean('trial') ?? false;
    final reason = r.str('reason', min: 3, max: 500, required: false);
    DateTime? start;
    final rawStart = r.str('startDate', max: 40, required: false);
    if (rawStart != null) {
      start = DateTime.tryParse(rawStart);
      if (start == null) {
        r.addIssue(
          'startDate',
          'invalid_date',
          'startDate must be an ISO-8601 date.',
        );
      }
    }
    r.throwIfInvalid();
    final sub = await subscriptions.assign(
      tenantId: tenantId!,
      planId: planId!,
      trial: trial,
      startDate: start,
      reason: reason,
      actor: _actor(req),
      requestId: _rid(req),
    );
    return ok(req, jsonSafe(sub), status: 201);
  }

  Future<Response> _patchSubscription(Request req, String id) async {
    final body = await _body(req);
    final r = BodyReader(body)
      ..rejectUnknown({'planId', 'overrides', 'reason'});
    final planId = r.str('planId', min: 3, max: 64, required: false);
    final reason = r.str('reason', min: 3, max: 500, required: false);
    Map<String, Object?>? overrides;
    if (body.containsKey('overrides')) {
      overrides = _parseOverrides(body['overrides'], r);
    }
    if (planId == null && overrides == null) {
      r.addIssue('body', 'empty', 'Provide planId and/or overrides.');
    }
    if (overrides != null && reason == null) {
      r.addIssue(
        'reason',
        'required',
        'A reason is required for entitlement overrides.',
      );
    }
    r.throwIfInvalid();
    final ctx = authContextOf(req);
    if (overrides != null &&
        !PermissionPolicy.platformRoleHas(
          ctx.user.platformRole,
          Permission.overrideEntitlements,
        )) {
      throw const ApiException.forbidden();
    }
    Map<String, Object?>? result;
    if (planId != null) {
      result = await subscriptions.changePlan(
        _id(id),
        planId,
        _actor(req),
        reason: reason,
        requestId: _rid(req),
      );
    }
    if (overrides != null) {
      final targetId = result?['subscriptionId'] as String? ?? _id(id);
      result = await subscriptions.setOverrides(
        targetId,
        overrides,
        _actor(req),
        reason: reason!,
        requestId: _rid(req),
      );
    }
    return ok(req, jsonSafe(result));
  }

  Map<String, Object?>? _parseOverrides(Object? raw, BodyReader r) {
    if (raw is! Map) {
      r.addIssue('overrides', 'invalid_type', 'overrides must be an object.');
      return null;
    }
    final out = <String, Object?>{};
    for (final k in raw.keys) {
      if (k != 'features' && k != 'limits') {
        r.addIssue('overrides.$k', 'not_allowed', 'Unknown override group.');
      }
    }
    final features = raw['features'];
    if (features != null) {
      if (features is! Map) {
        r.addIssue(
          'overrides.features',
          'invalid_type',
          'features must be an object.',
        );
      } else {
        final m = <String, bool>{};
        for (final e in features.entries) {
          if (!FeatureKey.all.contains(e.key) || e.value is! bool) {
            r.addIssue(
              'overrides.features.${e.key}',
              'invalid_value',
              'Unknown feature or non-boolean value.',
            );
          } else {
            m[e.key as String] = e.value as bool;
          }
        }
        if (m.isNotEmpty) out['features'] = m;
      }
    }
    final limits = raw['limits'];
    if (limits != null) {
      if (limits is! Map) {
        r.addIssue(
          'overrides.limits',
          'invalid_type',
          'limits must be an object.',
        );
      } else {
        final m = <String, int?>{};
        for (final e in limits.entries) {
          final v = e.value;
          if (!LimitKey.all.contains(e.key) ||
              !(v == null || (v is int && v >= 0 && v <= 1000000))) {
            r.addIssue(
              'overrides.limits.${e.key}',
              'invalid_value',
              'Unknown limit or invalid value (null = unlimited).',
            );
          } else {
            m[e.key as String] = v as int?;
          }
        }
        if (m.isNotEmpty) out['limits'] = m;
      }
    }
    return out;
  }

  Future<Response> _extendTrial(Request req, String id) async {
    final r = BodyReader(await _body(req));
    r.rejectUnknown({'days', 'reason'});
    final days = r.integer('days', min: 1, max: 90);
    final reason = r.str('reason', min: 3, max: 500);
    r.throwIfInvalid();
    return ok(
      req,
      jsonSafe(
        await subscriptions.extendTrial(
          _id(id),
          days!,
          _actor(req),
          reason: reason!,
          requestId: _rid(req),
        ),
      ),
    );
  }

  /// The tenant comes from the caller's server-resolved memberships. The
  /// optional `X-Tenant-Id` header only *selects* among memberships the
  /// caller already has; it never grants access to another clinic.
  Future<Response> _currentEntitlements(Request req) async {
    final memberships = authContextOf(req).memberships;
    if (memberships.isEmpty) {
      throw const ApiException.forbidden('You do not have access to a clinic.');
    }
    final selector = req.headers['x-tenant-id']?.trim();
    MembershipSummaryDto chosen;
    if (selector != null && selector.isNotEmpty) {
      final match = memberships.where((m) => m.tenantId == selector);
      if (match.isEmpty) {
        throw const ApiException.forbidden(
          'You do not have access to this clinic.',
        );
      }
      chosen = match.first;
    } else if (memberships.length == 1) {
      chosen = memberships.first;
    } else {
      throw const ApiException.conflict(
        'You belong to several clinics. Send X-Tenant-Id to choose one.',
      );
    }
    return ok(req, (await entitlements.forTenant(chosen.tenantId)).toJson());
  }
}
