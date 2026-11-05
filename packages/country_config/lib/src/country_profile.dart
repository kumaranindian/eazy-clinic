import 'currency.dart';
import 'timezones.dart';

/// Whether a country may be used at all. Disabling is a platform decision and
/// never deletes data.
enum CountryStatus {
  supported('supported'),
  disabled('disabled');

  const CountryStatus(this.wireName);

  final String wireName;

  static CountryStatus? tryParse(String? value) {
    for (final s in values) {
      if (s.wireName == value) return s;
    }
    return null;
  }
}

/// Postal-code rule of a country. Some countries (e.g. the UAE) have no
/// postal-code system, so the rule can be optional or absent.
class PostalCodeRule {
  const PostalCodeRule({
    required this.required,
    required this.label,
    this.pattern,
  });

  factory PostalCodeRule.fromJson(Map<String, Object?> json) => PostalCodeRule(
    required: json['required'] as bool? ?? false,
    label: json['label'] as String? ?? 'Postal code',
    pattern: json['pattern'] as String?,
  );

  final bool required;
  final String label;

  /// Regular expression the whole value must match, or null for free text.
  final String? pattern;

  /// Returns a failure code (`required`, `invalid_postal_code`) or null.
  String? check(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'required' : null;
    final p = pattern;
    if (p != null && !RegExp(p).hasMatch(v)) return 'invalid_postal_code';
    return null;
  }

  Map<String, Object?> toJson() => {
    'required': required,
    'label': label,
    'pattern': pattern,
  };
}

/// What a tenant may adjust inside its country. Anything not listed is fixed
/// by the platform.
class CountryPolicy {
  const CountryPolicy({
    required this.allowedTenantOverrides,
    required this.supportedCurrencies,
  });

  factory CountryPolicy.fromJson(Map<String, Object?> json) => CountryPolicy(
    allowedTenantOverrides: {
      for (final e in (json['allowedTenantOverrides'] as List?) ?? const [])
        e as String,
    },
    supportedCurrencies: [
      for (final e in (json['supportedCurrencies'] as List?) ?? const [])
        e as String,
    ],
  );

  /// Subset of `timezone`, `language`, `currency`.
  final Set<String> allowedTenantOverrides;
  final List<String> supportedCurrencies;

  static const Set<String> overridableKeys = {
    'timezone',
    'language',
    'currency',
  };

  Map<String, Object?> toJson() => {
    'allowedTenantOverrides': allowedTenantOverrides.toList()..sort(),
    'supportedCurrencies': supportedCurrencies,
  };
}

/// Platform-managed country master record (`countries/{ISO-3166-1 alpha-2}`).
///
/// A country is distinct from a tenant (the legal clinic entity), a branch
/// (a location), a user's display locale, and the deployment region.
class CountryProfile {
  const CountryProfile({
    required this.code,
    required this.name,
    required this.status,
    required this.onboardingEnabled,
    required this.callingCode,
    required this.defaultCurrency,
    required this.locales,
    required this.defaultLocale,
    required this.suggestedTimezones,
    required this.adminAreaLabel,
    required this.postalCode,
    required this.policy,
    required this.configurationVersion,
    required this.effectiveFrom,
    this.nativeName,
    this.reviewedOn,
    this.sources = const [],
  });

  factory CountryProfile.fromJson(Map<String, Object?> json) {
    final status = CountryStatus.tryParse(json['status'] as String?);
    if (status == null) throw const FormatException('Unknown country status.');
    final from = json['effectiveFrom'];
    return CountryProfile(
      code: json['code']! as String,
      name: json['name']! as String,
      nativeName: json['nativeName'] as String?,
      status: status,
      onboardingEnabled: json['onboardingEnabled'] as bool? ?? false,
      callingCode: json['callingCode']! as String,
      defaultCurrency: json['defaultCurrency']! as String,
      locales: [for (final l in json['locales']! as List) l as String],
      defaultLocale: json['defaultLocale']! as String,
      suggestedTimezones: [
        for (final t in json['suggestedTimezones']! as List) t as String,
      ],
      adminAreaLabel: json['adminAreaLabel'] as String? ?? 'Region',
      postalCode: PostalCodeRule.fromJson(
        (json['postalCode']! as Map).cast<String, Object?>(),
      ),
      policy: CountryPolicy.fromJson(
        (json['policy']! as Map).cast<String, Object?>(),
      ),
      configurationVersion: json['configurationVersion']! as int,
      effectiveFrom: from is DateTime ? from : DateTime.parse(from! as String),
      reviewedOn: json['reviewedOn'] as String?,
      sources: [
        for (final s in (json['sources'] as List?) ?? const []) s as String,
      ],
    );
  }

  /// ISO 3166-1 alpha-2, upper case.
  final String code;
  final String name;
  final String? nativeName;
  final CountryStatus status;

  /// Platform switch for new clinic applications. Independent of [status] so
  /// onboarding can pause without affecting existing tenants.
  final bool onboardingEnabled;

  /// E.164 calling code with a leading plus (`+91`).
  final String callingCode;

  /// ISO 4217 default currency. Stored amounts are never converted.
  final String defaultCurrency;
  final List<String> locales;
  final String defaultLocale;

  /// Suggested IANA zones. A default, not an invariant: branches choose their own.
  final List<String> suggestedTimezones;
  final String adminAreaLabel;
  final PostalCodeRule postalCode;
  final CountryPolicy policy;

