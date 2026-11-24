import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'currency.dart';
import 'timezones.dart';

/// Locale-aware presentation of dates, times, numbers and money.
///
/// * Instants are stored in UTC and rendered in an explicit IANA time zone
///   (the branch's), never the device zone.
/// * Money is an integer in minor units plus an ISO 4217 code; the number of
///   decimals comes from the currency. No conversion between currencies.
///
/// Locale data for non-default locales must be loaded first
/// (`initializeDateFormatting`); Flutter's localization delegates do this.
class LocaleFormatter {
  const LocaleFormatter(this.locale);

  /// BCP-47 or ICU locale name (`en-IN`, `ar-AE`).
  final String locale;

  String get _icu => locale.replaceAll('-', '_');

  String date(DateTime instant, String timezone) =>
      DateFormat.yMMMd(_icu).format(Timezones.toZone(instant, timezone));

  String time(DateTime instant, String timezone) =>
      DateFormat.jm(_icu).format(Timezones.toZone(instant, timezone));

  String dateTime(DateTime instant, String timezone) => DateFormat.yMMMd(
    _icu,
  ).add_jm().format(Timezones.toZone(instant, timezone));

  String number(num value, {int? decimalDigits}) => decimalDigits == null
      ? NumberFormat.decimalPattern(_icu).format(value)
      : NumberFormat.decimalPatternDigits(
          locale: _icu,
          decimalDigits: decimalDigits,
        ).format(value);

  /// Formats [minorUnits] of [currencyCode] (e.g. `123450`, `INR` → ₹1,234.50).
  ///
  /// The ISO code is always the source of truth. A symbol is used only for
  /// currencies whose symbol is unambiguous (see [currencySymbols]); every
  /// other currency is shown with its ISO code (`AED 1,234.50`), never with a
  /// guessed abbreviation.
  String currency(int minorUnits, String currencyCode) {
    final digits = Currency.minorUnits(currencyCode);
    final major = minorUnits / math.pow(10, digits);
    final symbol = currencySymbols[currencyCode] ?? '$currencyCode\u00A0';
    return NumberFormat.currency(
      locale: _icu,
      symbol: symbol,
      name: currencyCode,
      decimalDigits: digits,
    ).format(major);
  }

  /// Currencies shown with a symbol. Everything else uses the ISO 4217 code.
  static const Map<String, String> currencySymbols = {
    'INR': '₹',
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
  };
}
