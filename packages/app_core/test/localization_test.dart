import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../tool/l10n_report.dart' as report;
import 'support/fakes.dart';

final _routerProvider = Provider<GoRouter>((ref) => throw UnimplementedError());

/// App shell wired like the real apps: localization delegates, the locale
/// preference and the shared localized builder.
class Shell {
  Shell({FakeAuthRepository? repo, FakeAuthApi? api})
    : repo = repo ?? FakeAuthRepository(),
      api = api ?? FakeAuthApi();

  final FakeAuthRepository repo;
  final FakeAuthApi api;
  late ProviderContainer container;

  Widget build({String initialLocation = '/login'}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        authApiProvider.overrideWithValue(api),
        appAudienceProvider.overrideWithValue(AppAudience.patient),
        authUiConfigProvider.overrideWithValue(
          const AuthUiConfig(
            appName: 'Test',
            audienceLabel: 'Test',
            registrationEnabled: true,
            registrationNote: '',
          ),
        ),
        localePersistenceProvider.overrideWithValue(_NoSave()),
        _routerProvider.overrideWith(
          (ref) => buildAuthAwareRouter(
            ref,
            registrationEnabled: true,
            publicPaths: const {},
            routes: [
              GoRoute(
                path: '/',
                builder: (c, s) => const Scaffold(body: Text('HOME')),
              ),
            ],
          ),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp.router(
            theme: EcTheme.light(),
            locale: ref.watch(appLocaleProvider),
            supportedLocales: supportedAppLocales,
            localizationsDelegates: appLocalizationDelegates,
            builder: localizedAppBuilder,
            routerConfig: ref.watch(_routerProvider),
          );
        },
      ),
    );
  }
}

class _NoSave implements LocalePersistence {
  final List<String?> saved = [];
  @override
  Future<void> save(String? languageCode) async => saved.add(languageCode);
}

