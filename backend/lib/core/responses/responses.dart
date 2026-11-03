import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};

/// Request-scoped context key holding the correlation id.
const String requestIdContextKey = 'eazyclinic.requestId';

String? requestIdOf(Request request) =>
    request.context[requestIdContextKey] as String?;

/// 200 (or [status]) success envelope.
Response ok(Request request, Object? data, {int status = 200, PageMeta? page}) {
  final envelope = ApiEnvelope.ok(
    data,
    meta: ApiMeta(requestId: requestIdOf(request), page: page),
  );
  return Response(
    status,
    body: jsonEncode(envelope.toJson()),
    headers: _jsonHeaders,
  );
}

/// Error envelope with the HTTP status implied by [code].
Response failure(
  Request request,
  ApiErrorCode code,
  String message, {
  List<FieldIssue> issues = const [],
}) {
  final envelope = ApiEnvelope.failure(
    ApiErrorBody(code: code, message: message, issues: issues),
    meta: ApiMeta(requestId: requestIdOf(request)),
  );
  return Response(
    code.httpStatus,
    body: jsonEncode(envelope.toJson()),
    headers: _jsonHeaders,
  );
}
