import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// Plain paper canvas behind a screen. Kept as a widget (not just the
/// scaffold colour) so every screen shares one place to change it.
class NovaBackground extends StatelessWidget {
  const NovaBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.nova.canvas, child: child);
}

/// The background artwork, faded into the canvas at the bottom edge.
///
/// Shares a Hero tag between the splash (full screen) and the home header,
/// so on launch the picture visibly shrinks into place instead of cutting.
/// [parallax] shifts the image at half the scroll speed for depth.
class NovaArt extends StatelessWidget {
  const NovaArt({
    super.key,
    this.height,
    this.fade = true,
    this.parallax = 0,
    this.hero = true,
  });

  static const heroTag = 'nova-art';

  final double? height;
  final bool fade;
  final double parallax;
  final bool hero;

  static Widget _fade(NovaColors c) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.55, 1.0],
            colors: [
              c.canvas.withValues(alpha: 0),
              c.canvas.withValues(alpha: 0.35),
              c.canvas,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    Widget art = Stack(fit: StackFit.expand, children: [
      Transform.translate(
        offset: Offset(0, parallax * 0.5),
        child: AnimatedSwitcher(
          duration: NovaMotion.artSwap,
          // Default layout is a loose Stack, which would let the image
          // shrink to its own aspect ratio instead of covering the box.
          layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current]),
          child: Image.asset(
            c.art,
            key: ValueKey(c.art),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            gaplessPlayback: true,
          ),
        ),
      ),
      if (fade) _fade(c),
    ]);
    if (hero) {
      art = Hero(
        tag: heroTag,
        // The splash art has no fade and the header art does: grow the
        // fade in during the flight so nothing pops when it lands.
        flightShuttleBuilder: (_, anim, dir, __, ___) =>
            Stack(fit: StackFit.expand, children: [
          Image.asset(c.art, fit: BoxFit.cover, alignment: Alignment.topCenter),
          FadeTransition(
            opacity:
                dir == HeroFlightDirection.push ? anim : ReverseAnimation(anim),
            child: _fade(c),
          ),
        ]),
        child: art,
      );
    }
    return SizedBox(height: height, width: double.infinity, child: art);
  }
}
