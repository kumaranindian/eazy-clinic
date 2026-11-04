import 'package:app_core/app_core.dart';
import 'package:patient_mobile/features/portal/data/portal_repository.dart';

typedef Handler = Object? Function(String method, String path, Json? body);

/// Records every call and answers from a handler (tests only).
class FakePortalRepository implements PortalRepository {
  FakePortalRepository(this.handler);

  final Handler handler;
  final List<(String, String, Json?)> calls = [];

  static String withQuery(String path, Map<String, String>? query) {
    final q = {...?query}..removeWhere((k, v) => v.isEmpty);
    if (q.isEmpty) return path;
    final keys = q.keys.toList()..sort();
    return '$path?${keys.map((k) => '$k=${q[k]}').join('&')}';
  }

  Object? _run(String m, String p, Json? b) {
    calls.add((m, p, b));
    return handler(m, p, b);
  }

  @override
  Future<Json> getMap(String path, [Map<String, String>? query]) async =>
      (_run('GET', withQuery(path, query), null) as Map)
          .cast<String, Object?>();

  @override
  Future<List<Json>> getList(String path, [Map<String, String>? query]) async =>
      (_run('GET', withQuery(path, query), null) as List).cast<Json>();

  @override
  Future<List<String>> getStrings(
    String path, [
    Map<String, String>? query,
  ]) async => [
    for (final e in (_run('GET', withQuery(path, query), null) as List)) '$e',
  ];

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