void main() {
  setUpAll(() async {
    await RegionalDisplay.ensureInitialized();
  });
  setUp(RegionalDisplay.reset);

  void phone(WidgetTester t) {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(430, 1000);
    addTearDown(t.view.reset);
  }

  group('sign-in screen in every language', () {
    testWidgets('titles, buttons and links are translated', (t) async {
      phone(t);
      final s = Shell();
      await t.pumpWidget(s.build());
      await t.pumpAndSettle();
      expect(find.text('Sign in'), findsWidgets);

      for (final (code, title, link) in [
        ('ar', 'تسجيل الدخول', 'هل نسيت كلمة المرور؟'),
        ('hi', 'साइन इन करें', 'पासवर्ड भूल गए?'),
        ('ta', 'உள்நுழை', 'கடவுச்சொல்லை மறந்துவிட்டீர்களா?'),
      ]) {
        s.container.read(localePreferenceProvider.notifier).choose(code);
        await t.pumpAndSettle();
        expect(find.text(title), findsWidgets, reason: code);
        expect(find.text(link), findsOneWidget, reason: code);
        expect(find.text('Forgot password?'), findsNothing, reason: code);
      }
    });

    testWidgets('design-system widgets are translated too (password field)', (
      t,
    ) async {
      phone(t);
      final s = Shell();
      await t.pumpWidget(s.build());
      s.container.read(localePreferenceProvider.notifier).choose('ar');
      await t.pumpAndSettle();
      expect(find.text('كلمة المرور'), findsWidgets);
      expect(find.byTooltip('إظهار كلمة المرور'), findsOneWidget);
      expect(find.text('Password'), findsNothing);
    });

    testWidgets(
      'Arabic renders right-to-left with large text and no overflow',
      (t) async {
        phone(t);
        final s = Shell();
        await t.pumpWidget(s.build());
        s.container.read(localePreferenceProvider.notifier).choose('ar');
        await t.pumpAndSettle();
        final ctx = t.element(find.byType(AuthScaffold));
        expect(Directionality.of(ctx), TextDirection.rtl);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('font scaling up to 200% does not overflow in any language', (
      t,
    ) async {
      phone(t);
      final s = Shell();
      for (final code in ['en', 'ar', 'hi', 'ta']) {
        await t.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(430, 1000),
              textScaler: TextScaler.linear(2),
            ),
            child: s.build(),
          ),
        );
        s.container.read(localePreferenceProvider.notifier).choose(code);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: code);
      }
    });

    testWidgets(
      'tap targets and labels meet the accessibility guidelines in each language',
      (t) async {
        phone(t);
        final handle = t.ensureSemantics();
        final s = Shell();
        await t.pumpWidget(s.build());
        for (final code in ['en', 'ar', 'hi', 'ta']) {
          s.container.read(localePreferenceProvider.notifier).choose(code);
          await t.pumpAndSettle();
          await expectLater(
            t,
            meetsGuideline(androidTapTargetGuideline),
            reason: code,
          );
          await expectLater(
            t,
            meetsGuideline(labeledTapTargetGuideline),
            reason: code,
          );
        }
        handle.dispose();
      },
    );

    testWidgets('switching language keeps what the user typed', (t) async {
      phone(t);
      final s = Shell();
      await t.pumpWidget(s.build());
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, 'asha@example.test');
      await t.enterText(find.byType(TextFormField).last, 'Secret123');
      s.container.read(localePreferenceProvider.notifier).choose('ar');
      await t.pumpAndSettle();
      final fields = t
          .widgetList<EditableText>(find.byType(EditableText))
          .toList();
      expect(fields.first.controller.text, 'asha@example.test');
      expect(fields.last.controller.text, 'Secret123');
      expect(find.text('تسجيل الدخول'), findsWidgets);
    });

    testWidgets('validation messages follow the language', (t) async {
      phone(t);
      final s = Shell();
      await t.pumpWidget(s.build());
      s.container.read(localePreferenceProvider.notifier).choose('ar');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
      await t.pumpAndSettle();
      expect(find.text('البريد الإلكتروني مطلوب.'), findsOneWidget);
      expect(find.text('كلمة المرور مطلوبة.'), findsOneWidget);
      expect(find.text('Email is required.'), findsNothing);
    });

    testWidgets('sign-in failures are shown in the user\'s language', (
      t,
    ) async {
      phone(t);
      final s = Shell(
        repo: FakeAuthRepository()
          ..signInFailure = const AuthFailure(
            AuthFailureCode.invalidCredentials,
          ),
      );
      await t.pumpWidget(s.build());
      s.container.read(localePreferenceProvider.notifier).choose('hi');
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, 'a@b.co');
      await t.enterText(find.byType(TextFormField).last, 'wrongpass1');
      await t.tap(find.widgetWithText(FilledButton, 'साइन इन करें'));
      await t.pumpAndSettle();
      expect(
        find.text('ईमेल या पासवर्ड गलत है। कृपया फिर कोशिश करें।'),
        findsOneWidget,
      );
    });
  });

  group('account language', () {
    testWidgets(
      'a signed-in user\'s saved language is applied, and reset on sign-out',
      (t) async {
        phone(t);
        final api = FakeAuthApi()
          ..sessions = [
            AuthSessionDto(
              uid: 'u1',
              accountStatus: AccountStatus.active,
              emailVerified: true,
              accessGranted: true,
              preferredLanguage: 'ta',
            ),
          ];
        final s = Shell(
          repo: FakeAuthRepository(initial: testUser),
          api: api,
        );
        await t.pumpWidget(s.build(initialLocation: '/'));
        await t.pumpAndSettle();
        expect(s.container.read(localePreferenceProvider), 'ta');
        expect(s.container.read(appLocaleProvider), const Locale('ta'));

        s.repo.emit(null);
        await t.pumpAndSettle();
        expect(s.container.read(localePreferenceProvider), isNull);
      },
    );

    test('a choice is saved on the account only when asked to persist', () {
      final saver = _NoSave();
      final c = ProviderContainer(
        overrides: [localePersistenceProvider.overrideWithValue(saver)],
      );
      addTearDown(c.dispose);
      final prefs = c.read(localePreferenceProvider.notifier);
      prefs.choose('ar'); // signed out: local only
      expect(saver.saved, isEmpty);
      prefs.choose('hi', persist: true); // signed in
      expect(saver.saved, ['hi']);
      prefs.choose(null, persist: true); // back to the device language
      expect(saver.saved, ['hi', null]);
      expect(c.read(localePreferenceProvider), isNull);
    });

    test('an unsupported language is never stored', () {
      final c = ProviderContainer(
        overrides: [localePersistenceProvider.overrideWithValue(_NoSave())],
      );
      addTearDown(c.dispose);
      c.read(localePreferenceProvider.notifier).applyAccountLanguage('fr');
      expect(c.read(localePreferenceProvider), isNull);
      c.read(localePreferenceProvider.notifier).applyAccountLanguage('ar');
      expect(c.read(localePreferenceProvider), 'ar');
    });
  });

  group('RegionalDisplay (dates, times, numbers, money)', () {
    const instant = '2026-06-01T18:30:00Z';

    test('shows clinic-local time, not the device\'s', () {
      RegionalDisplay.update(
        language: 'en',
        countryCode: 'AE',
        timezone: 'Asia/Dubai',
        currency: 'AED',
      );
      expect(RegionalDisplay.dateTime(instant), contains('Jun 1, 2026'));
      expect(RegionalDisplay.time(instant).toLowerCase(), contains('10:30'));
      // the same instant in the Indian zone is already the next day
      expect(
        RegionalDisplay.date(instant, timezone: 'Asia/Kolkata'),
        contains('Jun 2, 2026'),
      );
    });

    test('money uses the currency code and its minor units', () {
      RegionalDisplay.update(
        language: 'en',
        countryCode: 'AE',
        timezone: 'Asia/Dubai',
        currency: 'AED',
      );
      expect(RegionalDisplay.money(123450), 'AED 1,234.50');
      expect(RegionalDisplay.money(123450, 'INR'), '₹1,234.50');
      expect(RegionalDisplay.money(1234567, 'KWD'), 'KWD 1,234.567');
      expect(RegionalDisplay.money('x'), '—');
      expect(RegionalDisplay.money(null), '—');
      expect(RegionalDisplay.money(100, 'rupee'), 'AED 1.00'); // bad code
    });

    test('before configuration: English with Indian grouping and rupees', () {
      expect(RegionalDisplay.locale, 'en-IN');
      expect(RegionalDisplay.money(120000), '₹1,200.00');
      expect(RegionalDisplay.number(1234567), '12,34,567');
    });

    test('each language formats in its own style', () {
      RegionalDisplay.update(
        language: 'ar',
        countryCode: 'AE',
        timezone: 'Asia/Dubai',
        currency: 'AED',
      );
      // month name in Arabic; the numeral system is the platform's choice
      expect(RegionalDisplay.date(instant), contains('يونيو'));
      expect(RegionalDisplay.money(123450), contains('1,234.50'));
      RegionalDisplay.update(
        language: 'hi',
        countryCode: 'IN',
        timezone: 'Asia/Kolkata',
        currency: 'INR',
      );
      expect(RegionalDisplay.date(instant), contains('जून'));
    });

    test('invalid input never throws', () {
      expect(RegionalDisplay.date(null), '—');
      expect(RegionalDisplay.dateTime('not a date'), '—');
      expect(RegionalDisplay.date(instant, timezone: 'Nope/Zone'), isNotEmpty);
      RegionalDisplay.update(language: 'xx', countryCode: 'ZZ');
      expect(RegionalDisplay.number(1234.5), isNotEmpty);
    });

    test('currency label for input fields', () {
      RegionalDisplay.update(language: 'en', currency: 'AED');
      expect(RegionalDisplay.currencyLabel(), 'AED');
      expect(RegionalDisplay.currencyLabel('INR'), '₹');
    });
  });

  group('translation completeness', () {
    final reports = report.analyze('lib/l10n');

    test('every locale has every key, with matching placeholders', () {
      expect(reports.map((r) => r.locale), ['ar', 'en', 'hi', 'ta']);
      for (final r in reports) {
        expect(r.missing, isEmpty, reason: '${r.locale} missing');
        expect(r.empty, isEmpty, reason: '${r.locale} empty');
        expect(
          r.placeholderMismatches,
          isEmpty,
          reason: '${r.locale} placeholders',
        );
      }
    });

    test('the report is readable and flags defects', () {
      final md = report.toMarkdown(reports);
      expect(md, contains('| ar |'));
      expect(md, contains('100.0%'));
      final broken = report.LocaleReport('xx', 10)..missing.add('k');
      expect(broken.hasDefects, isTrue);
      expect(broken.percent, 90);
    });

    test('ICU argument extraction', () {
      expect(report.argumentsIn('Hello {name}'), {'name'});
      expect(
        report.argumentsIn(
          '{count, plural, =0{none} =1{one} other{{count} items}}',
        ),
        {'count'},
      );
      expect(report.argumentsIn('plain'), isEmpty);
    });
  });
}
