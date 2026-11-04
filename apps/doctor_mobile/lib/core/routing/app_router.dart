import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_page.dart';
import '../../features/shell/doctor_shell.dart';
import '../../features/workspace/presentation/consultation_page.dart';
import '../../features/workspace/presentation/patient_pages.dart';
import '../../features/workspace/presentation/prescription_page.dart';
import '../../features/workspace/presentation/workspace_pages.dart';
import '../config/client_config_provider.dart';

/// App route paths. Authentication routes (/login, /forgot-password, ...)
/// come from `app_core`.
abstract final class AppRoutes {
  static const String home = '/';
  static const String account = '/account';
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
    publicPaths: {if (!config.environment.isProduction) AppRoutes.designSystem},
    registrationEnabled: false,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            DoctorShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (c, s) => const DashboardPage()),
          GoRoute(path: '/today', builder: (c, s) => const TodayPage()),
          GoRoute(path: '/queue', builder: (c, s) => const QueuePage()),
          GoRoute(path: '/followups', builder: (c, s) => const FollowupsPage()),
          GoRoute(
            path: '/patients',
            builder: (c, s) => const PatientSearchPage(),
          ),
          GoRoute(
            path: '/patients/:id',
            builder: (c, s) =>
                PatientClinicalPage(patientId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/consultations/:id',
            builder: (c, s) =>
                ConsultationPage(consultationId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/prescriptions/:id',
            builder: (c, s) =>
                PrescriptionPage(prescriptionId: s.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.account, builder: (c, s) => const HomePage()),
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
