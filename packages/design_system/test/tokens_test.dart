import 'package:design_system/design_system.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brand colours match the approved palette', () {
    expect(EcColors.navy, const Color(0xFF103B64));
    expect(EcColors.red, const Color(0xFFE92335));
    expect(EcColors.blue, const Color(0xFF087FAF));
    expect(EcColors.background, const Color(0xFFF8FAFC));
    expect(EcColors.infoBackground, const Color(0xFFE6F3FA));
    expect(EcColors.surface, const Color(0xFFFFFFFF));
    expect(EcColors.textPrimary, const Color(0xFF1F2937));
    expect(EcColors.textSecondary, const Color(0xFF6B7280));
    expect(EcColors.border, const Color(0xFFE5E7EB));
    expect(EcColors.success, const Color(0xFF16A34A));
    expect(EcColors.warning, const Color(0xFFD97706));
    expect(EcColors.error, const Color(0xFFDC2626));
  });

  test('breakpoints map widths to window sizes', () {
    expect(EcBreakpoints.fromWidth(360), EcWindowSize.compact);
    expect(EcBreakpoints.fromWidth(600), EcWindowSize.medium);
    expect(EcBreakpoints.fromWidth(1024), EcWindowSize.expanded);
    expect(EcBreakpoints.fromWidth(1440), EcWindowSize.large);
  });

  test('typography uses Inter', () {
    expect(EcTypography.body.fontFamily, contains('Inter'));
  });

  test('tap target meets the 48dp minimum', () {
    expect(EcSizes.minTapTarget, greaterThanOrEqualTo(48));
    expect(EcSizes.buttonHeight, greaterThanOrEqualTo(48));
  });
}
