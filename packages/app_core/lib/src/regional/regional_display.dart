import 'package:country_config/country_config.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Display settings used by every screen's date, time, number and money
/// text. The app root ([LocalizedAppScope]) keeps it in step with the user's
/// language and the clinic's configuration; screens call the static helpers.
///
/// * Instants are stored in UTC. They are shown in the **branch or clinic
///   time zone** when known (never silently the device zone for clinic
///   events); platform-level screens with no clinic fall back to the device
///   zone.
/// * Money is minor units plus an ISO 4217 code; the number of decimals comes
///   from the currency. Amounts are never converted.
/// * Defaults before a clinic configuration is known: English, Indian number
///   grouping, rupee (the behaviour of clinics created before country
///   configuration).
abstract final class RegionalDisplay {
  static String _language = 'en';
  static String? _countryCode;
  static String? _timezone;
  static String _currency = 'INR';

  /// Loads date symbols for all locales. Call once before `runApp`.
  static Future<void> ensureInitialized() => initializeDateFormatting();

  /// Sets the active display settings.
  static void update({
    required String language,
    String? countryCode,
    String? timezone,
    String? currency,
  }) {
    _language = language;
    _countryCode = countryCode;
    _timezone = timezone;
    _currency = currency ?? 'INR';
    Intl.defaultLocale = locale;
  }

  /// Back to the pre-configuration defaults.
  static void reset() => update(language: 'en');

  /// ICU locale for formatting, e.g. `en-IN`, `ar-AE`, `hi-IN`.
  static String get locale {
    final country = _countryCode ?? 'IN';
    return '$_language-$country';
  }

  static String get currency => _currency;
  static String? get timezone => _timezone;

  /// Runs [format] with the best locale for which data is available (full
  /// locale, then language, then English).
  static String _safe(String Function(String locale) format) {
    for (final l in [locale, _language, 'en']) {
      try {
        return format(l);
      } on Object {
        // locale data not loaded: try the next, more general, locale
      }
    }
    return '—';
  }

  static DateTime? _parse(Object? iso) =>
      iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

  static bool _hasZone(String? tz) => tz != null && Timezones.isValid(tz);

  /// `2026-06-01T18:30:00Z` → `2 Jun 2026` in the clinic/branch zone.
  static String date(Object? iso, {String? timezone}) {
    final d = _parse(iso);
    if (d == null) return '—';
    final tz = timezone ?? _timezone;
    return _safe(
      (l) => _hasZone(tz)
          ? LocaleFormatter(l).date(d, tz!)
          : DateFormat.yMMMd(l.replaceAll('-', '_')).format(d.toLocal()),
    );
  }

  static String time(Object? iso, {String? timezone}) {
    final d = _parse(iso);
    if (d == null) return '—';
    final tz = timezone ?? _timezone;
    return _safe(
      (l) => _hasZone(tz)
          ? LocaleFormatter(l).time(d, tz!)
          : DateFormat.jm(l.replaceAll('-', '_')).format(d.toLocal()),
    );
  }

  static String dateTime(Object? iso, {String? timezone}) {
    final d = _parse(iso);
    if (d == null) return '—';
    final tz = timezone ?? _timezone;
    return _safe(
      (l) => _hasZone(tz)
          ? LocaleFormatter(l).dateTime(d, tz!)
          : DateFormat.yMMMd(
              l.replaceAll('-', '_'),
            ).add_jm().format(d.toLocal()),
    );
  }

  static String number(num value, {int? decimalDigits}) => _safe(
    (l) => LocaleFormatter(l).number(value, decimalDigits: decimalDigits),
  );

  /// Minor units of [currency] (defaults to the clinic currency). `—` when
  /// [minor] is not a whole number.
  static String money(Object? minor, [Object? currency]) {
    if (minor is! int) return '—';
    final code = currency is String && Currency.isWellFormed(currency)
        ? currency
        : _currency;
    return _safe((l) => LocaleFormatter(l).currency(minor, code));
  }

  /// Short label for money input fields: the symbol when the currency has an
  /// unambiguous one, else its ISO code.
  static String currencyLabel([Object? currency]) {
    final code = currency is String && Currency.isWellFormed(currency)
        ? currency
        : _currency;
    return LocaleFormatter.currencySymbols[code] ?? code;
  }
}
