import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/routes/crack_reveal_route.dart';
import '../../core/routes/slide_up_route.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_open.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/gradient_background.dart';
// ADS DISABLED FOR RELEASE — re-enable: uncomment below + the strip at the bottom of the home Column
// import '../../core/widgets/ad_banner.dart';
import '../../services/file_service.dart';
import '../../services/storage_service.dart';
import '../batch/batch_screen.dart';
import '../formfill/formfill_screen.dart';
import '../../services/shortcut_service.dart';
import '../notes/notes_screen.dart';
import '../organize/organize_screen.dart';
import '../scan/scan_screen.dart';
import '../signature/signature_screen.dart';
import '../tool/tool_screen.dart';
import '../vault/vault_screen.dart';
import '../viewer/viewer_screen.dart';
import '../wifishare/wifishare_screen.dart';
import 'folder_screen.dart';
import 'tools.dart';
import 'widgets/tool_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    ShortcutService.instance.listenToolLaunch((toolIdName) {
      if (mounted) _openToolByName(toolIdName);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkShortcutLaunch();
    });
  }

  Future<void> _checkShortcutLaunch() async {
    final toolIdName = await ShortcutService.instance.getInitialShortcut();
    if (toolIdName != null && mounted) {
      _openToolByName(toolIdName);
    }
  }

  void _openToolByName(String toolIdName) {
    final matchingTool = allTools.firstWhere(
      (t) => t.id.name.toLowerCase() == toolIdName.toLowerCase(),
      orElse: () => allTools.first,
    );
    _openTool(
      matchingTool,
      Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      ),
    );
  }

  Widget _screenFor(Tool tool) => switch (tool.id) {
        ToolId.organize => OrganizeScreen(tool: tool),
        ToolId.sign => SignatureScreen(tool: tool),
        ToolId.formFill => FormFillScreen(tool: tool),
        ToolId.notes => NotesScreen(tool: tool),
        ToolId.scan => ScanScreen(tool: tool),
        ToolId.viewer => ViewerScreen(tool: tool),
        ToolId.vault => VaultScreen(tool: tool),
        ToolId.wifiShare => WifiShareScreen(tool: tool),
        ToolId.batch => BatchScreen(tool: tool),
        _ => ToolScreen(tool: tool),
      };

  void _openTool(Tool tool, Offset origin) {
    Navigator.of(context)
        .push(CrackRevealRoute(page: _screenFor(tool), origin: origin))
        .then((_) => setState(() {})); // refresh recents on return
  }

  @override
  Widget build(BuildContext context) {
    final recents = StorageService.instance.recents;
    var cardIndex = 0;
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (r) =>
                                  AppColors.aurora.createShader(r),
                              child: Text('PDF Nova',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(color: Colors.white)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Every tool runs on your phone. Nothing is uploaded.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        )
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.15, curve: Curves.easeOutCubic),
                      ),
                    ),
                    for (final section in toolSections) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                        sliver: SliverToBoxAdapter(
                          child: Text(section.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: AppColors.textMid)),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 1.18,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final visible = [
                                for (final t in section.tools)
                                  if (!t.androidOnly || Platform.isAndroid) t
                              ];
                              final tool = visible[i];
                              final delay = (40 * (cardIndex++ % 8)).ms;
                              return ToolCard(
                                tool: tool,
                                onOpen: (origin) => _openTool(tool, origin),
                              )
                                  .animate(delay: delay)
                                  .fadeIn(duration: 320.ms)
                                  .slideY(
                                      begin: 0.18,
                                      curve: Curves.easeOutCubic);
                            },
                            childCount: [
                              for (final t in section.tools)
                                if (!t.androidOnly || Platform.isAndroid) t
                            ].length,
                          ),
                        ),
                      ),
                    ],
                    if (recents.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                        sliver: SliverToBoxAdapter(
                            child: _RecentRail(recents: recents)),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
              // Reserved-height glass strip: content never jumps, ad
              // fades in when (and only if) it fills.
              // ADS DISABLED FOR RELEASE — re-enable: uncomment the line below.
              // const AdBannerStrip(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentFolder {
  final String categoryName;
  final IconData icon;
  final LinearGradient gradient;
  final List<Map<String, dynamic>> items;

  _RecentFolder({
    required this.categoryName,
    required this.icon,
    required this.gradient,
    required this.items,
  });
}

class _RecentRail extends StatefulWidget {
  const _RecentRail({required this.recents});
  final List<Map<String, dynamic>> recents;

  @override
  State<_RecentRail> createState() => _RecentRailState();
}

class _RecentRailState extends State<_RecentRail> {
  bool _showFolderView = true;

