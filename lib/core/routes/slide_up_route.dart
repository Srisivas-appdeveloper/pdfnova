import 'package:flutter/material.dart';

/// Screen entry "from down to up, neatly": the new page glides up on a
/// long settled curve while the page behind recedes and dims — real depth,
/// no hard cuts. 420ms easeOutQuint feels expensive without feeling slow.
class SlideUpRoute<T> extends PageRouteBuilder<T> {
  SlideUpRoute({required Widget page})
      : super(
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          opaque: false,
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutQuint,
                reverseCurve: Curves.easeInCubic);
            final recede = CurvedAnimation(
                parent: secondary, curve: Curves.easeOutCubic);
            return AnimatedBuilder(
              animation: recede,
              builder: (_, c) => Transform.scale(
                scale: 1.0 - recede.value * 0.04,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(recede.value * 0.35),
                      BlendMode.darken),
                  child: c,
                ),
              ),
              child: SlideTransition(
                position:
                    Tween(begin: const Offset(0, 0.12), end: Offset.zero)
                        .animate(curved),
                child: FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.97, end: 1.0).animate(curved),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
}
