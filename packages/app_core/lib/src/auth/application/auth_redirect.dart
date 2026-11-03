import '../domain/auth_state.dart';

/// Route paths owned by the shared authentication flow.
abstract final class AuthPaths {
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String verifyEmail = '/verify-email';
  static const String starting = '/starting';
  static const String accessDenied = '/access-denied';
  static const String authError = '/auth-error';

  /// Query parameter carrying the originally requested location.
  static const String fromParam = 'from';

  static const Set<String> entry = {login, register, forgotPassword};
  static const Set<String> all = {
    login,
    register,
    forgotPassword,
    verifyEmail,
    starting,
    accessDenied,
    authError,
  };
}

/// Pure routing rules for authentication. Used by every app's GoRouter.
///
/// - While [AuthResolving], every location is held on the loading screen and
///   the requested location is remembered, so deep links survive startup.
/// - Unauthenticated users can only reach entry screens and [isPublic] paths.
///   Opening [home] sends them to [signedOutLanding] (e.g. a welcome screen)
///   when one is configured, otherwise to the sign-in screen.
/// - Accounts that are signed in but not admitted see a dedicated screen.
/// - Authenticated users are moved off auth screens to the remembered
///   location (if it is a safe internal path) or [home].
///
/// This is a UX layer only. The backend authorizes every request.
String? authRedirect({
  required AuthState auth,
  required Uri location,
  required bool Function(String path) isPublic,
  String home = '/',
  bool registrationEnabled = true,
  String? signedOutLanding,
}) {
  final path = location.path;
  final onAuthScreen = AuthPaths.all.contains(path);

  String withFrom(String target) {
    final remembered = _asSafeInternal(
      onAuthScreen
          ? location.queryParameters[AuthPaths.fromParam]
          : '$location',
    );
    return remembered == null
        ? target
        : Uri(
            path: target,
            queryParameters: {AuthPaths.fromParam: remembered},
          ).toString();
  }

  switch (auth) {
    case AuthResolving():
      return path == AuthPaths.starting ? null : withFrom(AuthPaths.starting);
    case Unauthenticated():
      if (path == AuthPaths.register && !registrationEnabled) {
        return AuthPaths.login;
      }
      if (AuthPaths.entry.contains(path) || isPublic(path)) return null;
      if (signedOutLanding != null &&
          (path == home || onAuthScreen) &&
          !AuthPaths.entry.contains(path)) {
        // Home, or a transient status screen (e.g. the startup loader).
        return signedOutLanding;
      }
      return withFrom(AuthPaths.login);
    case AuthFailed():
      return path == AuthPaths.authError ? null : AuthPaths.authError;
    case AccessDenied(:final reason):
      final target = reason == AccessDeniedReason.emailUnverified
          ? AuthPaths.verifyEmail
          : AuthPaths.accessDenied;
      return path == target ? null : target;
    case Authenticated():
      if (!onAuthScreen) return null;
      return _asSafeInternal(location.queryParameters[AuthPaths.fromParam]) ??
          home;
  }
}

/// Accepts only same-app paths (never `//host` or absolute URLs) that are not
/// themselves auth screens. Prevents open-redirect abuse of `from`.
String? _asSafeInternal(String? candidate) {
  if (candidate == null || candidate.isEmpty) return null;
  if (!candidate.startsWith('/') || candidate.startsWith('//')) return null;
  if (candidate.contains('\\') || candidate.contains('://')) return null;
  final path = Uri.tryParse(candidate)?.path;
  if (path == null || path == '/' || AuthPaths.all.contains(path)) return null;
  return candidate;
}
