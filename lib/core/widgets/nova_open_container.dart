import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// A card that opens into a full screen. Normally the card grows into the
/// page (container transform); with reduced motion nothing moves — the page
/// simply fades in, as the Reduce motion setting promises.
class NovaOpenContainer extends StatelessWidget {
  const NovaOpenContainer({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.onClosed,
    this.radius = 22,
  });

  final Widget Function(BuildContext context, VoidCallback open) closedBuilder;
  final WidgetBuilder openBuilder;
  final VoidCallback? onClosed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: c.border),
    );
    if (NovaMotion.reduced(context)) {
      return Material(
        color: c.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        // Follow theme changes exactly, as NovaCard does.
        animationDuration: Duration.zero,
        child: Builder(
          builder: (context) => closedBuilder(context, () async {
            await Navigator.of(context)
                .push(NovaRoute<void>(page: openBuilder(context)));
            onClosed?.call();
          }),
        ),
      );
    }
    return OpenContainer(
      transitionType: ContainerTransitionType.fadeThrough,
      transitionDuration: NovaMotion.container,
      closedElevation: 0,
      openElevation: 0,
      closedColor: c.surface,
      openColor: c.canvas,
      middleColor: c.canvas,
      closedShape: shape,
      onClosed: (_) => onClosed?.call(),
      openBuilder: (context, _) => openBuilder(context),
      closedBuilder: closedBuilder,
    );
  }
}
