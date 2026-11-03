import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/auth_state.dart';
import '../presentation/auth_routes.dart';
import 'auth_controller.dart';
import 'auth_redirect.dart';

/// Builds an authentication-aware [GoRouter].
///
/// [routes] are the app's own routes; the shared auth routes are appended.
/// [appRedirect] adds app-specific, role-aware routing once the user is
/// authenticated. Everything not listed in [publicPaths] requires an admitted session, and
/// the router re-evaluates whenever the authentication state changes.
GoRouter buildAuthAwareRouter(
  Ref ref, {
  required List<RouteBase> routes,
  String home = '/',
  Set<String> publicPaths = const {},
  bool registrationEnabled = true,
  String? signedOutLanding,
  String? Function(AuthState auth, Uri location)? appRedirect,
}) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final redirect = authRedirect(
        auth: auth,
        location: state.uri,
        isPublic: publicPaths.contains,
        home: home,
        registrationEnabled: registrationEnabled,
        signedOutLanding: signedOutLanding,
      );
      // App-level routing is consulted only for locations the authentication
      // rules allow. When they redirect an authenticated user (e.g. off the
      // loading screen), the app rule is applied to that target right away
      // instead of relying on a second redirect pass. UX only: the backend
      // authorizes every request regardless.
      if (redirect != null) {
        if (auth is! Authenticated) return redirect;
        return appRedirect?.call(auth, Uri.parse(redirect)) ?? redirect;
      }
      return appRedirect?.call(auth, state.uri);
    },
    routes: [
      ...routes,
      ...buildAuthRoutes(registrationEnabled: registrationEnabled),
    ],
  );
}
