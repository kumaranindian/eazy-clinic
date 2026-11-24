import 'package:common_models/common_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

void main() {
  FakeRepo repo(List<(String, String, Object?)> sent) {
    final r = FakeRepo();
    r.on('getList', (a, n) {
      if (a[0] == '/platform/admins') {
        return [
          {
            'uid': 'u1',
            'displayName': 'Root Admin',
            'email': 'root@example.test',
            'platformRole': 'super_admin',
            'accountStatus': 'active',
          },
          {
            'uid': 'u2',
            'displayName': 'Sam Support',
            'email': 'sam@example.test',
            'platformRole': 'platform_support_admin',
            'accountStatus': 'active',
          },
        ];
      }
      return <Map<String, Object?>>[];
    });
    r.on('getMap', (a, n) => <String, Object?>{});
    r.on('dashboard', (a, n) => dashboardJson());
    r.on('sendMap', (a, n) {
      sent.add((a[0]! as String, a[1]! as String, a[2]));
      return <String, Object?>{'ok': true};
    });
    return r;
  }

  testWidgets(
    'a super admin sees administrators and can remove one with a reason',
    (t) async {
      final sent = <(String, String, Object?)>[];
      await open(
        t,
        buildApp(
          repo: repo(sent),
          session: sessionWith(platformRole: PlatformRole.superAdmin),
        ),
        '/platform/admins',
      );
      expect(find.text('Root Admin'), findsOneWidget);
      expect(find.textContaining('Platform support admin'), findsOneWidget);
      expect(find.byKey(const Key('add-admin')), findsOneWidget);
      await t.tap(find.byKey(const Key('revoke-u2')));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove role'));
      await t.pumpAndSettle();
      expect(sent, isEmpty, reason: 'a reason is required');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Reason'),
        'Left the team',
      );
      await t.tap(find.text('Remove role'));
      await t.pumpAndSettle();
      expect(sent.single.$2, '/platform/admins/u2/revoke');
      expect((sent.single.$3! as Map)['reason'], 'Left the team');
    },
  );

  testWidgets('a support admin can read but not change', (t) async {
    final sent = <(String, String, Object?)>[];
    await open(
      t,
      buildApp(
        repo: repo(sent),
        session: sessionWith(platformRole: PlatformRole.platformSupportAdmin),
      ),
      '/platform/admins',
    );
    expect(find.text('Sam Support'), findsOneWidget);
    expect(find.byKey(const Key('add-admin')), findsNothing);
    expect(find.byKey(const Key('revoke-u1')), findsNothing);
  });
}
