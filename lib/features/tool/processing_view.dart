import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_progress.dart';
// ADS DISABLED FOR RELEASE — the earlier banner slot lived below the label.
// Re-enable by adding a banner card under the privacy line when ads return.

/// Shown while the real work runs: a thin ring with a large serif
/// percentage, the task label, and a privacy reminder.
class ProcessingView extends StatelessWidget {
  const ProcessingView({super.key, required this.progress, required this.label});
  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    // NOTE: no entrance .animate() here — the bloc re-emits progress every
    // 90ms and flutter_animate would replay on each rebuild. The
    // AnimatedSwitcher in ToolScreen already handles the one-time entrance.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NovaProgress(progress: progress),
              const SizedBox(height: 32),
              Text(label, style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: c.success),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Processing on your phone — nothing leaves it.',
                      style: t.bodySmall, textAlign: TextAlign.center),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
