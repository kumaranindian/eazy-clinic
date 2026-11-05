import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/responses/responses.dart';

/// Service name and version reported by the health check. Deliberately
/// excludes environment, project ids, hostnames and dependency details.
const String serviceName = 'eazyclinic-backend';
const String serviceVersion = '0.1.0';

/// `GET /health` — unauthenticated liveness probe.
/// `GET /ready` — readiness probe: 200 only when the data store answers.
/// Neither reveals configuration, project ids or dependency detail.
void registerHealthRoutes(
  Router router, {
  Future<bool> Function()? storeCheck,
}) {
  router.get('/ready', (Request request) async {
    var ready = true;
    if (storeCheck != null) {
      try {
        ready = await storeCheck().timeout(const Duration(seconds: 3));
      } on Object {
        ready = false;
      }
    }
    return ready
        ? ok(request, {'status': 'ready', 'service': serviceName})
        : failure(
            request,
            ApiErrorCode.unavailable,
            'The service is not ready.',
          );
  });
  router.get('/health', (Request request) {
    return ok(request, {
      'status': 'ok',
      'service': serviceName,
      'version': serviceVersion,
    });
  });
}
