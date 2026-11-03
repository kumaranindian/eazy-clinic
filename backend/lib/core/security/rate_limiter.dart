/// Fixed-window in-memory rate limiter.
///
/// Per-instance only: with several Cloud Run instances the effective limit is
/// multiplied by the instance count. A shared limiter (Redis/Firestore) is
/// tracked as technical debt.
class RateLimiter {
  RateLimiter({
    required this.maxRequests,
    required this.window,
    DateTime Function()? clock,
    this.maxTrackedKeys = 10000,
  }) : _clock = clock ?? DateTime.now;

  final int maxRequests;
  final Duration window;
  final int maxTrackedKeys;
  final DateTime Function() _clock;
  final Map<String, _Bucket> _buckets = {};

  /// Counts a request for [key]. Returns `null` when allowed, otherwise the
  /// time to wait before retrying.
  Duration? hit(String key) {
    final now = _clock();
    if (_buckets.length >= maxTrackedKeys) {
      _buckets.removeWhere((_, b) => !b.resetAt.isAfter(now));
      if (_buckets.length >= maxTrackedKeys) _buckets.clear();
    }
    var bucket = _buckets[key];
    if (bucket == null || !bucket.resetAt.isAfter(now)) {
      bucket = _Bucket(now.add(window));
      _buckets[key] = bucket;
    }
    bucket.count++;
    if (bucket.count > maxRequests) return bucket.resetAt.difference(now);
    return null;
  }
}

class _Bucket {
  _Bucket(this.resetAt);
  final DateTime resetAt;
  int count = 0;
}
