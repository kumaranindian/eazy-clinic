import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/clinic_admin/access_pages.dart';
import '../../features/clinic_admin/branches_pages.dart';
import '../../features/clinic_admin/clinic_shell.dart';
import '../../features/clinic_admin/doctors_pages.dart';
import '../../features/clinic_admin/overview_pages.dart';
import '../../features/clinic_admin/settings_page.dart';
import '../../features/clinic_admin/staff_pages.dart';
import '../../features/onboarding/presentation/accept_invitation_page.dart';
import '../../features/onboarding/presentation/apply_page.dart';
import '../../features/onboarding/presentation/my_applications_pages.dart';
import '../../features/patients/patient_detail_page.dart';
import '../../features/patients/patients_pages.dart';
import '../../features/platform/applications_pages.dart';
import '../../features/platform/audit_page.dart';
import '../../features/platform/dashboard_page.dart';
import '../../features/platform/plans_pages.dart';
import '../../features/platform/platform_shell.dart';
import '../../features/platform/subscriptions_pages.dart';
import '../../features/platform/tenants_pages.dart';
import '../../features/shared/app_frame.dart';
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
            path: '/accept-invitation',
            builder: (context, state) =>
                AcceptInvitationPage(token: state.uri.queryParameters['token']),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) =>
            ClinicShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.clinic,
            builder: (context, state) => const ClinicOverviewPage(),
          ),
          GoRoute(
            path: '/clinic/profile',
            builder: (context, state) => const ClinicProfileEditPage(),
          ),
          GoRoute(
            path: '/clinic/settings',
            builder: (context, state) => const ClinicSettingsPage(),
          ),
          GoRoute(
            path: '/clinic/branches',
            builder: (context, state) => const BranchesPage(),
          ),
          GoRoute(
            path: '/clinic/branches/new',
            builder: (context, state) => const BranchFormPage(),
          ),
          GoRoute(
            path: '/clinic/branches/:id',
            builder: (context, state) =>
                BranchDetailPage(branchId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/clinic/branches/:id/edit',
            builder: (context, state) =>
                BranchFormPage(branchId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/clinic/doctors',
            builder: (context, state) => const DoctorsPage(),
          ),
          GoRoute(
            path: '/clinic/doctors/new',
            builder: (context, state) => const DoctorFormPage(),
          ),
          GoRoute(
            path: '/clinic/doctors/:id',
            builder: (context, state) =>
                DoctorDetailPage(doctorId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/clinic/doctors/:id/edit',
            builder: (context, state) =>
                DoctorFormPage(doctorId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/clinic/staff',
            builder: (context, state) => const StaffPage(),
          ),
          GoRoute(
            path: '/clinic/staff/new',
            builder: (context, state) => const StaffFormPage(),
          ),
          GoRoute(
            path: '/clinic/staff/:id',
            builder: (context, state) =>
                StaffDetailPage(staffId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/clinic/staff/:id/edit',
            builder: (context, state) =>
                StaffFormPage(staffId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/clinic/patients',
            builder: (context, state) => const PatientsPage(),
          ),
          GoRoute(
            path: '/clinic/patients/new',
            builder: (context, state) => const PatientFormPage(),
          ),
          GoRoute(
            path: '/clinic/patients/:id',
            builder: (context, state) =>
                PatientDetailPage(patientId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/clinic/patients/:id/edit',
            builder: (context, state) =>
                PatientFormPage(patientId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/clinic/invitations',
            builder: (context, state) => const InvitationsPage(),
          ),
          GoRoute(
            path: '/clinic/access',
            builder: (context, state) => const AccessPage(),
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
