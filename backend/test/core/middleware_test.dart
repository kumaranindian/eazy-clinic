import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:backend/core/errors/api_exception.dart';
import 'package:backend/core/logging/app_logger.dart';
import 'package:backend/core/middleware/cors_middleware.dart';
import 'package:backend/core/middleware/error_handler_middleware.dart';
import 'package:backend/core/middleware/request_id_middleware.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Future<Map<String, Object?>> _json(Response r) async =>
    (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

void main() {
  group('error handler', () {
    test('maps ApiException to its code and message', () async {
      final handler = Pipeline()
          .addMiddleware(requestIdMiddleware())
          .addMiddleware(errorHandlerMiddleware(AppLogger(sink: (_) {})))
          .addHandler((_) => throw const ApiException.forbidden());
      final response = await handler(Request('GET', Uri.parse('http://x/a')));
      expect(response.statusCode, 403);
      expect(((await _json(response))['error']! as Map)['code'], 'forbidden');
    });

    test(
      'hides internals of unexpected exceptions and logs only the type',
      () async {
        final logs = <String>[];
        final handler = Pipeline()
            .addMiddleware(requestIdMiddleware())
            .addMiddleware(errorHandlerMiddleware(AppLogger(sink: logs.add)))
            .addHandler(
              (_) => throw StateError('patient Ravi Kumar secret detail'),
            );
        final response = await handler(Request('GET', Uri.parse('http://x/a')));
        expect(response.statusCode, 500);
        final raw = await response.readAsString();
        expect(raw, isNot(contains('Ravi')));
        expect(raw, isNot(contains('StateError')));
        expect(raw, isNot(contains('#0')));
        expect(logs.single, contains('StateError'));
        expect(logs.single, isNot(contains('Ravi')));
      },
    );

    test('validation errors list every field issue', () async {
      final handler = Pipeline()
          .addMiddleware(requestIdMiddleware())
          .addMiddleware(errorHandlerMiddleware(AppLogger(sink: (_) {})))
          .addHandler(
            (_) => throw ApiException.validation(const [
              FieldIssue(field: 'a', code: 'required', message: 'A required'),
              FieldIssue(field: 'b', code: 'required', message: 'B required'),
            ]),
          );
      final response = await handler(Request('POST', Uri.parse('http://x/a')));
      expect(response.statusCode, 422);
      final issues =
          ((await _json(response))['error']! as Map)['issues'] as List;
      expect(issues, hasLength(2));
    });
  });

  group('CORS', () {
    Handler build() => Pipeline()
        .addMiddleware(corsMiddleware(['https://clinic.example.com']))
        .addHandler((_) => Response.ok('ok'));

    test('allows configured origins only', () async {
      final ok = await build()(
        Request(
          'GET',
          Uri.parse('http://x/a'),
          headers: {'origin': 'https://clinic.example.com'},
        ),
      );
      expect(
        ok.headers['access-control-allow-origin'],
        'https://clinic.example.com',
      );

      final denied = await build()(
        Request(
          'GET',
          Uri.parse('http://x/a'),
          headers: {'origin': 'https://evil.example.com'},
        ),
      );
      expect(
        denied.headers.containsKey('access-control-allow-origin'),
        isFalse,
      );
    });

    test('answers preflight for allowed origin and rejects others', () async {
      final ok = await build()(
        Request(
          'OPTIONS',
          Uri.parse('http://x/a'),
          headers: {'origin': 'https://clinic.example.com'},
        ),
      );
      expect(ok.statusCode, 204);
      final denied = await build()(
        Request(
          'OPTIONS',
          Uri.parse('http://x/a'),
          headers: {'origin': 'https://evil.example.com'},
        ),
      );
      expect(denied.statusCode, 403);
    });
  });
}
