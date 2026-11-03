import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:validation/validation.dart';

import '../errors/api_exception.dart';

/// Maximum accepted JSON body size (bytes). Larger bodies get 413.
const int maxJsonBodyBytes = 256 * 1024;

/// Reads and parses a JSON object body, enforcing content type and size.
Future<Map<String, Object?>> readJsonObject(
  Request request, {
  int maxBytes = maxJsonBodyBytes,
}) async {
  final contentType = request.headers['content-type'] ?? '';
  if (!contentType.toLowerCase().startsWith('application/json')) {
    throw const ApiException.badRequest(
      'Content-Type must be application/json.',
    );
  }
  final declared = request.contentLength;
  if (declared != null && declared > maxBytes) {
    throw const ApiException(
      ApiErrorCode.payloadTooLarge,
      'Request body is too large.',
    );
  }

  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) {
      throw const ApiException(
        ApiErrorCode.payloadTooLarge,
        'Request body is too large.',
      );
    }
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const ApiException.badRequest('Request body is not valid JSON.');
  }
  if (decoded is! Map) {
    throw const ApiException.badRequest('Request body must be a JSON object.');
  }
  return decoded.cast<String, Object?>();
}

/// Collects field problems, then throws one 422 response listing all of them.
///
/// ```dart
/// final v = RequestValidator(body);
/// final email = v.string('email', Validators.email);
/// v.throwIfInvalid();
/// ```
class RequestValidator {
  RequestValidator(this.body);

  final Map<String, Object?> body;
  final List<FieldIssue> _issues = [];

  /// Reads a string field and applies [validator]. Returns the trimmed value
  /// (empty string when absent or invalid; always call [throwIfInvalid]).
  String string(String field, FieldValidator validator) {
    final raw = body[field];
    if (raw != null && raw is! String) {
      _issues.add(
        FieldIssue(
          field: field,
          code: 'invalid_type',
          message: '$field must be a string.',
        ),
      );
      return '';
    }
    final value = raw as String?;
    final failure = validator(value);
    if (failure != null) {
      _issues.add(
        FieldIssue(field: field, code: failure.code, message: failure.message),
      );
      return '';
    }
    return value?.trim() ?? '';
  }

  bool get isValid => _issues.isEmpty;

  void throwIfInvalid() {
    if (_issues.isNotEmpty) throw ApiException.validation(List.of(_issues));
  }
}
