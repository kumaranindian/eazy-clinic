import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../control_plane/providers.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.path, [this.permission]);
  final String label;
  final IconData icon;
  final String path;
  final String? permission;
}

const _destinations = [
  _Dest(
    'Dashboard',
    Icons.dashboard_outlined,
    '/platform',
    Permission.readDashboard,
  ),
  _Dest(
    'Applications',
    Icons.assignment_outlined,
    '/platform/applications',
    Permission.readApplications,
  ),
  _Dest(
    'Tenants',
    Icons.apartment_outlined,
    '/platform/tenants',
    Permission.readTenants,
  ),
  _Dest('Plans', Icons.sell_outlined, '/platform/plans', Permission.readPlans),
  _Dest(
    'Subscriptions',
    Icons.card_membership_outlined,
    '/platform/subscriptions',
    Permission.readSubscriptions,
  ),
  _Dest(
    'Countries',
    Icons.public,
    '/platform/countries',
    Permission.readCountries,
  ),
  _Dest(
    'Audit log',
    Icons.history,
    '/platform/audit',
    Permission.readAuditLogs,
  ),
];

/// Platform administration layout: side navigation on wide screens, a drawer
/// on narrow ones. The visible entries follow the server-resolved platform
/// role, but this is presentation only; every API call is authorized by the
/// backend.
class PlatformShell extends ConsumerWidget {
  const PlatformShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(platformPermissionsProvider);
    final role = ref.watch(platformRoleProvider);
    final items = [
      for (final d in _destinations)
        if (permissions.contains(d.permission)) d,
    ];
    var selected = 0;
    for (var i = 0; i < items.length; i++) {
      final p = items[i].path;
      if (location == p || (p != '/platform' && location.startsWith(p))) {
        selected = i;
      }
    }
    final size = EcBreakpoints.of(context);
    final title = Row(
      children: [
        const EcBrandLogo.icon(height: 32),
        const SizedBox(width: EcSpacing.md),
        Flexible(
          child: Text(
            'Platform admin',
            overflow: TextOverflow.ellipsis,
            style: EcTypography.subsectionTitle,
          ),
        ),
        if (!size.isCompact) ...[
          const SizedBox(width: EcSpacing.md),
          EcStatusChip(label: role == null ? 'No role' : _roleLabel(role)),
        ],
      ],
    );
    final actions = [
      IconButton(
        tooltip: 'Sign out',
        icon: const Icon(Icons.logout),
        onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
      ),
    ];
    final appBar = AppBar(
      title: title,
      actions: actions,
      backgroundColor: EcColors.surface,
    );

    if (items.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: const EcEmptyState(
          title: 'No access',
          message: 'Your platform role has no sections.',
        ),
      );
    }
    if (size.isCompact) {
      return Scaffold(
        appBar: appBar,
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                for (var i = 0; i < items.length; i++)
                  ListTile(
                    leading: Icon(items[i].icon),
                    title: Text(items[i].label),
                    selected: i == selected,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(items[i].path);
                    },
                  ),
              ],
            ),
          ),
        ),
        body: child,
      );
    }
    return EcNavScaffold(
      appBar: appBar,
      destinations: [
        for (final d in items) EcNavDestination(label: d.label, icon: d.icon),
      ],
      selectedIndex: selected,
      onSelected: (i) => context.go(items[i].path),
      body: child,
    );
  }

  static String _roleLabel(PlatformRole r) =>
      r == PlatformRole.superAdmin ? 'Super admin' : 'Support admin';
}
