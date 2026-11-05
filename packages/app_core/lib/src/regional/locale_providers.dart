import 'package:common_models/common_models.dart';
import 'package:country_config/country_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../api/api_client.dart';
import 'regional_config.dart';

/// UI languages with resources: English (baseline), Arabic (right-to-left),
/// Hindi and Tamil. Arabic, Hindi and Tamil are starter packs.
final List<Locale> supportedAppLocales = [
  for (final code in supportedUiLanguages) Locale(code),
];

/// Delegates every app installs on `MaterialApp.router`: generated app
/// strings plus the Material/Widgets/Cupertino localizations.
const List<LocalizationsDelegate<Object?>> appLocalizationDelegates =
    AppLocalizations.localizationsDelegates;

/// The user's language choice (presentation only). `null` follows the
/// device. It is initialised from the account (`preferredLanguage`) after
/// sign-in and saved back when the user changes it. It never changes the
/// clinic's country, currency, policy, or any stored value.
class LocalePreference extends Notifier<String?> {
  @override
  String? build() => null;

  /// Accepts only supported UI languages; anything else clears the choice.
  /// With [persist] the choice is also saved on the account (best effort: a
  /// failure keeps the local choice).
  void choose(String? languageCode, {bool persist = false}) {
    final value = isSupportedUiLanguage(languageCode) ? languageCode : null;
    state = value;
    if (persist) {
      // Ignore the result: the screen already shows the new language.
      ref.read(localePersistenceProvider).save(value);
    }
  }

  /// Applies the account's stored language after sign-in (no write-back).
  void applyAccountLanguage(String? languageCode) {
    if (isSupportedUiLanguage(languageCode)) state = languageCode;
  }

  /// Back to following the device (after sign-out).
  void reset() => state = null;
}

final localePreferenceProvider = NotifierProvider<LocalePreference, String?>(
  LocalePreference.new,
);

/// Saves the language on the signed-in account.
abstract interface class LocalePersistence {
  Future<void> save(String? languageCode);
}

class _ApiLocalePersistence implements LocalePersistence {
  _ApiLocalePersistence(this._ref);

  final Ref _ref;

  @override
  Future<void> save(String? languageCode) async {
    try {
      await _ref
          .read(apiClientProvider)
          .patch('/auth/me', body: {'preferredLanguage': languageCode});
    } on Object {
      // Best effort. The language is a convenience, not a record.
    }
  }
}

/// Overridden in tests; production saves through `PATCH /auth/me`.
final localePersistenceProvider = Provider<LocalePersistence>(
  _ApiLocalePersistence.new,
);

/// Locale handed to `MaterialApp.locale`: the user's choice or `null`
/// (device default, falling back to English).
final appLocaleProvider = Provider<Locale?>((ref) {
  final choice = ref.watch(localePreferenceProvider);
  return choice == null ? null : Locale(choice);
});

/// Locale the UI resolves from the layers: user choice, then clinic
/// configuration, then country default (see `resolveLocale`).
ResolvedLocale resolveAppLocale({
  String? userPreference,
  RegionalConfig? config,
}) => resolveLocale(
  supported: supportedUiLanguages,
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
