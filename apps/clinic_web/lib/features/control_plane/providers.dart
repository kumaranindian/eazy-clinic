import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/control_plane_repository.dart';

/// API failures are shown to the user (with a Retry button) instead of being
/// retried silently in the background.
Duration? noRetry(int retryCount, Object error) => null;

final dashboardProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).dashboard(),
);

final applicationDetailProvider = FutureProvider.autoDispose
    .family<Json, String>(
      (ref, id) => ref.watch(controlPlaneRepositoryProvider).application(id),
    );

final myApplicationProvider = FutureProvider.autoDispose.family<Json, String>(
  retry: noRetry,
  (ref, id) => ref.watch(controlPlaneRepositoryProvider).myApplication(id),
);

final tenantDetailProvider = FutureProvider.autoDispose.family<Json, String>(
  retry: noRetry,
  (ref, id) => ref.watch(controlPlaneRepositoryProvider).tenant(id),
);

final planDetailProvider = FutureProvider.autoDispose.family<Json, String>(
  retry: noRetry,
  (ref, id) => ref.watch(controlPlaneRepositoryProvider).plan(id),
);

final subscriptionDetailProvider = FutureProvider.autoDispose
    .family<Json, String>(
      (ref, id) => ref.watch(controlPlaneRepositoryProvider).subscription(id),
    );

final entitlementsProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).entitlements(),
);

/// Active plans, for pickers (approval, subscription assignment).
final activePlansProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) async {
    final r = await ref.watch(controlPlaneRepositoryProvider).list(
      '/platform/subscription-plans',
      {'status': 'active', 'limit': '100'},
    );
    return r.list;
  },
);

/// Platform permissions of the signed-in user, for showing/hiding controls.
/// This only shapes the UI; the backend authorizes every call itself.
final platformPermissionsProvider = Provider<Set<String>>((ref) {
  final state = ref.watch(authControllerProvider);
  if (state is! Authenticated) return const {};
  return PermissionPolicy.forPlatformRole(state.session.platformRole);
});

final platformRoleProvider = Provider<PlatformRole?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is Authenticated ? state.session.platformRole : null;
});

/// Country master for platform admins (Phase 12).
final countriesProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).countries(),
);

/// Dry-run classification of tenants without a legal country.
final backfillReportProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).backfillReport(),
);

/// Countries a new clinic may register in (onboarding selector).
final onboardableCountriesProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).onboardableCountries(),
);
