import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_dialog.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../services/file_service.dart';
import '../../services/notes_store.dart';
import '../../services/pdf_service.dart';
import '../../services/tool_errors.dart';
import '../../services/unicode_text_layout.dart';
import '../../services/storage_service.dart';
import '../home/tools.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.tool});
  final Tool tool;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _store = NotesStore.instance;
  bool _saving = false;
  bool _loaded = false;

  /// Version of the note this editor is based on (compare-and-set).
  int _version = 0;
  bool _dirty = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bodyController.addListener(_onEdit);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flush();
    _debounce?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save before the user can switch to the widget; pick up widget edits
    // when they come back.
    if (state == AppLifecycleState.paused) _flush();
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    try {
      final note = await _store.load();
      if (!mounted) return;
      if (!_loaded || (!_dirty && note.updatedAt > _version)) {
        _bodyController
          ..removeListener(_onEdit)
          ..text = note.text
          ..addListener(_onEdit);
        _version = note.updatedAt;
      }
      setState(() => _loaded = true);
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _onEdit() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _flush);
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    final text = _bodyController.text;
    try {
      final r = await _store.save(text, baseVersion: _version);
      _version = r.note.updatedAt;
      if (r.merged && mounted) {
        _bodyController
          ..removeListener(_onEdit)
          ..text = r.note.text
          ..addListener(_onEdit);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Your note was also edited from the Home Screen widget — both versions were kept.')));
      }
    } catch (_) {
      _dirty = true; // try again on the next edit or pause
    }
  }

  Future<void> _showVersions() async {
    await _flush();
    final versions = await _store.versions();
    if (!mounted) return;
    showNovaSheet(
      context: context,
      builder: (sheet) {
        final c = sheet.nova;
        final t = Theme.of(sheet).textTheme;
        String when(int ms) {
          final d = DateTime.fromMillisecondsSinceEpoch(ms);
          return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Earlier versions', style: t.headlineSmall),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                  'Kept automatically (up to ${NotesStore.maxVersions}). Restoring keeps the current text as a version too.',
                  style: t.bodySmall),
            ),
            if (versions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No earlier versions yet.', style: t.bodyMedium),
              )
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final v in versions)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 24),
                      leading: Icon(Icons.history_rounded, color: c.inkMid),
                      title: Text(v.text.trim().split('\n').first,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(when(v.updatedAt)),
                      trailing: TextButton(
                        child: const Text('Restore'),
                        onPressed: () async {
                          Navigator.pop(sheet);
                          final note = await _store.restore(v);
                          _version = note.updatedAt;
                          _bodyController
                            ..removeListener(_onEdit)
                            ..text = note.text
                            ..addListener(_onEdit);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Version restored. The text it replaced is in Earlier versions.')));
                          }
                        },
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  Future<void> _exportNoteToPdf() async {
    final titleText = _titleController.text.trim();
    final bodyText = _bodyController.text.trim();

    if (bodyText.isEmpty && titleText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Please enter some text in your note before saving.')),
      );
      return;
    }

    setState(() => _saving = true);
    await _flush();
    try {
      final title = titleText.isEmpty ? 'Untitled Note' : titleText;
      final now = DateTime.now();
      // Same Unicode-aware writer as Word → PDF, so notes in Tamil, Hindi
      // and other supported scripts keep their text.
      final doc = sf.PdfDocument();
      await UnicodePdfWriter(doc).write([
        DocParagraph(title, heading: 1),
        DocParagraph(
            '${now.day}/${now.month}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'),
        for (final line
            in (bodyText.isEmpty ? 'No notes content.' : bodyText).split('\n'))
          DocParagraph(line),
      ]);
      final bytes = await doc.save();
      doc.dispose();

      final safeName = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final outPath = await PdfService.instance.outPath('${safeName}_Note');
      PdfService.verifyPdf(bytes);
      await writeAtomic(outPath, bytes);

      // Record in history under 'Notes'
      await StorageService.instance.addRecent(outPath, 'Notes');
      await StorageService.instance.incrementOps();

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved note as PDF: $safeName.pdf'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => FileService.instance.open(outPath),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the note as a PDF.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        actions: [
          NovaIconButton(
            tooltip: 'Earlier versions',
            icon: Icons.history_rounded,
            onPressed: _showVersions,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              height: 44,
              child: NovaButton(
                expanded: false,
                label: _saving ? 'Saving…' : 'Save PDF',
                icon: Icons.picture_as_pdf_outlined,
                onPressed: _saving ? null : _exportNoteToPdf,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 16 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _titleController,
                style: t.headlineLarge,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Untitled note',
                  hintStyle: t.headlineLarge?.copyWith(color: c.inkLow),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ).enter(context, delayMs: 120),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 16),
              child: Text(
                '${now.day} ${months[now.month - 1]} ${now.year} · ${Platform.isAndroid ? 'synced with your Home Screen note · ' : ''}Save PDF to keep a copy in Files',
                style: t.bodySmall,
              ),
            ).enter(context, delayMs: 180),
            Expanded(
              child: NovaCard(
                radius: 22,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: TextField(
                  controller: _bodyController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  style: t.bodyLarge?.copyWith(height: 1.6),
                  decoration: InputDecoration(
                    hintText: 'Start writing…',
                    hintStyle: t.bodyLarge?.copyWith(color: c.inkLow),
                    border: InputBorder.none,
                  ),
                ),
              ).enter(context, delayMs: 240),
            ),
          ],
        ),
      ),
    );
  }
}
