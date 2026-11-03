import 'package:flutter/painting.dart';

import 'ec_colors.dart';

/// Typography tokens. Inter is bundled with this package.
abstract final class EcTypography {
  static const String fontFamily = 'Inter';
  static const String fontPackage = 'design_system';

  static TextStyle _s(
    double size,
    FontWeight weight,
    double height, {
    Color color = EcColors.textPrimary,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: size,
    fontWeight: weight,
    height: height / size,
    color: color,
    letterSpacing: letterSpacing,
  );

  // Display
  static final TextStyle displayLarge = _s(
    32,
    FontWeight.w700,
    40,
    color: EcColors.navy,
  );
  static final TextStyle display = _s(
    28,
    FontWeight.w700,
    36,
    color: EcColors.navy,
  );

  // Titles
  static final TextStyle pageTitle = _s(
    24,
    FontWeight.w700,
    32,
    color: EcColors.navy,
  );
  static final TextStyle sectionTitle = _s(
    18,
    FontWeight.w600,
    26,
    color: EcColors.navy,
  );
  static final TextStyle subsectionTitle = _s(16, FontWeight.w600, 24);

  // Body
  static final TextStyle bodyLarge = _s(16, FontWeight.w400, 24);
  static final TextStyle body = _s(14, FontWeight.w400, 20);
  static final TextStyle bodyStrong = _s(14, FontWeight.w600, 20);
  static final TextStyle bodySecondary = _s(
    14,
    FontWeight.w400,
    20,
    color: EcColors.textSecondary,
  );

  // Labels and helpers
  static final TextStyle label = _s(
    12,
    FontWeight.w500,
    16,
    letterSpacing: 0.1,
  );
  static final TextStyle helper = _s(
    12,
    FontWeight.w400,
    16,
    color: EcColors.textSecondary,
  );
  static final TextStyle error = _s(
    12,
    FontWeight.w400,
    16,
    color: EcColors.error,
  );

  // Controls
  static final TextStyle button = _s(
    16,
    FontWeight.w600,
    24,
    color: EcColors.surface,
  );
  static final TextStyle buttonSmall = _s(
    14,
    FontWeight.w600,
    20,
    color: EcColors.surface,
  );

  // Data tables
  static final TextStyle tableHeader = _s(
    12,
    FontWeight.w600,
    16,
    color: EcColors.textSecondary,
    letterSpacing: 0.4,
  );
  static final TextStyle tableCell = _s(13, FontWeight.w400, 20);

  // Numeric highlights (stat tiles)
  static final TextStyle statValue = _s(
    24,
    FontWeight.w700,
    32,
    color: EcColors.navy,
  );
}
