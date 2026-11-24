import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart' show noRetry;

/// The clinic's compliance dashboard.
final complianceDashboardProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).complianceDashboard(),
);

final complianceCredentialsProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).complianceCredentials(),
);

/// Platform overview, registers and review queue.
final complianceOverviewProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).complianceOverview(),
);

final complianceProfilesProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).complianceProfiles(),
);

final complianceReviewQueueProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).complianceReviewQueue(),
);

/// One clinic's compliance, as seen by a platform reviewer.
final platformComplianceTenantProvider = FutureProvider.autoDispose
    .family<Json, String>(
      retry: noRetry,
      (ref, tenantId) => ref
          .watch(controlPlaneRepositoryProvider)
          .platformComplianceTenant(tenantId),
    );

final platformComplianceCredentialsProvider = FutureProvider.autoDispose
    .family<List<Json>, String>(
      retry: noRetry,
      (ref, tenantId) => ref
          .watch(controlPlaneRepositoryProvider)
          .platformComplianceCredentials(tenantId),
    );
