import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/portal_repository.dart';

Duration? _noRetry(int retryCount, Object error) => null;

/// One request: a path plus parameters (comparable, so it works as a key).
class Query {
  Query(this.path, [Map<String, String> params = const {}])
    : params = Map.unmodifiable(
        Map.fromEntries(
          params.entries.where((e) => e.value.isNotEmpty).toList()
            ..sort((a, b) => a.key.compareTo(b.key)),
        ),
      );

  final String path;
  final Map<String, String> params;

  @override
  bool operator ==(Object other) =>
      other is Query && other.path == path && '${other.params}' == '$params';

  @override
  int get hashCode => Object.hash(path, '$params');
}

final mapProvider = FutureProvider.autoDispose.family<Json, Query>(
  retry: _noRetry,
  (ref, q) => ref.watch(portalRepositoryProvider).getMap(q.path, q.params),
);

final stringsProvider = FutureProvider.autoDispose.family<List<String>, Query>(
  retry: _noRetry,
  (ref, q) => ref.watch(portalRepositoryProvider).getStrings(q.path, q.params),
);

final listProvider = FutureProvider.autoDispose.family<List<Json>, Query>(
  retry: _noRetry,
  (ref, q) => ref.watch(portalRepositoryProvider).getList(q.path, q.params),
);

String newIdempotencyKey() =>
    'pat-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Refreshes every workspace read after a change.
void refreshAll(WidgetRef ref) {
  ref
    ..invalidate(mapProvider)
    ..invalidate(listProvider);
}

/// Which person the lists show: `null` is the signed-in patient, otherwise a
/// family member the backend lets them act for. A selector, never a grant.
class SelectedPerson extends Notifier<String?> {
  @override
  String? build() => null;

  // ignore: use_setters_to_change_properties
  void select(String? accountId) => state = accountId;
}

final selectedPersonProvider = NotifierProvider<SelectedPerson, String?>(
  SelectedPerson.new,
);

/// Adds the selected person to a request, when it is not the caller.
Map<String, String> forPerson(
  String? accountId, [
  Map<String, String> more = const {},
]) => {...more, if (accountId != null) 'accountId': accountId};
