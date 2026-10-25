import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../home/tools.dart';

/// Top of every tool screen: tinted icon, serif title, one-line purpose.
class ToolHeader extends StatelessWidget {
  const ToolHeader({super.key, required this.tool, this.subtitle});
  final Tool tool;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = context.nova.tint(sectionIndexOf(tool));
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NovaIconTile(icon: tool.icon, fg: fg, bg: bg, size: 52),
          const SizedBox(height: 16),
          Text(tool.title, style: t.headlineLarge),
          const SizedBox(height: 4),
          Text(subtitle ?? tool.subtitle, style: t.bodyMedium),
        ],
      ).enter(context, delayMs: 120),
    );
  }
}

/// Small inline note with an icon — for honest caveats under inputs.
class ToolNote extends StatelessWidget {
  const ToolNote(this.text, {super.key, this.icon = Icons.info_outline_rounded});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: c.inkLow),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
