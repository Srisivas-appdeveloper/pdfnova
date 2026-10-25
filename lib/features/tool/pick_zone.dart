import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';

/// Large dashed drop zone — the "paper" you put a document on. The icon
/// flips to a green check once something is picked.
class PickZone extends StatelessWidget {
  const PickZone({
    super.key,
    required this.title,
    required this.hint,
    required this.onTap,
    this.done = false,
    this.icon = Icons.add_rounded,
  });

  final String title;
  final String hint;
  final VoidCallback? onTap;
  final bool done;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Pressable(
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _DashedBorder(color: c.borderStrong, radius: 22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(children: [
              AnimatedSwitcher(
                duration: NovaMotion.medium,
                transitionBuilder: (child, a) => ScaleTransition(
                    scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                    child: child),
                child: done
                    ? NovaIconTile(
                        key: const ValueKey('done'),
                        icon: Icons.check_rounded,
                        fg: c.success,
                        bg: c.successSoft,
                        size: 52)
                    : NovaIconTile(
                        key: const ValueKey('add'), icon: icon, size: 52),
              ),
              const SizedBox(height: 14),
              Text(title, style: t.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(hint, style: t.bodySmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.75), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final m in (Path()..addRRect(rrect)).computeMetrics()) {
      for (double d = 0; d < m.length; d += 11) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
