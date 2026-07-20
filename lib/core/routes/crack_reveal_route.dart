import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// The "cracker" transition, v2. From the exact tap point:
///   1. a white micro-flash (40ms) — the fuse
///   2. an aurora stroke ring races outward — the crack line
///   3. twelve gradient shards fly and tumble — the burst
///   4. the new screen opens inside a circular reveal and settles from
///      1.03 → 1.0 scale — the landing
/// One orchestrated moment, 560ms, with a light haptic at ignition.
class CrackRevealRoute<T> extends PageRouteBuilder<T> {
  CrackRevealRoute({required Widget page, required Offset origin})
      : super(
          transitionDuration: const Duration(milliseconds: 560),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (context, animation, _, child) {
            if (animation.status == AnimationStatus.forward &&
                animation.value == 0) {
              HapticFeedback.lightImpact();
            }
            final size = MediaQuery.of(context).size;
            final maxR = _farthestCorner(origin, size);
            final open = CurvedAnimation(
                parent: animation, curve: Curves.easeOutQuart);
            final settle = CurvedAnimation(
                parent: animation,
                curve: const Interval(0.55, 1.0, curve: Curves.easeOutBack));
            return AnimatedBuilder(
              animation: animation,
              builder: (_, __) => Stack(
                children: [
                  ClipPath(
                    clipper: _CircleClipper(origin, open.value * maxR),
                    child: Transform.scale(
                      scale: 1.03 - 0.03 * settle.value,
                      child: child,
                    ),
                  ),
                  if (animation.status == AnimationStatus.forward &&
                      open.value < 0.7)
                    IgnorePointer(
                      child: CustomPaint(
                        size: size,
                        painter: _BurstPainter(
                            origin, (open.value / 0.7).clamp(0.0, 1.0), maxR),
                      ),
                    ),
                ],
              ),
            );
          },
        );

  static double _farthestCorner(Offset o, Size s) {
    final corners = [
      Offset.zero,
      Offset(s.width, 0),
      Offset(0, s.height),
      Offset(s.width, s.height),
    ];
    return corners.map((c) => (c - o).distance).reduce(math.max);
  }
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.radius != radius || old.center != center;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.origin, this.t, this.maxR);
  final Offset origin;
  final double t; // 0→1 over the burst window
  final double maxR;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Micro-flash at ignition
    if (t < 0.12) {
      canvas.drawCircle(
        origin,
        26 * (t / 0.12),
        Paint()
          ..color = Colors.white.withOpacity(0.85 * (1 - t / 0.12))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }

    // 2. Crack ring racing outward, fading as it travels
    final ringR = t * maxR * 0.9;
    if (ringR > 4) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * (1 - t)
        ..shader = SweepGradient(
          colors: const [
            AppColors.violet,
            AppColors.cyan,
            AppColors.violet,
          ],
        ).createShader(Rect.fromCircle(center: origin, radius: ringR))
        ..color = Colors.white.withOpacity((1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(origin, ringR, ringPaint);
    }

    // 3. Twelve tumbling shards with slight gravity droop
    final rng = math.Random(7);
    for (var i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi + rng.nextDouble() * 0.35;
      final speed = 110 + rng.nextDouble() * 90;
      final droop = 30 * t * t; // gravity
      final pos = origin +
          Offset(math.cos(angle) * speed * t,
              math.sin(angle) * speed * t + droop);
      final opacity = (1 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = (i % 3 == 0
                ? Colors.white
                : i.isEven
                    ? AppColors.violet
                    : AppColors.cyan)
            .withOpacity(opacity);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle + t * (3 + rng.nextDouble() * 2));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero,
                width: 6.5 - t * 4,
                height: 15 - t * 7),
            const Radius.circular(2)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
