import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// Small uppercase section label ("ORGANIZE").
class NovaEyebrow extends StatelessWidget {
  const NovaEyebrow(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const Spacer(),
        if (trailing != null) trailing!,
      ]);
}

/// Tinted rounded square holding an icon — the visual anchor of tool
/// cards and file rows.
class NovaIconTile extends StatelessWidget {
  const NovaIconTile({
    super.key,
    required this.icon,
    this.fg,
    this.bg,
    this.size = 44,
  });

  final IconData icon;
  final Color? fg;
  final Color? bg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? c.accentSoft,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: fg ?? c.accent, size: size * 0.5),
    );
  }
}

/// Segmented control with a thumb that slides between options.
class NovaSegmented<T> extends StatelessWidget {
  const NovaSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String, IconData?)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final index = options.indexWhere((o) => o.$1 == value);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(15),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / options.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: NovaMotion.medium,
            curve: NovaMotion.emphasized,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: c.border),
                boxShadow: [
                  BoxShadow(
                      color: c.shadow,
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
            ),
          ),
          Row(children: [
            for (final (i, o) in options.indexed)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (o.$1 == value) return;
                    HapticFeedback.selectionClick();
                    onChanged(o.$1);
                  },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: NovaMotion.quick,
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                            color: i == index ? c.ink : c.inkLow,
                            fontWeight:
                                i == index ? FontWeight.w600 : FontWeight.w500,
                          ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (o.$3 != null) ...[
                          Icon(o.$3,
                              size: 16, color: i == index ? c.ink : c.inkLow),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(o.$2,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// Text input on a sunken surface. The border fades to the accent while
/// focused, so the active field is obvious without any glow.
class NovaField extends StatefulWidget {
  const NovaField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.number = false,
    this.obscure = false,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.textStyle,
    this.icon,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final bool autofocus;
  final String hint;
  final String? label;
  final bool number;
  final bool obscure;
  final int? maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final TextStyle? textStyle;
  final IconData? icon;

  @override
  State<NovaField> createState() => _NovaFieldState();
}

class _NovaFieldState extends State<NovaField> {
  final _focus = FocusNode();
  bool _hide = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: t.labelMedium),
          const SizedBox(height: 8),
        ],
        AnimatedContainer(
          duration: NovaMotion.quick,
          padding: EdgeInsets.symmetric(
              horizontal: 16, vertical: widget.maxLines == 1 ? 2 : 12),
          decoration: BoxDecoration(
            color: focused ? c.surface : c.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: focused ? c.accent : Colors.transparent, width: 1.4),
          ),
          child: Row(children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 19, color: focused ? c.accent : c.inkLow),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                obscureText: widget.obscure && _hide,
                maxLines: widget.obscure ? 1 : widget.maxLines,
                minLines: widget.minLines,
                keyboardType: widget.number
                    ? TextInputType.number
                    : (widget.maxLines == 1
                        ? TextInputType.text
                        : TextInputType.multiline),
                inputFormatters: widget.number
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                onChanged: widget.onChanged,
                style: widget.textStyle ?? t.bodyLarge,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  border: InputBorder.none,
                  isDense: widget.maxLines != 1,
                  contentPadding: widget.maxLines == 1
                      ? const EdgeInsets.symmetric(vertical: 14)
                      : EdgeInsets.zero,
                ),
              ),
            ),
            if (widget.obscure)
              GestureDetector(
                onTap: () => setState(() => _hide = !_hide),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    _hide
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19,
                    color: c.inkLow,
                  ),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Selectable pill. Selected chips invert (ink fill, canvas text).
class NovaChip extends StatelessWidget {
  const NovaChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final fg = selected ? c.canvas : c.inkMid;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: NovaMotion.quick,
        // 44pt minimum touch target (Apple HIG); keeps chips tappable.
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? c.ink : c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        // widthFactor 1: centre vertically in the 44pt height but keep the
        // chip as wide as its label (a plain `alignment` made chips stretch
        // to full width inside a Wrap).
        child: Align(
          widthFactor: 1,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

/// Circular icon button on a surface — used for app-bar actions.
class NovaIconButton extends StatelessWidget {
  const NovaIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: active ? c.accentSoft : c.surface,
          foregroundColor: active ? c.accent : c.ink,
          side: BorderSide(color: active ? Colors.transparent : c.border),
          fixedSize: const Size(44, 44),
        ),
        icon: AnimatedSwitcher(
          duration: NovaMotion.quick,
          transitionBuilder: (child, a) => ScaleTransition(
              scale: a, child: FadeTransition(opacity: a, child: child)),
          child: Icon(icon, key: ValueKey(icon), size: 20),
        ),
      ),
    );
  }
}
