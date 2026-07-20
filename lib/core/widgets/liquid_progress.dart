import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Liquid wave filling a glass ring — the processing indicator.
/// [progress] 0..1; wave keeps lapping even at constant progress so the
/// screen always feels alive.
class LiquidProgress extends StatefulWidget {
  const LiquidProgress({super.key, required this.progress, this.size = 168});
  final double progress;
  final double size;

  @override
  State<LiquidProgress> createState() => _LiquidProgressState();
}

class _LiquidProgressState extends State<LiquidProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))
    ..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _wave,
        builder: (_, __) => CustomPaint(
          painter: _LiquidPainter(widget.progress, _wave.value),
          child: Center(
            child: Text(
              '${(widget.progress * 100).round()}%',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  _LiquidPainter(this.progress, this.phase);
  final double progress;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;

    // Glass ring
    canvas.drawCircle(
      center,
      r - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.14),
    );

    // Liquid clipped to inner circle
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: r - 8)));

    final level = size.height * (1 - progress.clamp(0.0, 1.0));
    final path = Path()..moveTo(0, level);
    for (double x = 0; x <= size.width; x += 4) {
      path.lineTo(
        x,
        level +
            math.sin((x / size.width * 2 * math.pi) + phase * 2 * math.pi) * 6 +
            math.sin((x / size.width * 4 * math.pi) - phase * 2 * math.pi) * 3,
      );
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = AppColors.aurora.createShader(Offset.zero & size)
        ..color = Colors.white.withOpacity(0.9),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiquidPainter old) =>
      old.progress != progress || old.phase != phase;
}
