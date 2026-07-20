import 'package:flutter/material.dart';

/// PDF Nova design tokens — "ink & aurora" dark glass system.
/// Deep ink base so frosted glass reads clearly; a single violet→cyan
/// aurora gradient carries all accent duty. Never introduce new accents.
abstract class AppColors {
  // Base canvas
  static const ink = Color(0xFF0B0E1A);
  static const inkRaised = Color(0xFF121729);

  // Aurora accent (the only gradient in the app)
  static const violet = Color(0xFF7C5CFF);
  static const cyan = Color(0xFF37D3E8);
  static const magenta = Color(0xFFE85CB8); // ambient blob only, never UI

  // Glass surfaces
  static Color glassFill = Colors.white.withOpacity(0.07);
  static Color glassFillStrong = Colors.white.withOpacity(0.11);
  static Color glassBorder = Colors.white.withOpacity(0.14);

  // Text
  static const textHigh = Color(0xFFF4F6FF);
  static Color textMid = const Color(0xFFF4F6FF).withOpacity(0.66);
  static Color textLow = const Color(0xFFF4F6FF).withOpacity(0.38);

  // Semantic
  static const success = Color(0xFF4ADE9C);
  static const danger = Color(0xFFFF6B81);

  static const aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, cyan],
  );
}
