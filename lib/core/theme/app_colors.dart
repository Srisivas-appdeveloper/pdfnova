import 'package:flutter/material.dart';

/// PDF Nova design tokens — the "Folio" language.
///
/// Solid surfaces on a warm paper canvas, hairline borders instead of
/// shadows, one cobalt accent for action, and a quiet tint per tool family
/// so sections are recognisable at a glance. No glass, no blur, no
/// gradients on controls. Every colour has a light and a dark value; read
/// them through `context.nova` so a theme switch repaints everything.
@immutable
class NovaColors extends ThemeExtension<NovaColors> {
  const NovaColors({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.ink,
    required this.inkMid,
    required this.inkLow,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.scrim,
    required this.shadow,
    required this.tints,
    required this.art,
  });

  /// Page background.
  final Color canvas;

  /// Cards, sheets, bars.
  final Color surface;

  /// Sunken fields, segmented-control tracks, skeletons.
  final Color surfaceAlt;

  final Color border;
  final Color borderStrong;

  /// Text: primary, secondary, tertiary.
  final Color ink;
  final Color inkMid;
  final Color inkLow;

  final Color accent;
  final Color accentSoft;
  final Color onAccent;

  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;

  final Color scrim;
  final Color shadow;

  /// Per tool-section (foreground, background) pairs, indexed by section.
  final List<(Color, Color)> tints;

  /// Background artwork for the splash and home header.
  final String art;

  (Color, Color) tint(int index) => tints[index % tints.length];

  static const light = NovaColors(
    canvas: Color(0xFFF4F1EB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFECE8E0),
    border: Color(0xFFE4DFD5),
    borderStrong: Color(0xFFCFC9BD),
    ink: Color(0xFF16161A),
    inkMid: Color(0xFF5C5A55),
    inkLow: Color(0xFF6F6B64), // 4.7:1 on canvas (WCAG AA)
    accent: Color(0xFF3550E6),
    accentSoft: Color(0xFFE6EAFD),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF117A4C), // AA as text on canvas & successSoft
    successSoft: Color(0xFFDDF3E8),
    danger: Color(0xFFBC3127), // AA as text on canvas & dangerSoft
    dangerSoft: Color(0xFFFBE3E0),
    scrim: Color(0x6616161A),
    shadow: Color(0x1416161A),
    tints: [
      (Color(0xFF3550E6), Color(0xFFE6EAFD)), // Organize — cobalt
      (Color(0xFFB86E00), Color(0xFFFBEBD3)), // Shrink & convert — amber
      (Color(0xFF17915A), Color(0xFFDDF3E8)), // Secure — green
      (Color(0xFF7B4FE0), Color(0xFFEDE5FC)), // Smart — violet
      (Color(0xFFD2456E), Color(0xFFFBE3EA)), // More — rose
    ],
    art: 'assets/images/nova_art_light.jpg',
  );

  static const dark = NovaColors(
    canvas: Color(0xFF101012),
    surface: Color(0xFF1A1A1D),
    surfaceAlt: Color(0xFF242428),
    border: Color(0xFF2A2A2F),
    borderStrong: Color(0xFF3A3A40),
    ink: Color(0xFFF3F1EC),
    inkMid: Color(0xFFA8A59F),
    inkLow: Color(0xFF918E88), // 5.8:1 on canvas (WCAG AA)
    accent: Color(0xFF7C8FFF),
    accentSoft: Color(0xFF1E2347),
    onAccent: Color(0xFF0B0F2E),
    success: Color(0xFF5CD69A),
    successSoft: Color(0xFF12291E),
    danger: Color(0xFFFF7A6E),
    dangerSoft: Color(0xFF3A1714),
    scrim: Color(0x99000000),
    shadow: Color(0x00000000),
    tints: [
      (Color(0xFF8EA0FF), Color(0xFF1C2142)),
      (Color(0xFFF5B454), Color(0xFF2E2312)),
      (Color(0xFF5CD69A), Color(0xFF12291E)),
      (Color(0xFFB79BFF), Color(0xFF241B3B)),
      (Color(0xFFFF8DAE), Color(0xFF33161F)),
    ],
    art: 'assets/images/nova_art_dark.jpg',
  );

  @override
  NovaColors copyWith() => this;

  @override
  NovaColors lerp(NovaColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return NovaColors(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      ink: l(ink, other.ink),
      inkMid: l(inkMid, other.inkMid),
      inkLow: l(inkLow, other.inkLow),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      onAccent: l(onAccent, other.onAccent),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      scrim: l(scrim, other.scrim),
      shadow: l(shadow, other.shadow),
      tints: [
        for (var i = 0; i < tints.length; i++)
          (
            l(tints[i].$1, other.tints[i].$1),
            l(tints[i].$2, other.tints[i].$2)
          ),
      ],
      art: t < 0.5 ? art : other.art,
    );
  }
}

extension NovaContext on BuildContext {
  NovaColors get nova => Theme.of(this).extension<NovaColors>()!;
}
