import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../services/storage_service.dart';
import 'file_row.dart';

/// Every recent output made by one tool. Reads recents live so deletes
/// and removals show immediately.
class FolderScreen extends StatefulWidget {
  const FolderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  final String title;
  final IconData icon;
  final Color fg;
  final Color bg;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = StorageService.instance.recents
        .where((r) => r['tool'] == widget.title)
        .toList();
    return Scaffold(
      backgroundColor: context.nova.canvas,
      appBar: AppBar(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, 32 + MediaQuery.paddingOf(context).bottom),
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 22),
            child: Row(children: [
              NovaIconTile(
                  icon: widget.icon, fg: widget.fg, bg: widget.bg, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.headlineMedium),
                    Text(
                        '${items.length} ${items.length == 1 ? 'file' : 'files'}',
                        style: t.bodyMedium),
                  ],
                ),
              ),
            ]).enter(context),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text('This folder is empty.',
                  textAlign: TextAlign.center, style: t.bodyMedium),
            ),
          for (final (i, r) in items.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FileRow(item: r, onChanged: () => setState(() {}))
                  .enter(context, index: i, delayMs: 80),
            ),
        ],
      ),
    );
  }
}
