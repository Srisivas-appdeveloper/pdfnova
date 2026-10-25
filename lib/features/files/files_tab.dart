import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_dialog.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../core/widgets/nova_mark.dart';
import '../../services/file_service.dart';
import '../../services/storage_service.dart';
import '../home/tools.dart';
import 'file_row.dart';
import 'folder_screen.dart';

/// A group of recent outputs made by the same tool.
class FileFolder {
  FileFolder(this.title, this.tool, this.items);
  final String title;
  final Tool? tool;
  final List<OutputRecord> items;
}

/// Groups history by the tool that produced it. Folders are exact (one per
/// tool actually used) — no guessed categories.
List<FileFolder> groupByTool(List<OutputRecord> records) {
  final map = <String, List<OutputRecord>>{};
  for (final r in records) {
    map.putIfAbsent(r.tool, () => []).add(r);
  }
  return [
    for (final e in map.entries) FileFolder(e.key, toolNamed(e.key), e.value)
  ];
}

/// Tool for a history label. Notes saves its rows as "Notes"; the tool is
/// "Quick Notes".
Tool? toolNamed(String name) {
  for (final t in allTools) {
    if (t.title == name) return t;
  }
  if (name == 'Notes') return allTools.firstWhere((t) => t.id == ToolId.notes);
  return null;
}

enum FileSort { newest, oldest, name, size }

