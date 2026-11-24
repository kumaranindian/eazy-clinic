import 'package:country_config/country_config.dart';

import '../../../core/data/document_store.dart';

/// Reads the platform country master (`countries/{ISO code}`).
///
/// Fails closed: a missing, malformed or invalid stored profile is treated as
/// "not available", never replaced by guessed defaults. Profiles are cached
/// for [ttl]; security- and compliance-sensitive paths (onboarding,
/// provisioning, migration) pass `fresh: true` or read inside a transaction.
class CountryDirectory {
  CountryDirectory(
    this._store, {
    DateTime Function()? clock,
    this.ttl = const Duration(seconds: 60),
  }) : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final DateTime Function() _clock;
  final Duration ttl;

  static const String collection = 'countries';
  static final RegExp _code = RegExp(r'^[A-Z]{2}$');

  final Map<String, ({CountryProfile? profile, DateTime at})> _cache = {};

  /// True for a syntactically valid ISO 3166-1 alpha-2 code. Always check
  /// before building a path from a code.
  static bool isWellFormedCode(String? code) =>
      code != null && _code.hasMatch(code);

  static String pathOf(String code) => '$collection/$code';

  /// Parses a stored document; null when absent or invalid (fail closed).
  static CountryProfile? parse(DocData? data) {
    if (data == null) return null;
    try {
      final profile = CountryProfile.fromJson(data);
      return profile.problems().isEmpty ? profile : null;
    } on Object {
      return null;
    }
  }

  Future<CountryProfile?> profile(String code, {bool fresh = false}) async {
    if (!isWellFormedCode(code)) return null;
    final now = _clock();
    final hit = _cache[code];
    if (!fresh && hit != null && now.difference(hit.at) < ttl) {
      return hit.profile;
    }
    final parsed = parse(await _store.get(pathOf(code)));
    _cache[code] = (profile: parsed, at: now);
    return parsed;
  }

  /// Reads inside a transaction (always fresh, serializable).
  static Future<CountryProfile?> profileIn(TxContext tx, String code) async {
    if (!isWellFormedCode(code)) return null;
    return parse(await tx.get(pathOf(code)));
  }

  /// Drops cached profiles after an administrative change. Other server
  /// instances converge within [ttl].
  void invalidate([String? code]) {
    if (code == null) {
      _cache.clear();
    } else {
      _cache.remove(code);
    }
  }

  /// The tenant's legal country code from the trusted tenant record, or null
  /// for tenants that predate Phase 12 and have not been migrated.
  Future<String?> tenantCountryCode(String tenantId) async {
    final tenant = await _store.get('tenants/$tenantId');
    final code = tenant?['countryCode'];
    return code is String && isWellFormedCode(code) ? code : null;
  }

  Future<CountryProfile?> tenantProfile(String tenantId) async {
    final code = await tenantCountryCode(tenantId);
    return code == null ? null : profile(code);
  }
}
