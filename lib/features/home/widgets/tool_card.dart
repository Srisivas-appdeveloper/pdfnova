import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/nova_button.dart';
import '../../../core/widgets/nova_card.dart';
import '../../../core/widgets/nova_open_container.dart';
import '../../../core/widgets/nova_controls.dart';
import '../../../core/widgets/nova_dialog.dart';
import '../../../services/shortcut_service.dart';
import '../tool_router.dart';
import '../tools.dart';

/// Tool tile. Tapping it *becomes* the tool: a container transform grows
/// the card into the full screen (and shrinks back into it on close), so
/// you always see where you came from. Long-press (Android) offers to pin
/// the tool to the phone's home screen.
class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.tool, this.onClosed});
  final Tool tool;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final (fg, bg) = c.tint(sectionIndexOf(tool));
    return Pressable(
      child: NovaOpenContainer(
        onClosed: onClosed,
        openBuilder: (_) => screenFor(tool),
        closedBuilder: (context, open) => InkWell(
          onTap: () {
            // Drop search focus first, or closing the tool would hand focus
            // back to the search field and pop the keyboard up again.
            FocusManager.instance.primaryFocus?.unfocus();
            open();
          },
          onLongPress:
              Platform.isAndroid ? () => _offerPin(context, fg, bg) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NovaIconTile(icon: tool.icon, fg: fg, bg: bg),
                    const Spacer(),
                    Icon(Icons.north_east_rounded, size: 16, color: c.inkLow),
                  ],
                ),
                const Spacer(),
                Text(tool.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  tool.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
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

  void _offerPin(BuildContext context, Color fg, Color bg) {
    HapticFeedback.mediumImpact();
    final isNotes = tool.id == ToolId.notes;
    showNovaDialog(
      context: context,
      builder: (dialogContext) {
        final t = Theme.of(dialogContext).textTheme;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NovaIconTile(icon: tool.icon, fg: fg, bg: bg, size: 52),
                const SizedBox(height: 18),
                Text('Add to Home Screen', style: t.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  isNotes
                      ? 'Place the Quick Note widget on your Home Screen. It shows your note there — tap it any time to write or edit.'
                      : 'Put a one-tap shortcut to ${tool.title} on your Home Screen.',
                  style: t.bodyMedium,
                ),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                    child: NovaButton.secondary(
                      label: 'Cancel',
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NovaButton(
                      label: isNotes ? 'Add widget' : 'Add',
                      icon: Icons.add_to_home_screen_rounded,
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        final ok = await ShortcutService.instance
                            .pinShortcut(tool.id.name, tool.title);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Tap "Add" on the prompt to place it on your Home Screen.'
                              : 'Your launcher does not support pinning shortcuts.'),
                        ));
                      },
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
