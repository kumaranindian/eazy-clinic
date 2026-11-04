import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/clinical_repository.dart';

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
  (ref, q) => ref.watch(clinicalRepositoryProvider).getMap(q.path, q.params),
);

final listProvider = FutureProvider.autoDispose.family<List<Json>, Query>(
  retry: _noRetry,
  (ref, q) => ref.watch(clinicalRepositoryProvider).getList(q.path, q.params),
);

Query dashboardQuery() => Query('/doctor/dashboard');
Query consultationQuery(String id) => Query('/consultations/$id');
Query prescriptionQuery(String id) => Query('/prescriptions/$id');
Query overviewQuery(String pid) => Query('/clinical/patients/$pid/overview');
Query historyQuery(String pid) => Query('/clinical/patients/$pid/history');
Query vitalsQuery(String pid) =>
    Query('/clinical/patients/$pid/vitals', {'limit': '20'});

String newIdempotencyKey() =>
    'doc-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Refreshes every workspace read after a change.
void refreshAll(WidgetRef ref) {
  ref
    ..invalidate(mapProvider)
    ..invalidate(listProvider);
}
