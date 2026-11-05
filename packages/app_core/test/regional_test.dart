import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, Object?> dto({
  String code = 'AE',
  String tz = 'Asia/Dubai',
  String currency = 'AED',
  String tag = 'en',
  bool rtl = false,
  String? branchTz,
}) => {
  'countryConfigured': true,
  'country': {
    'code': code,
    'name': code == 'AE' ? 'United Arab Emirates' : 'India',
    'adminAreaLabel': code == 'AE' ? 'Emirate' : 'State',
    'postalCode': {'label': code == 'AE' ? 'PO Box' : 'PIN code'},
  },
  'effective': {
    'timezone': tz,
    'branchTimezone': ?branchTz,
    'currency': currency,
    'currencyMinorUnits': 2,
    'locale': {'tag': tag, 'rtl': rtl, 'source': 'country'},
  },
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('RegionalConfig', () {
    test('parses the server DTO', () {
      final c = RegionalConfig.fromJson(dto(branchTz: 'Asia/Kolkata'));
      expect(c.countryConfigured, isTrue);
      expect(c.countryCode, 'AE');
      expect(c.currency, 'AED');
      expect(c.effectiveTimezone, 'Asia/Kolkata'); // branch zone wins
      expect(c.adminAreaLabel, 'Emirate');
      expect(c.postalCodeLabel, 'PO Box');
    });

    test('an unconfigured clinic uses the explicit fallback, not a guess', () {
      final c = RegionalConfig.fromJson({
        'countryConfigured': false,
        'country': null,
        'effective': {
          'timezone': null,
          'currency': 'INR',
          'locale': {'tag': 'en', 'rtl': false},
        },
      });
      expect(c.countryConfigured, isFalse);
      expect(c.countryCode, isNull);
      expect(c.effectiveTimezone, 'UTC');
      expect(RegionalConfig.fallback.countryConfigured, isFalse);
    });
  });

  group('RegionalFormatter', () {
    // 18:30 UTC on 1 June is midnight in India and 22:30 in Dubai.
    final instant = DateTime.utc(2026, 6, 1, 18, 30);

    test('renders the same instant in each branch time zone', () {
      final india = RegionalFormatter(
        RegionalConfig.fromJson(
          dto(code: 'IN', tz: 'Asia/Kolkata', currency: 'INR', tag: 'en-IN'),
        ),
      );
      final dubai = RegionalFormatter(
        RegionalConfig.fromJson(dto(tag: 'en-AE')),
      );
      expect(india.date(instant), contains('2 Jun 2026'));
      expect(dubai.date(instant), 'Jun 1, 2026'); // CLDR en-AE pattern
      expect(dubai.time(instant).toLowerCase(), contains('10:30'));
      expect(dubai.date(instant, timezone: 'Asia/Kolkata'), 'Jun 2, 2026');
    });

    test('money uses the currency code and its minor units', () {
      final f = RegionalFormatter(RegionalConfig.fromJson(dto(tag: 'en-AE')));
      expect(f.money(123450), contains('1,234.50'));
      expect(f.money(123450), contains('AED'));
      expect(f.money(1234567, currency: 'KWD'), contains('1,234.567'));
      expect(f.money(1234, currency: 'JPY'), isNot(contains('.')));
    });
  });

  group('locale preference', () {
    test('only supported UI languages can be chosen', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(appLocaleProvider), isNull);
      c.read(localePreferenceProvider.notifier).choose('ar');
      expect(c.read(appLocaleProvider), const Locale('ar'));
      c.read(localePreferenceProvider.notifier).choose('xx');
      expect(c.read(appLocaleProvider), isNull);
      c.read(localePreferenceProvider.notifier).choose('hi');
      expect(c.read(appLocaleProvider), const Locale('hi'));
    });

    test('resolution order is user, clinic, then fallback', () {
      final cfg = RegionalConfig.fromJson(dto(tag: 'ar-AE', rtl: true));
      expect(resolveAppLocale(userPreference: 'hi', config: cfg).tag, 'hi');
      expect(resolveAppLocale(userPreference: 'ta').tag, 'ta');
      expect(resolveAppLocale(config: cfg).tag, 'ar');
      expect(resolveAppLocale(config: cfg).isRtl, isTrue);
      expect(resolveAppLocale().tag, 'en');
    });
  });

  group('generated localizations', () {
    Widget host(Locale? locale, Widget child) => MaterialApp(
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: appLocalizationDelegates,
      theme: EcTheme.light(),
      home: Scaffold(body: child),
    );

    testWidgets('English, Arabic, Hindi and Tamil strings resolve', (
      tester,
    ) async {
      final seen = <String, String>{};
      for (final code in ['en', 'ar', 'hi', 'ta']) {
        await tester.pumpWidget(
          host(
            Locale(code),
            Builder(
              builder: (context) {
                seen[code] = context.l10n.signIn;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(seen['en'], 'Sign in');
      expect(seen['ar'], 'تسجيل الدخول');
      expect(seen['hi'], 'साइन इन करें');
      expect(seen['ta'], 'உள்நுழை');
    });

    testWidgets('an unsupported device language falls back to English', (
      tester,
    ) async {
      late String text;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: appLocalizationDelegates,
          home: Builder(
            builder: (context) {
              text = context.l10n.country;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(text, 'Country');
    });

    testWidgets('widgets work with no localization installed', (tester) async {
      late String text;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              text = context.l10n.welcome;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(text, 'Welcome');
    });

    testWidgets('plurals follow each language\'s rules', (tester) async {
      final seen = <String, List<String>>{};
      for (final code in ['en', 'ar', 'hi', 'ta']) {
        await tester.pumpWidget(
          host(
            Locale(code),
            Builder(
              builder: (context) {
                seen[code] = [
                  for (final n in [0, 1, 2, 5])
                    context.l10n.appointmentsCount(n),
                ];
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(seen['en'], [
        'No appointments',
        '1 appointment',
        '2 appointments',
        '5 appointments',
      ]);
      expect(seen['ar']![1], 'موعد واحد');
      expect(seen['ar']![2], 'موعدان');
      expect(seen['ar']![3], contains('5'));
      expect(seen['hi']![1], '1 अपॉइंटमेंट');
      expect(seen['ta']![3], contains('5'));
    });
  });

  group('right-to-left smoke test (Arabic)', () {
    testWidgets('layout mirrors and does not overflow', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);
      const destinations = [
        EcNavDestination(label: 'Home', icon: Icons.home_outlined),
        EcNavDestination(label: 'Patients', icon: Icons.people_outline),
      ];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: appLocalizationDelegates,
          theme: EcTheme.light(),
          home: EcNavScaffold(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: (_) {},
            body: Center(
              child: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EcTextField(label: 'الاسم الكامل'),
                    const SizedBox(height: 12),
                    EcPrimaryButton(label: 'تسجيل الدخول', onPressed: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(EcNavScaffold));
      expect(Directionality.of(context), TextDirection.rtl);
      // the navigation rail moves to the right edge, content to the left of it
      expect(tester.getCenter(find.text('Patients')).dx, greaterThan(1000));
      expect(
        tester.getCenter(find.text('تسجيل الدخول')).dx,
        lessThan(tester.getCenter(find.text('Patients')).dx),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
