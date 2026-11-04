import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/api_exception.dart';
import '../../core/responses/responses.dart';
import '../../core/security/rate_limiter.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/tenant_context.dart';
import 'notification_service.dart';

const String _v1 = apiV1Prefix;
final RegExp _templateId = RegExp(r'^[A-Za-z0-9_:\-]{3,80}$');
final RegExp _channelName = RegExp(r'^[a-z_]{3,20}$');

/// Phase 10: staff notification center, preferences, devices and the
/// administration of templates, deliveries, channels and settings.
void registerNotificationRoutes(
  ClinicModule m,
  NotificationService n,
  Router r,
) {
  // Retries and device registration are rate limited per user.
  final retryLimiter = RateLimiter(
    maxRequests: 30,
    window: const Duration(hours: 1),
  );
  final deviceLimiter = RateLimiter(
    maxRequests: 30,
    window: const Duration(hours: 1),
  );

  Function g0(Future<Response> Function(Request, TenantContext) f) => f;
  Function g1(Future<Response> Function(Request, TenantContext, String) f) =>
      (Request req, TenantContext t, String a) => f(req, t, m.id(a));

  String? q(Request req, String name) => m.query(req, name);

  // ---------------------------------------------------------------- inbox
  r.get(
    '$_v1/notifications',
    m.secured(
      g0((req, t) async {
        final page = await n.inbox(
          t,
          req,
          unreadOnly: q(req, 'unread') == 'true',
        );
        return m.list(req, page, (d) => n.presentNotification(d.data));
      }),
    ),
  );
  r.get(
    '$_v1/notifications/unread-count',
    m.secured(g0((req, t) async => ok(req, await n.unreadCount(t)))),
  );
  r.post(
    '$_v1/notifications/read-all',
    m.secured(g0((req, t) async => ok(req, await n.readAll(t))), write: true),
  );
  r.post(
    '$_v1/notifications/<id>/read',
    m.secured(
      g1((req, t, id) async => ok(req, await n.markRead(t, id))),
      write: true,
    ),
  );
  r.post(
    '$_v1/notifications/<id>/archive',
    m.secured(
      g1((req, t, id) async => ok(req, await n.archive(t, id))),
      write: true,
    ),
  );

  // ------------------------------------------------- preferences, devices
  r.get(
    '$_v1/notifications/preferences',
    m.secured(g0((req, t) async => ok(req, await n.preferences(t)))),
  );
  r.patch(
    '$_v1/notifications/preferences',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await n.setPreferences(t, await m.body(req), requestId: m.rid(req)),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/notifications/devices',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await n.registerDevice(t, await m.body(req), requestId: m.rid(req)),
          status: 201,
        ),
      ),
      limiter: deviceLimiter,
    ),
  );
  r.delete(
    '$_v1/notifications/devices/<id>',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await n.removeDevice(t, id, requestId: m.rid(req))),
      ),
      limiter: deviceLimiter,
    ),
  );

  // ----------------------------------------------------------- templates
  r.get(
    '$_v1/admin/notification-templates',
    m.secured(g0((req, t) async => ok(req, await n.templates(t)))),
  );
  r.post(
    '$_v1/admin/notification-templates',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await n.createTemplate(t, await m.body(req), requestId: m.rid(req)),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/admin/notification-templates/<id>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await n.updateTemplate(
            t,
            id,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/admin/notification-templates/<id>/preview',
    m.secured((Request req, TenantContext t, String id) async {
      if (!_templateId.hasMatch(id)) throw const ApiException.notFound();
      return ok(req, await n.preview(t, id, await m.optionalBody(req)));
    }),
  );

  // ----------------------------------------- deliveries, channels, settings
  r.get(
    '$_v1/admin/notification-deliveries',
    m.secured(
      g0((req, t) async {
        final page = await n.deliveries(
          t,
          req,
          status: q(req, 'status'),
          channel: q(req, 'channel'),
          type: q(req, 'type'),
        );
        return m.list(req, page, (d) => n.presentDelivery(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/admin/notification-deliveries/<id>/retry',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await n.retry(t, id, requestId: m.rid(req))),
      ),
      limiter: retryLimiter,
    ),
  );
  r.get(
    '$_v1/admin/notification-channels',
    m.secured(g0((req, t) async => ok(req, await n.channels(t)))),
  );
  for (final action in const ['pause', 'resume']) {
    r.post(
      '$_v1/admin/notification-channels/<channel>/$action',
      m.secured((Request req, TenantContext t, String channel) async {
        if (!_channelName.hasMatch(channel)) {
          throw const ApiException.notFound();
        }
        return ok(
          req,
          await n.setPaused(
            t,
            channel,
            action == 'pause',
            requestId: m.rid(req),
          ),
        );
      }, write: true),
    );
  }
  r.get(
    '$_v1/admin/notification-settings',
    m.secured(g0((req, t) async => ok(req, await n.settings(t)))),
  );
  r.put(
    '$_v1/admin/notification-settings',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await n.updateSettings(t, await m.body(req), requestId: m.rid(req)),
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/admin/notification-health',
    m.secured(g0((req, t) async => ok(req, await n.health(t)))),
  );
}
