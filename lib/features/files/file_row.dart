import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/file_open.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_dialog.dart';
import '../../services/file_service.dart';
import '../../services/storage_service.dart';

/// File-type families used for icons and the Files filter.
enum FileKind { pdf, word, slides, image, text, other }

FileKind kindOf(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.pdf')) return FileKind.pdf;
  if (p.endsWith('.docx')) return FileKind.word;
  if (p.endsWith('.pptx')) return FileKind.slides;
  if (p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png')) {
    return FileKind.image;
  }
  if (p.endsWith('.txt')) return FileKind.text;
  return FileKind.other;
}

/// Icon and tint for a file, by extension.
(IconData, (Color, Color)) fileLook(BuildContext context, String path) {
  final c = context.nova;
  return switch (kindOf(path)) {
    FileKind.word => (Icons.description_outlined, c.tint(0)),
    FileKind.slides => (Icons.slideshow_outlined, c.tint(4)),
    FileKind.text => (Icons.notes_rounded, c.tint(3)),
    FileKind.image => (Icons.image_outlined, c.tint(2)),
    FileKind.pdf => (Icons.picture_as_pdf_outlined, (c.danger, c.dangerSoft)),
    FileKind.other => (
        Icons.insert_drive_file_outlined,
        (c.inkMid, c.surfaceAlt)
      ),
  };
}

String timeAgo(DateTime? t) {
  if (t == null || t.millisecondsSinceEpoch == 0) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  return kb >= 1024
      ? '${(kb / 1024).toStringAsFixed(1)} MB'
      : '${kb.toStringAsFixed(0)} KB';
}

/// Size read from disk now (not a cached value), or '' when missing.
String fileSize(String path) {
  final f = File(path);
  return f.existsSync() ? formatBytes(f.lengthSync()) : '';
}

