import 'package:flutter/widgets.dart';

/// Window-size classes. Layout code branches on these, never on raw widths.
enum EcWindowSize {
  /// Phones (< 600).
  compact,

  /// Large phones, small tablets (600-1023).
  medium,

  /// Tablets landscape, small desktop (1024-1439).
  expanded,

  /// Large desktop (>= 1440).
  large;

  bool get isCompact => this == EcWindowSize.compact;
  bool get isMediumOrLarger => index >= EcWindowSize.medium.index;
  bool get isExpandedOrLarger => index >= EcWindowSize.expanded.index;
}

abstract final class EcBreakpoints {
  static const double medium = 600;
  static const double expanded = 1024;
  static const double large = 1440;

  static EcWindowSize fromWidth(double width) {
    if (width >= large) return EcWindowSize.large;
    if (width >= expanded) return EcWindowSize.expanded;
    if (width >= medium) return EcWindowSize.medium;
    return EcWindowSize.compact;
  }

  static EcWindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);
}
