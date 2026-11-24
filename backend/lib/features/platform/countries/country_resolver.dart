import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:country_config/country_config.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import 'country_directory.dart';

/// Resolves the effective country configuration for a tenant by layering,
/// from most to least authoritative:
///
/// 1. country master and country policy (platform-managed, versioned),
/// 2. the tenant's legal country (set once, server-side),
/// 3. tenant overrides the country policy allows (settings),
/// 4. branch settings (time zone),
/// 5. the user's display preference (presentation only),
/// 6. deployment configuration (informational).
///
/// Country, tenant, branch, user locale and deployment region stay distinct:
/// no layer can change a higher one.
class CountryConfigResolver {
  CountryConfigResolver(this._store, this.directory, {this.deploymentRegion});

  final DocumentStore _store;
  final CountryDirectory directory;
  final String? deploymentRegion;

  /// Safe client DTO. [branchId] must already be authorized by the caller.
  Future<Map<String, Object?>> forTenant(
    String tenantId, {
    String? branchId,
    String? userLocale,
  }) async {
    final code = await directory.tenantCountryCode(tenantId);
    final settings =
        await _store.get('tenants/$tenantId/clinic_settings/operations') ??
        const <String, Object?>{};
    final deployment = {'region': deploymentRegion};

    if (code == null) {
      // Tenant predates Phase 12 and has no assigned country. Country-
      // dependent (tax, compliance, payment) features must treat this as
      // "not configured"; presentation falls back to the existing defaults.
      final locale = resolveLocale(
        supported: supportedUiLanguages,
        userPreference: userLocale,
        tenantDefault: settings['language'] as String?,
      );
      return {
        'tenantId': tenantId,
        'countryConfigured': false,
        'country': null,
        'effective': {
          'timezone': settings['timezone'],
          'currency': settings['currency'] ?? 'INR',
          'language': settings['language'] ?? 'en',
          'locale': {
            'tag': locale.tag,
            'rtl': locale.isRtl,
            'source': locale.source,
          },
        },
        'deployment': deployment,
      };
    }

    final profile = await directory.profile(code);
    if (profile == null || profile.status == CountryStatus.disabled) {
      // Fail closed: never guess a country configuration.
      throw const ApiException(
        ApiErrorCode.unavailable,
        'Country configuration is unavailable. Contact support.',
      );
    }

    final overrides = profile.policy.allowedTenantOverrides;
    String? tzFrom(Object? v) => v is String && Timezones.isValid(v) ? v : null;

    final tenantTz = tzFrom(settings['timezone']);
    final timezone = overrides.contains('timezone') && tenantTz != null
        ? tenantTz
        : (profile.suggestedTimezones.isEmpty
              ? null
              : profile.suggestedTimezones.first);

    final tenantCurrency = settings['currency'];
    final currency =
        overrides.contains('currency') &&
            tenantCurrency is String &&
            profile.policy.supportedCurrencies.contains(tenantCurrency)
        ? tenantCurrency
        : profile.defaultCurrency;

    final tenantLanguage = settings['language'];
    final languageAllowed =
        tenantLanguage is String &&
        overrides.contains('language') &&
        profile.locales.any(
          (l) => l.split('-').first == tenantLanguage.split('-').first,
        );
    final locale = resolveLocale(
      supported: supportedUiLanguages,
      userPreference: userLocale,
      tenantDefault: languageAllowed ? tenantLanguage : null,
      countryDefault: profile.defaultLocale,
    );

    String? branchTimezone;
    if (branchId != null) {
      final branch = await _store.get('tenants/$tenantId/branches/$branchId');
      if (branch == null) {
        throw const ApiException.notFound('Branch not found.');
      }
      branchTimezone = tzFrom(branch['timezone']) ?? timezone;
    }

    final tenant = await _store.get('tenants/$tenantId');
    return {
      'tenantId': tenantId,
      'countryConfigured': true,
      'country': profile.toClientJson(),
      'tenant': {
        'countryCode': code,
        'configurationVersionAtAssignment': tenant?['countryConfigVersion'],
      },
      'effective': {
        'timezone': timezone,
        if (branchId != null) 'branchTimezone': branchTimezone,
        'currency': currency,
        'currencyMinorUnits': Currency.minorUnits(currency),
        'language': locale.languageCode,
        'locale': {
          'tag': locale.tag,
          'rtl': locale.isRtl,
          'source': locale.source,
        },
      },
      'deployment': deployment,
    };
  }
}
