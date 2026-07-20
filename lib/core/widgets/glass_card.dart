import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Frosted glass surface. Real BackdropFilter blur is expensive on budget
/// Android, so it is opt-in via [frosted]; hero surfaces use frosted:true,
/// everything else gets the cheap translucent fill which looks 90% as good.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.frosted = false,
    this.strong = false,
    this.radius = 24,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final bool frosted;
  final bool strong;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    Widget surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? AppColors.glassFillStrong : AppColors.glassFill,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.glassBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(strong ? 0.13 : 0.09),
            Colors.white.withOpacity(strong ? 0.06 : 0.03),
          ],
        ),
      ),
      child: child,
    );

    // Top sheen: a 1px light streak across the upper edge sells the glass.
    surface = Stack(children: [
      surface,
      Positioned(
        top: 0,
        left: radius,
        right: radius,
        child: IgnorePointer(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.white.withOpacity(0),
                Colors.white.withOpacity(0.35),
                Colors.white.withOpacity(0),
              ]),
            ),
          ),
        ),
      ),
    ]);

    if (frosted) {
      surface = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: surface,
        ),
      );
    } else {
      surface = ClipRRect(borderRadius: borderRadius, child: surface);
    }

    if (onTap == null) return surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: borderRadius, onTap: onTap, child: surface),
    );
  }
}
