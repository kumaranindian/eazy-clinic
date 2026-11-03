import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';

/// Builds the EazyClinic Material theme from the design tokens.
abstract final class EcTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: EcColors.red,
      onPrimary: EcColors.surface,
      secondary: EcColors.blue,
      onSecondary: EcColors.surface,
      tertiary: EcColors.navy,
      onTertiary: EcColors.surface,
      error: EcColors.error,
      onError: EcColors.surface,
      surface: EcColors.surface,
      onSurface: EcColors.textPrimary,
      onSurfaceVariant: EcColors.textSecondary,
      outline: EcColors.border,
      outlineVariant: EcColors.border,
      surfaceContainerHighest: EcColors.inputFill,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: EcRadii.input,
      borderSide: BorderSide.none,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: EcTypography.fontFamily,
      package: EcTypography.fontPackage,
      scaffoldBackgroundColor: EcColors.background,
      dividerColor: EcColors.border,
      textTheme: TextTheme(
        displayLarge: EcTypography.displayLarge,
        displayMedium: EcTypography.display,
        headlineMedium: EcTypography.pageTitle,
        titleLarge: EcTypography.sectionTitle,
        titleMedium: EcTypography.subsectionTitle,
        bodyLarge: EcTypography.bodyLarge,
        bodyMedium: EcTypography.body,
        bodySmall: EcTypography.helper,
        labelLarge: EcTypography.bodyStrong,
        labelMedium: EcTypography.label,
        labelSmall: EcTypography.label,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: EcColors.surface,
        foregroundColor: EcColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: EcTypography.sectionTitle,
        shape: const Border(bottom: EcBorders.standard),
      ),
      cardTheme: CardThemeData(
        color: EcColors.surface,
        elevation: EcElevation.card,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: EcRadii.card,
          side: EcBorders.standard,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: EcColors.surface,
        elevation: EcElevation.dialog,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EcRadii.xl),
        ),
        titleTextStyle: EcTypography.sectionTitle,
        contentTextStyle: EcTypography.body,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: EcColors.surface,
        shape: RoundedRectangleBorder(borderRadius: EcRadii.sheet),
        showDragHandle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EcColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EcSpacing.lg,
          vertical: EcSpacing.md,
        ),
        hintStyle: EcTypography.body.copyWith(color: EcColors.textSecondary),
        labelStyle: EcTypography.label.copyWith(color: EcColors.textSecondary),
        errorStyle: EcTypography.error,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: EcColors.blue, width: 1.5),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: EcColors.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: EcColors.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: EcColors.red,
          foregroundColor: EcColors.surface,
          disabledBackgroundColor: EcColors.disabledBackground,
          disabledForegroundColor: EcColors.disabledForeground,
          minimumSize: const Size.fromHeight(EcSizes.buttonHeight),
          textStyle: EcTypography.button,
          shape: RoundedRectangleBorder(borderRadius: EcRadii.button),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: EcColors.blue,
          disabledForegroundColor: EcColors.disabledForeground,
          minimumSize: const Size.fromHeight(EcSizes.buttonHeight),
          textStyle: EcTypography.button,
          side: const BorderSide(color: EcColors.blue),
          shape: RoundedRectangleBorder(borderRadius: EcRadii.button),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: EcColors.red,
          textStyle: EcTypography.bodyStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? EcColors.red
              : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: EcColors.textSecondary, width: 1.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: EcColors.surface,
        height: EcSizes.bottomNavHeight,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: EcIconSizes.lg,
            color: states.contains(WidgetState.selected)
                ? EcColors.red
                : EcColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => EcTypography.label.copyWith(
            color: states.contains(WidgetState.selected)
                ? EcColors.red
                : EcColors.textSecondary,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: EcColors.border,
        thickness: EcSizes.borderWidth,
        space: EcSizes.borderWidth,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: EcColors.navy,
        contentTextStyle: EcTypography.body.copyWith(color: EcColors.surface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: EcRadii.button),
      ),
    );
  }
}
