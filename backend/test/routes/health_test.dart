import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../core/helpers.dart';

Future<Map<String, Object?>> _json(Response r) async =>
    (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

void main() {
  test('GET /health returns the standard success envelope', () async {
    final app = buildTestApp();
    final response = await app.handler(
      Request('GET', Uri.parse('http://localhost/health')),
    );
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('application/json'));

    final body = await _json(response);
    expect(body['success'], isTrue);
    expect((body['data']! as Map)['status'], 'ok');
    expect((body['meta']! as Map)['requestId'], isNotEmpty);
  });

  test(
    'health response exposes no environment or infrastructure details',
    () async {
      final app = buildTestApp(
        testConfig({'FIREBASE_PROJECT_ID': 'my-secret-proj'}),
      );
      final response = await app.handler(
        Request('GET', Uri.parse('http://localhost/health')),
      );
      final raw = await response.readAsString();
      expect(raw, isNot(contains('my-secret-proj')));
      expect(raw, isNot(contains('dev')));
      expect(raw, isNot(contains('firebase')));
    },
  );

  test('unknown routes return a 404 error envelope', () async {
    final app = buildTestApp();
    final response = await app.handler(
      Request('GET', Uri.parse('http://localhost/api/v1/nothing')),
    );
    expect(response.statusCode, 404);
    final body = await _json(response);
    expect(body['success'], isFalse);
    expect((body['error']! as Map)['code'], ApiErrorCode.notFound.wireName);
  });

  test('responses carry request id and security headers', () async {
    final app = buildTestApp();
    final response = await app.handler(
      Request(
        'GET',
        Uri.parse('http://localhost/health'),
        headers: {requestIdHeader: 'client-supplied'},
      ),
    );
    expect(response.headers[requestIdHeader], isNotEmpty);
    expect(response.headers[requestIdHeader], isNot('client-supplied'));
    expect(response.headers['x-content-type-options'], 'nosniff');
    expect(response.headers['cache-control'], 'no-store');
    expect(response.headers['x-frame-options'], 'DENY');
  });

  test('request log line has no query string and is valid JSON', () async {
    final app = buildTestApp();
    await app.handler(
      Request('GET', Uri.parse('http://localhost/health?phone=9876543210')),
    );
    final line = app.logs.single;
    expect(line, isNot(contains('9876543210')));
    final entry = jsonDecode(line) as Map;
    expect(entry['path'], '/health');
    expect(entry['status'], 200);
  });
}
