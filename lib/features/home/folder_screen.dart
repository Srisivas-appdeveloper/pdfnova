import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_open.dart';
import '../../core/widgets/gradient_background.dart';
import '../../services/file_service.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({
    super.key,
    required this.categoryName,
    required this.icon,
    required this.gradient,
    required this.items,
  });

  final String categoryName;
  final IconData icon;
  final LinearGradient gradient;
  final List<Map<String, dynamic>> items;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  late List<Map<String, dynamic>> _currentItems;

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.items);
  }

  void _deleteFile(int index, String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}

    setState(() {
      _currentItems.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File removed from folder')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.categoryName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Header Card with solid non-transparent background
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161C2E), // Solid dark surface
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A344E)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: widget.gradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(widget.icon, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.categoryName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_currentItems.length} Converted Files',
                              style: TextStyle(
                                color: AppColors.textMid,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // File List
              Expanded(
                child: _currentItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open_rounded,
                                size: 64, color: AppColors.textLow),
                            const SizedBox(height: 12),
                            Text(
                              'This folder is empty',
                              style: TextStyle(
                                  color: AppColors.textMid, fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _currentItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final item = _currentItems[i];
                          final pathStr = item['path'] as String;
                          final fileName = pathStr.split('/').last;
                          final exists = File(pathStr).existsSync();
                          final toolName = item['tool'] as String? ?? 'Converted File';

                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF131827), // Solid dark card background
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF252F48)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                )
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                 onTap: exists
                                     ? () => openAnyFile(context, pathStr)
                                     : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: AppColors.cyan.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.insert_drive_file_rounded,
                                          color: AppColors.cyan,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fileName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.violet
                                                        .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    toolName,
                                                    style: const TextStyle(
                                                      color: AppColors.cyan,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (!exists)
                                                  const Text(
                                                    '(File missing)',
                                                    style: TextStyle(
                                                        color: AppColors.danger,
                                                        fontSize: 11),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (exists) ...[
                                        IconButton(
                                          icon: const Icon(Icons.share_rounded,
                                              color: AppColors.cyan, size: 20),
                                          onPressed: () =>
                                              FileService.instance.share(pathStr),
                                        ),
                                      ],
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: AppColors.danger,
                                            size: 20),
                                        onPressed: () =>
                                            _deleteFile(i, pathStr),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                              .animate(delay: (30 * i).ms)
                              .fadeIn(duration: 250.ms)
                              .slideY(begin: 0.1, curve: Curves.easeOutCubic);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
