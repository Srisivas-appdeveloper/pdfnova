import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import 'nova_mark.dart';

/// Thin ring progress. With a measured [progress] it shows the arc and a
/// large serif percentage (easing toward each new value). With null — the
/// amount of work is unknown — it shows a slowly rotating arc around the
/// PDF Nova mark instead of inventing a number.
class NovaProgress extends StatefulWidget {
  const NovaProgress({super.key, required this.progress, this.size = 184});
  final double? progress;
  final double size;

  @override
  State<NovaProgress> createState() => _NovaProgressState();
}

class _NovaProgressState extends State<NovaProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: NovaMotion.ambient)..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final reduced = NovaMotion.reduced(context);
    if (widget.progress == null) {
      return SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _spin,
          builder: (context, child) => CustomPaint(
            painter: _SpinnerPainter(
                phase: reduced ? 0 : _spin.value,
                track: c.surfaceAlt,
                arc: c.accent),
            child: child,
          ),
          child: const Center(child: NovaMark(size: 56)),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.progress!.clamp(0.0, 1.0)),
      duration: NovaMotion.medium,
      curve: NovaMotion.emphasized,
      builder: (context, p, _) => SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _spin,
          builder: (context, child) => CustomPaint(
            painter: _RingPainter(
              progress: p,
              phase: reduced ? 0 : _spin.value,
              track: c.surfaceAlt,
              arc: c.accent,
              comet: !reduced && p < 1,
            ),
            child: child,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${(p * 100).round()}',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                Text('%',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: c.inkLow)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.phase,
    required this.track,
    required this.arc,
    required this.comet,
  });

  final double progress;
  final double phase;
  final Color track;
  final Color arc;
  final bool comet;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);

    const start = -math.pi / 2;
    final sweep = math.pi * 2 * progress;
    if (sweep > 0) {
      canvas.drawArc(rect, start, sweep, false, base..color = arc);
    }

    if (comet) {
      // A short gradient tail travelling around the remaining track.
      final remaining = math.pi * 2 - sweep;
      final head = start + sweep + remaining * phase;
      const tail = 0.7;
      final shader = SweepGradient(
        startAngle: 0,
        endAngle: tail,
        colors: [arc.withValues(alpha: 0), arc.withValues(alpha: 0.35)],
        transform: GradientRotation(head - tail),
      ).createShader(rect);
      canvas.drawArc(
          rect,
          head - tail,
          tail,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.phase != phase || old.arc != arc;
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(
      {required this.phase, required this.track, required this.arc});
  final double phase;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 2 * phase, math.pi * 0.55,
        false, paint..color = arc);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.phase != phase || old.arc != arc || old.track != track;
}
