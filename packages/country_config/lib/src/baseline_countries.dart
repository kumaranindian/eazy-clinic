import 'country_profile.dart';

/// Reviewed baseline for the first two markets. Seeded into `countries/` by a
/// platform admin (idempotent, create-if-absent); the stored copy is
/// authoritative afterwards. Other countries are added by platform admins and
/// stay disabled until reviewed.
///
/// Review date: 2026-11-05. Sources: ISO 3166-1 / ISO 4217 maintenance agency
/// lists, CLDR locale data (via `intl`), IANA tz database (via `timezone`),
/// India Post PIN code format (6 digits, first digit 1-9), UAE postal
/// practice (no nationwide postal-code system; PO Box addressing).
/// This metadata is not legal advice and is not a compliance claim.
abstract final class BaselineCountries {
  static const String reviewedOn = '2026-11-05';

  static CountryProfile india({DateTime? effectiveFrom}) => CountryProfile(
    code: 'IN',
    name: 'India',
    nativeName: 'भारत',
    status: CountryStatus.supported,
    onboardingEnabled: true,
    callingCode: '+91',
    defaultCurrency: 'INR',
    locales: const ['en-IN', 'hi-IN'],
    defaultLocale: 'en-IN',
    suggestedTimezones: const ['Asia/Kolkata'],
    adminAreaLabel: 'State',
    postalCode: const PostalCodeRule(
      required: true,
      label: 'PIN code',
      pattern: r'^[1-9][0-9]{5}$',
    ),
    policy: const CountryPolicy(
      allowedTenantOverrides: {'language', 'timezone'},
      supportedCurrencies: ['INR'],
    ),
    configurationVersion: 1,
    effectiveFrom: effectiveFrom ?? DateTime.utc(2026, 11, 5),
    reviewedOn: reviewedOn,
    sources: const [
      'https://www.iso.org/iso-3166-country-codes.html',
      'https://www.iso.org/iso-4217-currency-codes.html',
      'https://www.iana.org/time-zones',
      'https://cldr.unicode.org/',
    ],
  );

  static CountryProfile uae({DateTime? effectiveFrom}) => CountryProfile(
    code: 'AE',
    name: 'United Arab Emirates',
    nativeName: 'الإمارات العربية المتحدة',
    status: CountryStatus.supported,
    onboardingEnabled: true,
    callingCode: '+971',
    defaultCurrency: 'AED',
    locales: const ['en-AE', 'ar-AE'],
    defaultLocale: 'en-AE',
    suggestedTimezones: const ['Asia/Dubai'],
    adminAreaLabel: 'Emirate',
    postalCode: const PostalCodeRule(required: false, label: 'PO Box'),
    policy: const CountryPolicy(
      allowedTenantOverrides: {'language', 'timezone'},
      supportedCurrencies: ['AED'],
    ),
    configurationVersion: 1,
    effectiveFrom: effectiveFrom ?? DateTime.utc(2026, 11, 5),
    reviewedOn: reviewedOn,
    sources: const [
      'https://www.iso.org/iso-3166-country-codes.html',
      'https://www.iso.org/iso-4217-currency-codes.html',
      'https://www.iana.org/time-zones',
      'https://cldr.unicode.org/',
    ],
  );

  static List<CountryProfile> all({DateTime? effectiveFrom}) => [
    india(effectiveFrom: effectiveFrom),
    uae(effectiveFrom: effectiveFrom),
  ];
}
