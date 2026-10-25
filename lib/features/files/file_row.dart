import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_open.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_dialog.dart';
import '../../services/file_service.dart';
import '../../services/storage_service.dart';

/// Icon and tint for a file, by extension.
(IconData, (Color, Color)) fileLook(BuildContext context, String path) {
  final c = context.nova;
  final p = path.toLowerCase();
  if (p.endsWith('.docx')) return (Icons.description_outlined, c.tint(0));
  if (p.endsWith('.pptx')) return (Icons.slideshow_outlined, c.tint(4));
  if (p.endsWith('.txt')) return (Icons.notes_rounded, c.tint(3));
  if (p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png')) {
    return (Icons.image_outlined, c.tint(2));
  }
  return (Icons.picture_as_pdf_outlined, (c.danger, c.dangerSoft));
}

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

String fileSize(String path) {
  final f = File(path);
  if (!f.existsSync()) return '';
  final kb = f.lengthSync() / 1024;
  return kb > 1024
      ? '${(kb / 1024).toStringAsFixed(1)} MB'
      : '${kb.toStringAsFixed(0)} KB';
}

/// One output file: type tile, name, "Tool · 2h ago · 340 KB", and a menu
/// sheet (open, share, save, delete). Missing files say so plainly.
class FileRow extends StatelessWidget {
  const FileRow({super.key, required this.item, required this.onChanged});
  final Map<String, dynamic> item;
  final VoidCallback onChanged;

  String get _path => item['path'] as String;
  String get _name => _path.split('/').last;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final exists = File(_path).existsSync();
    final (icon, (fg, bg)) = fileLook(context, _path);
    final when = timeAgo(DateTime.tryParse(item['time'] as String? ?? ''));
    final meta = [item['tool'] as String? ?? '', when, fileSize(_path)]
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return NovaCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      onTap: exists ? () => openAnyFile(context, _path) : () => _menu(context),
      child: Row(children: [
        Opacity(
          opacity: exists ? 1 : 0.4,
          child: NovaIconTile(icon: icon, fg: fg, bg: bg, size: 42),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(
                      color: exists ? c.ink : c.inkLow)),
              const SizedBox(height: 3),
              Text(
                exists ? meta : 'No longer on this phone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: exists ? null : c.danger),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'More',
          icon: Icon(Icons.more_horiz_rounded, color: c.inkMid),
          onPressed: () => _menu(context),
        ),
      ]),
    );
  }

  void _menu(BuildContext context) {
    final exists = File(_path).existsSync();
    showNovaSheet(
      context: context,
      builder: (sheet) {
        final c = sheet.nova;
        final t = Theme.of(sheet).textTheme;
        final (icon, (fg, bg)) = fileLook(sheet, _path);
        Widget action(IconData i, String label, VoidCallback onTap,
                {Color? color}) =>
            ListTile(
              leading: Icon(i, color: color ?? c.ink),
              title: Text(label,
                  style: t.titleMedium?.copyWith(color: color ?? c.ink)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              onTap: () {
                Navigator.pop(sheet);
                onTap();
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(children: [
                NovaIconTile(icon: icon, fg: fg, bg: bg, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(_name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium),
                ),
              ]),
            ),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 6),
            if (exists) ...[
              action(Icons.open_in_new_rounded, 'Open',
                  () => openAnyFile(context, _path)),
              action(Icons.ios_share_rounded, 'Share',
                  () => FileService.instance.share(_path)),
              action(Icons.download_rounded, 'Save to Downloads',
                  () => _save(context)),
              action(Icons.delete_outline_rounded, 'Delete file',
                  () => _confirmDelete(context),
                  color: c.danger),
            ] else
              action(Icons.playlist_remove_rounded, 'Remove from list',
                  () async {
                await StorageService.instance.removeRecent(_path);
                onChanged();
              }),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  Future<void> _save(BuildContext context) async {
    String message;
    try {
      final where = await FileService.instance.saveToDownloads(_path);
      message = where.startsWith('Download/')
          ? 'Saved to $where'
          : 'Saved inside the app folder. Use Share to send it anywhere.';
    } catch (_) {
      message = 'Could not save the file. Try Share instead.';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _confirmDelete(BuildContext context) {
    showNovaDialog(
      context: context,
      builder: (d) {
        final t = Theme.of(d).textTheme;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delete this file?', style: t.headlineSmall),
                const SizedBox(height: 8),
                Text(
                    '"$_name" will be removed from this phone. Copies you saved to Downloads or shared are not affected.',
                    style: t.bodyMedium),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                    child: NovaButton.secondary(
                        label: 'Keep', onPressed: () => Navigator.pop(d)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NovaButton(
                      label: 'Delete',
                      color: d.nova.danger,
                      onPressed: () async {
                        Navigator.pop(d);
                        try {
                          final f = File(_path);
                          if (f.existsSync()) f.deleteSync();
                        } catch (_) {}
                        await StorageService.instance.removeRecent(_path);
                        onChanged();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('File deleted')));
                        }
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
