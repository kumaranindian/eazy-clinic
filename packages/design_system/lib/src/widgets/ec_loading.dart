import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';
import 'ec_texts.dart';

/// Centered loading indicator with an optional message.
class EcLoadingIndicator extends StatelessWidget {
  const EcLoadingIndicator({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: message ?? EcTexts.of(context).loading,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: EcColors.red),
            if (message != null) ...[
              const SizedBox(height: EcSpacing.lg),
              Text(message!, style: EcTypography.bodySecondary),
            ],
          ],
        ),
      ),
    );
  }
}
