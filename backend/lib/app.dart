import 'package:shelf/shelf.dart';

import 'config/app_config.dart';
import 'core/logging/app_logger.dart';
import 'core/middleware/cors_middleware.dart';
import 'core/middleware/error_handler_middleware.dart';
import 'core/middleware/request_id_middleware.dart';
import 'core/middleware/request_logging_middleware.dart';
import 'core/middleware/security_headers_middleware.dart';
import 'features/auth/presentation/auth_routes.dart';
import 'features/clinic/clinic_module.dart';
import 'features/platform/platform_module.dart';
import 'routes/api_v1_router.dart';

/// Assembles the full HTTP handler.
///
/// Middleware order (outermost first):
/// request id → CORS → security headers → request logging → error handler →
/// router. Authentication is applied per route group by [AuthModule.protect], so
/// public routes (health) stay open and every protected router opts in
/// explicitly.
Handler buildApp(
  AppConfig config,
  AppLogger logger, {
  AuthModule? auth,
  PlatformModule? platform,
  ClinicModule? clinic,
}) {
  return Pipeline()
      .addMiddleware(requestIdMiddleware())
      .addMiddleware(corsMiddleware(config.corsAllowedOrigins))
      .addMiddleware(securityHeadersMiddleware())
      .addMiddleware(requestLoggingMiddleware(logger))
      .addMiddleware(errorHandlerMiddleware(logger))
      .addHandler(
        buildRouter(auth: auth, platform: platform, clinic: clinic).call,
      );
}
