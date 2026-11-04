import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:doctor_mobile/app.dart';
import 'package:doctor_mobile/core/config/client_config_provider.dart';
import 'package:doctor_mobile/core/routing/app_router.dart';
import 'package:doctor_mobile/features/workspace/data/clinical_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utilities/utilities.dart';

import 'support/fake_auth.dart';
import 'support/fake_clinical.dart';

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
      authApiProvider.overrideWithValue(
        FakeAuthApi(
          session ??
              sessionWith(
                memberships: [
                  const MembershipSummaryDto(tenantId: 't', role: 'doctor'),
                ],
              ),
        ),
      ),
      clinicalRepositoryProvider.overrideWithValue(
        FakeClinicalRepository(
          (m, p, b) => {
            'counts': <String, Object?>{},
            'upcoming': <Object?>[],
            'queues': <Object?>[],
            'recentConsultations': <Object?>[],
          },
        ),
      ),
      appAudienceProvider.overrideWithValue(AppAudience.doctor),
      authUiConfigProvider.overrideWithValue(
        const AuthUiConfig(
          appName: 'Test',
          audienceLabel: 'Sign in to test',
          registrationEnabled: false,
        ),
      ),
    ],
    child: const EazyClinicApp(),
  );
}

/// The account page (the former home screen) now lives behind the shell.
Future<void> _account(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(EazyClinicApp)),
  ).read(appRouterProvider).go('/account');
  await tester.pumpAndSettle();
}

void _bigScreen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 3000);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('signed-out users see the sign-in screen, not the app', (
    tester,
  ) async {
    _bigScreen(tester);
    await tester.pumpWidget(_app('dev', 'http://localhost:8080'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Signed in as Test User'), findsNothing);
  });

  testWidgets('signed-in admitted users see the home screen', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(
      _app('dev', 'http://localhost:8080', signedIn: true),
    );
    await tester.pumpAndSettle();
    await _account(tester);
    expect(find.byType(EcBrandLogo), findsWidgets);
    expect(find.text('Signed in as Test User'), findsOneWidget);
    expect(find.text('Environment: dev'), findsOneWidget);
  });

  testWidgets('sign out returns to the sign-in screen', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(
      _app('dev', 'http://localhost:8080', signedIn: true),
    );
    await tester.pumpAndSettle();
    await _account(tester);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as Test User'), findsNothing);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('design-system gallery is reachable in dev', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(
      _app('dev', 'http://localhost:8080', signedIn: true),
    );
    await tester.pumpAndSettle();
    await _account(tester);
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
    await _account(tester);
    expect(find.text('Environment: production'), findsOneWidget);
    expect(find.text('Open design system'), findsNothing);
  });

  testWidgets('an active account without a role is denied', (tester) async {
    _bigScreen(tester);
    await tester.pumpWidget(
      _app(
        'dev',
        'http://localhost:8080',
        signedIn: true,
        session: sessionWith(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Access not available'), findsOneWidget);
    expect(find.text('Signed in as Test User'), findsNothing);
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
