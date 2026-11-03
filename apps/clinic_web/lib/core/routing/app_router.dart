import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/presentation/apply_page.dart';
import '../../features/onboarding/presentation/my_applications_pages.dart';
import '../../features/platform/applications_pages.dart';
import '../../features/platform/audit_page.dart';
import '../../features/platform/dashboard_page.dart';
import '../../features/platform/plans_pages.dart';
import '../../features/platform/platform_shell.dart';
import '../../features/platform/subscriptions_pages.dart';
import '../../features/platform/tenants_pages.dart';
import '../../features/shared/app_frame.dart';
import '../../features/tenant/clinic_home_page.dart';
import '../config/client_config_provider.dart';

/// App route paths. Authentication routes (/login, /forgot-password, ...)
/// come from `app_core`.
abstract final class AppRoutes {
  static const String home = '/';
  static const String apply = '/apply';
  static const String applications = '/applications';
  static const String clinic = '/clinic';
  static const String platform = '/platform';
  static const String designSystem = DesignSystemGallery.routePath;
}

/// Role-aware landing and guard. This only decides which screen to *show*;
/// every API call is authorized by the backend from server-side records.
String? clinicWebRedirect(AuthState auth, Uri location) {
  if (auth is! Authenticated) return null;
  final session = auth.session;
  final path = location.path;
  final isPlatform = session.platformRole != null;
  final hasClinic = session.memberships.isNotEmpty;
  // Redirect straight to the destination (a redirect to '/' would need a
  // second pass).
  final landing = isPlatform
      ? AppRoutes.platform
      : hasClinic
      ? AppRoutes.clinic
      : AppRoutes.applications;
  if (path == AppRoutes.home) return landing;
  if (path.startsWith(AppRoutes.platform) && !isPlatform) return landing;
  if (path.startsWith(AppRoutes.clinic) && !hasClinic) return landing;
  return null;
}

/// Application router. The design-system gallery is only registered (and
/// public) outside production.
final appRouterProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(clientConfigProvider);
  return buildAuthAwareRouter(
    ref,
    home: AppRoutes.home,
    publicPaths: {if (!config.environment.isProduction) AppRoutes.designSystem},
    appRedirect: clinicWebRedirect,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Scaffold(body: EcLoadingIndicator()),
      ),
      ShellRoute(
        builder: (context, state, child) => AppFrame(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.apply,
            builder: (context, state) => const ApplyPage(),
          ),
          GoRoute(
            path: AppRoutes.applications,
            builder: (context, state) => const MyApplicationsPage(),
          ),
          GoRoute(
            path: '${AppRoutes.applications}/:id',
            builder: (context, state) => MyApplicationDetailPage(
              applicationId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: AppRoutes.clinic,
            builder: (context, state) => const ClinicHomePage(),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) =>
            PlatformShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.platform,
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/platform/applications',
            builder: (context, state) => const ApplicationsPage(),
          ),
          GoRoute(
            path: '/platform/applications/:id',
            builder: (context, state) => ApplicationDetailPage(
              applicationId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/platform/tenants',
            builder: (context, state) => const TenantsPage(),
          ),
          GoRoute(
            path: '/platform/tenants/:id',
            builder: (context, state) =>
                TenantDetailPage(tenantId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/platform/plans',
            builder: (context, state) => const PlansPage(),
          ),
          GoRoute(
            path: '/platform/plans/new',
            builder: (context, state) => const PlanFormPage(),
          ),
          GoRoute(
            path: '/platform/plans/:id',
            builder: (context, state) =>
                PlanDetailPage(planId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/platform/plans/:id/edit',
            builder: (context, state) =>
                PlanFormPage(planId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/platform/subscriptions',
            builder: (context, state) => const SubscriptionsPage(),
          ),
          GoRoute(
            path: '/platform/subscriptions/:id',
            builder: (context, state) => SubscriptionDetailPage(
              subscriptionId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/platform/audit',
            builder: (context, state) => const AuditPage(),
          ),
        ],
      ),
      if (!config.environment.isProduction)
        GoRoute(
          path: AppRoutes.designSystem,
          builder: (context, state) => const DesignSystemGallery(),
        ),
    ],
  );
});
