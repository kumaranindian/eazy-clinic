import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';

import '../errors/api_exception.dart';
import '../logging/app_logger.dart';
import '../responses/responses.dart';

/// Converts every exception into the standard error envelope.
///
/// - [ApiException] → its own code and safe message.
/// - Anything else → 500 with a generic message. The exception type is logged
///   (with the request id) but its message and stack trace are never sent to
///   the client, because they can contain personal data or internals.
Middleware errorHandlerMiddleware(AppLogger logger) {
  return (inner) => (request) async {
    try {
      return await inner(request);
    } on ApiException catch (e) {
      return failure(request, e.code, e.message, issues: e.issues);
    } on HijackException {
      rethrow;
    } on Object catch (e) {
      logger.error('unhandled_exception', {
        'requestId': requestIdOf(request),
        'exceptionType': e.runtimeType.toString(),
      });
      return failure(
        request,
        ApiErrorCode.internalError,
        'An unexpected error occurred.',
      );
    }
  };
}
