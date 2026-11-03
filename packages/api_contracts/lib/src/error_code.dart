/// Machine-readable error codes returned in the `error.code` field.
///
/// Clients branch on [wireName], never on the human-readable message.
enum ApiErrorCode {
  badRequest('bad_request', 400),
  validationFailed('validation_failed', 422),
  unauthenticated('unauthenticated', 401),
  forbidden('forbidden', 403),
  notFound('not_found', 404),
  methodNotAllowed('method_not_allowed', 405),
  conflict('conflict', 409),
  idempotencyConflict('idempotency_conflict', 409),
  payloadTooLarge('payload_too_large', 413),
  rateLimited('rate_limited', 429),
  internalError('internal_error', 500),
  unavailable('unavailable', 503);

  const ApiErrorCode(this.wireName, this.httpStatus);

  /// Stable value sent over the wire.
  final String wireName;

  /// HTTP status that accompanies this error.
  final int httpStatus;

  static ApiErrorCode? tryParse(String? value) {
    for (final code in values) {
      if (code.wireName == value) return code;
    }
    return null;
  }
}
