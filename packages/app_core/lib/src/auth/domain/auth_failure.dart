import '../../../l10n/generated/app_localizations.dart';

/// Reasons an authentication action can fail, independent of Firebase.
enum AuthFailureCode {
  invalidCredentials,
  accountDisabled,
  emailInUse,
  weakPassword,
  invalidEmail,
  tooManyRequests,
  network,
  requiresRecentLogin,
  unknown,
}

/// A failed authentication action with a message that is safe to display.
class AuthFailure implements Exception {
  const AuthFailure(this.code);

  final AuthFailureCode code;

  /// Deliberately generic for credential errors: the same text for "wrong
  /// password" and "no such user" so accounts cannot be enumerated.
  String get message => switch (code) {
    AuthFailureCode.invalidCredentials =>
      'The email or password is incorrect. Please try again.',
    AuthFailureCode.accountDisabled =>
      'This account has been disabled. Please contact support.',
    AuthFailureCode.emailInUse =>
      'An account with this email may already exist. Try signing in or '
          'resetting your password.',
    AuthFailureCode.weakPassword =>
      'Please choose a stronger password (8+ characters with letters and '
          'numbers).',
    AuthFailureCode.invalidEmail => 'Please enter a valid email address.',
    AuthFailureCode.tooManyRequests =>
      'Too many attempts. Please wait a few minutes and try again.',
    AuthFailureCode.network =>
      'Cannot reach the server. Check your internet connection and try again.',
    AuthFailureCode.requiresRecentLogin =>
      'For your security, please sign in again to continue.',
    AuthFailureCode.unknown => 'Something went wrong. Please try again.',
  };

  /// The same safe texts as [message], in the user's language.
  String localized(AppLocalizations l10n) => switch (code) {
    AuthFailureCode.invalidCredentials => l10n.authInvalidCredentials,
    AuthFailureCode.accountDisabled => l10n.authAccountDisabled,
    AuthFailureCode.emailInUse => l10n.authEmailInUse,
    AuthFailureCode.weakPassword => l10n.authWeakPassword,
    AuthFailureCode.invalidEmail => l10n.authInvalidEmail,
    AuthFailureCode.tooManyRequests => l10n.authTooManyRequests,
    AuthFailureCode.network => l10n.errorNetwork,
    AuthFailureCode.requiresRecentLogin => l10n.authRequiresRecentLogin,
    AuthFailureCode.unknown => l10n.errorGeneric,
  };

  @override
  String toString() => 'AuthFailure(${code.name})';
}
