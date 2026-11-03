import 'package:flutter/painting.dart';

/// Official EazyClinic colour tokens. Never hardcode hex values in features.
abstract final class EcColors {
  // Brand
  static const Color navy = Color(
    0xFF103B64,
  ); // structure, navigation, headings
  static const Color red = Color(
    0xFFE92335,
  ); // primary actions, brand highlights
  static const Color blue = Color(0xFF087FAF); // secondary actions, information

  // Neutrals
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);

  /// Pale-blue background for information tiles (stat cards in the mockup).
  static const Color infoBackground = Color(0xFFE6F3FA);

  /// Filled-input background used by the mockup's form fields.
  static const Color inputFill = Color(0xFFF1F5F9);

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);

  // Tinted backgrounds for status chips and banners (derived from semantics).
  static const Color successBackground = Color(0xFFE8F7EE);
  static const Color warningBackground = Color(0xFFFEF3E2);
  static const Color errorBackground = Color(0xFFFDECEE);

  // Disabled states
  static const Color disabledBackground = Color(0xFFE5E7EB);
  static const Color disabledForeground = Color(0xFF9CA3AF);
}
