import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/shortcut_service.dart';
import '../tools.dart';

/// Grid tile v2: spring press-scale, aurora border-glow that blooms while
/// the finger is down, icon micro-tilt — the card visibly "charges up"
/// before the cracker fires. Reports the global tap position up so the
/// reveal bursts from exactly where the finger landed.
class ToolCard extends StatefulWidget {
  const ToolCard({super.key, required this.tool, required this.onOpen});
  final Tool tool;
  final void Function(Offset globalTapPosition) onOpen;

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _down = false;

  void _showAddWidgetDialog(BuildContext context) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161C2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF2A344E)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppColors.aurora,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.tool.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add to Home Screen',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(widget.tool.title,
                      style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        content: Text(
          widget.tool.id == ToolId.notes
              ? 'Place the Quick Note widget on your phone Home Screen. It shows your note right on the Home Screen — tap it anytime to write or edit.'
              : 'Would you like to place a 1-tap shortcut widget for "${widget.tool.title}" directly on your phone Home Screen?',
          style: TextStyle(color: AppColors.textMid, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.textLow)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await ShortcutService.instance.pinShortcut(
                widget.tool.id.name,
                widget.tool.title,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 3),
                    content: Text(
                      widget.tool.id == ToolId.notes
                          ? 'Tap "Add" on your phone prompt to place the Quick Note widget, then resize it as you like.'
                          : 'Requested widget for ${widget.tool.title}! Tap "Add" on your phone prompt to place on Home Screen.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
            label: const Text('Add Widget'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.violet,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onLongPress: () {
        setState(() => _down = false);
        _showAddWidgetDialog(context);
      },
      onTapUp: (details) {
        setState(() => _down = false);
        HapticFeedback.selectionClick();
        widget.onOpen(details.globalPosition);
      },
      child: AnimatedScale(
        scale: _down ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(1.2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: _down
                ? AppColors.aurora
                : LinearGradient(colors: [
                    AppColors.glassBorder,
                    AppColors.glassBorder,
                  ]),
            boxShadow: _down
                ? [
                    BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 6)),
                  ]
                : const [],
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              color: AppColors.ink.withValues(alpha: 0.55),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: _down ? 0.14 : 0.09),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedRotation(
                  turns: _down ? -0.015 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppColors.aurora,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.violet.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child:
                        Icon(widget.tool.icon, color: Colors.white, size: 22),
                  ),
                ),
                const Spacer(),
                Text(widget.tool.title,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  widget.tool.subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
