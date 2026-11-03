import 'package:app_core/app_core.dart';
import 'package:doctor_mobile/features/workspace/data/clinical_repository.dart';

typedef Handler = Object? Function(String method, String path, Json? body);

/// Records every call and answers from a handler (tests only).
class FakeClinicalRepository implements ClinicalRepository {
  FakeClinicalRepository(this.handler);

  final Handler handler;
  final List<(String, String, Json?)> calls = [];

  Object? _run(String m, String p, Json? b) {
    calls.add((m, p, b));
    return handler(m, p, b);
  }

  @override
  Future<Json> getMap(String path, [Map<String, String>? query]) async =>
      (_run('GET', path, null) as Map).cast<String, Object?>();

  @override
  Future<List<Json>> getList(String path, [Map<String, String>? query]) async =>
      (_run('GET', path, null) as List).cast<Json>();

  @override
  Future<ApiResult> getPage(String path, [Map<String, String>? query]) =>
      throw UnimplementedError();

  @override
  Future<Json> send(
    String method,
    String path, [
    Json? body,
    Map<String, String>? headers,
  ]) async =>
      ((_run(method, path, body) as Map?) ?? const {}).cast<String, Object?>();
}