  List<_RecentFolder> get _folders {
    final Map<String, List<Map<String, dynamic>>> map = {};

    for (final item in widget.recents) {
      final tool = (item['tool'] as String? ?? '').toLowerCase();
      final path = (item['path'] as String? ?? '').toLowerCase();

      String category = 'Other Converted';
      if (tool.contains('word') || path.endsWith('.docx') || path.endsWith('.doc')) {
        category = 'PDF to Word';
      } else if (tool.contains('excel') || path.endsWith('.xlsx') || path.endsWith('.xls')) {
        category = 'PDF to Excel';
      } else if (tool.contains('powerpoint') || tool.contains('ppt') || path.endsWith('.pptx') || path.endsWith('.ppt')) {
        category = 'PDF to PowerPoint';
      } else if (tool.contains('image') || path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg')) {
        category = 'PDF to Image / Image to PDF';
      } else if (tool.contains('compress')) {
        category = 'Compress PDF';
      } else if (tool.contains('split')) {
        category = 'Split PDF';
      } else if (tool.contains('merge')) {
        category = 'Merge PDF';
      } else if (tool.contains('organize') || tool.contains('page')) {
        category = 'Organize Pages';
      } else if (tool.contains('note') || path.contains('note')) {
        category = 'Notes';
      } else if (tool.contains('batch')) {
        category = 'Batch Converted';
      }

      map.putIfAbsent(category, () => []).add(item);
    }

    final List<_RecentFolder> folders = [];
    map.forEach((cat, items) {
      IconData icon = Icons.folder_copy_rounded;
      LinearGradient grad = AppColors.aurora;

      if (cat == 'PDF to Word') {
        icon = Icons.description_rounded;
        grad = const LinearGradient(colors: [Color(0xFF2B579A), Color(0xFF4B89DC)]);
      } else if (cat == 'PDF to Excel') {
        icon = Icons.table_chart_rounded;
        grad = const LinearGradient(colors: [Color(0xFF1D6F42), Color(0xFF21A366)]);
      } else if (cat == 'PDF to PowerPoint') {
        icon = Icons.slideshow_rounded;
        grad = const LinearGradient(colors: [Color(0xFFD24726), Color(0xFFF26522)]);
      } else if (cat == 'PDF to Image / Image to PDF') {
        icon = Icons.collections_rounded;
        grad = const LinearGradient(colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)]);
      } else if (cat == 'Notes') {
        icon = Icons.note_alt_rounded;
        grad = const LinearGradient(colors: [Color(0xFF7C5CFF), Color(0xFFE85CB8)]);
      } else if (cat == 'Compress PDF') {
        icon = Icons.compress_rounded;
        grad = const LinearGradient(colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)]);
      } else if (cat == 'Split PDF') {
        icon = Icons.call_split_rounded;
        grad = const LinearGradient(colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)]);
      } else if (cat == 'Merge PDF') {
        icon = Icons.merge_type_rounded;
        grad = const LinearGradient(colors: [Color(0xFFF7971E), Color(0xFFFFD200)]);
      } else if (cat == 'Organize Pages') {
        icon = Icons.dashboard_customize_rounded;
        grad = const LinearGradient(colors: [Color(0xFF11998E), Color(0xFF38EF7D)]);
      }

      folders.add(_RecentFolder(
        categoryName: cat,
        icon: icon,
        gradient: grad,
        items: items,
      ));
    });

    return folders;
  }

  void _openFolderDetails(_RecentFolder folder) {
    Navigator.of(context).push(
      SlideUpRoute(
        page: FolderScreen(
          categoryName: folder.categoryName,
          icon: folder.icon,
          gradient: folder.gradient,
          items: folder.items,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final folders = _folders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Converted',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.textMid)),
            Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showFolderView = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _showFolderView ? AppColors.cyan.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _showFolderView ? AppColors.cyan : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder_rounded,
                            size: 14,
                            color: _showFolderView ? AppColors.cyan : AppColors.textMid),
                        const SizedBox(width: 4),
                        Text('Folders',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _showFolderView ? AppColors.cyan : AppColors.textMid,
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _showFolderView = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: !_showFolderView ? AppColors.cyan.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !_showFolderView ? AppColors.cyan : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.list_alt_rounded,
                            size: 14,
                            color: !_showFolderView ? AppColors.cyan : AppColors.textMid),
                        const SizedBox(width: 4),
                        Text('All Files',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: !_showFolderView ? AppColors.cyan : AppColors.textMid,
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_showFolderView)
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: folders.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final folder = folders[i];
                return GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  radius: 18,
                  onTap: () => _openFolderDetails(folder),
                  child: SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                gradient: folder.gradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(folder.icon, color: Colors.white, size: 18),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${folder.items.length} files',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(folder.categoryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        const SizedBox(height: 2),
                        Text('Tap to open folder',
                            style: TextStyle(color: AppColors.textMid, fontSize: 10)),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        else
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.recents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final r = widget.recents[i];
                final name = (r['path'] as String).split('/').last;
                final exists = File(r['path'] as String).existsSync();
                return GlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  radius: 18,
                   onTap: exists
                       ? () => openAnyFile(context, r['path'] as String)
                       : null,
                  child: SizedBox(
                    width: 170,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(r['tool'] as String,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    fontSize: 12, color: AppColors.cyan)),
                        const SizedBox(height: 4),
                        Text(name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
