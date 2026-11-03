import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/ui_helpers.dart';
import '../tenant/clinic_home_page.dart';
import 'providers.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.path, this.permission);
  final String label;
  final IconData icon;
  final String path;
  final String permission;
}

const _destinations = [
  _Dest(
    'Overview',
    Icons.local_hospital_outlined,
    '/clinic',
    ClinicPermission.clinicView,
  ),
  _Dest(
    'Clinic settings',
    Icons.tune,
    '/clinic/settings',
    ClinicPermission.clinicView,
  ),
  _Dest(
    'Branches',
    Icons.account_tree_outlined,
    '/clinic/branches',
    ClinicPermission.branchesView,
  ),
  _Dest(
    'Patients',
    Icons.groups_outlined,
    '/clinic/patients',
    ClinicPermission.patientsView,
  ),
  _Dest(
    'Doctors',
    Icons.medical_services_outlined,
    '/clinic/doctors',
    ClinicPermission.doctorsView,
  ),
  _Dest(
    'Staff',
    Icons.badge_outlined,
    '/clinic/staff',
    ClinicPermission.staffView,
  ),
  _Dest(
    'Invitations',
    Icons.mail_outline,
    '/clinic/invitations',
    ClinicPermission.staffInvite,
  ),
  _Dest(
    'Roles & access',
    Icons.admin_panel_settings_outlined,
    '/clinic/access',
    ClinicPermission.rolesView,
  ),
];

/// Clinic administration layout. Entries follow the permissions the backend
/// reports for the signed-in member; the backend still authorises every call.
class ClinicShell extends ConsumerWidget {
  const ClinicShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(clinicAccessProvider);
    return access.when(
      loading: () => const Scaffold(
        body: EcLoadingIndicator(message: 'Loading your clinic…'),
      ),
      // A blocked clinic (suspended / expired) answers 403 here; the
      // entitlement endpoint still explains why, so show that instead.
      error: (e, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: EcColors.surface,
          title: const EcBrandLogo.icon(height: 32),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
            ),
          ],
        ),
        body: const ClinicHomePage(),
      ),
      data: (a) => _Frame(access: a, location: location, child: child),
    );
  }
}

class _Frame extends ConsumerWidget {
  const _Frame({
    required this.access,
    required this.location,
    required this.child,
  });

  final Map<String, Object?> access;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ((access['permissions'] as List?) ?? const [])
        .cast<String>()
        .toSet();
    final items = [
      for (final d in _destinations)
        if (permissions.contains(d.permission)) d,
    ];
    var selected = 0;
    for (var i = 0; i < items.length; i++) {
      final p = items[i].path;
      if (location == p || (p != '/clinic' && location.startsWith(p))) {
        selected = i;
      }
    }
    final size = EcBreakpoints.of(context);
    final branches = ((access['branches'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    final active = ref.watch(activeBranchProvider);
    final allBranches = access['allBranches'] == true;
    final auth = ref.watch(authControllerProvider);
    final name = auth is Authenticated
        ? (auth.user.displayName ?? auth.user.email)
        : null;
    final showSelector =
        branches.length > 1 || (!allBranches && branches.isNotEmpty);

    final appBar = AppBar(
      backgroundColor: EcColors.surface,
      title: Row(
        children: [
          const EcBrandLogo.icon(height: 32),
          const SizedBox(width: EcSpacing.md),
          Flexible(
            child: Text(
              'Clinic',
              overflow: TextOverflow.ellipsis,
              style: EcTypography.subsectionTitle,
            ),
          ),
          if (!size.isCompact) ...[
            const SizedBox(width: EcSpacing.md),
            EcStatusChip(label: Fmt.humanize(access['role'])),
          ],
        ],
      ),
      actions: [
        if (showSelector)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EcSpacing.sm),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                key: const Key('branch-selector'),
                value: branches.any((b) => b['branchId'] == active)
                    ? active
                    : null,
                hint: const Text('Branch'),
                items: [
                  if (allBranches)
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All branches'),
                    ),
                  for (final b in branches)
                    DropdownMenuItem<String?>(
                      value: b['branchId'] as String?,
                      child: Text('${b['name']}'),
                    ),
                ],
                onChanged: (v) =>
                    ref.read(activeBranchProvider.notifier).select(v),
              ),
            ),
          ),
        if (name != null && !size.isCompact)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: EcSpacing.sm),
              child: Text(name, style: EcTypography.bodySecondary),
            ),
          ),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
        ),
      ],
    );

    final banner = access['writesAllowed'] == false
        ? EcInlineMessage(
            tone: EcStatusTone.warning,
            message: access['accessLevel'] == 'read_only'
                ? 'Your subscription payment is overdue. You can view information but cannot make changes until it is renewed.'
                : 'Changes are currently disabled for this clinic.',
          )
        : null;
    final body = Column(
      children: [
        if (banner != null)
          Padding(padding: const EdgeInsets.all(EcSpacing.md), child: banner),
        Expanded(child: child),
      ],
    );

    if (items.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: const EcEmptyState(
          title: 'No access',
          message: 'Your role has no sections yet.',
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
        body: body,
      );
    }
    return EcNavScaffold(
      appBar: appBar,
      destinations: [
        for (final d in items) EcNavDestination(label: d.label, icon: d.icon),
      ],
      selectedIndex: selected,
      onSelected: (i) => context.go(items[i].path),
      body: body,
    );
  }
}
