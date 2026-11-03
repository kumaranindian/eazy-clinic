import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';

import '../responses/responses.dart';
import '../security/rate_limiter.dart';

/// Rejects requests with 429 once [limiter] is exceeded for the key returned
/// by [keyOf]. Sensitive endpoints should use a tight limiter.
Middleware rateLimitMiddleware(
  RateLimiter limiter,
  String Function(Request request) keyOf, {
  void Function(Request request)? onLimited,
}) {
  return (inner) => (request) {
    final wait = limiter.hit(keyOf(request));
    if (wait != null) {
      onLimited?.call(request);
      final seconds = (wait.inMilliseconds / 1000).ceil().clamp(1, 3600);
      return failure(
        request,
        ApiErrorCode.rateLimited,
        'Too many requests. Please try again shortly.',
      ).change(headers: {'retry-after': '$seconds'});
    }
    return inner(request);
  };
}

/// Client key for pre-authentication limiting. Behind a trusted proxy the
/// last `X-Forwarded-For` entry (appended by the proxy) is used; otherwise the
/// socket address. Never trust the first entry: clients can forge it.
String clientKeyOf(Request request, {required bool trustForwardedFor}) {
  if (trustForwardedFor) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.trim().isNotEmpty) {
      return forwarded.split(',').last.trim();
    }
  }
  final connection = request.context['shelf.io.connection_info'];
  if (connection != null) {
    // HttpConnectionInfo.remoteAddress; accessed dynamically to keep this
    // layer free of dart:io.
    try {
      return (connection as dynamic).remoteAddress.address as String;
    } on Object {
      return 'unknown';
    }
  }
  return 'unknown';
}
