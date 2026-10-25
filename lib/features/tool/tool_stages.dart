import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import 'processing_view.dart';
import 'success_view.dart';
import 'tool_bloc.dart';

/// Input → processing → success for custom-flow tools, with the same
/// fade-through the generic ToolScreen uses. Progress ticks update the
/// processing view in place (same key), so only stage changes animate.
class ToolStages extends StatelessWidget {
  const ToolStages({
    super.key,
    required this.state,
    required this.processingLabel,
    required this.input,
  });

  final ToolState state;
  final String processingLabel;
  final Widget input;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    return PopScope(
      // Block back mid-write so work never runs headless.
      canPop: state is! ToolProcessing,
      child: PageTransitionSwitcher(
        duration:
            NovaMotion.reduced(context) ? NovaMotion.quick : NovaMotion.page,
        transitionBuilder: (child, a, b) => FadeThroughTransition(
          animation: a,
          secondaryAnimation: b,
          fillColor: c.canvas,
          child: child,
        ),
        child: switch (state) {
          ToolProcessing s => ProcessingView(
              key: const ValueKey('processing'),
              progress: s.progress,
              label: processingLabel),
          ToolSuccess s => SuccessView(
              key: const ValueKey('success'), paths: s.paths, notes: s.notes),
          _ => KeyedSubtree(key: const ValueKey('input'), child: input),
        },
      ),
    );
  }
}

/// Primary action pinned to the bottom of a tool screen, above the
/// navigation bar, with a hairline separating it from scrolling content.
class ToolActionBar extends StatelessWidget {
  const ToolActionBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: c.canvas,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: child,
    );
  }
}
