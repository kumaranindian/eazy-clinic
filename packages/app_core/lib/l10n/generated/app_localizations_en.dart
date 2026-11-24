// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'EazyClinic';

  @override
  String get retry => 'Try again';

  @override
  String get loading => 'Loading…';

  @override
  String get signOut => 'Sign out';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get back => 'Back';

  @override
  String get language => 'Language';

  @override
  String get country => 'Country';

  @override
  String get selectCountry => 'Select your country';

  @override
  String get welcome => 'Welcome';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageTamil => 'தமிழ்';

  @override
  String get languageSystem => 'Device language';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get searchHint => 'Search';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get errorStateTitle => 'Something went wrong';

  @override
  String get errorStateMessage => 'Please check your connection and try again.';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String get newToApp => 'New to EazyClinic?';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get resetYourPassword => 'Reset your password';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get fullName => 'Full name';

  @override
  String get acceptTerms =>
      'I accept the Terms of Service and acknowledge the Privacy Policy.';

  @override
  String get mustAcceptTerms => 'You must accept the terms to continue.';

  @override
  String get checkingSession => 'Checking your session…';

  @override
  String get offlineTitle => 'You appear to be offline';

  @override
  String get cannotSignInTitle => 'Cannot sign you in';

  @override
  String get offlineMessage => 'Check your internet connection and try again.';

  @override
  String get sessionVerifyFailed =>
      'We could not verify your session. Please try again.';

  @override
  String get accountSuspendedTitle => 'Account suspended';

  @override
  String get accountSuspendedMessage =>
      'This account has been suspended. Please contact EazyClinic support or your clinic administrator.';

  @override
  String get accountDisabledTitle => 'Account disabled';

  @override
  String get accountDisabledMessage =>
      'This account has been disabled. Please contact EazyClinic support.';

  @override
  String get accessUnavailableTitle => 'Access not available';

  @override
  String get verifyEmailTitle => 'Verify your email';

  @override
  String get verificationSentGeneric => 'We sent you a verification link.';

  @override
  String verificationSentTo(String email) {
    return 'We sent a verification link to $email.';
  }

  @override
  String get verifyEmailInstructions =>
      'Open the link in that email, then come back and continue. You will get access once your email is verified.';

  @override
  String get resendVerification => 'Resend verification email';

  @override
  String get verificationResent => 'Verification email sent.';

  @override
  String get checkYourEmailTitle => 'Check your email';

  @override
  String get resetLinkInfo =>
      'If an account exists for this email, a password reset link has been sent. Check your inbox and spam folder. The link expires after a short time.';

  @override
  String get verifiedMyEmail => 'I\'ve verified my email';

  @override
  String get useDifferentEmail => 'Use a different email';

  @override
  String validationRequired(String field) {
    return '$field is required.';
  }

  @override
  String get validationEmail => 'Enter a valid email address.';

  @override
  String get validationPhone => 'Enter a valid phone number.';

  @override
  String get validationPasswordLength =>
      'Password must be at least 8 characters.';

  @override
  String get validationPasswordMix =>
      'Password must contain letters and numbers.';

  @override
  String validationTooShort(String field, int min) {
    return '$field must be at least $min characters.';
  }

  @override
  String validationTooLong(String field, int max) {
    return '$field must be at most $max characters.';
  }

  @override
  String get passwordRequired => 'Password is required.';

  @override
  String get confirmPasswordPrompt => 'Please confirm your password.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorNetwork =>
      'Cannot reach the server. Check your connection and try again.';

  @override
  String get authInvalidCredentials =>
      'The email or password is incorrect. Please try again.';

  @override
  String get authAccountDisabled =>
      'This account has been disabled. Please contact support.';

  @override
  String get authEmailInUse =>
      'An account with this email may already exist. Try signing in or resetting your password.';

  @override
  String get authWeakPassword =>
      'Please choose a stronger password (8+ characters with letters and numbers).';

  @override
  String get authInvalidEmail => 'Please enter a valid email address.';

  @override
  String get authTooManyRequests =>
      'Too many attempts. Please wait a few minutes and try again.';

  @override
  String get authRequiresRecentLogin =>
      'For your security, please sign in again to continue.';

  @override
  String get navHome => 'Home';

  @override
  String get navAppointments => 'Appointments';

  @override
  String get navPatients => 'Patients';

  @override
  String get navBilling => 'Billing';

  @override
  String get navReports => 'Reports';

  @override
  String get navProfile => 'Profile';

  @override
  String get navSettings => 'Settings';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navToday => 'Today';

  @override
  String get navQueue => 'Queue';

  @override
  String get navFollowups => 'Follow-ups';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get navAccount => 'Account';

  @override
  String get navRecords => 'Records';

  @override
  String get navClinics => 'Clinics';

  @override
  String get navOverview => 'Overview';

  @override
  String get navBranches => 'Branches';

  @override
  String get navLaboratory => 'Laboratory';

  @override
  String get bookAppointment => 'Book appointment';

  @override
  String get myAppointments => 'My appointments';

  @override
  String get prescriptions => 'Prescriptions';

  @override
  String get labReports => 'Lab reports';

  @override
  String get upcomingAppointment => 'Upcoming appointment';

  @override
  String get noAppointments => 'No appointments yet';

  @override
  String get statusBooked => 'Booked';

  @override
  String get statusConfirmed => 'Confirmed';

  @override
  String get statusCheckedIn => 'Checked in';

  @override
  String get statusInConsultation => 'In consultation';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusNoShow => 'No show';

  @override
  String get statusDraft => 'Draft';

  @override
  String get statusFinalized => 'Finalized';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusPartiallyPaid => 'Partially paid';

  @override
  String get statusOutstanding => 'Outstanding';

  @override
  String get statusRefunded => 'Refunded';

  @override
  String appointmentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count appointments',
      one: '1 appointment',
      zero: 'No appointments',
    );
    return '$_temp0';
  }

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }
}
