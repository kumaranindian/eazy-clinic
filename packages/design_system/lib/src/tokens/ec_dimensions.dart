import 'package:flutter/painting.dart';

import 'ec_colors.dart';

/// Spacing scale (logical pixels, 4-pt base).
abstract final class EcSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal page gutter on phones.
  static const double pageGutterCompact = 16;

  /// Horizontal page gutter on tablets and desktop.
  static const double pageGutterWide = 24;
}

/// Corner radii.
abstract final class EcRadii {
  static const double sm = 6;
  static const double md = 10; // buttons, inputs
  static const double lg = 14; // cards
  static const double xl = 20; // sheets, dialogs
  static const double pill = 999;

  static BorderRadius get button => BorderRadius.circular(md);
  static BorderRadius get input => BorderRadius.circular(md);
  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get sheet =>
      const BorderRadius.vertical(top: Radius.circular(xl));
}

/// Elevation levels. The visual language is mostly flat: borders and soft
/// shadows instead of heavy elevation.
abstract final class EcElevation {
  static const double none = 0;
  static const double card = 0;
  static const double raised = 1;
  static const double dialog = 6;
}

/// Soft shadows for raised surfaces.
abstract final class EcShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F103B64), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x1A103B64), blurRadius: 20, offset: Offset(0, 8)),
  ];
  static List<BoxShadow> get none => const [];
}

/// Icon sizes.
abstract final class EcIconSizes {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double hero = 64;
}

/// Control dimensions. 48 dp keeps tap targets one-handed friendly.
abstract final class EcSizes {
  static const double buttonHeight = 48;
  static const double buttonHeightCompact = 40;
  static const double inputHeight = 52;
  static const double minTapTarget = 48;
  static const double appBarHeight = 56;
  static const double bottomNavHeight = 64;
  static const double sideNavWidth = 248;
  static const double sideNavWidthCollapsed = 72;
  static const double maxContentWidth = 1200;
  static const double maxFormWidth = 440;
  static const double borderWidth = 1;
}

/// Convenience border used by cards and inputs.
abstract final class EcBorders {
  static const BorderSide standard = BorderSide(
    color: EcColors.border,
    width: EcSizes.borderWidth,
  );
}
