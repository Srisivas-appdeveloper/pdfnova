import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// Dialog that rises and scales up from 92% while the scrim fades in;
/// on dismiss it sinks back quicker than it arrived.
Future<T?> showNovaDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final reduced = NovaMotion.reduced(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: context.nova.scrim,
    transitionDuration: reduced ? NovaMotion.quick : NovaMotion.medium,
    pageBuilder: (context, _, __) => builder(context),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(
          parent: anim,
          curve: NovaMotion.emphasized,
          reverseCurve: NovaMotion.accelerate);
      if (reduced) return FadeTransition(opacity: curved, child: child);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(curved),
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Bottom sheet on the house curve: glides up with a long settle.
Future<T?> showNovaSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool scrollControlled = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: scrollControlled,
      useSafeArea: true,
      sheetAnimationStyle: NovaMotion.reduced(context)
          ? const AnimationStyle(duration: NovaMotion.quick)
          : const AnimationStyle(
              duration: NovaMotion.page,
              reverseDuration: NovaMotion.medium,
              curve: NovaMotion.emphasized,
              reverseCurve: NovaMotion.accelerate,
            ),
      builder: builder,
    );