/// One generated file: type tile, name, "Tool · 2h ago · 340 KB", and a
/// menu sheet. Missing files say so plainly. In selection mode a check
/// replaces the menu and taps toggle selection.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.record,
    required this.onChanged,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
  });

  final OutputRecord record;
  final VoidCallback onChanged;
  final bool selectionMode;
  final bool selected;

  /// Toggles selection; also used by long-press to enter selection mode.
  final VoidCallback? onSelect;

  String get _path => record.path;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final exists = record.exists;
    final (icon, (fg, bg)) = fileLook(context, _path);
    final size = record.currentBytes;
    final meta = [
      record.tool,
      timeAgo(record.time),
      if (size != null && exists) formatBytes(size),
    ].where((s) => s.isNotEmpty).join(' · ');

    return NovaCard(
      radius: 18,
      color: selected ? c.accentSoft : null,
      borderColor: selected ? c.accent : null,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      onTap: selectionMode
          ? onSelect
          : exists
              ? () => openAnyFile(context, _path)
              : () => _menu(context),
      onLongPress: onSelect,
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
              Text(record.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      t.titleSmall?.copyWith(color: exists ? c.ink : c.inkLow)),
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
        AnimatedSwitcher(
          duration: NovaMotion.quick,
          child: selectionMode
              ? Padding(
                  key: const ValueKey('check'),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? c.accent : c.inkLow,
                  ),
                )
              : IconButton(
                  key: const ValueKey('more'),
                  tooltip: 'More',
                  icon: Icon(Icons.more_horiz_rounded, color: c.inkMid),
                  onPressed: () => _menu(context),
                ),
        ),
      ]),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final exists = record.exists;
    final owned = await FileService.instance.isAppOutput(_path);
    if (!context.mounted) return;
    showNovaSheet(
      context: context,
      builder: (sheet) {
        final c = sheet.nova;
        final t = Theme.of(sheet).textTheme;
        final (icon, (fg, bg)) = fileLook(sheet, _path);
        Widget action(IconData i, String label, VoidCallback onTap,
                {Color? color, String? subtitle}) =>
            ListTile(
              minTileHeight: 52,
              leading: Icon(i, color: color ?? c.ink),
              title: Text(label,
                  style: t.titleMedium?.copyWith(color: color ?? c.ink)),
              subtitle: subtitle == null ? null : Text(subtitle),
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
                  child: Text(record.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium),
                ),
              ]),
            ),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 6),
            action(Icons.info_outline_rounded, 'Details',
                () => showFileDetails(context, record)),
            if (exists) ...[
              action(Icons.open_in_new_rounded, 'Open',
                  () => openAnyFile(context, _path)),
              action(Icons.ios_share_rounded, 'Share',
                  () => FileService.instance.share(_path)),
              action(Icons.download_rounded, 'Save to Downloads',
                  () => _save(context)),
              if (owned)
                action(Icons.drive_file_rename_outline_rounded, 'Rename',
                    () => _rename(context)),
            ],
            action(Icons.playlist_remove_rounded, 'Remove from history',
                () async {
              await StorageService.instance.removeRecent(_path);
              onChanged();
            }, subtitle: exists ? 'The file stays on your phone' : null),
            if (exists && owned)
              action(Icons.delete_outline_rounded, 'Delete file',
                  () => confirmDeleteOutputs(context, [record], onChanged),
                  color: c.danger),
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

  void _rename(BuildContext context) {
    final name = record.name;
    final dot = name.lastIndexOf('.');
    final ctrl =
        TextEditingController(text: dot > 0 ? name.substring(0, dot) : name);
    String? error;
    showNovaDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) {
          final t = Theme.of(d).textTheme;
          Future<void> submit() async {
            try {
              final to =
                  await FileService.instance.renameOutput(_path, ctrl.text);
              await StorageService.instance.renameRecent(_path, to);
              if (d.mounted) Navigator.pop(d);
              onChanged();
            } on FileSystemException {
              setD(() => error = 'A file with that name already exists.');
            } on ArgumentError catch (e) {
              setD(() => error = '${e.message}');
            } catch (_) {
              setD(() => error = 'Could not rename this file.');
            }
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rename', style: t.headlineSmall),
                  const SizedBox(height: 16),
                  NovaField(
                      controller: ctrl, hint: 'File name', autofocus: true),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: t.bodySmall?.copyWith(color: d.nova.danger)),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: NovaButton.secondary(
                          label: 'Cancel', onPressed: () => Navigator.pop(d)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: NovaButton(label: 'Rename', onPressed: submit)),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Confirms, then deletes generated files from disk and from history.
/// Files outside app storage are only removed from history (never deleted).
Future<void> confirmDeleteOutputs(
    BuildContext context, List<OutputRecord> records, VoidCallback onChanged) {
  final one = records.length == 1;
  return showNovaDialog(
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
              Text(
                  one ? 'Delete this file?' : 'Delete ${records.length} files?',
                  style: t.headlineSmall),
              const SizedBox(height: 8),
              Text(
                  '${one ? '"${records.first.name}" will be' : 'These files will be'} removed from this phone. '
                  'Copies you saved to Downloads or shared, and the documents you started from, are not affected.',
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
                      var kept = 0;
                      for (final r in records) {
                        try {
                          if (!await FileService.instance
                              .deleteOutput(r.path)) {
                            kept++;
                          }
                        } catch (_) {
                          kept++;
                        }
                      }
                      await StorageService.instance
                          .removeRecents({for (final r in records) r.path});
                      onChanged();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(kept == 0
                                ? (one ? 'File deleted' : 'Files deleted')
                                : 'Removed from history. $kept outside PDF Nova\'s folder ${kept == 1 ? 'was' : 'were'} left untouched.')));
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

const _kindLabel = {
  FileKind.pdf: 'PDF document',
  FileKind.word: 'Word document (.docx)',
  FileKind.slides: 'PowerPoint (.pptx)',
  FileKind.image: 'Image',
  FileKind.text: 'Text file',
  FileKind.other: 'File',
};

String _dateTime(DateTime t) =>
    '${t.day}/${t.month}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Sheet with what is actually known about a file, read from disk when
/// opened (page count is parsed off the UI thread).
void showFileDetails(BuildContext context, OutputRecord record) {
  showNovaSheet(
    context: context,
    builder: (sheet) {
      final c = sheet.nova;
      final t = Theme.of(sheet).textTheme;
      final (icon, (fg, bg)) = fileLook(sheet, record.path);
      Widget row(String label, String value, {Color? color}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 110, child: Text(label, style: t.bodyMedium)),
                Expanded(
                  child: Text(value,
                      style: t.bodyLarge?.copyWith(color: color ?? c.ink)),
                ),
              ],
            ),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: FutureBuilder<FileDetails>(
            future: FileDetails.read(record.path),
            builder: (context, snap) {
              final d = snap.data;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    NovaIconTile(icon: icon, fg: fg, bg: bg, size: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(record.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: 8),
                  row('Type', _kindLabel[kindOf(record.path)]!),
                  row('Made with', record.tool),
                  row('Created', _dateTime(record.time)),
                  if (d == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  else if (!d.exists)
                    row('Status',
                        'No longer on this phone. It may have been deleted or moved by another app.',
                        color: c.danger)
                  else ...[
                    row('Size', formatBytes(d.bytes!)),
                    if (d.pages != null) row('Pages', '${d.pages}'),
                    if (d.locked)
                      row('Pages', 'Password-protected — open it to see pages'),
                    row('Modified', _dateTime(d.modified!)),
                    row('Status', 'Available · stored privately in PDF Nova',
                        color: c.success),
                  ],
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
