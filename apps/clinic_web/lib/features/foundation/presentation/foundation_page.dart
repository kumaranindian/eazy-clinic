import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_info.dart';
import '../../../core/config/client_config_provider.dart';
import '../../../core/routing/app_router.dart';

/// Phase 0 placeholder: proves the shell, theme, routing and configuration
/// work. It is replaced by the real entry screens in Phase 1.
class FoundationPage extends ConsumerWidget {
  const FoundationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(clientConfigProvider);
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
                  const EcBrandLogo.full(height: 180),
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
                  const SizedBox(height: EcSpacing.lg),
                  EcStatusChip(
                    label: 'Environment: ${config.environment.wireName}',
                    tone: config.environment.isProduction
                        ? EcStatusTone.success
                        : EcStatusTone.info,
                  ),
                  const SizedBox(height: EcSpacing.xs),
                  const EcStatusChip(label: 'Phase 0 foundation'),
                  if (!config.environment.isProduction) ...[
                    const SizedBox(height: EcSpacing.xl),
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
