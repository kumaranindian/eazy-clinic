// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'إيزي كلينك';

  @override
  String get retry => 'حاول مرة أخرى';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get cancel => 'إلغاء';

  @override
  String get confirm => 'تأكيد';

  @override
  String get save => 'حفظ';

  @override
  String get back => 'رجوع';

  @override
  String get language => 'اللغة';

  @override
  String get country => 'الدولة';

  @override
  String get selectCountry => 'اختر دولتك';

  @override
  String get welcome => 'مرحبًا';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageTamil => 'தமிழ்';

  @override
  String get languageSystem => 'لغة الجهاز';

  @override
  String get showPassword => 'إظهار كلمة المرور';

  @override
  String get hidePassword => 'إخفاء كلمة المرور';

  @override
  String get searchHint => 'بحث';

  @override
  String get clearSearch => 'مسح البحث';

  @override
  String get errorStateTitle => 'حدث خطأ ما';

  @override
  String get errorStateMessage => 'يرجى التحقق من اتصالك والمحاولة مرة أخرى.';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get createAccount => 'إنشاء حساب';

  @override
  String get createYourAccount => 'أنشئ حسابك';

  @override
  String get newToApp => 'جديد في إيزي كلينك؟';

  @override
  String get alreadyHaveAccount => 'لديك حساب بالفعل؟';

  @override
  String get forgotPassword => 'هل نسيت كلمة المرور؟';

  @override
  String get resetYourPassword => 'إعادة تعيين كلمة المرور';

  @override
  String get sendResetLink => 'إرسال رابط إعادة التعيين';

  @override
  String get backToSignIn => 'العودة إلى تسجيل الدخول';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get password => 'كلمة المرور';

  @override
  String get confirmPassword => 'تأكيد كلمة المرور';

  @override
  String get fullName => 'الاسم الكامل';

  @override
  String get acceptTerms => 'أوافق على شروط الخدمة وأقرّ بسياسة الخصوصية.';

  @override
  String get mustAcceptTerms => 'يجب قبول الشروط للمتابعة.';

  @override
  String get checkingSession => 'جارٍ التحقق من جلستك…';

  @override
  String get offlineTitle => 'يبدو أنك غير متصل بالإنترنت';

  @override
  String get cannotSignInTitle => 'تعذّر تسجيل دخولك';

  @override
  String get offlineMessage => 'تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى.';

  @override
  String get sessionVerifyFailed =>
      'تعذّر التحقق من جلستك. يرجى المحاولة مرة أخرى.';

  @override
  String get accountSuspendedTitle => 'الحساب موقوف';

  @override
  String get accountSuspendedMessage =>
      'تم إيقاف هذا الحساب. يرجى التواصل مع دعم إيزي كلينك أو مسؤول عيادتك.';

  @override
  String get accountDisabledTitle => 'الحساب معطّل';

  @override
  String get accountDisabledMessage =>
      'تم تعطيل هذا الحساب. يرجى التواصل مع دعم إيزي كلينك.';

  @override
  String get accessUnavailableTitle => 'الوصول غير متاح';

  @override
  String get verifyEmailTitle => 'تحقّق من بريدك الإلكتروني';

  @override
  String get verificationSentGeneric => 'أرسلنا إليك رابط التحقق.';

  @override
  String verificationSentTo(String email) {
    return 'أرسلنا رابط التحقق إلى $email.';
  }

  @override
  String get verifyEmailInstructions =>
      'افتح الرابط في ذلك البريد ثم عد وتابع. ستحصل على الوصول بعد التحقق من بريدك الإلكتروني.';

  @override
  String get resendVerification => 'إعادة إرسال بريد التحقق';

  @override
  String get verificationResent => 'تم إرسال بريد التحقق.';

  @override
  String get checkYourEmailTitle => 'تحقّق من بريدك الإلكتروني';

  @override
  String get resetLinkInfo =>
      'إذا كان هناك حساب لهذا البريد الإلكتروني، فقد تم إرسال رابط إعادة تعيين كلمة المرور. تحقق من بريدك الوارد ومجلد الرسائل غير المرغوبة. تنتهي صلاحية الرابط بعد وقت قصير.';

  @override
  String get verifiedMyEmail => 'لقد تحققت من بريدي الإلكتروني';

  @override
  String get useDifferentEmail => 'استخدم بريدًا إلكترونيًا آخر';

  @override
  String validationRequired(String field) {
    return '$field مطلوب.';
  }

  @override
  String get validationEmail => 'أدخل عنوان بريد إلكتروني صالحًا.';

  @override
  String get validationPhone => 'أدخل رقم هاتف صالحًا.';

  @override
  String get validationPasswordLength => 'يجب ألا تقل كلمة المرور عن 8 أحرف.';

  @override
  String get validationPasswordMix =>
      'يجب أن تحتوي كلمة المرور على أحرف وأرقام.';

  @override
  String validationTooShort(String field, int min) {
    return 'يجب ألا يقل $field عن $min أحرف.';
  }

  @override
  String validationTooLong(String field, int max) {
    return 'يجب ألا يزيد $field عن $max حرفًا.';
  }

  @override
  String get passwordRequired => 'كلمة المرور مطلوبة.';

  @override
  String get confirmPasswordPrompt => 'يرجى تأكيد كلمة المرور.';

  @override
  String get passwordsDoNotMatch => 'كلمتا المرور غير متطابقتين.';

  @override
  String get errorGeneric => 'حدث خطأ ما. يرجى المحاولة مرة أخرى.';

  @override
  String get errorNetwork =>
      'تعذّر الوصول إلى الخادم. تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get authInvalidCredentials =>
      'البريد الإلكتروني أو كلمة المرور غير صحيحة. يرجى المحاولة مرة أخرى.';

  @override
  String get authAccountDisabled =>
      'تم تعطيل هذا الحساب. يرجى التواصل مع الدعم.';

  @override
  String get authEmailInUse =>
      'قد يكون هناك حساب بهذا البريد الإلكتروني بالفعل. جرّب تسجيل الدخول أو إعادة تعيين كلمة المرور.';

  @override
  String get authWeakPassword =>
      'يرجى اختيار كلمة مرور أقوى (8 أحرف أو أكثر مع أحرف وأرقام).';

  @override
  String get authInvalidEmail => 'يرجى إدخال عنوان بريد إلكتروني صالح.';

  @override
  String get authTooManyRequests =>
      'محاولات كثيرة جدًا. يرجى الانتظار بضع دقائق ثم المحاولة مرة أخرى.';

  @override
  String get authRequiresRecentLogin =>
      'حفاظًا على أمانك، يرجى تسجيل الدخول مرة أخرى للمتابعة.';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navAppointments => 'المواعيد';

  @override
  String get navPatients => 'المرضى';

  @override
  String get navBilling => 'الفواتير';

  @override
  String get navReports => 'التقارير';

  @override
  String get navProfile => 'الملف الشخصي';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get navDashboard => 'لوحة التحكم';

  @override
  String get navToday => 'اليوم';

  @override
  String get navQueue => 'الطابور';

  @override
  String get navFollowups => 'المتابعات';

  @override
  String get navNotifications => 'الإشعارات';

  @override
  String get navAccount => 'الحساب';

  @override
  String get navRecords => 'السجلات';

  @override
  String get navClinics => 'العيادات';

  @override
  String get navOverview => 'نظرة عامة';

  @override
  String get navBranches => 'الفروع';

  @override
  String get navLaboratory => 'المختبر';

  @override
  String get bookAppointment => 'حجز موعد';

  @override
  String get myAppointments => 'مواعيدي';

  @override
  String get prescriptions => 'الوصفات الطبية';

  @override
  String get labReports => 'تقارير المختبر';

  @override
  String get upcomingAppointment => 'الموعد القادم';

  @override
  String get noAppointments => 'لا توجد مواعيد بعد';

  @override
  String get statusBooked => 'محجوز';

  @override
  String get statusConfirmed => 'مؤكد';

  @override
  String get statusCheckedIn => 'تم تسجيل الوصول';

  @override
  String get statusInConsultation => 'في الاستشارة';

  @override
  String get statusCompleted => 'مكتمل';

  @override
  String get statusCancelled => 'ملغى';

  @override
  String get statusNoShow => 'لم يحضر';

  @override
  String get statusDraft => 'مسودة';

  @override
  String get statusFinalized => 'نهائي';

  @override
  String get statusPaid => 'مدفوع';

  @override
  String get statusPartiallyPaid => 'مدفوع جزئيًا';

  @override
  String get statusOutstanding => 'مستحق';

  @override
  String get statusRefunded => 'تم الاسترداد';

  @override
  String appointmentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count موعد',
      many: '$count موعدًا',
      few: '$count مواعيد',
      two: 'موعدان',
      one: 'موعد واحد',
      zero: 'لا توجد مواعيد',
    );
    return '$_temp0';
  }

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبل $count دقيقة',
      many: 'قبل $count دقيقة',
      few: 'قبل $count دقائق',
      two: 'قبل دقيقتين',
      one: 'قبل دقيقة',
    );
    return '$_temp0';
  }
}
