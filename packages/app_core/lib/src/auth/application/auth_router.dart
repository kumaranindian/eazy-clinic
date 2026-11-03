import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/auth_routes.dart';
import 'auth_controller.dart';
import 'auth_redirect.dart';

/// Builds an authentication-aware [GoRouter].
///
/// [routes] are the app's own routes; the shared auth routes are appended.
/// Everything not listed in [publicPaths] requires an admitted session, and
/// the router re-evaluates whenever the authentication state changes.
GoRouter buildAuthAwareRouter(
  Ref ref, {
  required List<RouteBase> routes,
  String home = '/',
  Set<String> publicPaths = const {},
  bool registrationEnabled = true,
  String? signedOutLanding,
}) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: home,
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(
      auth: ref.read(authControllerProvider),
      location: state.uri,
      isPublic: publicPaths.contains,
      home: home,
      registrationEnabled: registrationEnabled,
      signedOutLanding: signedOutLanding,
    ),
    routes: [
      ...routes,
      ...buildAuthRoutes(registrationEnabled: registrationEnabled),
    ],
  );
}
