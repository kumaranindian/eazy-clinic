import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';

/// Identifies one list: endpoint plus filter/search parameters.
class ListQuery {
  ListQuery(this.path, [Map<String, String> params = const {}])
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
      other is ListQuery &&
      other.path == path &&
      '${other.params}' == '$params';

  @override
  int get hashCode => Object.hash(path, '$params');
}

class PagedState {
  const PagedState({
    this.items = const [],
    this.nextCursor,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  final List<Json> items;
  final String? nextCursor;
  final bool loading;
  final bool loadingMore;
  final ApiFailure? error;

  bool get hasMore => nextCursor != null;
}

/// Cursor-paginated list loader (the backend returns `meta.page.nextCursor`).
class PagedListNotifier extends Notifier<PagedState> {
  PagedListNotifier(this.query);

  final ListQuery query;

  @override
  PagedState build() {
    Future.microtask(refresh);
    return const PagedState();
  }

  Future<void> refresh() async {
    state = const PagedState();
    await _load(null);
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.loadingMore) return;
    state = PagedState(
      items: state.items,
      nextCursor: cursor,
      loading: false,
      loadingMore: true,
    );
    await _load(cursor);
  }

  Future<void> _load(String? cursor) async {
    try {
      final r = await ref.read(controlPlaneRepositoryProvider).list(
        query.path,
        {...query.params, 'limit': '20', 'cursor': ?cursor},
      );
      final more = r.page?.hasMore ?? false;
      state = PagedState(
        items: [...(cursor == null ? const <Json>[] : state.items), ...r.list],
        nextCursor: more ? r.page?.nextCursor : null,
        loading: false,
      );
    } on ApiFailure catch (e) {
      state = PagedState(items: state.items, loading: false, error: e);
    }
  }
}

final pagedListProvider = NotifierProvider.autoDispose
    .family<PagedListNotifier, PagedState, ListQuery>(PagedListNotifier.new);
