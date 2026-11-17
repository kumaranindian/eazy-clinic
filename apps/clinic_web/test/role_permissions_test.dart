import 'package:api_contracts/api_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

FakeRepo _repo(List<String> perms, List<(String, String, Object?)> sent) {
  final r = FakeRepo();
  r.on('getMap', (a, n) {
    final path = a[0]! as String;
    if (path.startsWith('/members/current/permissions')) {
      return {
        'tenantId': 'ten_1',
        'role': 'clinic_owner',
        'allBranches': true,
        'branches': <Object?>[],
        'accessLevel': 'full',
        'writesAllowed': true,
        'permissions': perms,
      };
    }
    if (path == '/permissions') {
      return {
        'groups': {
          'billing': ['billing.view', 'billing.create'],
          'roles': ['roles.view', 'roles.manage'],
        },
        'ownerOnly': ['roles.manage'],
        'matrix': <String, Object?>{},
      };
    }
    return ownerAccess(path);
  });
  r.on('getList', (a, n) {
    if (a[0] == '/roles') {
      return [
        {
          'role': 'clinic_owner',
          'description': 'Owner',
          'permissions': ['billing.view', 'roles.manage'],
          'defaultPermissions': ['billing.view', 'roles.manage'],
          'editable': false,
          'custom': false,
        },
        {
          'role': 'nurse',
          'description': 'Nurse',
          'permissions': ['roles.view'],
          'defaultPermissions': ['roles.view'],
          'editable': true,
          'custom': false,
        },
      ];
    }
    return <Map<String, Object?>>[];
  });
  r.on('list', (a, n) => listOf([]));
  r.on('sendMap', (a, n) {
    sent.add((a[0]! as String, a[1]! as String, a[2]));
    return <String, Object?>{'ok': true};
  });
  return r;
}

Future<void> _openRoles(
  WidgetTester t,
  List<String> perms,
  List<(String, String, Object?)> sent,
) async {
  await open(
    t,
    buildApp(
      repo: _repo(perms, sent),
      session: sessionWith(
        memberships: [
          const MembershipSummaryDto(tenantId: 'ten_1', role: 'clinic_owner'),
        ],
      ),
    ),
    '/clinic/access',
  );
  await t.tap(find.text('Roles'));
  await t.pumpAndSettle();
}

void main() {
  const owner = [
    'clinic.view',
    'roles.view',
    'permissions.view',
    'members.view',
    'roles.manage',
  ];

  testWidgets(
    'the owner edits a role: only the differences and a reason are sent',
    (t) async {
      final sent = <(String, String, Object?)>[];
      await _openRoles(t, owner, sent);
      expect(find.byKey(const Key('edit-role-clinic_owner')), findsNothing);
      await t.tap(find.byKey(const Key('edit-role-nurse')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('perm-billing.view')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('perm-roles.view')));
      await t.pumpAndSettle();
      expect(find.text('Added for this clinic'), findsOneWidget);
      expect(find.text('Removed for this clinic'), findsOneWidget);
      // the owner-only permission cannot be ticked
      final ownerOnly = t.widget<CheckboxListTile>(
        find.byKey(const Key('perm-roles.manage')),
      );
      expect(ownerOnly.onChanged, isNull);
      await t.tap(find.byKey(const Key('role-save')));
      await t.pumpAndSettle();
      expect(sent, isEmpty, reason: 'a reason is required');
      await t.enterText(
        find.byKey(const Key('role-reason')),
        'Nurses now help at the billing desk',
      );
      await t.tap(find.byKey(const Key('role-save')));
      await t.pumpAndSettle();
      final s = sent.single;
      expect(s.$1, 'PUT');
      expect(s.$2, '/roles/nurse/permissions');
      expect((s.$3! as Map)['grant'], ['billing.view']);
      expect((s.$3! as Map)['revoke'], ['roles.view']);
    },
  );

  testWidgets('"Use standard permissions" resets the role', (t) async {
    final sent = <(String, String, Object?)>[];
    await _openRoles(t, owner, sent);
    await t.tap(find.byKey(const Key('edit-role-nurse')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('role-reason')), 'Back to standard');
    await t.tap(find.byKey(const Key('role-reset')));
    await t.pumpAndSettle();
    expect(sent.single.$2, '/roles/nurse/permissions/reset');
  });

  testWidgets('without roles.manage there is no edit action', (t) async {
    final sent = <(String, String, Object?)>[];
    await _openRoles(t, owner.where((p) => p != 'roles.manage').toList(), sent);
    expect(find.byKey(const Key('edit-role-nurse')), findsNothing);
  });
}
