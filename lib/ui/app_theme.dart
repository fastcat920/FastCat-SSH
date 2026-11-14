import 'package:flutter/material.dart';
import 'code_theme.dart';

ThemeData buildAppTheme(String accent, Brightness brightness) {
  final colors = ColorScheme.fromSeed(
    seedColor: brandColors[accent] ?? brandColors['mint']!,
    brightness: brightness,
  );
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    colorScheme: colors,
    useMaterial3: true,
    scaffoldBackgroundColor: colors.surface,
    canvasColor: colors.surface,
    extensions: [
      CodePalette.named('classic', brightness == Brightness.dark).copyWith(
        background: colors.surfaceContainerLow,
        foreground: colors.onSurface,
      ),
    ],
    dialogTheme: DialogThemeData(backgroundColor: colors.surfaceContainerHigh),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: border,
      enabledBorder: border.copyWith(
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
  );
}
