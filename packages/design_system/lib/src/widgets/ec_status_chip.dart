import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';

/// Semantic tone of a status indicator.
enum EcStatusTone { success, warning, error, info, neutral }

/// Compact tinted status pill (e.g. "Follow Up", "Paid", "Waiting").
///
/// Meaning is carried by the label, not by colour alone.
class EcStatusChip extends StatelessWidget {
  const EcStatusChip({
    required this.label,
    this.tone = EcStatusTone.neutral,
    super.key,
  });

  final String label;
  final EcStatusTone tone;

  (Color, Color) get _colors => switch (tone) {
    EcStatusTone.success => (EcColors.successBackground, EcColors.success),
    EcStatusTone.warning => (EcColors.warningBackground, EcColors.warning),
    EcStatusTone.error => (EcColors.errorBackground, EcColors.error),
    EcStatusTone.info => (EcColors.infoBackground, EcColors.blue),
    EcStatusTone.neutral => (EcColors.inputFill, EcColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(EcRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: EcSpacing.sm,
          vertical: EcSpacing.xs,
        ),
        child: Text(
          label,
          style: EcTypography.label.copyWith(color: foreground),
        ),
      ),
    );
  }
}
