import 'package:country_config/country_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'app_strings.dart';
import 'regional_config.dart';

/// UI languages with representative translations (Phase 12).
const List<Locale> supportedAppLocales = [
  Locale('en'),
  Locale('hi'),
  Locale('ar'),
];

/// Delegates every app installs on `MaterialApp.router`.
const List<LocalizationsDelegate<Object?>> appLocalizationDelegates = [
  AppStrings.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// The user's own language choice (presentation only). `null` follows the
/// device. It is held in memory in Phase 12; persisting it per user is part
/// of Phase 13. It never changes the clinic's country, currency or any
/// stored value.
class LocalePreference extends Notifier<String?> {
  @override
  String? build() => null;

  /// Accepts only supported UI languages; anything else clears the choice.
  void choose(String? languageCode) {
    state = AppStrings.supportedLanguageCodes.contains(languageCode)
        ? languageCode
        : null;
  }
}

final localePreferenceProvider = NotifierProvider<LocalePreference, String?>(
  LocalePreference.new,
);

/// Locale handed to `MaterialApp.locale`: the user's choice or `null`
/// (device default, falling back to English).
final appLocaleProvider = Provider<Locale?>((ref) {
  final choice = ref.watch(localePreferenceProvider);
  return choice == null ? null : Locale(choice);
});

/// Locale the UI resolves for [ctx] layers: user choice, then clinic
/// configuration, then country default (see `resolveLocale`).
ResolvedLocale resolveAppLocale({
  String? userPreference,
  RegionalConfig? config,
}) => resolveLocale(
  supported: [for (final l in supportedAppLocales) l.languageCode],
  userPreference: userPreference,
  tenantDefault: config?.localeTag,
);

/// Reads the signed-in clinic's country configuration. Watch it only from
/// signed-in clinic screens. A failure is surfaced to the screen; the
/// formatter then uses [RegionalConfig.fallback].
final regionalConfigProvider = FutureProvider.autoDispose
    .family<RegionalConfig, String?>((ref, branchId) async {
      final api = ref.watch(apiClientProvider);
      final result = await api.get(
        '/clinics/current/country-config',
        query: {'branchId': ?branchId},
      );
      return RegionalConfig.fromJson(result.map);
    });

/// Formatter for the current clinic. Falls back to the English/rupee
/// defaults until the configuration has loaded.
final regionalFormatterProvider = Provider.autoDispose
    .family<RegionalFormatter, String?>((ref, branchId) {
      final config =
          ref.watch(regionalConfigProvider(branchId)).value ??
          RegionalConfig.fallback;
      final preference = ref.watch(localePreferenceProvider);
      return RegionalFormatter(config, localeOverride: preference);
    });
