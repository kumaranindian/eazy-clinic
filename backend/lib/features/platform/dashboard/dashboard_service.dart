import '../../../core/data/document_store.dart';
import '../audit/audit_service.dart';
import '../common/paging.dart';
import '../plans/plan_service.dart';

/// Platform dashboard: counts and recent items only. No patient or clinical
/// data exists in the queried collections.
class DashboardService {
  DashboardService(this._store, this._audit, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final DateTime Function() _clock;

  Future<int> _count(
    String collection, [
    List<QueryFilter> filters = const [],
  ]) => _store.count(DocQuery(collection, filters: filters));

  QueryFilter _eq(String f, Object v) => QueryFilter(f, FilterOp.eq, v);

  Future<Map<String, Object?>> build() async {
    final now = _clock().toUtc();
    const apps = 'clinic_applications';
    const tenants = 'tenants';
    const subs = 'platform_subscriptions';

    Future<int> appCount(String s) => _count(apps, [_eq('status', s)]);
    Future<int> tenantCount(String s) => _count(tenants, [_eq('status', s)]);
    Future<int> subCount(String s) => _count(subs, [_eq('status', s)]);
    Future<int> lapsed(String s) => _count(subs, [
      _eq('status', s),
      QueryFilter('endDate', FilterOp.lte, now),
    ]);

    final results = await Future.wait([
      appCount('submitted'),
      appCount('under_review'),
      appCount('additional_information_required'),
      appCount('approved'),
      appCount('rejected'),
      appCount('withdrawn'),
      tenantCount('provisioning'),
      tenantCount('active'),
      tenantCount('suspended'),
      tenantCount('closed'),
      subCount('trial'),
      subCount('active'),
      subCount('past_due'),
      subCount('expired'),
      subCount('cancelled'),
      subCount('suspended'),
      lapsed('trial'),
      lapsed('active'),
    ]);
    final submitted = results[0],
        underReview = results[1],
        infoNeeded = results[2];
    final approved = results[3], rejected = results[4], withdrawn = results[5];
    final tProvisioning = results[6],
        tActive = results[7],
        tSuspended = results[8],
        tClosed = results[9];
    final trial = results[10], active = results[11], pastDue = results[12];
    final expiredStored = results[13],
        cancelled = results[14],
        suspended = results[15];
    final lapsedTrials = results[16], lapsedActive = results[17];

    final planRows = await _store.query(
      const DocQuery(
        PlanService.collection,
        orderBy: OrderBy('createdAt', descending: true),
        limit: 100,
      ),
    );
    final distribution = await Future.wait([
      for (final p in planRows)
        _count(subs, [
          _eq('planId', p.id),
          const QueryFilter(
            'status',
            FilterOp.inList,
            PlanService.liveStatuses,
          ),
        ]).then(
          (n) => {'planId': p.id, 'name': p.data['name'], 'subscriptions': n},
        ),
    ]);

    final recentApps = await _store.query(
      const DocQuery(
        apps,
        orderBy: OrderBy('submittedAt', descending: true),
        limit: 5,
      ),
    );
    final recentTenants = await _store.query(
      const DocQuery(
        tenants,
        orderBy: OrderBy('approvedAt', descending: true),
        limit: 5,
      ),
    );

    return {
      'generatedAt': now.toIso8601String(),
      'applications': {
        'total':
            submitted +
            underReview +
            infoNeeded +
            approved +
            rejected +
            withdrawn,
        'pending': submitted + underReview,
        'additionalInformationRequired': infoNeeded,
        'approved': approved,
        'rejected': rejected,
        'withdrawn': withdrawn,
      },
      'tenants': {
        'total': tProvisioning + tActive + tSuspended + tClosed,
        'active': tActive,
        'suspended': tSuspended,
        'provisioning': tProvisioning,
        'closed': tClosed,
      },
      'subscriptions': {
        'trial': trial - lapsedTrials,
        'active': active - lapsedActive,
        'pastDue': pastDue,
        'expired': expiredStored + lapsedTrials + lapsedActive,
        'cancelled': cancelled,
        'suspended': suspended,
      },
      'planDistribution': distribution,
      // No payment data exists in Phase 2, so revenue is deliberately absent.
      'monthlyRecurringRevenue': {
        'available': false,
        'reason': 'No billing data yet.',
      },
      'recentApplications': recentApps
          .map(
            (d) => {
              'applicationId': d.id,
              'clinicName': (d.data['clinic'] as Map?)?['name'],
              'status': d.data['status'],
              'submittedAt': jsonSafe(d.data['submittedAt']),
            },
          )
          .toList(),
      'recentlyApprovedClinics': recentTenants
          .map(
            (d) => {
              'tenantId': d.id,
              'clinicName': d.data['clinicName'],
              'status': d.data['status'],
              'approvedAt': jsonSafe(d.data['approvedAt']),
            },
          )
          .toList(),
      'recentActivity': await _audit.recent(10),
    };
  }
}
