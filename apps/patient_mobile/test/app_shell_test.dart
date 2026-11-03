import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_mobile/app.dart';
import 'package:patient_mobile/core/config/client_config_provider.dart';
import 'package:utilities/utilities.dart';

import 'support/fake_auth.dart';

Widget _app(
  String env,
  String url, {
  bool signedIn = false,
  AuthSessionDto? session,
}) {
  return ProviderScope(
    overrides: [
      clientConfigProvider.overrideWithValue(
        ClientConfig.validated(appEnv: env, apiBaseUrl: url),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(signedIn: signedIn),
      ),
      authApiProvider.overrideWithValue(FakeAuthApi(session ?? sessionWith())),
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
}

void _bigScreen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 3000);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('signed-out users see the welcome screen, not the app', (
    tester,
  ) async {
    _bigScreen(tester);
    await tester.pumpWidget(_app('dev', 'http://localhost:8080'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to EazyClinic'), findsWidgets);
    expect(find.text('Signed in as Test User'), findsNothing);
  });

  testWidgets('signed-in admitted users see the home screen', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(
      _app('dev', 'http://localhost:8080', signedIn: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EcBrandLogo), findsOneWidget);
    expect(find.text('Signed in as Test User'), findsOneWidget);
    expect(find.text('Environment: dev'), findsOneWidget);
  });

  testWidgets('sign out returns to the welcome screen', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(
      _app('dev', 'http://localhost:8080', signedIn: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as Test User'), findsNothing);
    expect(find.text('Welcome to EazyClinic'), findsWidgets);
  });

  testWidgets('design-system gallery is reachable in dev', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(
      _app('dev', 'http://localhost:8080', signedIn: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open design system'));
    // The gallery contains looping progress indicators, so pumpAndSettle would
    // never finish; advance time explicitly instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(DesignSystemGallery), findsOneWidget);
  });

  testWidgets('production hides the gallery entry point', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(
      _app('production', 'https://api.example.com', signedIn: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Environment: production'), findsOneWidget);
    expect(find.text('Open design system'), findsNothing);
  });

  testWidgets('welcome offers registration and sign-in', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(_app('dev', 'http://localhost:8080'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('invalid configuration shows an error screen, not the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ConfigurationErrorApp(
        message: 'API_BASE_URL must be an absolute http(s) URL.',
      ),
    );
    expect(find.text('Configuration error'), findsOneWidget);
    expect(find.byType(EcBrandLogo), findsNothing);
  });
}
