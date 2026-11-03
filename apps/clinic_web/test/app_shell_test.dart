import 'package:clinic_web/app.dart';
import 'package:clinic_web/core/config/client_config_provider.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utilities/utilities.dart';

Widget _app(String env, String url) {
  return ProviderScope(
    overrides: [
      clientConfigProvider.overrideWithValue(
        ClientConfig.validated(appEnv: env, apiBaseUrl: url),
      ),
    ],
    child: const EazyClinicApp(),
  );
}

void main() {
  testWidgets('shell renders the brand, app name and environment', (
    tester,
  ) async {
    await tester.pumpWidget(_app('dev', 'http://localhost:8080'));
    await tester.pumpAndSettle();
    expect(find.byType(EcBrandLogo), findsOneWidget);
    expect(find.text('EazyClinic'), findsOneWidget);
    expect(find.text('Environment: dev'), findsOneWidget);
  });

  testWidgets('design-system gallery is reachable in dev', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app('dev', 'http://localhost:8080'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open design system'));
    // The gallery contains looping progress indicators, so pumpAndSettle would
    // never finish; advance time explicitly instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(DesignSystemGallery), findsOneWidget);
  });

  testWidgets('production hides the gallery entry point', (tester) async {
    await tester.pumpWidget(_app('production', 'https://api.example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Environment: production'), findsOneWidget);
    expect(find.text('Open design system'), findsNothing);
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
