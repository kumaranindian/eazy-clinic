import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';
import 'ec_button.dart';

/// Guidance shown when a list or screen has no data yet.
class EcEmptyState extends StatelessWidget {
  const EcEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

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
              CircleAvatar(
                radius: 36,
                backgroundColor: EcColors.infoBackground,
                child: Icon(icon, size: EcIconSizes.xl, color: EcColors.blue),
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
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: EcSpacing.xl),
                EcPrimaryButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
