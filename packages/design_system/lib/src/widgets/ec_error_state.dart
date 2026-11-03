import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';
import 'ec_button.dart';

/// Error placeholder with an optional retry action. Pass a user-safe message;
/// never raw exceptions or stack traces.
class EcErrorState extends StatelessWidget {
  const EcErrorState({
    this.title = 'Something went wrong',
    this.message = 'Please check your connection and try again.',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EcSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 36,
                backgroundColor: EcColors.errorBackground,
                child: Icon(
                  Icons.error_outline,
                  size: EcIconSizes.xl,
                  color: EcColors.error,
                ),
              ),
              const SizedBox(height: EcSpacing.lg),
              Text(
                title,
                style: EcTypography.sectionTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: EcSpacing.sm),
              Text(
                message,
                style: EcTypography.bodySecondary,
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: EcSpacing.xl),
                EcSecondaryButton(
                  label: 'Try again',
                  icon: Icons.refresh,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
