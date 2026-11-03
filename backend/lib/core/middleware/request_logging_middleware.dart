import 'package:shelf/shelf.dart';

import '../logging/app_logger.dart';
import '../responses/responses.dart';

/// Logs one structured line per request.
///
/// Deliberately excludes the query string (it may hold phone numbers or names
/// from patient search), headers and bodies.
Middleware requestLoggingMiddleware(AppLogger logger) {
  return (inner) => (request) async {
    final stopwatch = Stopwatch()..start();
    final response = await inner(request);
    stopwatch.stop();
    logger.info('request', {
      'requestId': requestIdOf(request),
      'method': request.method,
      'path': '/${request.url.path}',
      'status': response.statusCode,
      'durationMs': stopwatch.elapsedMilliseconds,
    });
    return response;
  };
}
