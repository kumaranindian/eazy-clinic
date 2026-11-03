import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/errors/api_exception.dart';
import '../core/responses/responses.dart';
import '../features/auth/presentation/auth_routes.dart';
import '../features/clinic/clinic_module.dart';
import '../features/platform/platform_module.dart';
import 'health_routes.dart';

/// Builds the root router.
///
/// Domain routers (auth, clinics, patients, ...) will be mounted under
/// [apiV1Prefix] by later phases, e.g.
/// `router.mount('$apiV1Prefix/clinics/', clinicsRouter.call)`.
/// Phase 1 mounts `/auth`. When authentication is not configured (dev only)
/// the auth routes answer 503 rather than being absent.
Router buildRouter({
  AuthModule? auth,
  PlatformModule? platform,
  ClinicModule? clinic,
}) {
  final router = Router(
    notFoundHandler: (Request request) =>
        failure(request, ApiErrorCode.notFound, 'Resource not found.'),
  );
  registerHealthRoutes(router);
  if (auth != null) {
    router.mount('$apiV1Prefix/auth/', auth.router.call);
  } else {
    router.all('$apiV1Prefix/auth/<ignored|.*>', (Request request) {
      throw const ApiException(
        ApiErrorCode.unavailable,
        'Authentication is not configured.',
      );
    });
  }
  clinic?.register(router);
  if (platform != null) {
    platform.register(router);
  } else {
    for (final prefix in [
      'platform',
      'clinic-applications',
      'tenants',
      if (clinic == null) ...[
        'clinics',
        'branches',
        'doctors',
        'staff',
        'invitations',
        'roles',
        'permissions',
        'members',
      ],
    ]) {
      router.all('$apiV1Prefix/$prefix/<ignored|.*>', (Request request) {
        throw const ApiException(
          ApiErrorCode.unavailable,
          'The platform is not configured.',
        );
      });
    }
  }
  return router;
}
