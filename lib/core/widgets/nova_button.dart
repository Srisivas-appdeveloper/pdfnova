import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

enum NovaButtonStyle { primary, secondary, quiet }

/// The one button. Primary is solid accent; secondary is a bordered
/// surface; quiet is text-only. 54px tall, 16px radius, spring press,
/// and an animated fade when it becomes enabled.
class NovaButton extends StatefulWidget {
  const NovaButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = true,
    this.style = NovaButtonStyle.primary,
    this.color,
  });

  const NovaButton.secondary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = true,
    this.color,
  }) : style = NovaButtonStyle.secondary;

  const NovaButton.quiet({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = false,
    this.color,
  }) : style = NovaButtonStyle.quiet;

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;
  final NovaButtonStyle style;

  /// Overrides the fill (primary) or text colour (secondary/quiet),
  /// e.g. danger for destructive actions.
  final Color? color;

  @override
  State<NovaButton> createState() => _NovaButtonState();
}

class _NovaButtonState extends State<NovaButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final enabled = widget.onPressed != null;
    final reduced = NovaMotion.reduced(context);

    final (Color bg, Color fg, Color? border) = switch (widget.style) {
      NovaButtonStyle.primary => (
          widget.color ?? c.accent,
          widget.color == null ? c.onAccent : Colors.white,
          null
        ),
      NovaButtonStyle.secondary => (c.surface, widget.color ?? c.ink, c.border),
      NovaButtonStyle.quiet => (
          Colors.transparent,
          widget.color ?? c.accent,
          null
        ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down && !reduced ? 0.97 : 1,
          duration: _down ? NovaMotion.quick : NovaMotion.medium,
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: AnimatedOpacity(
            duration: NovaMotion.medium,
            opacity: enabled ? 1 : 0.38,
            child: AnimatedContainer(
              duration: NovaMotion.quick,
              width: widget.expanded ? double.infinity : null,
              height: widget.style == NovaButtonStyle.quiet ? 44 : 54,
              padding: EdgeInsets.symmetric(
                  horizontal:
                      widget.style == NovaButtonStyle.quiet ? 12 : 22),
              decoration: BoxDecoration(
                color: _down && widget.style != NovaButtonStyle.primary
                    ? c.surfaceAlt
                    : bg,
                borderRadius: BorderRadius.circular(16),
                border: border == null ? null : Border.all(color: border),
              ),
              child: Row(
                mainAxisSize:
                    widget.expanded ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 19, color: fg),
                    const SizedBox(width: 9),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
