import 'package:shelf/shelf.dart';

/// CORS for the Flutter Web apps. Only exact origins from configuration are
/// allowed; there is no wildcard. Requests from other origins receive no CORS
/// headers, so browsers block them.
Middleware corsMiddleware(List<String> allowedOrigins) {
  final allowed = allowedOrigins.toSet();
  return (inner) => (request) async {
    final origin = request.headers['origin'];
    final isAllowed = origin != null && allowed.contains(origin);

    if (request.method == 'OPTIONS' && origin != null) {
      return Response(
        isAllowed ? 204 : 403,
        headers: {
          if (isAllowed) ..._corsHeaders(origin),
          if (isAllowed) 'access-control-max-age': '600',
        },
      );
    }

    final response = await inner(request);
    if (!isAllowed) return response;
    return response.change(headers: _corsHeaders(origin));
  };
}

Map<String, String> _corsHeaders(String origin) => {
  'access-control-allow-origin': origin,
  'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'access-control-allow-headers':
      'authorization, content-type, idempotency-key',
  'access-control-expose-headers': 'x-request-id',
  'vary': 'Origin',
};
