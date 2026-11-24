import 'package:intl/intl.dart';

/// Currency helpers. Amounts are stored as integer **minor units** together
/// with the ISO 4217 code; the number of decimals comes from the currency
/// (maintained `intl` data), never from an assumption of two.
abstract final class Currency {
  static final RegExp _code = RegExp(r'^[A-Z]{3}$');

  /// Syntactic ISO 4217 check (three upper-case letters).
  static bool isWellFormed(String? code) =>
      code != null && _code.hasMatch(code);

  /// Decimal digits of the minor unit (INR 2, AED 2, KWD 3, JPY 0...).
  static int minorUnits(String code) {
    if (!isWellFormed(code)) {
      throw ArgumentError.value(code, 'code', 'Not an ISO 4217 code');
    }
    return NumberFormat.currency(name: code).decimalDigits ?? 2;
  }
}
