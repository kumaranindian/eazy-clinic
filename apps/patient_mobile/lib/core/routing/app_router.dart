import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_page.dart';
import '../../features/onboarding/presentation/welcome_page.dart';
import '../../features/portal/presentation/account_pages.dart';
import '../../features/portal/presentation/appointments_pages.dart';
import '../../features/portal/presentation/clinics_pages.dart';
import '../../features/portal/presentation/home_page.dart';
import '../../features/portal/presentation/records_pages.dart';
import '../../features/portal/presentation/shell.dart';
import '../config/client_config_provider.dart';

/// App route paths. Feature routes are added here (or in per-feature route
/// files composed here) as each phase lands. Authentication routes
/// (/login, /forgot-password, ...) come from `app_core`.
abstract final class AppRoutes {
  static const String home = '/';
  static const String account = '/account';
  static const String welcome = '/welcome';
  static const String designSystem = DesignSystemGallery.routePath;
}

/// Application router. Everything except the paths listed in `publicPaths`
/// requires a signed-in, admitted account; the design-system gallery is only
/// registered (and public) outside production.
final appRouterProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(clientConfigProvider);
  return buildAuthAwareRouter(
    ref,
    home: AppRoutes.home,
    publicPaths: {
      AppRoutes.welcome,
      if (!config.environment.isProduction) AppRoutes.designSystem,
    },
    registrationEnabled: true,
    signedOutLanding: AppRoutes.welcome,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            PatientShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (c, s) => const PatientHomePage()),
          GoRoute(
            path: '/appointments',
            builder: (c, s) => const AppointmentsPage(),
          ),
          GoRoute(
            path: '/appointments/new',
            builder: (c, s) => BookAppointmentPage(
              clinicId: s.uri.queryParameters['clinicId'],
            ),
          ),
          GoRoute(
            path: '/appointments/:clinicId/:id',
            builder: (c, s) => AppointmentDetailPage(
              clinicId: s.pathParameters['clinicId']!,
              appointmentId: s.pathParameters['id']!,
              accountId: s.uri.queryParameters['accountId'],
            ),
          ),
          GoRoute(
            path: '/records',
            builder: (c, s) => RecordsPage(
              initialTab: s.uri.queryParameters['tab'] ?? 'overview',
            ),
          ),
          GoRoute(
            path: '/records/invoices/:clinicId/:id',
            builder: (c, s) => InvoicePage(
              clinicId: s.pathParameters['clinicId']!,
              invoiceId: s.pathParameters['id']!,
              accountId: s.uri.queryParameters['accountId'],
            ),
          ),
          GoRoute(path: '/clinics', builder: (c, s) => const ClinicsPage()),
          GoRoute(
            path: '/clinics/:id',
            builder: (c, s) =>
                ClinicDetailPage(clinicId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/profile', builder: (c, s) => const ProfilePage()),
          GoRoute(
            path: '/profile/privacy/:clinicId',
            builder: (c, s) =>
                PrivacyPage(clinicId: s.pathParameters['clinicId']!),
          ),
          GoRoute(path: '/family', builder: (c, s) => const FamilyPage()),
          GoRoute(
            path: '/notifications',
            builder: (c, s) => const NotificationsPage(),
          ),
          GoRoute(
            path: '/notifications/settings',
            builder: (c, s) => const NotificationSettingsPage(),
          ),
          GoRoute(path: AppRoutes.account, builder: (c, s) => const HomePage()),
        ],
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomePage(),
      ),
      if (!config.environment.isProduction)
        GoRoute(
          path: AppRoutes.designSystem,
          builder: (context, state) => const DesignSystemGallery(),
        ),
    ],
  );
});
