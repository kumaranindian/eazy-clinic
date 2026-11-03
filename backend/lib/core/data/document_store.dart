/// Storage abstraction for the backend (Firestore in production).
///
/// Values are plain Dart: `String`, `bool`, `int`, `double`, `DateTime`,
/// `null`, `List`, and `Map<String, Object?>`. Paths are slash separated
/// (`tenants/abc/members/uid`); collection paths have an odd number of
/// segments.
library;

typedef DocData = Map<String, Object?>;

class StoredDoc {
  const StoredDoc(this.path, this.data);

  final String path;
  final DocData data;

  /// Last path segment.
  String get id => path.substring(path.lastIndexOf('/') + 1);
}

class AlreadyExistsException implements Exception {
  const AlreadyExistsException();
}

class NotFoundException implements Exception {
  const NotFoundException();
}

/// Infrastructure failure. The message never contains document content.
class StoreException implements Exception {
  const StoreException(this.message);
  final String message;
  @override
  String toString() => 'StoreException: $message';
}

enum FilterOp { eq, lt, lte, gt, gte, arrayContains, inList }

class QueryFilter {
  const QueryFilter(this.field, this.op, this.value);
  final String field;
  final FilterOp op;
  final Object? value;
}

class OrderBy {
  const OrderBy(this.field, {this.descending = false});
  final String field;
  final bool descending;
}

/// Opaque position after the last returned document.
class PageCursor {
  const PageCursor(this.orderValue, this.docId);
  final Object? orderValue;
  final String docId;
}

class DocQuery {
  const DocQuery(
    this.collection, {
    this.filters = const [],
    this.orderBy,
    this.limit,
    this.after,
    this.collectionGroup = false,
  });

  /// Collection path, or just the collection id when [collectionGroup].
  final String collection;
  final List<QueryFilter> filters;

  /// At most one ordering field is supported (plus the document id as
  /// tie-breaker), which is what cursor pagination needs.
  final OrderBy? orderBy;
  final int? limit;
  final PageCursor? after;
  final bool collectionGroup;
}

sealed class WriteOp {
  const WriteOp(this.path);
  final String path;
}

/// Creates a document; the whole commit fails with [AlreadyExistsException]
/// when it already exists.
class CreateOp extends WriteOp {
  const CreateOp(super.path, this.data);
  final DocData data;
}

/// Merges [fields] into an existing document; fails with
/// [NotFoundException] when it does not exist.
class UpdateOp extends WriteOp {
  const UpdateOp(super.path, this.fields);
  final DocData fields;
}

/// Deletes a document (no error if it is already gone). Used only for
/// releasing subscription seats; business records are never deleted.
class DeleteOp extends WriteOp {
  const DeleteOp(super.path);
}

/// Reads inside a transaction; all writes commit atomically at the end.
abstract interface class TxContext {
  Future<DocData?> get(String path);
  Future<List<StoredDoc>> query(DocQuery query);

  /// Queues writes applied atomically when the transaction body completes.
  void write(List<WriteOp> ops);
}

abstract interface class DocumentStore {
  Future<DocData?> get(String path);

  Future<List<StoredDoc>> query(DocQuery query);

  Future<int> count(DocQuery query);

  /// Applies all [ops] atomically or none.
  Future<void> commit(List<WriteOp> ops);

  /// Runs [body] with serializable isolation, retrying on contention.
  Future<T> transaction<T>(Future<T> Function(TxContext tx) body);
}
