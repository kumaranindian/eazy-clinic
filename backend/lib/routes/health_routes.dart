import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/responses/responses.dart';

/// Service name and version reported by the health check. Deliberately
/// excludes environment, project ids, hostnames and dependency details.
const String serviceName = 'eazyclinic-backend';
const String serviceVersion = '0.1.0';

/// `GET /health` — unauthenticated liveness probe.
void registerHealthRoutes(Router router) {
  router.get('/health', (Request request) {
    return ok(request, {
      'status': 'ok',
      'service': serviceName,
      'version': serviceVersion,
    });
  });
}
