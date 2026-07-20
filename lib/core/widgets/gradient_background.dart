import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated aurora mesh behind every screen. Three soft blobs drift slowly
/// on sine paths. This is what makes the glass surfaces "read" as glass —
/// blur needs something colourful moving behind it. Cheap to render:
/// plain gradients, no BackdropFilter here.
class GradientBackground extends StatefulWidget {
  const GradientBackground({super.key, required this.child});
  final Widget child;

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.ink),
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value * 2 * math.pi;
            return CustomPaint(
              painter: _BlobPainter(t),
              // Respect reduced motion: freeze when disabled.
              willChange: !MediaQuery.of(context).disableAnimations,
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.t);
  final double t;

  void _blob(Canvas canvas, Size s, Color color, double phase, double dx,
      double dy, double r) {
    final cx = s.width * (dx + 0.10 * math.sin(t + phase));
    final cy = s.height * (dy + 0.08 * math.cos(t * 0.8 + phase));
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.32), color.withOpacity(0)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _blob(canvas, size, AppColors.violet, 0, 0.20, 0.15, size.width * 0.62);
    _blob(canvas, size, AppColors.cyan, 2.1, 0.85, 0.35, size.width * 0.52);
    _blob(canvas, size, AppColors.magenta, 4.2, 0.45, 0.92, size.width * 0.55);
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t;
}