/// Pure filtering/sorting used by the Files tab (unit-tested).
List<OutputRecord> filterRecords(
  List<OutputRecord> all, {
  String query = '',
  FileKind? kind,
  FileSort sort = FileSort.newest,
}) {
  final q = query.trim().toLowerCase();
  final out = [
    for (final r in all)
      if ((q.isEmpty || r.name.toLowerCase().contains(q)) &&
          (kind == null || kindOf(r.path) == kind))
        r
  ];
  int bytes(OutputRecord r) => r.currentBytes ?? -1;
  out.sort(switch (sort) {
    FileSort.newest => (a, b) => b.time.compareTo(a.time),
    FileSort.oldest => (a, b) => a.time.compareTo(b.time),
    FileSort.name => (a, b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    FileSort.size => (a, b) => bytes(b).compareTo(bytes(a)),
  });
  return out;
}

class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.onBrowseTools});
  final VoidCallback onBrowseTools;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  bool _folders = true;
  final _query = TextEditingController();
  FileKind? _kind;
  FileSort _sort = FileSort.newest;
  final _selected = <String>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
        final paths = {for (final r in StorageService.instance.history) r.path};
        _selected.retainAll(paths);
      });

  void _toggle(String path) => setState(() {
        if (!_selected.remove(path)) _selected.add(path);
        if (_selected.isNotEmpty) _folders = false;
      });

  Future<void> _cleanUp(int missing) async {
    final n = await StorageService.instance.pruneMissing();
    _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Removed $n ${n == 1 ? 'entry' : 'entries'} for files that are no longer on this phone.')));
    }
  }

  void _pickSort() {
    showNovaSheet(
      context: context,
      builder: (sheet) {
        final c = sheet.nova;
        final t = Theme.of(sheet).textTheme;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Sort by', style: t.headlineSmall)),
            ),
            for (final (s, label, icon) in const [
              (FileSort.newest, 'Newest first', Icons.south_rounded),
              (FileSort.oldest, 'Oldest first', Icons.north_rounded),
              (FileSort.name, 'Name', Icons.sort_by_alpha_rounded),
              (FileSort.size, 'Largest first', Icons.data_usage_rounded),
            ])
              ListTile(
                minTileHeight: 52,
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: Icon(icon, color: s == _sort ? c.accent : c.inkMid),
                title: Text(label,
                    style: t.titleMedium
                        ?.copyWith(color: s == _sort ? c.accent : c.ink)),
                trailing: s == _sort
                    ? Icon(Icons.check_rounded, color: c.accent)
                    : null,
                onTap: () {
                  Navigator.pop(sheet);
                  setState(() => _sort = s);
                },
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.nova;
    final all = StorageService.instance.history;
    final folders = groupByTool(all);
    final missing = all.where((r) => !r.exists).length;
    final shown =
        filterRecords(all, query: _query.text, kind: _kind, sort: _sort);
    final selecting = _selected.isNotEmpty;

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Stack(children: [
        SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 28, 16, 20),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Files', style: t.displaySmall).enter(context),
                            const SizedBox(height: 6),
                            Text(
                              all.isEmpty
                                  ? 'What you create shows up here.'
                                  : '${all.length} ${all.length == 1 ? 'file' : 'files'} made with PDF Nova, stored on this phone.',
                              style: t.bodyMedium,
                            ).enter(context, delayMs: 60),
                          ],
                        ),
                      ),
                      if (missing > 0)
                        TextButton.icon(
                          onPressed: () => _cleanUp(missing),
                          icon: const Icon(Icons.cleaning_services_outlined,
                              size: 18),
                          label: Text('Clean up $missing'),
                        ),
                    ],
                  ),
                ),
              ),
              if (all.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(onBrowseTools: widget.onBrowseTools),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  sliver: SliverToBoxAdapter(
                    child: NovaSegmented<bool>(
                      value: _folders,
                      onChanged: (v) => setState(() {
                        _folders = v;
                        if (v) _selected.clear();
                      }),
                      options: const [
                        (true, 'By tool', Icons.folder_outlined),
                        (false, 'All files', Icons.list_rounded),
                      ],
                    ).enter(context, delayMs: 100),
                  ),
                ),
                if (!_folders)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                            child: NovaField(
                              controller: _query,
                              hint: 'Search by name',
                              icon: Icons.search_rounded,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 4),
                          NovaIconButton(
                            tooltip: 'Sort',
                            icon: Icons.swap_vert_rounded,
                            active: _sort != FileSort.newest,
                            onPressed: _pickSort,
                          ),
                        ]),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final (k, label) in const [
                                (null, 'All'),
                                (FileKind.pdf, 'PDF'),
                                (FileKind.word, 'Word'),
                                (FileKind.slides, 'Slides'),
                                (FileKind.image, 'Images'),
                                (FileKind.text, 'Text'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: NovaChip(
                                    label: label,
                                    selected: _kind == k,
                                    onTap: () => setState(() => _kind = k),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ]),
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
                              onChanged: _refresh)
                          : Column(
                              key: const ValueKey('list'),
                              children: [
                                if (shown.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 32),
                                    child: Column(children: [
                                      Icon(Icons.search_off_rounded,
                                          size: 36, color: c.inkLow),
                                      const SizedBox(height: 10),
                                      Text('No files match',
                                          style: t.titleMedium),
                                      const SizedBox(height: 4),
                                      Text('Try another name or filter.',
                                          style: t.bodyMedium),
                                    ]),
                                  ),
                                for (final (i, r) in shown.indexed)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: FileRow(
                                      record: r,
                                      onChanged: _refresh,
                                      selectionMode: selecting,
                                      selected: _selected.contains(r.path),
                                      onSelect: () => _toggle(r.path),
                                    ).enter(context, index: i),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                    child: SizedBox(
                        height: (selecting ? 100 : 32) +
                            MediaQuery.paddingOf(context).bottom)),
              ],
            ],
          ),
        ),
        // Selection bar slides up from the bottom while files are selected.
        AnimatedPositioned(
          duration: NovaMotion.medium,
          curve: NovaMotion.emphasized,
          left: 16,
          right: 16,
          bottom: selecting ? 16 : -96,
          child: _SelectionBar(
            count: _selected.length,
            onClear: () => setState(_selected.clear),
            onShare: () {
              final paths = [
                for (final r in all)
                  if (_selected.contains(r.path) && r.exists) r.path
              ];
              if (paths.isNotEmpty) FileService.instance.shareAll(paths);
            },
            onRemove: () async {
              await StorageService.instance.removeRecents({..._selected});
              setState(_selected.clear);
            },
            onDelete: () => confirmDeleteOutputs(
                context,
                [
                  for (final r in all)
                    if (_selected.contains(r.path)) r
                ],
                () => setState(_selected.clear)),
          ),
        ),
      ]),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onClear,
    required this.onShare,
    required this.onRemove,
    required this.onDelete,
  });
  final int count;
  final VoidCallback onClear, onShare, onRemove, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: IconTheme(
        data: IconThemeData(color: c.canvas),
        child: Row(children: [
          IconButton(
              tooltip: 'Clear selection',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded)),
          Expanded(
            child: Text('$count selected',
                style: t.titleMedium?.copyWith(color: c.canvas)),
          ),
          IconButton(
              tooltip: 'Share',
              onPressed: onShare,
              icon: const Icon(Icons.ios_share_rounded)),
          IconButton(
              tooltip: 'Remove from history',
              onPressed: onRemove,
              icon: const Icon(Icons.playlist_remove_rounded)),
          IconButton(
              tooltip: 'Delete files',
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
        ]),
      ),
    );
  }
}

class _FolderGrid extends StatelessWidget {
  const _FolderGrid(
      {super.key, required this.folders, required this.onChanged});
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
        final latest = timeAgo(f.items.first.time);
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
            openBuilder: (_, __) =>
                FolderScreen(title: f.title, icon: icon, fg: fg, bg: bg),
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
              image:
                  DecorationImage(image: AssetImage(c.art), fit: BoxFit.cover),
              border: Border.all(color: c.border),
            ),
            alignment: Alignment.center,
            child: const NovaMark(size: 48),
          ),
          const SizedBox(height: 22),
          Text('No files yet', style: t.headlineSmall),
          const SizedBox(height: 8),
          Text(
              'Merge, convert or scan something — the result will wait for you here.',
              style: t.bodyMedium,
              textAlign: TextAlign.center),
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
