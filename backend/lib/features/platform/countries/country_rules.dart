import 'package:country_config/country_config.dart';

import '../common/body_reader.dart';

/// Country-aware field rules. With no profile (a tenant that predates
/// Phase 12) the legacy India behaviour applies unchanged, so existing
/// workflows keep working until the tenant is assigned a country.
class CountryRules {
  const CountryRules(this.profile);

  /// Authoritative country of the tenant, resolved server-side. Never a
  /// value taken from the request.
  final CountryProfile? profile;

  String? get code => profile?.code;

  /// Reads a phone field with the country's rule (E.164 result).
  String? phone(
    BodyReader r,
    String field, {
    bool required = true,
    String prefix = '',
  }) => r.phone(field, required: required, prefix: prefix, country: code);

  /// Validates a postal code. Returns the value when acceptable.
  String? postal(BodyReader a, String? value, {String? legacyCountryText}) {
    final p = profile;
    if (p != null) {
      // Absence is handled by the reader's own required/partial logic.
      if (value == null) return null;
      final failure = p.postalCode.check(value);
      if (failure != null) {
        a.addIssue(
          'postalCode',
          failure == 'required' ? 'required' : 'invalid_postal_code',
          failure == 'required'
              ? '${p.postalCode.label} is required.'
              : 'Enter a valid ${p.postalCode.label}.',
        );
        return null;
      }
      final v = value.trim();
      return v.isEmpty ? null : v;
    }
    if (value != null &&
        (legacyCountryText ?? 'india').toLowerCase() == 'india' &&
        !RegExp(r'^[1-9][0-9]{5}$').hasMatch(value)) {
      a.addIssue(
        'postalCode',
        'invalid_postal_code',
        'Enter a valid 6-digit PIN code.',
      );
      return null;
    }
    return value;
  }

  /// Rejects an address whose `countryCode` differs from the tenant's legal
  /// country and returns the canonical country fields to store.
  Map<String, Object?> canonicalCountry(
    BodyReader a, {
    String? suppliedCode,
    String? suppliedName,
  }) {
    final p = profile;
    if (p == null) {
      return {'country': suppliedName};
    }
    if (suppliedCode != null && suppliedCode != p.code) {
      a.addIssue(
        'countryCode',
        'country_mismatch',
        'The address must be in the clinic\'s registered country.',
      );
    }
    return {'countryCode': p.code, 'country': p.name};
  }
}

/// Maximum number of alternative-language address variants per record.
const int maxLocalizedAddressVariants = 4;

final RegExp _localeTag = RegExp(r'^[a-z]{2,3}(-[A-Z]{2})?$');

/// Reads the optional `localized` address variants:
/// `{ "ar": { "line1": "...", "city": "..." } }`.
/// Variants are presentation data only; the canonical address fields stay
/// authoritative for validation and matching.
Map<String, Object?>? readLocalizedAddress(BodyReader a) {
  final raw = a.body['localized'];
  if (raw == null) return null;
  if (raw is! Map || raw.length > maxLocalizedAddressVariants) {
    a.addIssue(
      'localized',
      'invalid_value',
      'localized must be an object with at most '
          '$maxLocalizedAddressVariants languages.',
    );
    return null;
  }
  final out = <String, Object?>{};
  for (final entry in raw.entries) {
    final tag = entry.key;
    final value = entry.value;
    if (tag is! String || !_localeTag.hasMatch(tag) || value is! Map) {
      a.addIssue(
        'localized',
        'invalid_value',
        'localized keys must be language tags such as "ar".',
      );
      return null;
    }
    final variant = <String, Object?>{};
    for (final f in const ['line1', 'line2', 'city', 'state']) {
      final v = value[f];
      if (v == null) continue;
      if (v is! String || v.trim().isEmpty || v.length > 120) {
        a.addIssue(
          'localized',
          'invalid_value',
          'localized.$tag.$f must be text of at most 120 characters.',
        );
        return null;
      }
      variant[f] = v.trim();
    }
    if (value.keys.any(
      (k) => !const {'line1', 'line2', 'city', 'state'}.contains(k),
    )) {
      a.addIssue(
        'localized',
        'unknown_field',
        'localized.$tag has an unsupported field.',
      );
      return null;
    }
    out[tag] = variant;
  }
  return out;
}
