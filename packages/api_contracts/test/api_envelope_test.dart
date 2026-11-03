import 'package:api_contracts/api_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('success envelope serializes and round-trips', () {
    final envelope = ApiEnvelope.ok(
      {'status': 'ok'},
      meta: const ApiMeta(
        requestId: 'r1',
        page: PageMeta(limit: 20, hasMore: true, nextCursor: 'abc'),
      ),
    );
    final json = envelope.toJson();
    expect(json['success'], isTrue);
    expect(json.containsKey('error'), isFalse);

    final parsed = ApiEnvelope.fromJson(json);
    expect(parsed.success, isTrue);
    expect(parsed.data, {'status': 'ok'});
    expect(parsed.meta.requestId, 'r1');
    expect(parsed.meta.page!.nextCursor, 'abc');
  });

  test('failure envelope carries code, message and field issues', () {
    final envelope = ApiEnvelope.failure(
      const ApiErrorBody(
        code: ApiErrorCode.validationFailed,
        message: 'Invalid request.',
        issues: [
          FieldIssue(field: 'email', code: 'invalid', message: 'Bad email'),
        ],
      ),
      meta: const ApiMeta(requestId: 'r2'),
    );
    final json = envelope.toJson();
    expect(json['success'], isFalse);
    expect(json.containsKey('data'), isFalse);

    final parsed = ApiEnvelope.fromJson(json);
    expect(parsed.error!.code, ApiErrorCode.validationFailed);
    expect(parsed.error!.issues.single.field, 'email');
  });

  test('error codes have unique wire names and sensible statuses', () {
    expect(
      ApiErrorCode.values.map((c) => c.wireName).toSet().length,
      ApiErrorCode.values.length,
    );
    expect(ApiErrorCode.unauthenticated.httpStatus, 401);
    expect(ApiErrorCode.forbidden.httpStatus, 403);
    expect(ApiErrorCode.tryParse('nope'), isNull);
  });
}
