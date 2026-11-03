import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp, routerOf;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

const _ownerPerms = [
  'clinic.view',
  'clinic.update',
  'branches.view',
  'branches.create',
  'branches.update',
  'doctors.view',
  'staff.view',
  'staff.invite',
  'roles.view',
];

Map<String, Object?> _access(
  List<String> perms, {
  String role = 'clinic_owner',
}) => {
  'tenantId': 'ten_1',
  'role': role,
  'allBranches': true,
  'branches': [
    {'branchId': 'br_1', 'name': 'Main'},
    {'branchId': 'br_2', 'name': 'North'},
  ],
  'accessLevel': 'full',
  'writesAllowed': true,
  'permissions': perms,
};

FakeRepo _repo(List<String> perms, {String role = 'clinic_owner'}) {
  final r = FakeRepo();
  r.on('entitlements', (a, n) => entitlementsJson());
  r.on('getMap', (a, n) {
    final path = a[0]! as String;
    if (path.startsWith('/members/current/permissions')) {
      return _access(perms, role: role);
    }
    return ownerAccess(path);
  });
  r.on('list', (a, n) {
    final path = a[0]! as String;
    if (path == '/branches') {
      return listOf([
        {
          'branchId': 'br_1',
          'name': 'Main',
          'code': 'MAIN',
          'type': 'clinic',
          'status': 'active',
          'address': {'city': 'Pune'},
        },
      ]);
    }
    return listOf([]);
  });
  return r;
}

Widget _app(FakeRepo repo, {bool member = true}) => buildApp(
  repo: repo,
  session: sessionWith(
    memberships: member
        ? [const MembershipSummaryDto(tenantId: 'ten_1', role: 'clinic_owner')]
        : const [],
  ),
);

void main() {
  group('clinic navigation follows backend permissions', () {
    testWidgets('owner sees every section and the branch selector', (t) async {
      await open(t, _app(_repo(_ownerPerms)), '/clinic');
      for (final l in ['Branches', 'Doctors', 'Staff', 'Invitations']) {
        expect(find.text(l), findsWidgets);
      }
      expect(find.byKey(const Key('branch-selector')), findsOneWidget);
    });

    testWidgets('a limited role does not see staff or access sections', (
      t,
    ) async {
      final repo = _repo([
        'clinic.view',
        'branches.view',
      ], role: 'receptionist');
      await open(t, _app(repo), '/clinic');
      expect(find.text('Branches'), findsWidgets);
      expect(find.text('Staff'), findsNothing);
      expect(find.text('Roles & access'), findsNothing);
      expect(find.text('Invitations'), findsNothing);
    });
  });

  group('branches', () {
    testWidgets('list shows rows and the create action for permitted roles', (
      t,
    ) async {
      await open(t, _app(_repo(_ownerPerms)), '/clinic/branches');
      expect(find.textContaining('Main (MAIN)'), findsOneWidget);
      expect(find.text('New branch'), findsOneWidget);
    });

    testWidgets('create action is hidden without branches.create', (t) async {
      final repo = _repo(['clinic.view', 'branches.view']);
      await open(t, _app(repo), '/clinic/branches');
      expect(find.textContaining('Main (MAIN)'), findsOneWidget);
      expect(find.text('New branch'), findsNothing);
    });

    testWidgets('empty list shows guidance', (t) async {
      final repo = _repo(_ownerPerms)..on('list', (a, n) => listOf([]));
      await open(t, _app(repo), '/clinic/branches');
      expect(find.text('No branches yet'), findsOneWidget);
    });

    testWidgets('form validates and sends nothing when invalid', (t) async {
      final repo = _repo(_ownerPerms);
      await open(t, _app(repo), '/clinic/branches/new');
      final create = find.text('Create branch');
      await t.ensureVisible(create);
      await t.tap(create);
      await t.pumpAndSettle();
      expect(find.textContaining('required'), findsWidgets);
      expect(repo.calls, isNot(contains('sendMap')));
    });

    testWidgets('a list failure shows an error with retry', (t) async {
      final repo = _repo(_ownerPerms)
        ..on('list', (a, n) => throw const ApiFailure(message: 'Nope'));
      await open(t, _app(repo), '/clinic/branches');
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('invitation acceptance', () {
    testWidgets('a link without a token is explained', (t) async {
      await open(t, _app(FakeRepo(), member: false), '/accept-invitation');
      expect(find.textContaining('incomplete'), findsOneWidget);
    });

    testWidgets('accepting posts only the token', (t) async {
      final repo = FakeRepo()..on('sendMap', (a, n) => {'ok': true});
      await open(
        t,
        _app(repo, member: false),
        '/accept-invitation?token=ecinv_abc',
      );
      await t.tap(find.text('Accept invitation'));
      await t.pumpAndSettle();
      final call = repo.callArgs.firstWhere((c) => c.length == 3);
      expect(call[1], '/invitations/accept');
      expect(call[2], {'token': 'ecinv_abc'});
    });

    testWidgets('a refusal is shown without leaking detail', (t) async {
      final repo = FakeRepo()
        ..on(
          'sendMap',
          (a, n) =>
              throw const ApiFailure(message: 'This invitation is not valid.'),
        );
      await open(
        t,
        _app(repo, member: false),
        '/accept-invitation?token=ecinv_bad',
      );
      await t.tap(find.text('Accept invitation'));
      await t.pumpAndSettle();
      expect(find.text('This invitation is not valid.'), findsOneWidget);
      expect(routerOf(t), isNotNull);
    });
  });
}
