import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/foundation/presentation/foundation_page.dart';
import '../config/client_config_provider.dart';

/// Route paths. Feature routes are added here (or in per-feature route files
/// composed here) as each phase lands.
abstract final class AppRoutes {
  static const String home = '/';
  static const String designSystem = DesignSystemGallery.routePath;
}

/// Application router. The design-system gallery is only registered outside
/// production.
final appRouterProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(clientConfigProvider);
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const FoundationPage(),
      ),
      if (!config.environment.isProduction)
        GoRoute(
          path: AppRoutes.designSystem,
          builder: (context, state) => const DesignSystemGallery(),
        ),
    ],
  );
});
