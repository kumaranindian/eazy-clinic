import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Frame for the non-platform screens (clinic registration, applications,
/// clinic home): brand, section links, sign out.
class AppFrame extends ConsumerWidget {
  const AppFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final name = auth is Authenticated
        ? (auth.user.displayName ?? auth.user.email)
        : null;
    final hasClinic =
        auth is Authenticated && auth.session.memberships.isNotEmpty;
    return Scaffold(
      backgroundColor: EcColors.background,
      appBar: AppBar(
        backgroundColor: EcColors.surface,
        title: Row(
          children: [
            const EcBrandLogo.icon(height: 32),
            const SizedBox(width: EcSpacing.md),
            Text('EazyClinic', style: EcTypography.subsectionTitle),
          ],
        ),
        actions: [
          if (hasClinic)
            TextButton(
              onPressed: () => context.go('/clinic'),
              child: const Text('My clinic'),
            ),
          TextButton(
            onPressed: () => context.go('/applications'),
            child: const Text('Applications'),
          ),
          if (name != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EcSpacing.sm),
              child: Center(
                child: Text(
                  name,
                  style: EcTypography.bodySecondary,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: EcSizes.maxContentWidth),
          child: child,
        ),
      ),
    );
  }
}
