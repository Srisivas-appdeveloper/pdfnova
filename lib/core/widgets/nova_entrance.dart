import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_motion.dart';

/// Staggered "rise into place" entrance used across screens. Items fade
/// in while sliding up a few pixels; [index] staggers siblings 40ms apart
/// (wrapping every 8 so long lists never wait). Skipped with reduced motion.
extension NovaEntrance on Widget {
  Widget enter(BuildContext context, {int index = 0, int delayMs = 0}) {
    if (NovaMotion.reduced(context)) return this;
    return animate(delay: (delayMs + 40 * (index % 8)).ms)
        .fadeIn(duration: NovaMotion.entranceFade, curve: Curves.easeOut)
        .slideY(
            begin: 0.08,
            end: 0,
            duration: NovaMotion.entrance,
            curve: NovaMotion.emphasized);
  }
}
