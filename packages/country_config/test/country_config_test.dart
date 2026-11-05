import 'package:country_config/country_config.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('baseline profiles', () {
    test('India and UAE validate with no problems', () {
      for (final p in BaselineCountries.all()) {
        expect(p.problems(), isEmpty, reason: p.code);
        expect(p.configurationVersion, 1);
        expect(p.isOnboardable, isTrue);
      }
    });

    test('values match the approved baseline', () {
      final i = BaselineCountries.india();
      expect([i.code, i.defaultCurrency, i.callingCode], ['IN', 'INR', '+91']);
      expect(i.suggestedTimezones, ['Asia/Kolkata']);
      final a = BaselineCountries.uae();
      expect([a.code, a.defaultCurrency, a.callingCode], ['AE', 'AED', '+971']);
      expect(a.suggestedTimezones, ['Asia/Dubai']);
      expect(a.locales, contains('ar-AE'));
    });

    test('JSON round trip preserves everything', () {
      for (final p in BaselineCountries.all()) {
        final back = CountryProfile.fromJson(p.toJson());
        expect(back.toJson(), p.toJson());
      }
    });

    test('client DTO hides review metadata and policy internals', () {
      final dto = BaselineCountries.india().toClientJson();
      expect(dto.keys, isNot(contains('sources')));
      expect(dto.keys, isNot(contains('policy')));
      expect(dto.keys, isNot(contains('status')));
      expect(dto['code'], 'IN');
    });

    test('postal rules: India needs a 6-digit PIN, UAE has none', () {
      final india = BaselineCountries.india().postalCode;
      expect(india.check('411001'), isNull);
      expect(india.check('41100'), 'invalid_postal_code');
      expect(india.check('011001'), 'invalid_postal_code');
      expect(india.check(''), 'required');
      final uae = BaselineCountries.uae().postalCode;
      expect(uae.check(null), isNull);
      expect(uae.check('12345'), isNull);
    });
  });

  group('invalid profiles', () {
    CountryProfile bad(Map<String, Object?> patch) => CountryProfile.fromJson({
      ...BaselineCountries.india().toJson(),
      ...patch,
    });

    test('rejects malformed fields', () {
      expect(bad({'code': 'india'}).problems(), isNotEmpty);
      expect(bad({'callingCode': '91'}).problems(), isNotEmpty);
      expect(bad({'defaultCurrency': 'rupee'}).problems(), isNotEmpty);
      expect(
        bad({
          'suggestedTimezones': ['Mars/Base'],
        }).problems(),
        isNotEmpty,
      );
      expect(bad({'defaultLocale': 'fr-FR'}).problems(), isNotEmpty);
      expect(bad({'configurationVersion': 0}).problems(), isNotEmpty);
      expect(
        bad({
          'policy': {
            'allowedTenantOverrides': ['country'],
            'supportedCurrencies': ['INR'],
          },
        }).problems(),
        isNotEmpty,
      );
    });

    test('completeness warnings flag unreviewed profiles', () {
      final p = bad({
        'sources': <String>[],
        'reviewedOn': null,
        'suggestedTimezones': <String>[],
      });
      expect(
        p.completenessWarnings(),
        containsAll([
          'no_review_sources',
          'never_reviewed',
          'no_suggested_timezone',
        ]),
      );
      expect(BaselineCountries.india().completenessWarnings(), isEmpty);
    });

    test('unknown status fails to parse', () {
      expect(
        () => CountryProfile.fromJson({
          ...BaselineCountries.india().toJson(),
          'status': 'beta',
        }),
        throwsFormatException,
      );
    });
  });

  group('timezones', () {
    test('validates IANA names', () {
      expect(Timezones.isValid('Asia/Kolkata'), isTrue);
      expect(Timezones.isValid('Asia/Dubai'), isTrue);
      expect(Timezones.isValid('UTC'), isTrue);
      expect(Timezones.isValid('Asia/Atlantis'), isFalse);
      expect(Timezones.isValid(''), isFalse);
      expect(Timezones.isValid(null), isFalse);
    });

    test('offsets differ per zone', () {
      final t = DateTime.utc(2026, 6, 1, 12);
      expect(
        Timezones.offsetAt(t, 'Asia/Kolkata'),
        const Duration(hours: 5, minutes: 30),
      );
      expect(Timezones.offsetAt(t, 'Asia/Dubai'), const Duration(hours: 4));
    });

    test('unknown zone throws instead of silently falling back', () {
      expect(
        () => Timezones.toZone(DateTime.utc(2026), 'Nope/Zone'),
        throwsArgumentError,
      );
    });
  });

  group('currency', () {
    test('minor units come from the currency, not an assumption of two', () {
      expect(Currency.minorUnits('INR'), 2);
      expect(Currency.minorUnits('AED'), 2);
      expect(Currency.minorUnits('KWD'), 3);
      expect(Currency.minorUnits('JPY'), 0);
      expect(() => Currency.minorUnits('rs'), throwsArgumentError);
    });
  });

  group('phone numbers', () {
    test(
      'accepts valid Indian and UAE mobiles in national and international form',
      () {
        expect(
          PhoneNumbers.validate('98765 43210', 'IN').e164,
          '+919876543210',
        );
        expect(
          PhoneNumbers.validate('+91 98765 43210', 'IN').e164,
          '+919876543210',
        );
        expect(
          PhoneNumbers.validate('050 123 4567', 'AE').e164,
          '+971501234567',
        );
        expect(
          PhoneNumbers.validate('+971 50 123 4567', 'AE').e164,
          '+971501234567',
        );
      },
    );

    test('rejects invalid numbers and numbers of another country', () {
      expect(PhoneNumbers.validate('12345', 'IN').failureCode, 'invalid_phone');
      expect(PhoneNumbers.validate('', 'IN').failureCode, 'invalid_phone');
      expect(PhoneNumbers.validate('+971 50 123 4567', 'IN').isValid, isFalse);
      expect(PhoneNumbers.validate('+91 98765 43210', 'AE').isValid, isFalse);
      expect(
        PhoneNumbers.validate('9876543210', 'ZZ').failureCode,
        'unsupported_country',
      );
    });
  });

  group('locale resolution', () {
    const supported = ['en', 'ar', 'hi'];

    test('user preference wins, then tenant, then country, then fallback', () {
      expect(
        resolveLocale(
          supported: supported,
          userPreference: 'ar',
          tenantDefault: 'hi',
          countryDefault: 'en-IN',
        ).tag,
        'ar',
      );
      expect(
        resolveLocale(
          supported: supported,
          tenantDefault: 'hi',
          countryDefault: 'en-IN',
        ).source,
        'tenant',
      );
      expect(
        resolveLocale(supported: supported, countryDefault: 'ar-AE').tag,
        'ar',
      );
      expect(
        resolveLocale(supported: supported, userPreference: 'fr').source,
        'fallback',
      );
    });

    test('matches by language and flags right-to-left locales', () {
      final r = resolveLocale(supported: supported, userPreference: 'ar-AE');
      expect(r.tag, 'ar');
      expect(r.isRtl, isTrue);
      expect(
        resolveLocale(supported: supported, userPreference: 'en-IN').isRtl,
        isFalse,
      );
    });
  });

  group('formatting', () {
    // 2026-06-01 18:30 UTC is 2026-06-02 00:00 in India and 22:30 in Dubai.
    final instant = DateTime.utc(2026, 6, 1, 18, 30);

    test('renders UTC instants in the branch time zone', () {
      const f = LocaleFormatter('en-IN');
      expect(f.date(instant, 'Asia/Kolkata'), contains('2 Jun 2026'));
      expect(f.date(instant, 'Asia/Dubai'), contains('1 Jun 2026'));
      expect(f.time(instant, 'Asia/Kolkata').toLowerCase(), contains('12:00'));
      expect(f.time(instant, 'Asia/Dubai').toLowerCase(), contains('10:30'));
    });

    test('formats money from minor units with currency-specific digits', () {
      const f = LocaleFormatter('en-IN');
      expect(f.currency(123450, 'INR'), contains('1,234.50'));
      expect(f.currency(123450, 'AED'), contains('1,234.50'));
      expect(f.currency(1234567, 'KWD'), contains('1,234.567'));
      expect(f.currency(1234, 'JPY'), contains('1,234'));
      expect(f.currency(1234, 'JPY'), isNot(contains('.')));
    });

    test('Indian grouping differs from international grouping', () {
      expect(const LocaleFormatter('en-IN').number(1234567), '12,34,567');
      expect(const LocaleFormatter('en-US').number(1234567), '1,234,567');
    });

    test('Arabic locale formats without throwing', () {
      const f = LocaleFormatter('ar-AE');
      expect(f.date(instant, 'Asia/Dubai'), isNotEmpty);
      expect(f.currency(123450, 'AED'), isNotEmpty);
    });
  });
}
