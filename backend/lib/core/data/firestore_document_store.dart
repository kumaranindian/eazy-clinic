import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'document_store.dart';
import 'firestore_codec.dart';

/// [DocumentStore] over the Firestore REST API. [client] must carry service
/// account credentials (Application Default Credentials in production;
/// "Bearer owner" against the emulator). Clients never reach Firestore.
class FirestoreDocumentStore implements DocumentStore {
  FirestoreDocumentStore({
    required this.projectId,
    required http.Client client,
    this.host = 'https://firestore.googleapis.com',
    this.maxAttempts = 5,
  }) : _client = client;

  final String projectId;
  final String host;
  final int maxAttempts;
  final http.Client _client;
  final Random _random = Random();

  static const Map<String, String> _json = {'content-type': 'application/json'};

  String get _db => 'projects/$projectId/databases/(default)';
  String get _root => '$host/v1/$_db/documents';
  String _name(String path) => '$_db/documents/$path';

  // ------------------------------------------------------------------ reads

  @override
  Future<DocData?> get(String path) => _get(path, null);

  Future<DocData?> _get(String path, String? tx) async {
    if (tx != null) {
      // batchGet is the documented way to read inside a transaction.
      final r = await _send(
        () => _client.post(
          Uri.parse('$_root:batchGet'),
          headers: _json,
          body: jsonEncode({
            'documents': [_name(path)],
            'transaction': tx,
          }),
        ),
      );
      _ensureOk(r);
      final first = (jsonDecode(r.body) as List).first as Map;
      final found = first['found'] as Map?;
      if (found == null) return null;
      return decodeFields(
        (found['fields'] as Map?)?.cast<String, Object?>() ?? const {},
      );
    }
    final r = await _send(() => _client.get(Uri.parse('$_root/$path')));
    if (r.statusCode == 404) return null;
    _ensureOk(r);
    final body = jsonDecode(r.body) as Map<String, Object?>;
    return decodeFields(
      (body['fields'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  @override
  Future<List<StoredDoc>> query(DocQuery q) => _query(q, null);

  Future<List<StoredDoc>> _query(DocQuery q, String? tx) async {
    final (parent, structured) = _structured(q);
    final r = await _send(
      () => _client.post(
        Uri.parse('$_root$parent:runQuery'),
        headers: _json,
        body: jsonEncode({
          'structuredQuery': structured,
          if (tx != null) 'transaction': tx,
        }),
      ),
    );
    _ensureOk(r);
    final out = <StoredDoc>[];
    for (final item in jsonDecode(r.body) as List) {
      final doc = (item as Map)['document'] as Map?;
      if (doc == null) continue;
      final name = doc['name']! as String;
      final path = name.substring(name.indexOf('/documents/') + 11);
      out.add(
        StoredDoc(
          path,
          decodeFields(
            (doc['fields'] as Map?)?.cast<String, Object?>() ?? const {},
          ),
        ),
      );
    }
    return out;
  }

  @override
  Future<int> count(DocQuery q) async {
    // Counting needs no ordering, cursor or limit (and Firestore rejects an
    // explicit ordering after an inequality filter on another field).
    final (parent, structured) = _structured(
      DocQuery(
        q.collection,
        filters: q.filters,
        collectionGroup: q.collectionGroup,
      ),
      ordered: false,
    );
    final r = await _send(
      () => _client.post(
        Uri.parse('$_root$parent:runAggregationQuery'),
        headers: _json,
        body: jsonEncode({
          'structuredAggregationQuery': {
            'structuredQuery': structured,
            'aggregations': [
              {'alias': 'c', 'count': <String, Object?>{}},
            ],
          },
        }),
      ),
    );
    _ensureOk(r);
    final first = (jsonDecode(r.body) as List).first as Map;
    final fields = (first['result'] as Map)['aggregateFields'] as Map;
    return int.parse((fields['c'] as Map)['integerValue'] as String);
  }

  /// Returns (parent path suffix, structuredQuery).
  (String, Map<String, Object?>) _structured(
    DocQuery q, {
    bool ordered = true,
  }) {
    String parent = '';
    String collectionId;
    if (q.collectionGroup) {
      collectionId = q.collection;
    } else {
      final segments = q.collection.split('/');
      collectionId = segments.last;
      if (segments.length > 1) {
        parent = '/${segments.sublist(0, segments.length - 1).join('/')}';
      }
    }
    const ops = {
      FilterOp.eq: 'EQUAL',
      FilterOp.lt: 'LESS_THAN',
      FilterOp.lte: 'LESS_THAN_OR_EQUAL',
      FilterOp.gt: 'GREATER_THAN',
      FilterOp.gte: 'GREATER_THAN_OR_EQUAL',
      FilterOp.arrayContains: 'ARRAY_CONTAINS',
      FilterOp.inList: 'IN',
    };
    final filters = [
      for (final f in q.filters)
        {
          'fieldFilter': {
            'field': {'fieldPath': f.field},
            'op': ops[f.op],
            'value': encodeValue(f.value),
          },
        },
    ];
    final direction = (q.orderBy?.descending ?? false)
        ? 'DESCENDING'
        : 'ASCENDING';
    final structured = <String, Object?>{
      'from': [
        {'collectionId': collectionId, 'allDescendants': q.collectionGroup},
      ],
      if (filters.length == 1) 'where': filters.first,
      if (filters.length > 1)
        'where': {
          'compositeFilter': {'op': 'AND', 'filters': filters},
        },
      // Explicit __name__ tie-breaker only when a field ordering (or a
      // cursor) is requested; otherwise Firestore applies its own default.
      if (ordered && (q.orderBy != null || q.after != null))
        'orderBy': [
          if (q.orderBy != null)
            {
              'field': {'fieldPath': q.orderBy!.field},
              'direction': direction,
            },
          {
            'field': {'fieldPath': '__name__'},
            'direction': direction,
          },
        ],
      if (q.limit != null) 'limit': q.limit,
      if (q.after != null)
        'startAt': {
          'before': false,
          'values': [
            if (q.orderBy != null) encodeValue(q.after!.orderValue),
            {'referenceValue': _name('${q.collection}/${q.after!.docId}')},
          ],
        },
    };
    return (parent, structured);
  }

  // ----------------------------------------------------------------- writes

  @override
  Future<void> commit(List<WriteOp> ops) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await _commit(ops, null);
        return;
      } on _Aborted {
        if (attempt >= maxAttempts) {
          throw const StoreException('Firestore commit kept aborting.');
        }
        await _backoff(attempt);
      }
    }
  }

  Future<void> _commit(List<WriteOp> ops, String? tx) async {
    final r = await _send(
      () => _client.post(
        Uri.parse('$_root:commit'),
        headers: _json,
        body: jsonEncode({
          'writes': ops.map(_encodeWrite).toList(),
          if (tx != null) 'transaction': tx,
        }),
      ),
    );
    if (r.statusCode == 200) return;
    final status = _errorStatus(r);
    if (status == 'ALREADY_EXISTS') throw const AlreadyExistsException();
    if (status == 'NOT_FOUND' || r.statusCode == 404) {
      throw const NotFoundException();
    }
    if (status == 'ABORTED' || r.statusCode == 409) throw _Aborted();
    throw StoreException('Firestore commit failed (${r.statusCode}).');
  }

  Map<String, Object?> _encodeWrite(WriteOp op) => switch (op) {
    CreateOp() => {
      'update': {'name': _name(op.path), 'fields': encodeFields(op.data)},
      'currentDocument': {'exists': false},
    },
    DeleteOp() => {'delete': _name(op.path)},
    UpdateOp() => {
      'update': {'name': _name(op.path), 'fields': encodeFields(op.fields)},
      'updateMask': {'fieldPaths': op.fields.keys.map(_fieldPath).toList()},
      'currentDocument': {'exists': true},
    },
  };

  static final RegExp _simple = RegExp(r'^[A-Za-z_][A-Za-z_0-9]*$');
  String _fieldPath(String key) =>
      _simple.hasMatch(key) ? key : '`${key.replaceAll('`', r'\`')}`';

  @override
  Future<T> transaction<T>(Future<T> Function(TxContext tx) body) async {
    for (var attempt = 1; ; attempt++) {
      final begin = await _send(
        () => _client.post(
          Uri.parse('$_root:beginTransaction'),
          headers: _json,
          body: jsonEncode({
            'options': {'readWrite': <String, Object?>{}},
          }),
        ),
      );
      _ensureOk(begin);
      final txId = (jsonDecode(begin.body) as Map)['transaction']! as String;
      final ctx = _Tx(this, txId);
      try {
        final T result;
        try {
          result = await body(ctx);
        } on Object {
          // Release the read locks right away; otherwise they linger until
          // the transaction times out and block unrelated requests.
          await _rollback(txId);
          rethrow;
        }
        await _commit(ctx.pending, txId);
        return result;
      } on _Aborted {
        if (attempt >= maxAttempts) {
          throw const StoreException('Firestore transaction kept aborting.');
        }
        await _backoff(attempt);
      }
    }
  }

  Future<void> _rollback(String txId) async {
    try {
      await _client.post(
        Uri.parse('$_root:rollback'),
        headers: _json,
        body: jsonEncode({'transaction': txId}),
      );
    } on Object {
      // best effort: the transaction expires on its own
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _backoff(int attempt) => Future<void>.delayed(
    Duration(milliseconds: 20 * attempt + _random.nextInt(30)),
  );

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on Object {
      throw const StoreException('Firestore is unreachable.');
    }
  }

  String? _errorStatus(http.Response r) {
    try {
      return ((jsonDecode(r.body) as Map)['error'] as Map?)?['status']
          as String?;
    } on Object {
      return null;
    }
  }

  /// Errors never include response bodies (they can echo document content).
  void _ensureOk(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      if (_errorStatus(r) == 'ABORTED') throw _Aborted();
      throw StoreException('Firestore request failed (${r.statusCode}).');
    }
  }
}

class _Aborted implements Exception {}

class _Tx implements TxContext {
  _Tx(this._store, this._id);
  final FirestoreDocumentStore _store;
  final String _id;
  final List<WriteOp> pending = [];

  @override
  Future<DocData?> get(String path) => _store._get(path, _id);

  @override
  Future<List<StoredDoc>> query(DocQuery query) => _store._query(query, _id);

  @override
  void write(List<WriteOp> ops) => pending.addAll(ops);
}
