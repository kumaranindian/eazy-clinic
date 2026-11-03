import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';
import 'ec_status_chip.dart';

/// Inline banner for form-level feedback (errors, confirmations, hints).
/// Announced to screen readers as a live region.
class EcInlineMessage extends StatelessWidget {
  const EcInlineMessage({
    required this.message,
    this.tone = EcStatusTone.error,
    super.key,
  });

  final String message;
  final EcStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (tone) {
      EcStatusTone.success => (
        EcColors.successBackground,
        EcColors.success,
        Icons.check_circle_outline,
      ),
      EcStatusTone.warning => (
        EcColors.warningBackground,
        EcColors.warning,
        Icons.warning_amber_outlined,
      ),
      EcStatusTone.info => (
        EcColors.infoBackground,
        EcColors.blue,
        Icons.info_outline,
      ),
      _ => (EcColors.errorBackground, EcColors.error, Icons.error_outline),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: EcRadii.input,
        ),
        child: Padding(
          padding: const EdgeInsets.all(EcSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: EcIconSizes.md, color: foreground),
              const SizedBox(width: EcSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: EcTypography.body.copyWith(
                    color: EcColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
