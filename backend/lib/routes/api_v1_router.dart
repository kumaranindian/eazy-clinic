import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/responses/responses.dart';
import 'health_routes.dart';

/// Builds the root router.
///
/// Domain routers (auth, clinics, patients, ...) will be mounted under
/// [apiV1Prefix] by later phases, e.g.
/// `router.mount('$apiV1Prefix/clinics/', clinicsRouter.call)`.
/// Phase 0 mounts none.
Router buildRouter() {
  final router = Router(
    notFoundHandler: (Request request) =>
        failure(request, ApiErrorCode.notFound, 'Resource not found.'),
  );
  registerHealthRoutes(router);
  return router;
}
