import 'package:shelf/shelf.dart';

/// Adds conservative security headers to every API response.
Middleware securityHeadersMiddleware() {
  const headers = {
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'cache-control': 'no-store',
    'content-security-policy': "default-src 'none'; frame-ancestors 'none'",
    'strict-transport-security': 'max-age=31536000; includeSubDomains',
  };
  return (inner) => (request) async {
    final response = await inner(request);
    return response.change(
      headers: {
        for (final entry in headers.entries)
          if (!response.headers.containsKey(entry.key)) entry.key: entry.value,
      },
    );
  };
}
