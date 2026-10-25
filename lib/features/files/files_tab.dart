import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../core/widgets/nova_mark.dart';
import '../../services/storage_service.dart';
import '../home/tools.dart';
import 'file_row.dart';
import 'folder_screen.dart';

/// A group of recent outputs made by the same tool.
class FileFolder {
  FileFolder(this.title, this.tool, this.items);
  final String title;
  final Tool? tool;
  final List<Map<String, dynamic>> items;
}

/// Groups recents by the tool that produced them. Folders are exact (one
/// per tool actually used) — no guessed categories.
List<FileFolder> groupByTool(List<Map<String, dynamic>> recents) {
  final map = <String, List<Map<String, dynamic>>>{};
  for (final r in recents) {
    map.putIfAbsent(r['tool'] as String? ?? 'Other', () => []).add(r);
  }
  Tool? lookup(String name) {
    for (final t in allTools) {
      if (t.title == name) return t;
    }
    // Notes saves its recents as "Notes"; the tool is "Quick Notes".
    if (name == 'Notes') return allTools.firstWhere((t) => t.id == ToolId.notes);
    return null;
  }

  return [for (final e in map.entries) FileFolder(e.key, lookup(e.key), e.value)];
}

class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.onBrowseTools});
  final VoidCallback onBrowseTools;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  bool _folders = true;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final recents = StorageService.instance.recents;
    final folders = groupByTool(recents);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Files', style: t.displaySmall).enter(context),
                  const SizedBox(height: 6),
                  Text(
                    recents.isEmpty
                        ? 'What you create shows up here.'
                        : '${recents.length} recent ${recents.length == 1 ? 'file' : 'files'}, stored on this phone.',
                    style: t.bodyMedium,
                  ).enter(context, delayMs: 60),
                ],
              ),
            ),
          ),
          if (recents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(onBrowseTools: widget.onBrowseTools),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              sliver: SliverToBoxAdapter(
                child: NovaSegmented<bool>(
                  value: _folders,
                  onChanged: (v) => setState(() => _folders = v),
                  options: const [
                    (true, 'By tool', Icons.folder_outlined),
                    (false, 'All files', Icons.list_rounded),
                  ],
                ).enter(context, delayMs: 100),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: PageTransitionSwitcher(
                  duration: NovaMotion.page,
                  reverse: !_folders,
                  transitionBuilder: (child, a, b) => SharedAxisTransition(
                    animation: a,
                    secondaryAnimation: b,
                    transitionType: SharedAxisTransitionType.horizontal,
                    fillColor: Colors.transparent,
                    child: child,
                  ),
                  child: _folders
                      ? _FolderGrid(
                          key: const ValueKey('folders'),
                          folders: folders,
                          onChanged: () => setState(() {}))
                      : Column(
                          key: const ValueKey('list'),
                          children: [
                            for (final (i, r) in recents.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: FileRow(
                                  item: r,
                                  onChanged: () => setState(() {}),
                                ).enter(context, index: i),
                              ),
                          ],
                        ),
                ),
              ),
            ),
            SliverToBoxAdapter(
                child: SizedBox(
                    height: 32 + MediaQuery.paddingOf(context).bottom)),
          ],
        ],
      ),
    );
  }
}

class _FolderGrid extends StatelessWidget {
  const _FolderGrid({super.key, required this.folders, required this.onChanged});
  final List<FileFolder> folders;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final extent = 92 + 44 * MediaQuery.textScalerOf(context).scale(1);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: folders.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: extent,
      ),
      itemBuilder: (context, i) {
        final f = folders[i];
        final (fg, bg) = f.tool == null
            ? (c.inkMid, c.surfaceAlt)
            : c.tint(sectionIndexOf(f.tool!));
        final icon = f.tool?.icon ?? Icons.folder_outlined;
        final latest =
            timeAgo(DateTime.tryParse(f.items.first['time'] as String? ?? ''));
        return Pressable(
          child: OpenContainer(
            transitionType: ContainerTransitionType.fadeThrough,
            transitionDuration: NovaMotion.reduced(context)
                ? NovaMotion.quick
                : NovaMotion.container,
            closedElevation: 0,
            openElevation: 0,
            closedColor: c.surface,
            openColor: c.canvas,
            middleColor: c.canvas,
            closedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: c.border),
            ),
            onClosed: (_) => onChanged(),
            openBuilder: (_, __) => FolderScreen(
                title: f.title, icon: icon, fg: fg, bg: bg),
            closedBuilder: (context, open) => InkWell(
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      NovaIconTile(icon: icon, fg: fg, bg: bg, size: 40),
                      const Spacer(),
                      Text('${f.items.length}',
                          style: t.headlineSmall?.copyWith(color: c.inkMid)),
                    ]),
                    const Spacer(),
                    Text(f.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium),
                    const SizedBox(height: 2),
                    Text('Latest $latest',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ).enter(context, index: i);
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onBrowseTools});
  final VoidCallback onBrowseTools;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
                  image: AssetImage(c.art), fit: BoxFit.cover),
              border: Border.all(color: c.border),
            ),
            alignment: Alignment.center,
            child: const NovaMark(size: 48),
          ),
          const SizedBox(height: 22),
          Text('No files yet', style: t.headlineSmall),
          const SizedBox(height: 8),
          Text('Merge, convert or scan something — the result will wait for you here.',
              style: t.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 22),
          NovaButton.secondary(
            label: 'Browse tools',
            icon: Icons.grid_view_rounded,
            expanded: false,
            onPressed: onBrowseTools,
          ),
        ],
      ).enter(context),
    );
  }
}
