import 'package:api_contracts/api_contracts.dart';

import 'auth_user.dart';

/// Why a signed-in account cannot use the app.
enum AccessDeniedReason {
  /// E-mail not verified yet.
  emailUnverified,
  suspended,
  disabled,

  /// Active account, but no role/membership grants access to this app.
  notAuthorized,
}

/// Single source of truth for authentication in the UI and router.
sealed class AuthState {
  const AuthState();
}

/// Startup: the stored session has not been checked with the backend yet.
/// Protected routes stay closed.
class AuthResolving extends AuthState {
  const AuthResolving();
}

class Unauthenticated extends AuthState {
  const Unauthenticated({this.notice});

  /// Optional explanation shown on the sign-in screen (e.g. session expired).
  final String? notice;
}

class Authenticated extends AuthState {
  const Authenticated({required this.user, required this.session});

  final AuthUser user;
  final AuthSessionDto session;
}

class AccessDenied extends AuthState {
  const AccessDenied({required this.reason, this.user});

  final AccessDeniedReason reason;
  final AuthUser? user;
}

/// The session could not be verified (offline/server error). Not signed out:
/// the user may retry.
class AuthFailed extends AuthState {
  const AuthFailed({required this.isNetwork});

  final bool isNetwork;
}
