// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'ईज़ीक्लिनिक';

  @override
  String get retry => 'फिर से कोशिश करें';

  @override
  String get loading => 'लोड हो रहा है…';

  @override
  String get signOut => 'साइन आउट करें';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get confirm => 'पुष्टि करें';

  @override
  String get save => 'सहेजें';

  @override
  String get back => 'वापस';

  @override
  String get language => 'भाषा';

  @override
  String get country => 'देश';

  @override
  String get selectCountry => 'अपना देश चुनें';

  @override
  String get welcome => 'स्वागत है';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageTamil => 'தமிழ்';

  @override
  String get languageSystem => 'डिवाइस की भाषा';

  @override
  String get showPassword => 'पासवर्ड दिखाएँ';

  @override
  String get hidePassword => 'पासवर्ड छिपाएँ';

  @override
  String get searchHint => 'खोजें';

  @override
  String get clearSearch => 'खोज साफ़ करें';

  @override
  String get errorStateTitle => 'कुछ गलत हो गया';

  @override
  String get errorStateMessage =>
      'कृपया अपना कनेक्शन जाँचें और फिर कोशिश करें।';

  @override
  String get signIn => 'साइन इन करें';

  @override
  String get createAccount => 'खाता बनाएँ';

  @override
  String get createYourAccount => 'अपना खाता बनाएँ';

  @override
  String get newToApp => 'ईज़ीक्लिनिक में नए हैं?';

  @override
  String get alreadyHaveAccount => 'क्या आपके पास पहले से खाता है?';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get resetYourPassword => 'अपना पासवर्ड रीसेट करें';

  @override
  String get sendResetLink => 'रीसेट लिंक भेजें';

  @override
  String get backToSignIn => 'साइन इन पर वापस जाएँ';

  @override
  String get email => 'ईमेल';

  @override
  String get password => 'पासवर्ड';

  @override
  String get confirmPassword => 'पासवर्ड की पुष्टि करें';

  @override
  String get fullName => 'पूरा नाम';

  @override
  String get acceptTerms =>
      'मैं सेवा की शर्तों को स्वीकार करता/करती हूँ और गोपनीयता नीति को मानता/मानती हूँ।';

  @override
  String get mustAcceptTerms =>
      'जारी रखने के लिए शर्तें स्वीकार करना आवश्यक है।';

  @override
  String get checkingSession => 'आपका सत्र जाँचा जा रहा है…';

  @override
  String get offlineTitle => 'आप ऑफ़लाइन लगते हैं';

  @override
  String get cannotSignInTitle => 'आपको साइन इन नहीं किया जा सका';

  @override
  String get offlineMessage => 'अपना इंटरनेट कनेक्शन जाँचें और फिर कोशिश करें।';

  @override
  String get sessionVerifyFailed =>
      'हम आपका सत्र सत्यापित नहीं कर सके। कृपया फिर कोशिश करें।';

  @override
  String get accountSuspendedTitle => 'खाता निलंबित है';

  @override
  String get accountSuspendedMessage =>
      'यह खाता निलंबित कर दिया गया है। कृपया ईज़ीक्लिनिक सहायता या अपने क्लिनिक प्रशासक से संपर्क करें।';

  @override
  String get accountDisabledTitle => 'खाता अक्षम है';

  @override
  String get accountDisabledMessage =>
      'यह खाता अक्षम कर दिया गया है। कृपया ईज़ीक्लिनिक सहायता से संपर्क करें।';

  @override
  String get accessUnavailableTitle => 'पहुँच उपलब्ध नहीं है';

  @override
  String get verifyEmailTitle => 'अपना ईमेल सत्यापित करें';

  @override
  String get verificationSentGeneric => 'हमने आपको एक सत्यापन लिंक भेजा है।';

  @override
  String verificationSentTo(String email) {
    return 'हमने $email पर एक सत्यापन लिंक भेजा है।';
  }

  @override
  String get verifyEmailInstructions =>
      'उस ईमेल में दिया लिंक खोलें, फिर वापस आकर जारी रखें। ईमेल सत्यापित होने के बाद आपको पहुँच मिलेगी।';

  @override
  String get resendVerification => 'सत्यापन ईमेल फिर से भेजें';

  @override
  String get verificationResent => 'सत्यापन ईमेल भेज दिया गया।';

  @override
  String get checkYourEmailTitle => 'अपना ईमेल देखें';

  @override
  String get resetLinkInfo =>
      'यदि इस ईमेल का कोई खाता है, तो पासवर्ड रीसेट लिंक भेज दिया गया है। अपना इनबॉक्स और स्पैम फ़ोल्डर देखें। लिंक कुछ समय बाद समाप्त हो जाता है।';

  @override
  String get verifiedMyEmail => 'मैंने अपना ईमेल सत्यापित कर लिया है';

  @override
  String get useDifferentEmail => 'दूसरा ईमेल उपयोग करें';

  @override
  String validationRequired(String field) {
    return '$field आवश्यक है।';
  }

  @override
  String get validationEmail => 'मान्य ईमेल पता दर्ज करें।';

  @override
  String get validationPhone => 'मान्य फ़ोन नंबर दर्ज करें।';

  @override
  String get validationPasswordLength =>
      'पासवर्ड कम से कम 8 अक्षरों का होना चाहिए।';

  @override
  String get validationPasswordMix =>
      'पासवर्ड में अक्षर और संख्याएँ होनी चाहिए।';

  @override
  String validationTooShort(String field, int min) {
    return '$field कम से कम $min अक्षरों का होना चाहिए।';
  }

  @override
  String validationTooLong(String field, int max) {
    return '$field अधिकतम $max अक्षरों का होना चाहिए।';
  }

  @override
  String get passwordRequired => 'पासवर्ड आवश्यक है।';

  @override
  String get confirmPasswordPrompt => 'कृपया अपने पासवर्ड की पुष्टि करें।';

  @override
  String get passwordsDoNotMatch => 'पासवर्ड मेल नहीं खाते।';

  @override
  String get errorGeneric => 'कुछ गलत हो गया। कृपया फिर कोशिश करें।';

  @override
  String get errorNetwork =>
      'सर्वर तक नहीं पहुँच सके। अपना कनेक्शन जाँचें और फिर कोशिश करें।';

  @override
  String get authInvalidCredentials =>
      'ईमेल या पासवर्ड गलत है। कृपया फिर कोशिश करें।';

  @override
  String get authAccountDisabled =>
      'यह खाता अक्षम कर दिया गया है। कृपया सहायता से संपर्क करें।';

  @override
  String get authEmailInUse =>
      'इस ईमेल से खाता पहले से मौजूद हो सकता है। साइन इन करें या पासवर्ड रीसेट करें।';

  @override
  String get authWeakPassword =>
      'कृपया अधिक मज़बूत पासवर्ड चुनें (8+ अक्षर, अक्षर और संख्याओं के साथ)।';

  @override
  String get authInvalidEmail => 'कृपया मान्य ईमेल पता दर्ज करें।';

  @override
  String get authTooManyRequests =>
      'बहुत अधिक प्रयास। कृपया कुछ मिनट प्रतीक्षा करें और फिर कोशिश करें।';

  @override
  String get authRequiresRecentLogin =>
      'आपकी सुरक्षा के लिए, जारी रखने हेतु कृपया फिर से साइन इन करें।';

  @override
  String get navHome => 'होम';

  @override
  String get navAppointments => 'अपॉइंटमेंट';

  @override
  String get navPatients => 'मरीज़';

  @override
  String get navBilling => 'बिलिंग';

  @override
  String get navReports => 'रिपोर्ट';

  @override
  String get navProfile => 'प्रोफ़ाइल';

  @override
  String get navSettings => 'सेटिंग्स';

  @override
  String get navDashboard => 'डैशबोर्ड';

  @override
  String get navToday => 'आज';

  @override
  String get navQueue => 'कतार';

  @override
  String get navFollowups => 'फ़ॉलो-अप';

  @override
  String get navNotifications => 'सूचनाएँ';

  @override
  String get navAccount => 'खाता';

  @override
  String get navRecords => 'रिकॉर्ड';

  @override
  String get navClinics => 'क्लिनिक';

  @override
  String get navOverview => 'अवलोकन';

  @override
  String get navBranches => 'शाखाएँ';

  @override
  String get navLaboratory => 'प्रयोगशाला';

  @override
  String get bookAppointment => 'अपॉइंटमेंट बुक करें';

  @override
  String get myAppointments => 'मेरे अपॉइंटमेंट';

  @override
  String get prescriptions => 'पर्चे';

  @override
  String get labReports => 'लैब रिपोर्ट';

  @override
  String get upcomingAppointment => 'आगामी अपॉइंटमेंट';

  @override
  String get noAppointments => 'अभी कोई अपॉइंटमेंट नहीं';

  @override
  String get statusBooked => 'बुक किया गया';

  @override
  String get statusConfirmed => 'पुष्टि हो गई';

  @override
  String get statusCheckedIn => 'चेक-इन हो गया';

  @override
  String get statusInConsultation => 'परामर्श में';

  @override
  String get statusCompleted => 'पूर्ण';

  @override
  String get statusCancelled => 'रद्द';

  @override
  String get statusNoShow => 'उपस्थित नहीं हुए';

  @override
  String get statusDraft => 'ड्राफ़्ट';

  @override
  String get statusFinalized => 'अंतिम';

  @override
  String get statusPaid => 'भुगतान किया';

  @override
  String get statusPartiallyPaid => 'आंशिक भुगतान';

  @override
  String get statusOutstanding => 'बकाया';

  @override
  String get statusRefunded => 'रिफ़ंड किया गया';

  @override
  String appointmentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count अपॉइंटमेंट',
      one: '1 अपॉइंटमेंट',
      zero: 'कोई अपॉइंटमेंट नहीं',
    );
    return '$_temp0';
  }

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count मिनट पहले',
      one: '1 मिनट पहले',
    );
    return '$_temp0';
  }
}
