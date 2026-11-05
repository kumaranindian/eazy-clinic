import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_mobile/app.dart';
import 'package:patient_mobile/core/config/client_config_provider.dart';
import 'package:patient_mobile/features/portal/data/portal_repository.dart';
import 'package:patient_mobile/features/portal/presentation/ui_kit.dart';
import 'package:utilities/utilities.dart';

import 'support/fake_auth.dart';
import 'support/fake_portal.dart';

Widget _app() => ProviderScope(
  overrides: [
    clientConfigProvider.overrideWithValue(
      ClientConfig.validated(
        appEnv: 'dev',
        apiBaseUrl: 'http://localhost:8080',
      ),
    ),
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(signedIn: true),
    ),
    authApiProvider.overrideWithValue(FakeAuthApi(sessionWith())),
    portalRepositoryProvider.overrideWithValue(
      FakePortalRepository(
        (m, p, b) => p.startsWith('/patient/profile')
            ? {
                'accountId': 'pa_1',
                'displayName': 'Test User',
                'profileCompletion': 100,
                'linkedClinics': <Object?>[],
              }
            : p == '/patient/notifications'
            ? {'items': <Object?>[], 'unread': 0}
            : <Object?>[],
      ),
    ),
    appAudienceProvider.overrideWithValue(AppAudience.patient),
    authUiConfigProvider.overrideWithValue(
      const AuthUiConfig(
        appName: 'Test',
        audienceLabel: 'Sign in to test',
        registrationEnabled: true,
      ),
    ),
  ],
  child: const EazyClinicApp(),
);

void _wide(WidgetTester t) {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(1300, 2400);
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() async {
    await RegionalDisplay.ensureInitialized();
  });
  setUp(RegionalDisplay.reset);

  testWidgets('navigation follows the user\'s language and mirrors in Arabic', (
    t,
  ) async {
    _wide(t);
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    expect(find.text('Appointments'), findsWidgets);
    final container = ProviderScope.containerOf(
      t.element(find.byType(EazyClinicApp)),
    );

    container.read(localePreferenceProvider.notifier).choose('ar');
    await t.pumpAndSettle();
    expect(find.text('الرئيسية'), findsWidgets);
    expect(find.text('المواعيد'), findsWidgets);
    expect(find.text('Appointments'), findsNothing);
    final ctx = t.element(find.text('المواعيد').first);
    expect(Directionality.of(ctx), TextDirection.rtl);
    // the navigation rail is on the right edge in right-to-left layouts
    expect(t.getCenter(find.text('المواعيد').first).dx, greaterThan(1000));
    expect(t.takeException(), isNull);

    container.read(localePreferenceProvider.notifier).choose('hi');
    await t.pumpAndSettle();
    expect(find.text('होम'), findsWidgets);
    expect(find.text('சந்திப்புகள்'), findsNothing);

    container.read(localePreferenceProvider.notifier).choose('ta');
    await t.pumpAndSettle();
    expect(find.text('சந்திப்புகள்'), findsWidgets);
  });

  testWidgets('the language menu switches the app without a restart', (
    t,
  ) async {
    _wide(t);
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    await t.tap(find.text('Profile').first);
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.language));
    await t.pumpAndSettle();
    await t.tap(find.text('العربية'));
    await t.pumpAndSettle();
    expect(find.text('الملف الشخصي'), findsWidgets);
  });

  testWidgets('status chips use the translated status words', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: appLocalizationDelegates,
          theme: EcTheme.light(),
          home: Scaffold(
            body: Column(
              children: [
                statusChip('confirmed'),
                statusChip('no_show'),
                statusChip('something_new'),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('مؤكد'), findsOneWidget);
    expect(find.text('لم يحضر'), findsOneWidget);
    // an unknown value is readable, never a raw key with underscores
    expect(find.text('Something new'), findsOneWidget);
    expect(find.textContaining('_'), findsNothing);
  });

  test('appointment times show in the clinic\'s zone, not the device\'s', () {
    RegionalDisplay.update(
      language: 'en',
      countryCode: 'AE',
      timezone: 'Asia/Dubai',
      currency: 'AED',
    );
    const instant = '2026-06-01T18:30:00Z';
    expect(shortDateTime(instant), contains('10:30'));
    expect(shortDateTime(instant, timezone: 'Asia/Kolkata'), contains('12:00'));
    expect(money(123450), 'AED 1,234.50');
    expect(money(123450, 'INR'), '₹1,234.50');
    expect(money(null), '—');
  });
}
