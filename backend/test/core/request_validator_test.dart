import 'dart:convert';

import 'package:backend/core/errors/api_exception.dart';
import 'package:backend/core/validation/request_validator.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:validation/validation.dart';

Request _post(String body, {String contentType = 'application/json'}) =>
    Request(
      'POST',
      Uri.parse('http://x/a'),
      body: body,
      headers: {'content-type': contentType},
    );

void main() {
  test('readJsonObject parses an object body', () async {
    final body = await readJsonObject(_post(jsonEncode({'a': 1})));
    expect(body['a'], 1);
  });

  test(
    'readJsonObject rejects wrong content type, bad JSON and non-objects',
    () async {
      await expectLater(
        readJsonObject(_post('{}', contentType: 'text/plain')),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        readJsonObject(_post('{oops')),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        readJsonObject(_post('[1]')),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('readJsonObject rejects oversized bodies', () async {
    final big = jsonEncode({'x': 'a' * (maxJsonBodyBytes + 10)});
    await expectLater(readJsonObject(_post(big)), throwsA(isA<ApiException>()));
  });

  test('RequestValidator collects all issues then throws once', () {
    final v = RequestValidator({'email': 'nope', 'phone': 5});
    v.string('email', Validators.email);
    v.string('phone', Validators.indianMobile);
    expect(v.isValid, isFalse);
    try {
      v.throwIfInvalid();
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.issues.map((i) => i.field), ['email', 'phone']);
      expect(e.issues.last.code, 'invalid_type');
    }
  });

  test('RequestValidator returns trimmed values when valid', () {
    final v = RequestValidator({'email': ' a@b.co '});
    expect(v.string('email', Validators.email), 'a@b.co');
    v.throwIfInvalid();
  });
}
