import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// Solid surface with a hairline border — the basic building block of the
/// Folio language. [sunken] uses the recessed tone (fields, tracks).
/// With [onTap] it becomes pressable: a gentle press-in and a ripple.
class NovaCard extends StatelessWidget {
  const NovaCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.onLongPress,
    this.sunken = false,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool sunken;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
          color: borderColor ?? (sunken ? Colors.transparent : c.border)),
    );
    final surface = Material(
      color: color ?? (sunken ? c.surfaceAlt : c.surface),
      shape: shape,
      // Material otherwise runs its own 200ms shape/colour animation, so on a
      // theme switch card borders lagged the app's cross-fade (white outlines
      // flashed on dark cards). Follow the theme animation exactly instead.
      animationDuration: Duration.zero,
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(padding: padding, child: child),
            ),
    );
    if (onTap == null) return surface;
    return Pressable(child: surface);
  }
}

/// Wraps any tappable widget with a spring press-in (scale 0.97) and a
/// selection haptic. It only listens to pointers — the child still handles
/// the actual tap — so it composes with InkWell, OpenContainer, etc.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = 0.97});
  final Widget child;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = NovaMotion.reduced(context);
    return Listener(
      onPointerDown: (_) {
        _set(true);
        HapticFeedback.selectionClick();
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1,
        duration: _down ? NovaMotion.quick : NovaMotion.medium,
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
