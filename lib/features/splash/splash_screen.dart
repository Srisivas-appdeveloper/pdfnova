import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_background.dart';
import '../../core/widgets/nova_mark.dart';
import '../home/home_shell.dart';

/// Opening moment, ~1.9s (tap anywhere to skip). It starts as an exact
/// copy of Android's launch screen (same mark, size and position), then:
///   1. the artwork fades in and settles from a slow 1.12× zoom,
///   2. the mark glides up and shrinks into place,
///   3. "PDF Nova" rises out of a mask, the tagline fades in,
///   4. the foreground fades out and the artwork flies up into the home
///      header (Hero) while Home fades in.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: NovaMotion.splash);
  bool _navigated = false;

  Animation<double> _span(double a, double b,
          [Curve curve = NovaMotion.emphasized]) =>
      CurvedAnimation(parent: _c, curve: Interval(a, b, curve: curve));

  // Timeline (fractions of NovaMotion.splash):
  //   0.00–0.20  hold: identical to Android's launch screen, which fades
  //              out over ~200ms after our first frame (measured) — moving
  //              earlier showed two marks at once
  //   0.18–0.50  artwork fades in from the plain canvas, slow zoom settles
  //   0.20–0.54  the mark glides up and shrinks to its place
  //   0.42–0.72  "PDF Nova" rises out of a clip; 0.55–0.82 tagline fades in
  //   0.86–1.00  foreground fades out, so nothing ghosts over Home
  late final _zoom = _span(0, 1, Curves.easeOutCubic);
  late final _artIn = _span(0.18, 0.50, Curves.easeOut);
  late final _settle = _span(0.20, 0.54);
  late final _word = _span(0.42, 0.72);
  late final _tag = _span(0.55, 0.82);
  late final _out = _span(0.86, 1.0, Curves.easeIn);

  /// Size of NovaMark that matches the Android 12+ system splash icon
  /// (measured on device: the adaptive-icon foreground shown at screen
  /// centre), so the hand-off from the system splash has no jump.
  static const _systemMarkSize = 131.0;
  static const _markSize = 76.0;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NovaMotion.reduced(context)) {
      // Less motion: show the finished mark briefly, then fade to Home.
      _c.value = 1;
      Future.delayed(NovaMotion.splashReduced, _go);
    } else {
      _c.forward().whenComplete(_go);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration:
          NovaMotion.reduced(context) ? NovaMotion.quick : NovaMotion.handover,
      pageBuilder: (_, __, ___) => const HomeShell(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(
            parent: anim,
            curve: const Interval(0.25, 1, curve: Curves.easeOut)),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final screen = MediaQuery.sizeOf(context);
    final center = screen.height / 2;
    // Final layout: mark above centre, wordmark + tagline below it.
    const markGap = 26.0;
    final finalMarkCenter = center - 52;
    return GestureDetector(
      onTap: _go,
      child: Scaffold(
        backgroundColor: c.canvas,
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final s = _settle.value;
            final size = _systemMarkSize + (_markSize - _systemMarkSize) * s;
            final markCenter = center + (finalMarkCenter - center) * s;
            final fg = 1 - _out.value;
            return Stack(fit: StackFit.expand, children: [
              Opacity(
                opacity: _artIn.value,
                child: Transform.scale(
                  scale: 1.12 - 0.12 * _zoom.value,
                  child: const NovaArt(fade: false),
                ),
              ),
              Positioned(
                left: (screen.width - size) / 2,
                top: markCenter - size / 2,
                child: Opacity(opacity: fg, child: NovaMark(size: size)),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: finalMarkCenter + _markSize / 2 + markGap,
                child: Opacity(
                  opacity: fg,
                  child: Column(children: [
                    // Wordmark rises out of a clip, like type set into a page.
                    ClipRect(
                      child: FractionalTranslation(
                        translation: Offset(0, 1 - _word.value),
                        child: Opacity(
                          opacity: _word.value,
                          child: Text('PDF Nova', style: t.displayMedium),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: _tag.value,
                      child: Text('Your documents. Your phone.',
                          style: t.bodyMedium?.copyWith(color: c.inkMid)),
                    ),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
