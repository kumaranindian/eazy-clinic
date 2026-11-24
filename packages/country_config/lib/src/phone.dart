import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Result of validating a phone number for a country.
class PhoneCheck {
  const PhoneCheck._(this.e164, this.failureCode);

  const PhoneCheck.valid(String e164) : this._(e164, null);

  const PhoneCheck.invalid(String code) : this._(null, code);

  /// Normalised E.164 number (`+971501234567`), null when invalid.
  final String? e164;

  /// `invalid_phone` or `unsupported_country`.
  final String? failureCode;

  bool get isValid => e164 != null;
}

/// Country-aware phone validation backed by `phone_numbers_parser`
/// (libphonenumber metadata). The destination country must come from trusted
/// configuration (the tenant's country), never from the number itself.
abstract final class PhoneNumbers {
  /// Validates [raw] as a number of [countryCode]. National formats
  /// (`98765 43210`, `050 123 4567`) and international formats are accepted,
  /// but an international number for another country is rejected.
  static PhoneCheck validate(String raw, String countryCode) {
    final IsoCode iso;
    try {
      iso = IsoCode.values.byName(countryCode);
    } on ArgumentError {
      return const PhoneCheck.invalid('unsupported_country');
    }
    final cleaned = raw.trim();
    if (cleaned.isEmpty || cleaned.length > 25) {
      return const PhoneCheck.invalid('invalid_phone');
    }
    try {
      final number = PhoneNumber.parse(cleaned, callerCountry: iso);
      if (number.isoCode != iso || !number.isValid()) {
        return const PhoneCheck.invalid('invalid_phone');
      }
      return PhoneCheck.valid('+${number.countryCode}${number.nsn}');
    } on PhoneNumberException {
      return const PhoneCheck.invalid('invalid_phone');
    }
  }
}
