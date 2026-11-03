import 'package:api_contracts/api_contracts.dart';

import '../../../core/data/document_store.dart';
import '../domain/access_resolver.dart';
import '../domain/platform_user.dart';

/// Resolves clinic memberships from `tenants/{tenantId}/members/{uid}` with a
/// collection-group query on trusted, server-written records. Requires the
/// collection-group index on `members.uid` + `members.status`.
class MembershipAccessResolver implements AccessResolver {
  MembershipAccessResolver(this._store);

  final DocumentStore _store;

  @override
  Future<List<MembershipSummaryDto>> membershipsFor(PlatformUser user) async {
    final rows = await _store.query(
      DocQuery(
        'members',
        collectionGroup: true,
        filters: [
          QueryFilter('uid', FilterOp.eq, user.uid),
          const QueryFilter('status', FilterOp.eq, 'active'),
        ],
        limit: 50,
      ),
    );
    final out = <MembershipSummaryDto>[];
    for (final r in rows) {
      final segs = r.path.split('/');
      // tenants/{tenantId}/members/{uid}
      if (segs.length != 4 || segs[0] != 'tenants') continue;
      out.add(
        MembershipSummaryDto(
          tenantId: segs[1],
          role: r.data['role'] as String? ?? '',
          branchIds: ((r.data['branchIds'] as List?) ?? const [])
              .whereType<String>()
              .toList(),
        ),
      );
    }
    return out;
  }
}
