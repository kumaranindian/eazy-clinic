import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';

/// White rounded surface with a hairline border. Tappable when [onTap] is set.
class EcCard extends StatelessWidget {
  const EcCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(EcSpacing.lg),
    this.color = EcColors.surface,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: EcRadii.card,
        side: EcBorders.standard,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Pale-blue statistic tile (value + caption), as used on dashboards.
class EcStatTile extends StatelessWidget {
  const EcStatTile({
    required this.value,
    required this.label,
    this.onTap,
    super.key,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return EcCard(
      color: EcColors.infoBackground,
      onTap: onTap,
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: EcTypography.statValue),
            const SizedBox(height: EcSpacing.xs),
            Text(label, style: EcTypography.bodySecondary),
          ],
        ),
      ),
    );
  }
}
