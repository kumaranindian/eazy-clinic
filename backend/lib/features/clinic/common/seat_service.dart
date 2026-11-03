import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';

enum SeatKind {
  branches('branches'),
  doctors('doctors'),
  staff('staff');

  const SeatKind(this.wireName);
  final String wireName;
}

/// A claimed seat: the write that reserves it and the slot to remember.
class SeatClaim {
  const SeatClaim(this.slot, this.op);
  final int slot;
  final WriteOp op;
}

/// Race-free enforcement of subscription limits.
///
/// Each occupied seat is a document `tenants/{id}/seats/{kind}_{n}` created
/// with a does-not-exist precondition **in the same atomic commit** as the
/// entity it belongs to. Two concurrent requests can therefore never both take
/// the same slot, and the number of slots never exceeds the limit. Releasing a
/// seat deletes the slot. Unlimited plans (`limit == null`) use no slots.
class SeatService {
  SeatService(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final DateTime Function() _clock;

  String _path(String tenantId, SeatKind kind, int n) =>
      'tenants/$tenantId/seats/${kind.wireName}_$n';

  /// Picks a free slot or throws 403 when [limit] is reached. Returns `null`
  /// for unlimited plans. The returned op MUST be committed together with the
  /// entity; on [AlreadyExistsException] callers retry (see [withSeat]).
  Future<SeatClaim?> claim(
    String tenantId,
    SeatKind kind,
    int? limit,
    String entityId,
  ) async {
    if (limit == null) return null;
    if (limit <= 0) {
      throw const ApiException.forbidden(
        'Your subscription does not allow this.',
      );
    }
    final taken = await _store.query(
      DocQuery(
        'tenants/$tenantId/seats',
        filters: [QueryFilter('kind', FilterOp.eq, kind.wireName)],
      ),
    );
    if (taken.length >= limit) {
      throw const ApiException.forbidden(
        'Your subscription limit has been reached.',
      );
    }
    final used = {for (final d in taken) d.data['slot'] as int};
    var n = 1;
    while (used.contains(n)) {
      n++;
    }
    return SeatClaim(
      n,
      CreateOp(_path(tenantId, kind, n), {
        'kind': kind.wireName,
        'slot': n,
        'entityId': entityId,
        'createdAt': _clock().toUtc(),
      }),
    );
  }

  /// Delete op that frees [slot] (null → nothing to free).
  DeleteOp? release(String tenantId, SeatKind kind, Object? slot) =>
      slot is int ? DeleteOp(_path(tenantId, kind, slot)) : null;

  Future<int> used(String tenantId, SeatKind kind) => _store.count(
    DocQuery(
      'tenants/$tenantId/seats',
      filters: [QueryFilter('kind', FilterOp.eq, kind.wireName)],
    ),
  );

  /// Claims a seat (when the plan has a limit) and commits [build]'s writes
  /// together with it inside one transaction, retrying when another request
  /// takes the same slot. [build] runs inside the transaction and may read
  /// through `tx` to validate the entity's current state.
  Future<T> withSeat<T>({
    required String tenantId,
    required SeatKind kind,
    required int? limit,
    required String entityId,
    required Future<(T result, List<WriteOp> ops)> Function(
      TxContext tx,
      int? slot,
    )
    build,
  }) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final claimed = await claim(tenantId, kind, limit, entityId);
      try {
        return await _store.transaction((tx) async {
          final (result, ops) = await build(tx, claimed?.slot);
          tx.write([...ops, ?claimed?.op]);
          return result;
        });
      } on AlreadyExistsException {
        // another request took this slot first: pick again
      }
    }
    throw const ApiException.conflict(
      'Too many concurrent changes. Please retry.',
    );
  }
}
