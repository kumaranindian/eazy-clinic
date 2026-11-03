import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_info.dart';
import '../../../core/config/client_config_provider.dart';
import '../../../core/routing/app_router.dart';

/// Signed-in landing screen. Feature navigation replaces this as modules land;
/// until then it confirms the verified session and offers sign-out.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(clientConfigProvider);
    final auth = ref.watch(authControllerProvider);
    final name = auth is Authenticated
        ? (auth.user.displayName?.isNotEmpty ?? false)
              ? auth.user.displayName!
              : auth.user.email
        : null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(EcSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: EcSizes.maxFormWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EcBrandLogo.full(height: 160),
                  const SizedBox(height: EcSpacing.xl),
                  Text(
                    AppInfo.name,
                    style: EcTypography.pageTitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EcSpacing.sm),
                  Text(
                    AppInfo.description,
                    style: EcTypography.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                  if (name != null) ...[
                    const SizedBox(height: EcSpacing.lg),
                    Text('Signed in as $name', style: EcTypography.bodyStrong),
                  ],
                  const SizedBox(height: EcSpacing.lg),
                  EcStatusChip(
                    label: 'Environment: ${config.environment.wireName}',
                    tone: config.environment.isProduction
                        ? EcStatusTone.success
                        : EcStatusTone.info,
                  ),
                  const SizedBox(height: EcSpacing.xl),
                  EcSecondaryButton(
                    label: 'Sign out',
                    icon: Icons.logout,
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                  ),
                  if (!config.environment.isProduction) ...[
                    const SizedBox(height: EcSpacing.md),
                    EcSecondaryButton(
                      label: 'Open design system',
                      onPressed: () => context.go(AppRoutes.designSystem),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