  /// Increases on every change; snapshots are kept in `countries/{code}/versions`.
  final int configurationVersion;
  final DateTime effectiveFrom;

  /// Date (YYYY-MM-DD) the metadata was last reviewed against [sources].
  final String? reviewedOn;
  final List<String> sources;

  static final RegExp _codePattern = RegExp(r'^[A-Z]{2}$');
  static final RegExp _callingPattern = RegExp(r'^\+[1-9][0-9]{0,3}$');
  static final RegExp _localePattern = RegExp(r'^[a-z]{2,3}(-[A-Z]{2})?$');

  bool get isOnboardable =>
      status == CountryStatus.supported && onboardingEnabled;

  /// Hard errors: a profile with any of these must not be saved.
  List<String> problems() {
    final out = <String>[];
    if (!_codePattern.hasMatch(code)) {
      out.add('code must be ISO 3166-1 alpha-2.');
    }
    if (name.trim().isEmpty || name.length > 80) out.add('name is required.');
    if (!_callingPattern.hasMatch(callingCode)) {
      out.add('callingCode must look like +91.');
    }
    if (!Currency.isWellFormed(defaultCurrency)) {
      out.add('defaultCurrency must be an ISO 4217 code.');
    }
    if (locales.isEmpty) out.add('at least one locale is required.');
    for (final l in locales) {
      if (!_localePattern.hasMatch(l)) {
        out.add('locale "$l" is not a BCP-47 tag.');
      }
    }
    if (!locales.contains(defaultLocale)) {
      out.add('defaultLocale must be one of locales.');
    }
    for (final t in suggestedTimezones) {
      if (!Timezones.isValid(t)) out.add('timezone "$t" is not an IANA zone.');
    }
    final pattern = postalCode.pattern;
    if (pattern != null) {
      try {
        RegExp(pattern);
      } on FormatException {
        out.add('postalCode.pattern is not a valid expression.');
      }
    }
    for (final k in policy.allowedTenantOverrides) {
      if (!CountryPolicy.overridableKeys.contains(k)) {
        out.add('policy override "$k" is not supported.');
      }
    }
    for (final c in policy.supportedCurrencies) {
      if (!Currency.isWellFormed(c)) {
        out.add('supported currency "$c" is invalid.');
      }
    }
    if (policy.supportedCurrencies.isNotEmpty &&
        !policy.supportedCurrencies.contains(defaultCurrency)) {
      out.add('defaultCurrency must be among supportedCurrencies.');
    }
    if (configurationVersion < 1) out.add('configurationVersion must be >= 1.');
    return out;
  }

  /// Non-blocking gaps shown to platform admins before enabling onboarding.
  List<String> completenessWarnings() {
    final out = <String>[];
    if (suggestedTimezones.isEmpty) out.add('no_suggested_timezone');
    if (sources.isEmpty) out.add('no_review_sources');
    if (reviewedOn == null) out.add('never_reviewed');
    if (policy.supportedCurrencies.isEmpty) out.add('no_supported_currencies');
    if (postalCode.pattern == null && postalCode.required) {
      out.add('postal_required_without_pattern');
    }
    if (nativeName == null) out.add('no_native_name');
    return out;
  }

  CountryProfile copyWith({
    CountryStatus? status,
    bool? onboardingEnabled,
    int? configurationVersion,
    DateTime? effectiveFrom,
    String? reviewedOn,
    List<String>? sources,
  }) => CountryProfile(
    code: code,
    name: name,
    nativeName: nativeName,
    status: status ?? this.status,
    onboardingEnabled: onboardingEnabled ?? this.onboardingEnabled,
    callingCode: callingCode,
    defaultCurrency: defaultCurrency,
    locales: locales,
    defaultLocale: defaultLocale,
    suggestedTimezones: suggestedTimezones,
    adminAreaLabel: adminAreaLabel,
    postalCode: postalCode,
    policy: policy,
    configurationVersion: configurationVersion ?? this.configurationVersion,
    effectiveFrom: effectiveFrom ?? this.effectiveFrom,
    reviewedOn: reviewedOn ?? this.reviewedOn,
    sources: sources ?? this.sources,
  );

  /// Full document (platform admins and storage).
  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'nativeName': nativeName,
    'status': status.wireName,
    'onboardingEnabled': onboardingEnabled,
    'callingCode': callingCode,
    'defaultCurrency': defaultCurrency,
    'locales': locales,
    'defaultLocale': defaultLocale,
    'suggestedTimezones': suggestedTimezones,
    'adminAreaLabel': adminAreaLabel,
    'postalCode': postalCode.toJson(),
    'policy': policy.toJson(),
    'configurationVersion': configurationVersion,
    'effectiveFrom': effectiveFrom.toUtc().toIso8601String(),
    'reviewedOn': reviewedOn,
    'sources': sources,
  };

  /// Safe subset for clients: no internal review metadata and no policy
  /// internals beyond what a form needs.
  Map<String, Object?> toClientJson() => {
    'code': code,
    'name': name,
    'nativeName': nativeName,
    'callingCode': callingCode,
    'defaultCurrency': defaultCurrency,
    'locales': locales,
    'defaultLocale': defaultLocale,
    'suggestedTimezones': suggestedTimezones,
    'adminAreaLabel': adminAreaLabel,
    'postalCode': {
      'required': postalCode.required,
      'label': postalCode.label,
      'pattern': postalCode.pattern,
    },
    'configurationVersion': configurationVersion,
  };
}
