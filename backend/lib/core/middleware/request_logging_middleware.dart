import 'package:shelf/shelf.dart';

import '../logging/app_logger.dart';
import '../responses/responses.dart';

/// A request taking at least this long is logged as a warning.
const int slowRequestMs = 2000;

/// Logs one structured line per request.
///
/// Deliberately excludes the query string (it may hold phone numbers or names
/// from patient search), headers and bodies.
Middleware requestLoggingMiddleware(AppLogger logger) {
  return (inner) => (request) async {
    final stopwatch = Stopwatch()..start();
    final response = await inner(request);
    stopwatch.stop();
    final fields = {
      'requestId': requestIdOf(request),
      'method': request.method,
      'path': '/${request.url.path}',
      'status': response.statusCode,
      'durationMs': stopwatch.elapsedMilliseconds,
    };
    // Severity drives alerting: server errors are errors, slow requests are
    // warnings (the 2 s line is the latency budget's upper bound, see
    // docs/phase-11/PERFORMANCE_BASELINE.md).
    if (response.statusCode >= 500) {
      logger.error('request', fields);
    } else if (stopwatch.elapsedMilliseconds >= slowRequestMs) {
      logger.warning('request_slow', fields);
    } else {
      logger.info('request', fields);
    }
    return response;
  };
}
