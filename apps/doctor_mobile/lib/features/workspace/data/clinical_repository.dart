import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Json = Map<String, Object?>;

/// Every call of the doctor workspace goes through here. Thin on purpose:
/// authorization, validation and clinical rules live on the backend.
class ClinicalRepository {
  ClinicalRepository(this._api);

  final ApiClient _api;

  Future<Json> getMap(String path, [Map<String, String>? query]) async =>
      (await _api.get(path, query: query)).map;

  Future<List<Json>> getList(String path, [Map<String, String>? query]) async =>
      (await _api.get(path, query: query)).list;

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
      _ => throw ArgumentError('Unsupported method $method'),
    };
    return r.data is Map ? r.map : const {};
  }
}

/// Overridden in tests.
final clinicalRepositoryProvider = Provider<ClinicalRepository>(
  (ref) => ClinicalRepository(ref.watch(apiClientProvider)),
);
