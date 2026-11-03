import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart' show noRetry;

/// Doctors the caller may see (optionally of one branch).
final doctorChoicesProvider = FutureProvider.autoDispose
    .family<List<Json>, String?>(
      retry: noRetry,
      (ref, branchId) => ref.watch(controlPlaneRepositoryProvider).getList(
        '/doctors',
        {'limit': '100', 'status': 'active', 'branchId': ?branchId},
      ),
    );

final appointmentTypeChoicesProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).getList(
    '/appointment-types',
    {'limit': '100', 'status': 'active'},
  ),
);

/// One list request: path plus parameters, comparable for provider families.
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

final listProvider = FutureProvider.autoDispose.family<List<Json>, Query>(
  retry: noRetry,
  (ref, q) =>
      ref.watch(controlPlaneRepositoryProvider).getList(q.path, q.params),
);

final mapProvider = FutureProvider.autoDispose.family<Json, Query>(
  retry: noRetry,
  (ref, q) =>
      ref.watch(controlPlaneRepositoryProvider).getMap(q.path, q.params),
);

/// Pickers of the slot finder: slots of one doctor on one date.
final slotsProvider = FutureProvider.autoDispose.family<Json, Query>(
  retry: noRetry,
  (ref, q) =>
      ref.watch(controlPlaneRepositoryProvider).getMap(q.path, q.params),
);

String newIdempotencyKey() =>
    'ui-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDate(String s) => DateTime.parse('${s}T00:00:00');
