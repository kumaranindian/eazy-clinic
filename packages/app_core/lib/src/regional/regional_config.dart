import 'package:country_config/country_config.dart';

/// The country configuration a signed-in clinic user sees, as returned by
/// `GET /clinics/current/country-config`. It is read-only presentation data:
/// the backend remains the authority for the clinic's legal country.
class RegionalConfig {
  const RegionalConfig({
    required this.countryConfigured,
    required this.currency,
    required this.currencyMinorUnits,
    required this.localeTag,
    required this.isRtl,
    this.countryCode,
    this.countryName,
    this.timezone,
    this.branchTimezone,
    this.adminAreaLabel,
    this.postalCodeLabel,
  });

  factory RegionalConfig.fromJson(Map<String, Object?> json) {
    final effective = (json['effective']! as Map).cast<String, Object?>();
    final locale = (effective['locale']! as Map).cast<String, Object?>();
    final country = (json['country'] as Map?)?.cast<String, Object?>();
    final currency = effective['currency']! as String;
    return RegionalConfig(
      countryConfigured: json['countryConfigured'] == true,
      countryCode: country?['code'] as String?,
      countryName: country?['name'] as String?,
      timezone: effective['timezone'] as String?,
      branchTimezone: effective['branchTimezone'] as String?,
      currency: currency,
      currencyMinorUnits:
          effective['currencyMinorUnits'] as int? ??
          Currency.minorUnits(currency),
      localeTag: locale['tag']! as String,
      isRtl: locale['rtl'] == true,
      adminAreaLabel: country?['adminAreaLabel'] as String?,
      postalCodeLabel: (country?['postalCode'] as Map?)?['label'] as String?,
    );
  }

  /// Used before the configuration has loaded and for tenants that predate
  /// country configuration: English, rupee, no time zone (device-independent
  /// formatting then falls back to UTC).
  static const RegionalConfig fallback = RegionalConfig(
    countryConfigured: false,
    currency: 'INR',
    currencyMinorUnits: 2,
    localeTag: 'en',
    isRtl: false,
  );

  final bool countryConfigured;
  final String? countryCode;
  final String? countryName;

  /// Clinic default IANA zone.
  final String? timezone;

  /// Zone of the requested branch, when one was asked for.
  final String? branchTimezone;
  final String currency;
  final int currencyMinorUnits;
  final String localeTag;
  final bool isRtl;
  final String? adminAreaLabel;
  final String? postalCodeLabel;

  String get effectiveTimezone => branchTimezone ?? timezone ?? 'UTC';
}

/// Formats values for display with the clinic's configuration.
///
/// * Instants are stored in UTC and shown in the branch/clinic time zone.
/// * Money is minor units + ISO currency code; no conversion is ever done.
class RegionalFormatter {
  RegionalFormatter(this.config, {String? localeOverride})
    : _formatter = LocaleFormatter(localeOverride ?? config.localeTag);

  final RegionalConfig config;
  final LocaleFormatter _formatter;

  String date(DateTime instant, {String? timezone}) =>
      _formatter.date(instant, timezone ?? config.effectiveTimezone);

  String time(DateTime instant, {String? timezone}) =>
      _formatter.time(instant, timezone ?? config.effectiveTimezone);

  String dateTime(DateTime instant, {String? timezone}) =>
      _formatter.dateTime(instant, timezone ?? config.effectiveTimezone);

  String number(num value, {int? decimalDigits}) =>
      _formatter.number(value, decimalDigits: decimalDigits);

  /// [minorUnits] of [currency] (defaults to the clinic currency).
  String money(int minorUnits, {String? currency}) =>
      _formatter.currency(minorUnits, currency ?? config.currency);
}
