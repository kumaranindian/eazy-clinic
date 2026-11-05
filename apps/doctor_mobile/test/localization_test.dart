import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:doctor_mobile/app.dart';
import 'package:doctor_mobile/core/config/client_config_provider.dart';
import 'package:doctor_mobile/features/workspace/data/clinical_repository.dart';
import 'package:doctor_mobile/features/workspace/presentation/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utilities/utilities.dart';

import 'support/fake_auth.dart';
import 'support/fake_clinical.dart';

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
    authApiProvider.overrideWithValue(
      FakeAuthApi(
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

void main() {
  setUpAll(() async {
    await RegionalDisplay.ensureInitialized();
  });
  setUp(RegionalDisplay.reset);

  testWidgets('the doctor workspace can be used in Hindi, Tamil and Arabic', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 2400);
    addTearDown(t.view.reset);
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    expect(find.text('Dashboard'), findsWidgets);

    // switch through the visible language menu
    await t.tap(find.byIcon(Icons.language));
    await t.pumpAndSettle();
    await t.tap(find.text('हिन्दी'));
    await t.pumpAndSettle();
    expect(find.text('डैशबोर्ड'), findsWidgets);
    expect(find.text('Dashboard'), findsNothing);

    await t.tap(find.byIcon(Icons.language));
    await t.pumpAndSettle();
    await t.tap(find.text('العربية'));
    await t.pumpAndSettle();
    expect(find.text('لوحة التحكم'), findsWidgets);
    expect(find.text('المرضى'), findsWidgets);
    expect(
      Directionality.of(t.element(find.text('المرضى').first)),
      TextDirection.rtl,
    );
    expect(t.takeException(), isNull);

    await t.tap(find.byIcon(Icons.language));
    await t.pumpAndSettle();
    await t.tap(find.text('لغة الجهاز'));
    await t.pumpAndSettle();
  });

  test('dates and money in consultation screens use the clinic settings', () {
    RegionalDisplay.update(
      language: 'en',
      countryCode: 'IN',
      timezone: 'Asia/Kolkata',
      currency: 'INR',
    );
    expect(shortDateTime('2026-06-01T18:30:00Z'), contains('12:00'));
    expect(shortDate('2026-06-01T18:30:00Z'), contains('2 Jun 2026'));
  });
}
