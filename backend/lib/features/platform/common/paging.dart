import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';

const int defaultPageSize = 25;
const int maxPageSize = 100;

/// `?limit=` clamped to 1..[maxPageSize]; invalid → 400.
int readLimit(Request request) {
  final raw = request.url.queryParameters['limit'];
  if (raw == null) return defaultPageSize;
  final n = int.tryParse(raw);
  if (n == null || n < 1 || n > maxPageSize) {
    throw const ApiException.badRequest('limit must be between 1 and 100.');
  }
  return n;
}

String encodeCursor(PageCursor c) {
  final v = c.orderValue;
  final json = {
    'v': v is DateTime ? v.toUtc().toIso8601String() : v,
    'k': v is DateTime ? 't' : 'p',
    'i': c.docId,
  };
  return base64Url.encode(utf8.encode(jsonEncode(json)));
}

PageCursor? decodeCursor(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final m = jsonDecode(utf8.decode(base64Url.decode(raw))) as Map;
    final v = m['k'] == 't' ? DateTime.parse(m['v'] as String).toUtc() : m['v'];
    return PageCursor(v, m['i'] as String);
  } on Object {
    throw const ApiException.badRequest('cursor is invalid.');
  }
}

class Paged {
  const Paged(this.docs, this.meta);
  final List<StoredDoc> docs;
  final PageMeta meta;
}

/// Runs [base] with cursor pagination taken from the request. [base] must
/// have an [OrderBy]; the page boundary is derived from that field.
Future<Paged> runPaged(
  DocumentStore store,
  DocQuery base,
  Request request,
) async {
  final limit = readLimit(request);
  final cursor = decodeCursor(request.url.queryParameters['cursor']);
  final rows = await store.query(
    DocQuery(
      base.collection,
      filters: base.filters,
      orderBy: base.orderBy,
      limit: limit + 1,
      after: cursor,
      collectionGroup: base.collectionGroup,
    ),
  );
  final hasMore = rows.length > limit;
  final page = hasMore ? rows.sublist(0, limit) : rows;
  String? next;
  if (hasMore) {
    final last = page.last;
    next = encodeCursor(PageCursor(last.data[base.orderBy!.field], last.id));
  }
  return Paged(
    page,
    PageMeta(limit: limit, hasMore: hasMore, nextCursor: next),
  );
}

/// Recursively converts values to JSON-safe form (DateTime → ISO-8601).
Object? jsonSafe(Object? v) {
  if (v is DateTime) return v.toUtc().toIso8601String();
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: jsonSafe(e.value)};
  }
  if (v is List) return v.map(jsonSafe).toList();
  return v;
}
