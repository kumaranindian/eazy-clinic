import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_page.dart';
import '../config/client_config_provider.dart';

/// App route paths. Feature routes are added here (or in per-feature route
/// files composed here) as each phase lands. Authentication routes
/// (/login, /forgot-password, ...) come from `app_core`.
abstract final class AppRoutes {
  static const String home = '/';
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
    registrationEnabled: true,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
      ),
      if (!config.environment.isProduction)
        GoRoute(
          path: AppRoutes.designSystem,
          builder: (context, state) => const DesignSystemGallery(),
        ),
    ],
  );
});
