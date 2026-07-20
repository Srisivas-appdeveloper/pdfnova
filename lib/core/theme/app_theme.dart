import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

abstract class AppTheme {
  static ThemeData get dark {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final display = GoogleFonts.soraTextTheme(base.textTheme);
    final body = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.ink,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.violet,
        secondary: AppColors.cyan,
        surface: AppColors.inkRaised,
        error: AppColors.danger,
      ),
      textTheme: body.copyWith(
        displayLarge: display.displayLarge?.copyWith(
            fontWeight: FontWeight.w700, color: AppColors.textHigh),
        headlineMedium: display.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700, color: AppColors.textHigh),
        titleLarge: display.titleLarge?.copyWith(
            fontWeight: FontWeight.w600, color: AppColors.textHigh),
        titleMedium: display.titleMedium?.copyWith(
            fontWeight: FontWeight.w600, color: AppColors.textHigh),
        bodyLarge: body.bodyLarge?.copyWith(color: AppColors.textHigh),
        bodyMedium: body.bodyMedium?.copyWith(color: AppColors.textMid),
        labelLarge: body.labelLarge?.copyWith(
            fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.inkRaised,
        // The default M3 content color (onInverseSurface) is a DARK grey —
        // invisible on our dark pill. Set light text explicitly.
        contentTextStyle: const TextStyle(color: AppColors.textHigh, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
