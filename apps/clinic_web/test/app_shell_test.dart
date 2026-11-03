import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:clinic_web/app.dart';
import 'package:clinic_web/core/config/client_config_provider.dart';
import 'package:clinic_web/core/routing/app_router.dart';
import 'package:clinic_web/features/control_plane/data/control_plane_repository.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:utilities/utilities.dart';

import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

/// Builds the real app with fake identity + backend.
Widget buildApp({
  String env = 'dev',
  String url = 'http://localhost:8080',
  bool signedIn = true,
  AuthSessionDto? session,
  FakeRepo? repo,
  List<Override> overrides = const [],
}) {
  final fake = repo ?? FakeRepo();
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
          session ?? sessionWith(platformRole: PlatformRole.superAdmin),
        ),
      ),
      appAudienceProvider.overrideWithValue(AppAudience.clinicWeb),
      authUiConfigProvider.overrideWithValue(
        const AuthUiConfig(
          appName: 'Test',
          audienceLabel: 'Sign in to test',
          registrationEnabled: true,
        ),
      ),
      controlPlaneRepositoryProvider.overrideWithValue(fake),
      ...overrides,
    ],
    child: const EazyClinicApp(),
  );
}

void bigScreen(WidgetTester tester, {Size size = const Size(1280, 3200)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

GoRouter routerOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MaterialApp)),
).read(appRouterProvider);

void main() {
  testWidgets('signed-out users see the sign-in screen', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(buildApp(signedIn: false));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Platform overview'), findsNothing);
  });

  testWidgets('design-system gallery is reachable in dev only', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(buildApp(signedIn: false));
    await tester.pumpAndSettle();
    routerOf(tester).go(AppRoutes.designSystem);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(DesignSystemGallery), findsOneWidget);
  });

  testWidgets('production does not register the gallery', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(
      buildApp(
        env: 'production',
        url: 'https://api.example.com',
        signedIn: false,
      ),
    );
    await tester.pumpAndSettle();
    routerOf(tester).go(AppRoutes.designSystem);
    await tester.pumpAndSettle();
    expect(find.byType(DesignSystemGallery), findsNothing);
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
