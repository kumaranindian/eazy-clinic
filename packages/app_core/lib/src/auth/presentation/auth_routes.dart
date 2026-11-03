import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_redirect.dart';
import 'forgot_password_page.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'status_pages.dart';

/// The shared authentication routes. Every app adds these to its router.
List<RouteBase> buildAuthRoutes({bool registrationEnabled = true}) => [
  GoRoute(
    path: AuthPaths.login,
    builder: (BuildContext context, GoRouterState state) => const LoginPage(),
  ),
  if (registrationEnabled)
    GoRoute(
      path: AuthPaths.register,
      builder: (context, state) => const RegisterPage(),
    ),
  GoRoute(
    path: AuthPaths.forgotPassword,
    builder: (context, state) => const ForgotPasswordPage(),
  ),
  GoRoute(
    path: AuthPaths.verifyEmail,
    builder: (context, state) => const VerifyEmailPage(),
  ),
  GoRoute(
    path: AuthPaths.starting,
    builder: (context, state) => const AuthLoadingPage(),
  ),
  GoRoute(
    path: AuthPaths.accessDenied,
    builder: (context, state) => const AccessDeniedPage(),
  ),
  GoRoute(
    path: AuthPaths.authError,
    builder: (context, state) => const AuthErrorPage(),
  ),
];
