import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_background.dart';
import '../../core/widgets/nova_mark.dart';
import '../home/home_shell.dart';

/// Opening moment, ~1.9s (tap anywhere to skip):
///   1. the artwork settles from a slow 1.12× zoom (Ken Burns),
///   2. the mark draws itself: page outline → fold → the star blooms,
///   3. "PDF Nova" rises out of a mask, the tagline fades in,
///   4. hand-over: the artwork flies up into the home header (Hero) while
///      home fades in underneath.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1900));
  bool _navigated = false;

  Animation<double> _span(double a, double b, [Curve curve = NovaMotion.emphasized]) =>
      CurvedAnimation(parent: _c, curve: Interval(a, b, curve: curve));

  late final _zoom = _span(0, 1, Curves.easeOutCubic);
  late final _mark = _span(0.05, 0.62, Curves.linear);
  late final _word = _span(0.38, 0.72);
  late final _tag = _span(0.55, 0.85);

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_go);
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
      transitionDuration: const Duration(milliseconds: 750),
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
    return GestureDetector(
      onTap: _go,
      child: Scaffold(
        backgroundColor: c.canvas,
        body: Stack(fit: StackFit.expand, children: [
          AnimatedBuilder(
            animation: _zoom,
            builder: (_, child) =>
                Transform.scale(scale: 1.12 - 0.12 * _zoom.value, child: child),
            child: const NovaArt(fade: false),
          ),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _mark,
                builder: (_, __) =>
                    NovaMark(size: 76, progress: _mark.value),
              ),
              const SizedBox(height: 26),
              // Wordmark rises out of a clip, like type set into a page.
              ClipRect(
                child: AnimatedBuilder(
                  animation: _word,
                  builder: (_, child) => FractionalTranslation(
                    translation: Offset(0, 1 - _word.value),
                    child: Opacity(opacity: _word.value, child: child),
                  ),
                  child: Text('PDF Nova', style: t.displayMedium),
                ),
              ),
              const SizedBox(height: 10),
              FadeTransition(
                opacity: _tag,
                child: Text('Your documents. Your phone.',
                    style: t.bodyMedium?.copyWith(color: c.inkMid)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
