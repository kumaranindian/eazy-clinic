import 'error_code.dart';
import 'page_meta.dart';

/// Metadata attached to every response.
class ApiMeta {
  const ApiMeta({this.requestId, this.page});

  factory ApiMeta.fromJson(Map<String, Object?> json) => ApiMeta(
    requestId: json['requestId'] as String?,
    page: json['page'] == null
        ? null
        : PageMeta.fromJson((json['page']! as Map).cast<String, Object?>()),
  );

  final String? requestId;
  final PageMeta? page;

  Map<String, Object?> toJson() => {
    if (requestId != null) 'requestId': requestId,
    if (page != null) 'page': page!.toJson(),
  };
}

/// One field-level validation problem.
class FieldIssue {
  const FieldIssue({
    required this.field,
    required this.code,
    required this.message,
  });

  factory FieldIssue.fromJson(Map<String, Object?> json) => FieldIssue(
    field: json['field']! as String,
    code: json['code']! as String,
    message: json['message']! as String,
  );

  final String field;
  final String code;
  final String message;

  Map<String, Object?> toJson() => {
    'field': field,
    'code': code,
    'message': message,
  };
}

/// The `error` object of a failed response.
class ApiErrorBody {
  const ApiErrorBody({
    required this.code,
    required this.message,
    this.issues = const [],
  });

  factory ApiErrorBody.fromJson(Map<String, Object?> json) => ApiErrorBody(
    code:
        ApiErrorCode.tryParse(json['code'] as String?) ??
        ApiErrorCode.internalError,
    message: json['message']! as String,
    issues: ((json['issues'] as List?) ?? const [])
        .map((e) => FieldIssue.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
  );

  final ApiErrorCode code;

  /// Safe, human-readable message. Never contains stack traces or internals.
  final String message;
  final List<FieldIssue> issues;

  Map<String, Object?> toJson() => {
    'code': code.wireName,
    'message': message,
    if (issues.isNotEmpty) 'issues': issues.map((i) => i.toJson()).toList(),
  };
}

/// The single response shape used by every `/api/v1` endpoint.
///
/// Success: `{ "success": true,  "data": ..., "meta": { ... } }`
/// Failure: `{ "success": false, "error": { "code", "message", "issues" }, "meta": { ... } }`
class ApiEnvelope {
  const ApiEnvelope._({
    required this.success,
    required this.meta,
    this.data,
    this.error,
  });

  factory ApiEnvelope.ok(Object? data, {ApiMeta meta = const ApiMeta()}) =>
      ApiEnvelope._(success: true, data: data, meta: meta);

  factory ApiEnvelope.failure(
    ApiErrorBody error, {
    ApiMeta meta = const ApiMeta(),
  }) => ApiEnvelope._(success: false, error: error, meta: meta);

  factory ApiEnvelope.fromJson(Map<String, Object?> json) {
    final meta = json['meta'] == null
        ? const ApiMeta()
        : ApiMeta.fromJson((json['meta']! as Map).cast<String, Object?>());
    if (json['success'] == true) {
      return ApiEnvelope.ok(json['data'], meta: meta);
    }
    return ApiEnvelope.failure(
      ApiErrorBody.fromJson((json['error']! as Map).cast<String, Object?>()),
      meta: meta,
    );
  }

  final bool success;
  final Object? data;
  final ApiErrorBody? error;
  final ApiMeta meta;

  Map<String, Object?> toJson() => {
    'success': success,
    if (success) 'data': data else 'error': error!.toJson(),
    'meta': meta.toJson(),
  };
}
