/// Cursor-based pagination metadata (a good fit for Firestore queries).
class PageMeta {
  const PageMeta({required this.limit, required this.hasMore, this.nextCursor});

  factory PageMeta.fromJson(Map<String, Object?> json) => PageMeta(
    limit: json['limit']! as int,
    hasMore: json['hasMore']! as bool,
    nextCursor: json['nextCursor'] as String?,
  );

  final int limit;
  final bool hasMore;

  /// Opaque cursor; pass it back as `?cursor=` to fetch the next page.
  final String? nextCursor;

  Map<String, Object?> toJson() => {
    'limit': limit,
    'hasMore': hasMore,
    if (nextCursor != null) 'nextCursor': nextCursor,
  };
}
