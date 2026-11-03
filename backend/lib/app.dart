import 'package:shelf/shelf.dart';

import 'config/app_config.dart';
import 'core/logging/app_logger.dart';
import 'core/middleware/cors_middleware.dart';
import 'core/middleware/error_handler_middleware.dart';
import 'core/middleware/request_id_middleware.dart';
import 'core/middleware/request_logging_middleware.dart';
import 'core/middleware/security_headers_middleware.dart';
import 'routes/api_v1_router.dart';

/// Assembles the full HTTP handler.
///
/// Middleware order (outermost first):
/// request id → CORS → security headers → request logging → error handler →
/// router. Authentication and tenant-context middleware are added in Phase 1,
/// between the error handler and the router.
Handler buildApp(AppConfig config, AppLogger logger) {
  return Pipeline()
      .addMiddleware(requestIdMiddleware())
      .addMiddleware(corsMiddleware(config.corsAllowedOrigins))
      .addMiddleware(securityHeadersMiddleware())
      .addMiddleware(requestLoggingMiddleware(logger))
      .addMiddleware(errorHandlerMiddleware(logger))
      .addHandler(buildRouter().call);
}
