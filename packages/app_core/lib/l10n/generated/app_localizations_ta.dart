// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get appName => 'ஈஸிகிளினிக்';

  @override
  String get retry => 'மீண்டும் முயற்சிக்கவும்';

  @override
  String get loading => 'ஏற்றுகிறது…';

  @override
  String get signOut => 'வெளியேறு';

  @override
  String get cancel => 'ரத்து செய்';

  @override
  String get confirm => 'உறுதிப்படுத்து';

  @override
  String get save => 'சேமி';

  @override
  String get back => 'பின்செல்';

  @override
  String get language => 'மொழி';

  @override
  String get country => 'நாடு';

  @override
  String get selectCountry => 'உங்கள் நாட்டைத் தேர்ந்தெடுக்கவும்';

  @override
  String get welcome => 'வரவேற்கிறோம்';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageTamil => 'தமிழ்';

  @override
  String get languageSystem => 'சாதன மொழி';

  @override
  String get showPassword => 'கடவுச்சொல்லைக் காட்டு';

  @override
  String get hidePassword => 'கடவுச்சொல்லை மறை';

  @override
  String get searchHint => 'தேடு';

  @override
  String get clearSearch => 'தேடலை அழி';

  @override
  String get errorStateTitle => 'ஏதோ தவறு நடந்தது';

  @override
  String get errorStateMessage =>
      'உங்கள் இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.';

  @override
  String get signIn => 'உள்நுழை';

  @override
  String get createAccount => 'கணக்கை உருவாக்கு';

  @override
  String get createYourAccount => 'உங்கள் கணக்கை உருவாக்குங்கள்';

  @override
  String get newToApp => 'ஈஸிகிளினிக்கிற்குப் புதியவரா?';

  @override
  String get alreadyHaveAccount => 'ஏற்கனவே கணக்கு உள்ளதா?';

  @override
  String get forgotPassword => 'கடவுச்சொல்லை மறந்துவிட்டீர்களா?';

  @override
  String get resetYourPassword => 'உங்கள் கடவுச்சொல்லை மீட்டமைக்கவும்';

  @override
  String get sendResetLink => 'மீட்டமைப்பு இணைப்பை அனுப்பு';

  @override
  String get backToSignIn => 'உள்நுழைவுக்குத் திரும்பு';

  @override
  String get email => 'மின்னஞ்சல்';

  @override
  String get password => 'கடவுச்சொல்';

  @override
  String get confirmPassword => 'கடவுச்சொல்லை உறுதிப்படுத்தவும்';

  @override
  String get fullName => 'முழுப் பெயர்';

  @override
  String get acceptTerms =>
      'சேவை விதிமுறைகளை ஏற்கிறேன்; தனியுரிமைக் கொள்கையை அங்கீகரிக்கிறேன்.';

  @override
  String get mustAcceptTerms => 'தொடர விதிமுறைகளை ஏற்க வேண்டும்.';

  @override
  String get checkingSession => 'உங்கள் அமர்வைச் சரிபார்க்கிறது…';

  @override
  String get offlineTitle => 'நீங்கள் இணைப்பில் இல்லை எனத் தெரிகிறது';

  @override
  String get cannotSignInTitle => 'உங்களை உள்நுழைய முடியவில்லை';

  @override
  String get offlineMessage =>
      'உங்கள் இணைய இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.';

  @override
  String get sessionVerifyFailed =>
      'உங்கள் அமர்வைச் சரிபார்க்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.';

  @override
  String get accountSuspendedTitle => 'கணக்கு இடைநிறுத்தப்பட்டுள்ளது';

  @override
  String get accountSuspendedMessage =>
      'இந்தக் கணக்கு இடைநிறுத்தப்பட்டுள்ளது. ஈஸிகிளினிக் ஆதரவை அல்லது உங்கள் கிளினிக் நிர்வாகியைத் தொடர்பு கொள்ளவும்.';

  @override
  String get accountDisabledTitle => 'கணக்கு முடக்கப்பட்டுள்ளது';

  @override
  String get accountDisabledMessage =>
      'இந்தக் கணக்கு முடக்கப்பட்டுள்ளது. ஈஸிகிளினிக் ஆதரவைத் தொடர்பு கொள்ளவும்.';

  @override
  String get accessUnavailableTitle => 'அணுகல் கிடைக்கவில்லை';

  @override
  String get verifyEmailTitle => 'உங்கள் மின்னஞ்சலைச் சரிபார்க்கவும்';

  @override
  String get verificationSentGeneric =>
      'சரிபார்ப்பு இணைப்பை உங்களுக்கு அனுப்பினோம்.';

  @override
  String verificationSentTo(String email) {
    return '$email முகவரிக்கு சரிபார்ப்பு இணைப்பை அனுப்பினோம்.';
  }

  @override
  String get verifyEmailInstructions =>
      'அந்த மின்னஞ்சலில் உள்ள இணைப்பைத் திறந்து, பிறகு திரும்பி வந்து தொடரவும். மின்னஞ்சல் சரிபார்க்கப்பட்டதும் அணுகல் கிடைக்கும்.';

  @override
  String get resendVerification => 'சரிபார்ப்பு மின்னஞ்சலை மீண்டும் அனுப்பு';

  @override
  String get verificationResent => 'சரிபார்ப்பு மின்னஞ்சல் அனுப்பப்பட்டது.';

  @override
  String get checkYourEmailTitle => 'உங்கள் மின்னஞ்சலைப் பார்க்கவும்';

  @override
  String get resetLinkInfo =>
      'இந்த மின்னஞ்சலுக்குக் கணக்கு இருந்தால், கடவுச்சொல் மீட்டமைப்பு இணைப்பு அனுப்பப்பட்டுள்ளது. உங்கள் இன்பாக்ஸையும் ஸ்பேம் கோப்புறையையும் பார்க்கவும். இணைப்பு குறுகிய நேரத்தில் காலாவதியாகும்.';

  @override
  String get verifiedMyEmail => 'என் மின்னஞ்சலைச் சரிபார்த்துவிட்டேன்';

  @override
  String get useDifferentEmail => 'வேறு மின்னஞ்சலைப் பயன்படுத்து';

  @override
  String validationRequired(String field) {
    return '$field தேவை.';
  }

  @override
  String get validationEmail => 'சரியான மின்னஞ்சல் முகவரியை உள்ளிடவும்.';

  @override
  String get validationPhone => 'சரியான தொலைபேசி எண்ணை உள்ளிடவும்.';

  @override
  String get validationPasswordLength =>
      'கடவுச்சொல் குறைந்தது 8 எழுத்துகள் இருக்க வேண்டும்.';

  @override
  String get validationPasswordMix =>
      'கடவுச்சொல்லில் எழுத்துகளும் எண்களும் இருக்க வேண்டும்.';

  @override
  String validationTooShort(String field, int min) {
    return '$field குறைந்தது $min எழுத்துகள் இருக்க வேண்டும்.';
  }

  @override
  String validationTooLong(String field, int max) {
    return '$field அதிகபட்சம் $max எழுத்துகள் இருக்க வேண்டும்.';
  }

  @override
  String get passwordRequired => 'கடவுச்சொல் தேவை.';

  @override
  String get confirmPasswordPrompt => 'உங்கள் கடவுச்சொல்லை உறுதிப்படுத்தவும்.';

  @override
  String get passwordsDoNotMatch => 'கடவுச்சொற்கள் பொருந்தவில்லை.';

  @override
  String get errorGeneric => 'ஏதோ தவறு நடந்தது. மீண்டும் முயற்சிக்கவும்.';

  @override
  String get errorNetwork =>
      'சேவையகத்தை அடைய முடியவில்லை. உங்கள் இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.';

  @override
  String get authInvalidCredentials =>
      'மின்னஞ்சல் அல்லது கடவுச்சொல் தவறானது. மீண்டும் முயற்சிக்கவும்.';

  @override
  String get authAccountDisabled =>
      'இந்தக் கணக்கு முடக்கப்பட்டுள்ளது. ஆதரவைத் தொடர்பு கொள்ளவும்.';

  @override
  String get authEmailInUse =>
      'இந்த மின்னஞ்சலுடன் கணக்கு ஏற்கனவே இருக்கலாம். உள்நுழையவும் அல்லது கடவுச்சொல்லை மீட்டமைக்கவும்.';

  @override
  String get authWeakPassword =>
      'வலுவான கடவுச்சொல்லைத் தேர்ந்தெடுக்கவும் (எழுத்துகளும் எண்களும் உள்ள 8+ எழுத்துகள்).';

  @override
  String get authInvalidEmail => 'சரியான மின்னஞ்சல் முகவரியை உள்ளிடவும்.';

  @override
  String get authTooManyRequests =>
      'பல முறை முயற்சித்துவிட்டீர்கள். சில நிமிடங்கள் காத்திருந்து மீண்டும் முயற்சிக்கவும்.';

  @override
  String get authRequiresRecentLogin =>
      'உங்கள் பாதுகாப்பிற்காக, தொடர மீண்டும் உள்நுழையவும்.';

  @override
  String get navHome => 'முகப்பு';

  @override
  String get navAppointments => 'சந்திப்புகள்';

  @override
  String get navPatients => 'நோயாளிகள்';

  @override
  String get navBilling => 'கட்டணம்';

  @override
  String get navReports => 'அறிக்கைகள்';

  @override
  String get navProfile => 'சுயவிவரம்';

  @override
  String get navSettings => 'அமைப்புகள்';

  @override
  String get navDashboard => 'டாஷ்போர்டு';

  @override
  String get navToday => 'இன்று';

  @override
  String get navQueue => 'வரிசை';

  @override
  String get navFollowups => 'தொடர் சந்திப்புகள்';

  @override
  String get navNotifications => 'அறிவிப்புகள்';

  @override
  String get navAccount => 'கணக்கு';

  @override
  String get navRecords => 'பதிவுகள்';

  @override
  String get navClinics => 'கிளினிக்குகள்';

  @override
  String get navOverview => 'மேலோட்டம்';

  @override
  String get navBranches => 'கிளைகள்';

  @override
  String get navLaboratory => 'ஆய்வகம்';

  @override
  String get bookAppointment => 'சந்திப்பை முன்பதிவு செய்';

  @override
  String get myAppointments => 'என் சந்திப்புகள்';

  @override
  String get prescriptions => 'மருந்துச் சீட்டுகள்';

  @override
  String get labReports => 'ஆய்வக அறிக்கைகள்';

  @override
  String get upcomingAppointment => 'வரவிருக்கும் சந்திப்பு';

  @override
  String get noAppointments => 'இன்னும் சந்திப்புகள் இல்லை';

  @override
  String get statusBooked => 'முன்பதிவு செய்யப்பட்டது';

  @override
  String get statusConfirmed => 'உறுதிசெய்யப்பட்டது';

  @override
  String get statusCheckedIn => 'வருகை பதிவு செய்யப்பட்டது';

  @override
  String get statusInConsultation => 'ஆலோசனையில்';

  @override
  String get statusCompleted => 'முடிந்தது';

  @override
  String get statusCancelled => 'ரத்து செய்யப்பட்டது';

  @override
  String get statusNoShow => 'வரவில்லை';

  @override
  String get statusDraft => 'வரைவு';

  @override
  String get statusFinalized => 'இறுதியானது';

  @override
  String get statusPaid => 'செலுத்தப்பட்டது';

  @override
  String get statusPartiallyPaid => 'பகுதியளவு செலுத்தப்பட்டது';

  @override
  String get statusOutstanding => 'நிலுவையில்';

  @override
  String get statusRefunded => 'திரும்பப் பெறப்பட்டது';

  @override
  String appointmentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count சந்திப்புகள்',
      one: '1 சந்திப்பு',
      zero: 'சந்திப்புகள் இல்லை',
    );
    return '$_temp0';
  }

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count நிமிடங்களுக்கு முன்',
      one: '1 நிமிடத்துக்கு முன்',
    );
    return '$_temp0';
  }
}
