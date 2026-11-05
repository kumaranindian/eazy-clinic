import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Navigation frame of the Doctor Workspace. Only decides what to show; every
/// call is authorized by the backend.
class DoctorShell extends StatelessWidget {
  const DoctorShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  static const _items = <(String, EcNavDestination)>[
    ('/', EcNavDestination(label: 'Dashboard', icon: Icons.dashboard_outlined)),
    ('/today', EcNavDestination(label: 'Today', icon: Icons.event_outlined)),
    ('/queue', EcNavDestination(label: 'Queue', icon: Icons.people_outline)),
    (
      '/patients',
      EcNavDestination(label: 'Patients', icon: Icons.person_search_outlined),
    ),
    ('/followups', EcNavDestination(label: 'Follow-ups', icon: Icons.update)),
    (
      '/notifications',
      EcNavDestination(
        label: 'Notifications',
        icon: Icons.notifications_outlined,
      ),
    ),
    (
      '/account',
      EcNavDestination(label: 'Account', icon: Icons.account_circle_outlined),
    ),
  ];

  /// Navigation label in the user's language (path decides the wording).
  static EcNavDestination _localized(
    BuildContext context,
    (String, EcNavDestination) item,
  ) {
    final t = context.l10n;
    final label = switch (item.$1) {
      '/' => t.navDashboard,
      '/today' => t.navToday,
      '/queue' => t.navQueue,
      '/patients' => t.navPatients,
      '/followups' => t.navFollowups,
      '/notifications' => t.navNotifications,
      '/account' => t.navAccount,
      _ => item.$2.label,
    };
    return EcNavDestination(
      label: label,
      icon: item.$2.icon,
      selectedIcon: item.$2.selectedIcon,
    );
  }

  int get _selected {
    for (var i = _items.length - 1; i > 0; i--) {
      if (location.startsWith(_items[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) => EcNavScaffold(
    appBar: AppBar(
      backgroundColor: EcColors.surface,
      title: const EcBrandLogo.icon(height: 32),
      actions: const [LanguageSelector()],
    ),
    destinations: [for (final i in _items) _localized(context, i)],
    selectedIndex: _selected,
    onSelected: (i) => context.go(_items[i].$1),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: child,
        ),
      ),
    ),
  );
}
