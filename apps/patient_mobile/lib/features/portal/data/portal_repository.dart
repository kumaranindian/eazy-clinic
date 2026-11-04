import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Json = Map<String, Object?>;

/// Every call of the patient app goes through here. Thin on purpose:
/// identity, authorization, consent and policy live on the backend; the app
/// never decides who may see what.
class PortalRepository {
  PortalRepository(this._api);

  final ApiClient _api;

  Future<Json> getMap(String path, [Map<String, String>? query]) async =>
      (await _api.get(path, query: query)).map;

  Future<List<Json>> getList(String path, [Map<String, String>? query]) async =>
      (await _api.get(path, query: query)).list;

  /// A list of plain strings (for example specialities).
  Future<List<String>> getStrings(
    String path, [
    Map<String, String>? query,
  ]) async => [
    for (final e
        in ((await _api.get(path, query: query)).data as List?) ?? const [])
      '$e',
  ];

  /// A list with its paging information.
  Future<ApiResult> getPage(String path, [Map<String, String>? query]) =>
      _api.get(path, query: query);

  Future<Json> send(
    String method,
    String path, [
    Json? body,
    Map<String, String>? headers,
  ]) async {
    final r = switch (method) {
      'POST' => await _api.post(path, body: body, headers: headers),
      'PATCH' => await _api.patch(path, body: body),
      'PUT' => await _api.put(path, body: body),
      'DELETE' => await _api.delete(path),
      _ => throw ArgumentError('Unsupported method $method'),
    };
    return r.data is Map ? r.map : const {};
  }
}

/// Overridden in tests.
final portalRepositoryProvider = Provider<PortalRepository>(
  (ref) => PortalRepository(ref.watch(apiClientProvider)),
);
