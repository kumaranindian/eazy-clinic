import 'package:flutter/material.dart';

import '../tokens/ec_breakpoints.dart';
import '../tokens/ec_dimensions.dart';

/// Centers content, caps its width and applies the responsive page gutter.
class EcResponsiveContainer extends StatelessWidget {
  const EcResponsiveContainer({
    required this.child,
    this.maxWidth = EcSizes.maxContentWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final gutter = EcBreakpoints.of(context).isCompact
        ? EcSpacing.pageGutterCompact
        : EcSpacing.pageGutterWide;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: child,
        ),
      ),
    );
  }
}

/// Rebuilds [builder] with the current [EcWindowSize].
class EcBreakpointBuilder extends StatelessWidget {
  const EcBreakpointBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, EcWindowSize size) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, EcBreakpoints.of(context));
}
