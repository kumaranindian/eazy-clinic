import 'package:flutter/material.dart';

/// Representative translations (Phase 12). They prove the localization wiring
/// (delegate, fallback, right-to-left); the full string catalogue and review
/// workflow belong to Phase 13. Clinical and legal wording is never
/// translated here.
class AppStrings {
  const AppStrings._(this.locale, this._values);

  final Locale locale;
  final Map<String, String> _values;

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static const Map<String, Map<String, String>> _catalogue = {
    'en': {
      'signIn': 'Sign in',
      'createAccount': 'Create account',
      'country': 'Country',
      'selectCountry': 'Select your country',
      'language': 'Language',
      'welcome': 'Welcome',
    },
    'hi': {
      'signIn': 'साइन इन करें',
      'createAccount': 'खाता बनाएँ',
      'country': 'देश',
      'selectCountry': 'अपना देश चुनें',
      'language': 'भाषा',
      'welcome': 'स्वागत है',
    },
    'ar': {
      'signIn': 'تسجيل الدخول',
      'createAccount': 'إنشاء حساب',
      'country': 'الدولة',
      'selectCountry': 'اختر دولتك',
      'language': 'اللغة',
      'welcome': 'مرحبًا',
    },
  };

  static const Set<String> supportedLanguageCodes = {'en', 'hi', 'ar'};

  /// Strings for [context]'s locale; English when none are installed (so
  /// widgets keep working in tests and in apps that have not added the
  /// delegate).
  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      AppStrings._(const Locale('en'), _catalogue['en']!);

  String get signIn => _get('signIn');
  String get createAccount => _get('createAccount');
  String get country => _get('country');
  String get selectCountry => _get('selectCountry');
  String get language => _get('language');
  String get welcome => _get('welcome');

  String _get(String key) => _values[key] ?? _catalogue['en']![key]!;
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppStrings.supportedLanguageCodes.contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async {
    final code = AppStrings.supportedLanguageCodes.contains(locale.languageCode)
        ? locale.languageCode
        : 'en';
    return AppStrings._(locale, AppStrings._catalogue[code]!);
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
