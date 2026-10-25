import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The PDF Nova mark: a page with a folded corner and a four-point star.
///
/// [progress] 0→1 animates it: the page outline draws itself on (0–0.65),
/// the fold tucks in (0.45–0.8) and the star blooms with a slight spin
/// (0.6–1). At 1 it is the static logo.
class NovaMark extends StatelessWidget {
  const NovaMark({super.key, this.size = 40, this.progress = 1, this.color});
  final double size;
  final double progress;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(progress, color ?? c.ink, c.accent),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t, this.ink, this.accent);
  final double t;
  final Color ink;
  final Color accent;

  double _seg(double a, double b) =>
      Curves.easeInOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.075;
    final fold = s * 0.26;
    final l = s * 0.16, r = s * 0.84, top = s * 0.08, bottom = s * 0.92;
    final radius = s * 0.09;

    // Page outline, starting just after the fold and running clockwise.
    final page = Path()
      ..moveTo(r, top + fold)
      ..lineTo(r, bottom - radius)
      ..quadraticBezierTo(r, bottom, r - radius, bottom)
      ..lineTo(l + radius, bottom)
      ..quadraticBezierTo(l, bottom, l, bottom - radius)
      ..lineTo(l, top + radius)
      ..quadraticBezierTo(l, top, l + radius, top)
      ..lineTo(r - fold, top)
      ..lineTo(r, top + fold);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;

    final draw = _seg(0, 0.65);
    for (final ui.PathMetric m in page.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * draw), paint);
    }

    // Fold: the inner crease of the dog-ear, drawn on after the outline.
    final f = _seg(0.45, 0.8);
    if (f > 0) {
      final corner = Path()
        ..moveTo(r - fold, top)
        ..lineTo(r - fold, top + fold - radius)
        ..quadraticBezierTo(r - fold, top + fold, r - fold + radius, top + fold)
        ..lineTo(r, top + fold);
      for (final ui.PathMetric m in corner.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * f), paint);
      }
    }

    // Star: four-point sparkle, bottom-left of centre.
    final st = _seg(0.6, 1.0);
    if (st > 0) {
      final cx = s * 0.43, cy = s * 0.6;
      final outer = s * 0.2 * Curves.easeOutBack.transform(st);
      final inner = outer * 0.28;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate((1 - st) * math.pi / 2);
      final star = Path();
      for (var i = 0; i < 8; i++) {
        final a = -math.pi / 2 + i * math.pi / 4;
        final rr = i.isEven ? outer : inner;
        final p = Offset(math.cos(a) * rr, math.sin(a) * rr);
        i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
      }
      star.close();
      canvas.drawPath(star, Paint()..color = accent);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.t != t || old.ink != ink || old.accent != accent;
}
