import 'package:app_core/app_core.dart';
import 'package:clinic_web/features/shared/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show adminRepo, open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

void main() {
  setUpAll(() async {
    await RegionalDisplay.ensureInitialized();
  });
  setUp(RegionalDisplay.reset);

  testWidgets('registration form is usable in Arabic (right-to-left)', (
    t,
  ) async {
    await open(t, buildApp(repo: FakeRepo(), session: sessionWith()), '/apply');
    final container = ProviderScope.containerOf(
      t.element(find.byType(MaterialApp)),
    );
    container.read(localePreferenceProvider.notifier).choose('ar');
    await t.pumpAndSettle();
    // the country selector label comes from the generated Arabic resources
    expect(find.text('الدولة'), findsWidgets);
    expect(
      Directionality.of(t.element(find.text('الدولة').first)),
      TextDirection.rtl,
    );
    expect(t.takeException(), isNull);
    // typed data survives the switch back
    await t.enterText(
      find.widgetWithText(TextFormField, 'Clinic name'),
      'عيادة النور',
    );
    container.read(localePreferenceProvider.notifier).choose('en');
    await t.pumpAndSettle();
    expect(find.text('عيادة النور'), findsOneWidget);
  });

  testWidgets('platform navigation shows the translated dashboard label', (
    t,
  ) async {
    await open(t, buildApp(repo: adminRepo()));
    final container = ProviderScope.containerOf(
      t.element(find.byType(MaterialApp)),
    );
    container.read(localePreferenceProvider.notifier).choose('ta');
    await t.pumpAndSettle();
    expect(find.text('டாஷ்போர்டு'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  test('Fmt shows clinic-local time, localized money and number style', () {
    RegionalDisplay.update(
      language: 'en',
      countryCode: 'AE',
      timezone: 'Asia/Dubai',
      currency: 'AED',
    );
    expect(Fmt.dateTime('2026-06-01T18:30:00Z'), contains('10:30'));
    expect(Fmt.money(120000), 'AED 1,200.00');
    expect(Fmt.money(120000, 'INR'), '₹1,200.00');
    expect(Fmt.money(1500, 'KWD'), 'KWD 1.500');
    expect(Fmt.date('not a date'), '—');
    RegionalDisplay.reset();
    expect(Fmt.money(12345678), '₹1,23,456.78');
  });
}
