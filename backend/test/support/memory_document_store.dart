import 'package:backend/core/data/document_store.dart';

/// In-memory [DocumentStore] with the same observable semantics as Firestore
/// for what the backend uses. Test double only (lives in `test/`).
class MemoryDocumentStore implements DocumentStore {
  final Map<String, DocData> docs = {};
  Future<void> _lock = Future.value();

  /// Test hook: make matching commits fail with a [StoreException].
  bool Function(List<WriteOp> ops)? failWhen;

  DocData _copy(DocData d) => {
    for (final e in d.entries) e.key: _clone(e.value),
  };

  Object? _clone(Object? v) => v is Map
      ? _copy(v.cast<String, Object?>())
      : v is List
      ? v.map(_clone).toList()
      : v;

  @override
  Future<DocData?> get(String path) async =>
      docs[path] == null ? null : _copy(docs[path]!);

  bool _inCollection(String path, DocQuery q) {
    final segs = path.split('/');
    if (q.collectionGroup) {
      return segs.length >= 2 &&
          segs.length.isEven &&
          segs[segs.length - 2] == q.collection;
    }
    final prefix = '${q.collection}/';
    return path.startsWith(prefix) &&
        !path.substring(prefix.length).contains('/');
  }

  bool _match(DocData d, QueryFilter f) {
    final v = d[f.field];
    final t = f.value;
    int cmp(Object? a, Object? b) {
      if (a is num && b is num) return a.compareTo(b);
      if (a is String && b is String) return a.compareTo(b);
      if (a is DateTime && b is DateTime) return a.compareTo(b);
      if (a is bool && b is bool) return (a ? 1 : 0) - (b ? 1 : 0);
      return a == b ? 0 : (a == null ? -1 : 1);
    }

    switch (f.op) {
      case FilterOp.eq:
        return v == t;
      case FilterOp.lt:
        return v != null && cmp(v, t) < 0;
      case FilterOp.lte:
        return v != null && cmp(v, t) <= 0;
      case FilterOp.gt:
        return v != null && cmp(v, t) > 0;
      case FilterOp.gte:
        return v != null && cmp(v, t) >= 0;
      case FilterOp.arrayContains:
        return v is List && v.contains(t);
      case FilterOp.inList:
        return t is List && t.contains(v);
    }
  }

  List<StoredDoc> _run(DocQuery q) {
    var list = docs.entries
        .where((e) => _inCollection(e.key, q))
        .where((e) => q.filters.every((f) => _match(e.value, f)))
        .map((e) => StoredDoc(e.key, _copy(e.value)))
        .toList();
    final order = q.orderBy;
    int cmpVals(Object? a, Object? b) {
      if (a is DateTime && b is DateTime) return a.compareTo(b);
      if (a is num && b is num) return a.compareTo(b);
      if (a is String && b is String) return a.compareTo(b);
      if (a == null && b == null) return 0;
      return a == null ? -1 : 1;
    }

    list.sort((a, b) {
      var c = 0;
      if (order != null) c = cmpVals(a.data[order.field], b.data[order.field]);
      if (c == 0) c = a.id.compareTo(b.id);
      return (order?.descending ?? false) ? -c : c;
    });
    final after = q.after;
    if (after != null) {
      final desc = order?.descending ?? false;
      list = list.where((d) {
        var c = 0;
        if (order != null) c = cmpVals(d.data[order.field], after.orderValue);
        if (c == 0) c = d.id.compareTo(after.docId);
        return desc ? c < 0 : c > 0;
      }).toList();
    }
    if (q.limit != null && list.length > q.limit!) {
      list = list.sublist(0, q.limit);
    }
    return list;
  }

  @override
  Future<List<StoredDoc>> query(DocQuery q) async => _run(q);

  @override
  Future<int> count(DocQuery q) async => _run(
    DocQuery(
      q.collection,
      filters: q.filters,
      collectionGroup: q.collectionGroup,
    ),
  ).length;

  /// Validates all ops first, then applies them (atomic).
  void _apply(List<WriteOp> ops) {
    if (failWhen?.call(ops) ?? false) {
      throw const StoreException('injected failure');
    }
    final staged = <String, DocData?>{};
    DocData? current(String p) => staged.containsKey(p) ? staged[p] : docs[p];
    for (final op in ops) {
      switch (op) {
        case CreateOp():
          if (current(op.path) != null) throw const AlreadyExistsException();
          staged[op.path] = _copy(op.data);
        case UpdateOp():
          final existing = current(op.path);
          if (existing == null) throw const NotFoundException();
          staged[op.path] = {...existing, ..._copy(op.fields)};
      }
    }
    staged.forEach((p, d) => docs[p] = d!);
  }

  @override
  Future<void> commit(List<WriteOp> ops) => _serial(() async => _apply(ops));

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _lock.then((_) => action());
    _lock = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(TxContext tx) body) =>
      _serial(() async {
        final ctx = _MemTx(this);
        final result = await body(ctx);
        _apply(ctx.pending);
        return result;
      });
}

class _MemTx implements TxContext {
  _MemTx(this._store);
  final MemoryDocumentStore _store;
  final List<WriteOp> pending = [];

  @override
  Future<DocData?> get(String path) => _store.get(path);

  @override
  Future<List<StoredDoc>> query(DocQuery query) => _store.query(query);

  @override
  void write(List<WriteOp> ops) => pending.addAll(ops);
}
