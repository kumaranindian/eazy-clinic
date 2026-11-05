# -*- coding: utf-8 -*-
#!/usr/bin/env python3
"""Generates lib/l10n/app_<locale>.arb from the table below.

Translations for ar / hi / ta are machine-assisted STARTER packs. They have not
been reviewed by native speakers or a professional translator and must not be
used for legal, clinical or consent wording (see docs/phase-13).
"""
import json, os
OUT = os.path.join(os.path.dirname(__file__), '..', 'lib', 'l10n')

# key: (en, ar, hi, ta, placeholders)
T = {
 # --- common ---
 'appName': ('EazyClinic','إيزي كلينك','ईज़ीक्लिनिक','ஈஸிகிளினிக்',None),
 'retry': ('Try again','حاول مرة أخرى','फिर से कोशिश करें','மீண்டும் முயற்சிக்கவும்',None),
 'loading': ('Loading…','جارٍ التحميل…','लोड हो रहा है…','ஏற்றுகிறது…',None),
 'signOut': ('Sign out','تسجيل الخروج','साइन आउट करें','வெளியேறு',None),
 'cancel': ('Cancel','إلغاء','रद्द करें','ரத்து செய்',None),
 'confirm': ('Confirm','تأكيد','पुष्टि करें','உறுதிப்படுத்து',None),
 'save': ('Save','حفظ','सहेजें','சேமி',None),
 'back': ('Back','رجوع','वापस','பின்செல்',None),
 'language': ('Language','اللغة','भाषा','மொழி',None),
 'country': ('Country','الدولة','देश','நாடு',None),
 'selectCountry': ('Select your country','اختر دولتك','अपना देश चुनें','உங்கள் நாட்டைத் தேர்ந்தெடுக்கவும்',None),
 'welcome': ('Welcome','مرحبًا','स्वागत है','வரவேற்கிறோம்',None),
 'languageEnglish': ('English','English','English','English',None),
 'languageArabic': ('العربية','العربية','العربية','العربية',None),
 'languageHindi': ('हिन्दी','हिन्दी','हिन्दी','हिन्दी',None),
 'languageTamil': ('தமிழ்','தமிழ்','தமிழ்','தமிழ்',None),
 'languageSystem': ('Device language','لغة الجهاز','डिवाइस की भाषा','சாதன மொழி',None),
 'showPassword': ('Show password','إظهار كلمة المرور','पासवर्ड दिखाएँ','கடவுச்சொல்லைக் காட்டு',None),
 'hidePassword': ('Hide password','إخفاء كلمة المرور','पासवर्ड छिपाएँ','கடவுச்சொல்லை மறை',None),
 'searchHint': ('Search','بحث','खोजें','தேடு',None),
 'clearSearch': ('Clear search','مسح البحث','खोज साफ़ करें','தேடலை அழி',None),
 'errorStateTitle': ('Something went wrong','حدث خطأ ما','कुछ गलत हो गया','ஏதோ தவறு நடந்தது',None),
 'errorStateMessage': ('Please check your connection and try again.','يرجى التحقق من اتصالك والمحاولة مرة أخرى.','कृपया अपना कनेक्शन जाँचें और फिर कोशिश करें।','உங்கள் இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',None),
 # --- auth ---
 'signIn': ('Sign in','تسجيل الدخول','साइन इन करें','உள்நுழை',None),
 'createAccount': ('Create account','إنشاء حساب','खाता बनाएँ','கணக்கை உருவாக்கு',None),
 'createYourAccount': ('Create your account','أنشئ حسابك','अपना खाता बनाएँ','உங்கள் கணக்கை உருவாக்குங்கள்',None),
 'newToApp': ('New to EazyClinic?','جديد في إيزي كلينك؟','ईज़ीक्लिनिक में नए हैं?','ஈஸிகிளினிக்கிற்குப் புதியவரா?',None),
 'alreadyHaveAccount': ('Already have an account?','لديك حساب بالفعل؟','क्या आपके पास पहले से खाता है?','ஏற்கனவே கணக்கு உள்ளதா?',None),
 'forgotPassword': ('Forgot password?','هل نسيت كلمة المرور؟','पासवर्ड भूल गए?','கடவுச்சொல்லை மறந்துவிட்டீர்களா?',None),
 'resetYourPassword': ('Reset your password','إعادة تعيين كلمة المرور','अपना पासवर्ड रीसेट करें','உங்கள் கடவுச்சொல்லை மீட்டமைக்கவும்',None),
 'sendResetLink': ('Send reset link','إرسال رابط إعادة التعيين','रीसेट लिंक भेजें','மீட்டமைப்பு இணைப்பை அனுப்பு',None),
 'backToSignIn': ('Back to sign in','العودة إلى تسجيل الدخول','साइन इन पर वापस जाएँ','உள்நுழைவுக்குத் திரும்பு',None),
 'email': ('Email','البريد الإلكتروني','ईमेल','மின்னஞ்சல்',None),
 'password': ('Password','كلمة المرور','पासवर्ड','கடவுச்சொல்',None),
 'confirmPassword': ('Confirm password','تأكيد كلمة المرور','पासवर्ड की पुष्टि करें','கடவுச்சொல்லை உறுதிப்படுத்தவும்',None),
 'fullName': ('Full name','الاسم الكامل','पूरा नाम','முழுப் பெயர்',None),
 'acceptTerms': ('I accept the Terms of Service and acknowledge the Privacy Policy.','أوافق على شروط الخدمة وأقرّ بسياسة الخصوصية.','मैं सेवा की शर्तों को स्वीकार करता/करती हूँ और गोपनीयता नीति को मानता/मानती हूँ।','சேவை விதிமுறைகளை ஏற்கிறேன்; தனியுரிமைக் கொள்கையை அங்கீகரிக்கிறேன்.',None),
 'mustAcceptTerms': ('You must accept the terms to continue.','يجب قبول الشروط للمتابعة.','जारी रखने के लिए शर्तें स्वीकार करना आवश्यक है।','தொடர விதிமுறைகளை ஏற்க வேண்டும்.',None),
 'checkingSession': ('Checking your session…','جارٍ التحقق من جلستك…','आपका सत्र जाँचा जा रहा है…','உங்கள் அமர்வைச் சரிபார்க்கிறது…',None),
 'offlineTitle': ('You appear to be offline','يبدو أنك غير متصل بالإنترنت','आप ऑफ़लाइन लगते हैं','நீங்கள் இணைப்பில் இல்லை எனத் தெரிகிறது',None),
 'cannotSignInTitle': ('Cannot sign you in','تعذّر تسجيل دخولك','आपको साइन इन नहीं किया जा सका','உங்களை உள்நுழைய முடியவில்லை',None),
 'offlineMessage': ('Check your internet connection and try again.','تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى.','अपना इंटरनेट कनेक्शन जाँचें और फिर कोशिश करें।','உங்கள் இணைய இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',None),
 'sessionVerifyFailed': ('We could not verify your session. Please try again.','تعذّر التحقق من جلستك. يرجى المحاولة مرة أخرى.','हम आपका सत्र सत्यापित नहीं कर सके। कृपया फिर कोशिश करें।','உங்கள் அமர்வைச் சரிபார்க்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',None),
 'accountSuspendedTitle': ('Account suspended','الحساب موقوف','खाता निलंबित है','கணக்கு இடைநிறுத்தப்பட்டுள்ளது',None),
 'accountSuspendedMessage': ('This account has been suspended. Please contact EazyClinic support or your clinic administrator.','تم إيقاف هذا الحساب. يرجى التواصل مع دعم إيزي كلينك أو مسؤول عيادتك.','यह खाता निलंबित कर दिया गया है। कृपया ईज़ीक्लिनिक सहायता या अपने क्लिनिक प्रशासक से संपर्क करें।','இந்தக் கணக்கு இடைநிறுத்தப்பட்டுள்ளது. ஈஸிகிளினிக் ஆதரவை அல்லது உங்கள் கிளினிக் நிர்வாகியைத் தொடர்பு கொள்ளவும்.',None),
 'accountDisabledTitle': ('Account disabled','الحساب معطّل','खाता अक्षम है','கணக்கு முடக்கப்பட்டுள்ளது',None),
 'accountDisabledMessage': ('This account has been disabled. Please contact EazyClinic support.','تم تعطيل هذا الحساب. يرجى التواصل مع دعم إيزي كلينك.','यह खाता अक्षम कर दिया गया है। कृपया ईज़ीक्लिनिक सहायता से संपर्क करें।','இந்தக் கணக்கு முடக்கப்பட்டுள்ளது. ஈஸிகிளினிக் ஆதரவைத் தொடர்பு கொள்ளவும்.',None),
 'accessUnavailableTitle': ('Access not available','الوصول غير متاح','पहुँच उपलब्ध नहीं है','அணுகல் கிடைக்கவில்லை',None),
 'verifyEmailTitle': ('Verify your email','تحقّق من بريدك الإلكتروني','अपना ईमेल सत्यापित करें','உங்கள் மின்னஞ்சலைச் சரிபார்க்கவும்',None),
 'verificationSentGeneric': ('We sent you a verification link.','أرسلنا إليك رابط التحقق.','हमने आपको एक सत्यापन लिंक भेजा है।','சரிபார்ப்பு இணைப்பை உங்களுக்கு அனுப்பினோம்.',None),
 'verificationSentTo': ('We sent a verification link to {email}.','أرسلنا رابط التحقق إلى {email}.','हमने {email} पर एक सत्यापन लिंक भेजा है।','{email} முகவரிக்கு சரிபார்ப்பு இணைப்பை அனுப்பினோம்.',{'email':'String'}),
 'verifyEmailInstructions': ('Open the link in that email, then come back and continue. You will get access once your email is verified.','افتح الرابط في ذلك البريد ثم عد وتابع. ستحصل على الوصول بعد التحقق من بريدك الإلكتروني.','उस ईमेल में दिया लिंक खोलें, फिर वापस आकर जारी रखें। ईमेल सत्यापित होने के बाद आपको पहुँच मिलेगी।','அந்த மின்னஞ்சலில் உள்ள இணைப்பைத் திறந்து, பிறகு திரும்பி வந்து தொடரவும். மின்னஞ்சல் சரிபார்க்கப்பட்டதும் அணுகல் கிடைக்கும்.',None),
 'resendVerification': ('Resend verification email','إعادة إرسال بريد التحقق','सत्यापन ईमेल फिर से भेजें','சரிபார்ப்பு மின்னஞ்சலை மீண்டும் அனுப்பு',None),
 'verificationResent': ('Verification email sent.','تم إرسال بريد التحقق.','सत्यापन ईमेल भेज दिया गया।','சரிபார்ப்பு மின்னஞ்சல் அனுப்பப்பட்டது.',None),
 'checkYourEmailTitle': ('Check your email','تحقّق من بريدك الإلكتروني','अपना ईमेल देखें','உங்கள் மின்னஞ்சலைப் பார்க்கவும்',None),
 'resetLinkInfo': ('If an account exists for this email, a password reset link has been sent. Check your inbox and spam folder. The link expires after a short time.','إذا كان هناك حساب لهذا البريد الإلكتروني، فقد تم إرسال رابط إعادة تعيين كلمة المرور. تحقق من بريدك الوارد ومجلد الرسائل غير المرغوبة. تنتهي صلاحية الرابط بعد وقت قصير.','यदि इस ईमेल का कोई खाता है, तो पासवर्ड रीसेट लिंक भेज दिया गया है। अपना इनबॉक्स और स्पैम फ़ोल्डर देखें। लिंक कुछ समय बाद समाप्त हो जाता है।','இந்த மின்னஞ்சலுக்குக் கணக்கு இருந்தால், கடவுச்சொல் மீட்டமைப்பு இணைப்பு அனுப்பப்பட்டுள்ளது. உங்கள் இன்பாக்ஸையும் ஸ்பேம் கோப்புறையையும் பார்க்கவும். இணைப்பு குறுகிய நேரத்தில் காலாவதியாகும்.',None),
 'verifiedMyEmail': ("I've verified my email",'لقد تحققت من بريدي الإلكتروني','मैंने अपना ईमेल सत्यापित कर लिया है','என் மின்னஞ்சலைச் சரிபார்த்துவிட்டேன்',None),
 'useDifferentEmail': ('Use a different email','استخدم بريدًا إلكترونيًا آخر','दूसरा ईमेल उपयोग करें','வேறு மின்னஞ்சலைப் பயன்படுத்து',None),
 # --- validation / errors ---
 'validationRequired': ('{field} is required.','{field} مطلوب.','{field} आवश्यक है।','{field} தேவை.',{'field':'String'}),
 'validationEmail': ('Enter a valid email address.','أدخل عنوان بريد إلكتروني صالحًا.','मान्य ईमेल पता दर्ज करें।','சரியான மின்னஞ்சல் முகவரியை உள்ளிடவும்.',None),
 'validationPhone': ('Enter a valid phone number.','أدخل رقم هاتف صالحًا.','मान्य फ़ोन नंबर दर्ज करें।','சரியான தொலைபேசி எண்ணை உள்ளிடவும்.',None),
 'validationPasswordLength': ('Password must be at least 8 characters.','يجب ألا تقل كلمة المرور عن 8 أحرف.','पासवर्ड कम से कम 8 अक्षरों का होना चाहिए।','கடவுச்சொல் குறைந்தது 8 எழுத்துகள் இருக்க வேண்டும்.',None),
 'validationPasswordMix': ('Password must contain letters and numbers.','يجب أن تحتوي كلمة المرور على أحرف وأرقام.','पासवर्ड में अक्षर और संख्याएँ होनी चाहिए।','கடவுச்சொல்லில் எழுத்துகளும் எண்களும் இருக்க வேண்டும்.',None),
 'validationTooShort': ('{field} must be at least {min} characters.','يجب ألا يقل {field} عن {min} أحرف.','{field} कम से कम {min} अक्षरों का होना चाहिए।','{field} குறைந்தது {min} எழுத்துகள் இருக்க வேண்டும்.',{'field':'String','min':'int'}),
 'validationTooLong': ('{field} must be at most {max} characters.','يجب ألا يزيد {field} عن {max} حرفًا.','{field} अधिकतम {max} अक्षरों का होना चाहिए।','{field} அதிகபட்சம் {max} எழுத்துகள் இருக்க வேண்டும்.',{'field':'String','max':'int'}),
 'passwordRequired': ('Password is required.','كلمة المرور مطلوبة.','पासवर्ड आवश्यक है।','கடவுச்சொல் தேவை.',None),
 'confirmPasswordPrompt': ('Please confirm your password.','يرجى تأكيد كلمة المرور.','कृपया अपने पासवर्ड की पुष्टि करें।','உங்கள் கடவுச்சொல்லை உறுதிப்படுத்தவும்.',None),
 'passwordsDoNotMatch': ('Passwords do not match.','كلمتا المرور غير متطابقتين.','पासवर्ड मेल नहीं खाते।','கடவுச்சொற்கள் பொருந்தவில்லை.',None),
 'errorGeneric': ('Something went wrong. Please try again.','حدث خطأ ما. يرجى المحاولة مرة أخرى.','कुछ गलत हो गया। कृपया फिर कोशिश करें।','ஏதோ தவறு நடந்தது. மீண்டும் முயற்சிக்கவும்.',None),
 'errorNetwork': ('Cannot reach the server. Check your connection and try again.','تعذّر الوصول إلى الخادم. تحقق من اتصالك وحاول مرة أخرى.','सर्वर तक नहीं पहुँच सके। अपना कनेक्शन जाँचें और फिर कोशिश करें।','சேவையகத்தை அடைய முடியவில்லை. உங்கள் இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',None),
 'authInvalidCredentials': ('The email or password is incorrect. Please try again.','البريد الإلكتروني أو كلمة المرور غير صحيحة. يرجى المحاولة مرة أخرى.','ईमेल या पासवर्ड गलत है। कृपया फिर कोशिश करें।','மின்னஞ்சல் அல்லது கடவுச்சொல் தவறானது. மீண்டும் முயற்சிக்கவும்.',None),
 'authAccountDisabled': ('This account has been disabled. Please contact support.','تم تعطيل هذا الحساب. يرجى التواصل مع الدعم.','यह खाता अक्षम कर दिया गया है। कृपया सहायता से संपर्क करें।','இந்தக் கணக்கு முடக்கப்பட்டுள்ளது. ஆதரவைத் தொடர்பு கொள்ளவும்.',None),
 'authEmailInUse': ('An account with this email may already exist. Try signing in or resetting your password.','قد يكون هناك حساب بهذا البريد الإلكتروني بالفعل. جرّب تسجيل الدخول أو إعادة تعيين كلمة المرور.','इस ईमेल से खाता पहले से मौजूद हो सकता है। साइन इन करें या पासवर्ड रीसेट करें।','இந்த மின்னஞ்சலுடன் கணக்கு ஏற்கனவே இருக்கலாம். உள்நுழையவும் அல்லது கடவுச்சொல்லை மீட்டமைக்கவும்.',None),
 'authWeakPassword': ('Please choose a stronger password (8+ characters with letters and numbers).','يرجى اختيار كلمة مرور أقوى (8 أحرف أو أكثر مع أحرف وأرقام).','कृपया अधिक मज़बूत पासवर्ड चुनें (8+ अक्षर, अक्षर और संख्याओं के साथ)।','வலுவான கடவுச்சொல்லைத் தேர்ந்தெடுக்கவும் (எழுத்துகளும் எண்களும் உள்ள 8+ எழுத்துகள்).',None),
 'authInvalidEmail': ('Please enter a valid email address.','يرجى إدخال عنوان بريد إلكتروني صالح.','कृपया मान्य ईमेल पता दर्ज करें।','சரியான மின்னஞ்சல் முகவரியை உள்ளிடவும்.',None),
 'authTooManyRequests': ('Too many attempts. Please wait a few minutes and try again.','محاولات كثيرة جدًا. يرجى الانتظار بضع دقائق ثم المحاولة مرة أخرى.','बहुत अधिक प्रयास। कृपया कुछ मिनट प्रतीक्षा करें और फिर कोशिश करें।','பல முறை முயற்சித்துவிட்டீர்கள். சில நிமிடங்கள் காத்திருந்து மீண்டும் முயற்சிக்கவும்.',None),
 'authRequiresRecentLogin': ('For your security, please sign in again to continue.','حفاظًا على أمانك، يرجى تسجيل الدخول مرة أخرى للمتابعة.','आपकी सुरक्षा के लिए, जारी रखने हेतु कृपया फिर से साइन इन करें।','உங்கள் பாதுகாப்பிற்காக, தொடர மீண்டும் உள்நுழையவும்.',None),
 # --- navigation / patient-facing ---
 'navHome': ('Home','الرئيسية','होम','முகப்பு',None),
 'navAppointments': ('Appointments','المواعيد','अपॉइंटमेंट','சந்திப்புகள்',None),
 'navPatients': ('Patients','المرضى','मरीज़','நோயாளிகள்',None),
 'navBilling': ('Billing','الفواتير','बिलिंग','கட்டணம்',None),
 'navReports': ('Reports','التقارير','रिपोर्ट','அறிக்கைகள்',None),
 'navProfile': ('Profile','الملف الشخصي','प्रोफ़ाइल','சுயவிவரம்',None),
 'navSettings': ('Settings','الإعدادات','सेटिंग्स','அமைப்புகள்',None),
 'navDashboard': ('Dashboard','لوحة التحكم','डैशबोर्ड','டாஷ்போர்டு',None),
 'navToday': ('Today','اليوم','आज','இன்று',None),
 'navQueue': ('Queue','الطابور','कतार','வரிசை',None),
 'navFollowups': ('Follow-ups','المتابعات','फ़ॉलो-अप','தொடர் சந்திப்புகள்',None),
 'navNotifications': ('Notifications','الإشعارات','सूचनाएँ','அறிவிப்புகள்',None),
 'navAccount': ('Account','الحساب','खाता','கணக்கு',None),
 'navRecords': ('Records','السجلات','रिकॉर्ड','பதிவுகள்',None),
 'navClinics': ('Clinics','العيادات','क्लिनिक','கிளினிக்குகள்',None),
 'navOverview': ('Overview','نظرة عامة','अवलोकन','மேலோட்டம்',None),
 'navBranches': ('Branches','الفروع','शाखाएँ','கிளைகள்',None),
 'navLaboratory': ('Laboratory','المختبر','प्रयोगशाला','ஆய்வகம்',None),
 'bookAppointment': ('Book appointment','حجز موعد','अपॉइंटमेंट बुक करें','சந்திப்பை முன்பதிவு செய்',None),
 'myAppointments': ('My appointments','مواعيدي','मेरे अपॉइंटमेंट','என் சந்திப்புகள்',None),
 'prescriptions': ('Prescriptions','الوصفات الطبية','पर्चे','மருந்துச் சீட்டுகள்',None),
 'labReports': ('Lab reports','تقارير المختبر','लैब रिपोर्ट','ஆய்வக அறிக்கைகள்',None),
 'upcomingAppointment': ('Upcoming appointment','الموعد القادم','आगामी अपॉइंटमेंट','வரவிருக்கும் சந்திப்பு',None),
 'noAppointments': ('No appointments yet','لا توجد مواعيد بعد','अभी कोई अपॉइंटमेंट नहीं','இன்னும் சந்திப்புகள் இல்லை',None),
 # --- statuses ---
 'statusBooked': ('Booked','محجوز','बुक किया गया','முன்பதிவு செய்யப்பட்டது',None),
 'statusConfirmed': ('Confirmed','مؤكد','पुष्टि हो गई','உறுதிசெய்யப்பட்டது',None),
 'statusCheckedIn': ('Checked in','تم تسجيل الوصول','चेक-इन हो गया','வருகை பதிவு செய்யப்பட்டது',None),
 'statusInConsultation': ('In consultation','في الاستشارة','परामर्श में','ஆலோசனையில்',None),
 'statusCompleted': ('Completed','مكتمل','पूर्ण','முடிந்தது',None),
 'statusCancelled': ('Cancelled','ملغى','रद्द','ரத்து செய்யப்பட்டது',None),
 'statusNoShow': ('No show','لم يحضر','उपस्थित नहीं हुए','வரவில்லை',None),
 'statusDraft': ('Draft','مسودة','ड्राफ़्ट','வரைவு',None),
 'statusFinalized': ('Finalized','نهائي','अंतिम','இறுதியானது',None),
 'statusPaid': ('Paid','مدفوع','भुगतान किया','செலுத்தப்பட்டது',None),
 'statusPartiallyPaid': ('Partially paid','مدفوع جزئيًا','आंशिक भुगतान','பகுதியளவு செலுத்தப்பட்டது',None),
 'statusOutstanding': ('Outstanding','مستحق','बकाया','நிலுவையில்',None),
 'statusRefunded': ('Refunded','تم الاسترداد','रिफ़ंड किया गया','திரும்பப் பெறப்பட்டது',None),
 # --- plurals / relative time ---
 'appointmentsCount': (
   '{count, plural, =0{No appointments} =1{1 appointment} other{{count} appointments}}',
   '{count, plural, =0{لا توجد مواعيد} =1{موعد واحد} =2{موعدان} few{{count} مواعيد} many{{count} موعدًا} other{{count} موعد}}',
   '{count, plural, =0{कोई अपॉइंटमेंट नहीं} =1{1 अपॉइंटमेंट} other{{count} अपॉइंटमेंट}}',
   '{count, plural, =0{சந்திப்புகள் இல்லை} =1{1 சந்திப்பு} other{{count} சந்திப்புகள்}}',
   {'count':'int'}),
 'minutesAgo': (
   '{count, plural, =1{1 minute ago} other{{count} minutes ago}}',
   '{count, plural, =1{قبل دقيقة} =2{قبل دقيقتين} few{قبل {count} دقائق} many{قبل {count} دقيقة} other{قبل {count} دقيقة}}',
   '{count, plural, =1{1 मिनट पहले} other{{count} मिनट पहले}}',
   '{count, plural, =1{1 நிமிடத்துக்கு முன்} other{{count} நிமிடங்களுக்கு முன்}}',
   {'count':'int'}),
}
LOCALES = ['en','ar','hi','ta']
for i,loc in enumerate(LOCALES):
    d = {'@@locale': loc}
    if loc != 'en':
        d['@@comment'] = 'Machine-assisted starter translation. Not reviewed by a native speaker or professional translator; do not use for legal, clinical or consent wording.'
    for k,v in T.items():
        d[k] = v[i]
        if loc == 'en' and v[4]:
            d['@'+k] = {'placeholders': {n: {'type': t} for n,t in v[4].items()}}
    with open(os.path.join(OUT, f'app_{loc}.arb'),'w',encoding='utf-8') as f:
        json.dump(d,f,ensure_ascii=False,indent=2); f.write('\n')
print(len(T),'keys x',len(LOCALES),'locales')
