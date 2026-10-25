import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_motion.dart';

/// Builds the light and dark ThemeData from [NovaColors].
///
/// Type: Instrument Serif for display moments (hero lines, screen titles,
/// big numbers) and Inter for everything you read or tap. Both fonts are
/// bundled in assets/fonts so the app looks right with no network.
abstract class AppTheme {
  static const serif = 'InstrumentSerif';
  static const sans = 'Inter';

  static ThemeData get light => _build(NovaColors.light, Brightness.light);
  static ThemeData get dark => _build(NovaColors.dark, Brightness.dark);

  static ThemeData _build(NovaColors c, Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMid,
      outline: c.borderStrong,
      outlineVariant: c.border,
      surfaceContainerHighest: c.surfaceAlt,
      inverseSurface: c.ink,
      onInverseSurface: c.canvas,
    );

    TextStyle serifStyle(double size, {double height = 1.1}) => TextStyle(
        fontFamily: serif,
        fontSize: size,
        height: height,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w400,
        color: c.ink);

    TextStyle sansStyle(double size, FontWeight w, Color color,
            {double spacing = 0, double height = 1.35}) =>
        TextStyle(
            fontFamily: sans,
            fontSize: size,
            fontWeight: w,
            color: color,
            letterSpacing: spacing,
            height: height);

    final text = TextTheme(
      displayLarge: serifStyle(56, height: 1.0),
      displayMedium: serifStyle(46, height: 1.02),
      displaySmall: serifStyle(40, height: 1.05),
      headlineLarge: serifStyle(36),
      headlineMedium: serifStyle(32),
      headlineSmall: serifStyle(26),
      titleLarge: sansStyle(19, FontWeight.w600, c.ink, spacing: -0.2),
      titleMedium: sansStyle(15.5, FontWeight.w600, c.ink, spacing: -0.1),
      titleSmall: sansStyle(13.5, FontWeight.w600, c.ink),
      bodyLarge: sansStyle(15.5, FontWeight.w400, c.ink),
      bodyMedium: sansStyle(14, FontWeight.w400, c.inkMid),
      bodySmall: sansStyle(12.5, FontWeight.w400, c.inkLow),
      labelLarge: sansStyle(15, FontWeight.w600, c.ink),
      labelMedium: sansStyle(13, FontWeight.w500, c.inkMid),
      labelSmall:
          sansStyle(11, FontWeight.w600, c.inkLow, spacing: 1.1, height: 1.2),
    );

    final overlay = (isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: c.canvas,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    final shape16 =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: sans,
      textTheme: text,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      dividerColor: c.border,
      splashFactory: InkSparkle.splashFactory,
      highlightColor: Colors.transparent,
      extensions: [c],
      iconTheme: IconThemeData(color: c.ink, size: 22),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: NovaPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: NovaPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        systemOverlayStyle: overlay,
        titleTextStyle: text.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle:
            sansStyle(14, FontWeight.w500, c.canvas, height: 1.4),
        actionTextColor: isDark ? c.onAccent : c.accentSoft,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: shape16,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: c.border),
        ),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.surfaceAlt,
        thumbColor: c.accent,
        overlayColor: c.accent.withValues(alpha: 0.12),
        trackHeight: 4,
        showValueIndicator: ShowValueIndicator.never,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.onAccent : c.inkLow),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.accent : c.surfaceAlt),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.accent : c.borderStrong),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceAlt,
        circularTrackColor: c.surfaceAlt,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          textStyle: text.labelLarge,
          shape: shape16,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.25),
        selectionHandleColor: c.accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: text.bodyLarge?.copyWith(color: c.inkLow),
        border: InputBorder.none,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkMid,
        textColor: c.ink,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
      ),
    );
  }
}

/// Default page transition for every MaterialPageRoute on Android.
///
/// The incoming page glides in from the right with a fade while the page
/// underneath drifts left and dims — a "parallax push". Reversed on pop.
/// With reduced motion it collapses to a short cross-fade.
class NovaPageTransitionsBuilder extends PageTransitionsBuilder {
  const NovaPageTransitionsBuilder();

  @override
  Duration get transitionDuration => NovaMotion.page;

  @override
  Duration get reverseTransitionDuration => NovaMotion.pageReverse;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      novaPushTransition(context, animation, secondaryAnimation, child);
}

/// Shared by [NovaPageTransitionsBuilder] and [NovaRoute].
Widget novaPushTransition(BuildContext context, Animation<double> animation,
    Animation<double> secondary, Widget child) {
  if (NovaMotion.reduced(context)) {
    return FadeTransition(opacity: animation, child: child);
  }
  final inCurve = CurvedAnimation(
      parent: animation,
      curve: NovaMotion.emphasized,
      reverseCurve: NovaMotion.emphasized.flipped);
  final outCurve = CurvedAnimation(
      parent: secondary,
      curve: NovaMotion.emphasized,
      reverseCurve: NovaMotion.emphasized.flipped);
  final shade = context.nova.scrim;

  return AnimatedBuilder(
    animation: outCurve,
    builder: (context, page) => Transform.translate(
      offset: Offset(-MediaQuery.sizeOf(context).width * 0.18 * outCurve.value, 0),
      child: Stack(fit: StackFit.passthrough, children: [
        page!,
        if (outCurve.value > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                  color: shade.withValues(
                      alpha: shade.a * 0.5 * outCurve.value)),
            ),
          ),
      ]),
    ),
    child: SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(inCurve),
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(-4, 0)),
        ]),
        child: child,
      ),
    ),
  );
}

/// Explicit route with the house push transition — for pushes that are not
/// MaterialPageRoutes (and so would not pick up the theme's builder).
class NovaRoute<T> extends PageRouteBuilder<T> {
  NovaRoute({required Widget page})
      : super(
          transitionDuration: NovaMotion.page,
          reverseTransitionDuration: NovaMotion.pageReverse,
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: novaPushTransition,
        );
}
