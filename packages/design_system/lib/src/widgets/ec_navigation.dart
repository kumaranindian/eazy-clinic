import 'package:flutter/material.dart';

import '../tokens/ec_breakpoints.dart';
import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';
import 'ec_brand_logo.dart';

/// A destination in the primary navigation.
class EcNavDestination {
  const EcNavDestination({
    required this.label,
    required this.icon,
    IconData? selectedIcon,
  }) : selectedIcon = selectedIcon ?? icon;

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Adaptive navigation scaffold: bottom bar on phones, navy side rail/drawer
/// on wider windows. Apps pass destinations and a body; routing stays in the
/// app (GoRouter) and is wired through [selectedIndex] / [onSelected].
class EcNavScaffold extends StatelessWidget {
  const EcNavScaffold({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    this.appBar,
    super.key,
  });

  final List<EcNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    final size = EcBreakpoints.of(context);

    if (size.isCompact) {
      return Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Row(
        children: [
          _SideNav(
            destinations: destinations,
            selectedIndex: selectedIndex,
            onSelected: onSelected,
            collapsed: !size.isExpandedOrLarger,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.collapsed,
  });

  final List<EcNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: collapsed ? EcSizes.sideNavWidthCollapsed : EcSizes.sideNavWidth,
      color: EcColors.navy,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(EcSpacing.lg),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: EcColors.surface,
                    borderRadius: BorderRadius.circular(EcRadii.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(EcSpacing.sm),
                    child: collapsed
                        ? const EcBrandLogo.icon(height: 32)
                        : const EcBrandLogo.full(height: 56),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < destinations.length; i++)
              _SideNavItem(
                destination: destinations[i],
                selected: i == selectedIndex,
                collapsed: collapsed,
                onTap: () => onSelected(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final EcNavDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EcColors.surface : const Color(0xB3FFFFFF);
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: EcSizes.minTapTarget,
          decoration: BoxDecoration(
            color: selected ? const Color(0x1FFFFFFF) : null,
            border: Border(
              left: BorderSide(
                color: selected ? EcColors.red : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : EcSpacing.lg,
          ),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: color,
                size: EcIconSizes.lg,
              ),
              if (!collapsed) ...[
                const SizedBox(width: EcSpacing.md),
                Flexible(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EcTypography.bodyStrong.copyWith(color: color),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
