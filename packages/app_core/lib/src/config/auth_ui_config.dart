import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-app wording and options for the shared authentication screens.
class AuthUiConfig {
  const AuthUiConfig({
    required this.appName,
    required this.audienceLabel,
    required this.registrationEnabled,
    this.registrationNote,
    this.deniedHint =
        'Your account is signed in but has not been given access to this '
        'application yet.',
  });

  /// e.g. "Clinic Management".
  final String appName;

  /// Shown under the logo, e.g. "Sign in to manage your clinic".
  final String audienceLabel;
  final bool registrationEnabled;

  /// Explains what registering does and does not grant.
  final String? registrationNote;

  /// Text of the "not authorized" screen.
  final String deniedHint;
}

/// Overridden in each app's `main()`.
final authUiConfigProvider = Provider<AuthUiConfig>(
  (ref) => throw StateError('authUiConfigProvider must be overridden.'),
);
