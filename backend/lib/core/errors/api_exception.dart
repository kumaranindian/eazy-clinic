import 'package:api_contracts/api_contracts.dart';

/// Throw from any handler or service to return a controlled error response.
/// The [message] is sent to the client, so it must be safe to display and must
/// never contain internal details or personal data.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.issues = const []});

  const ApiException.badRequest(String message)
    : this(ApiErrorCode.badRequest, message);

  const ApiException.unauthenticated([
    String message = 'Authentication required.',
  ]) : this(ApiErrorCode.unauthenticated, message);

  const ApiException.forbidden([
    String message = 'You do not have access to this resource.',
  ]) : this(ApiErrorCode.forbidden, message);

  const ApiException.notFound([String message = 'Resource not found.'])
    : this(ApiErrorCode.notFound, message);

  const ApiException.conflict(String message)
    : this(ApiErrorCode.conflict, message);

  ApiException.validation(List<FieldIssue> issues)
    : this(
        ApiErrorCode.validationFailed,
        'The request is invalid.',
        issues: issues,
      );

  final ApiErrorCode code;
  final String message;
  final List<FieldIssue> issues;

  @override
  String toString() => 'ApiException(${code.wireName}): $message';
}
