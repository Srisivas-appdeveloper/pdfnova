import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../services/file_service.dart';
import '../../services/storage_service.dart';
import '../home/tools.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.tool});
  final Tool tool;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _exportNoteToPdf() async {
    final titleText = _titleController.text.trim();
    final bodyText = _bodyController.text.trim();

    if (bodyText.isEmpty && titleText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter some text in your note before saving.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final title = titleText.isEmpty ? 'Untitled Note' : titleText;

      // Create PDF Document using Syncfusion
      final doc = sf.PdfDocument();
      final page = doc.pages.add();
      final graphics = page.graphics;
      final pageSize = page.getClientSize();

      // Title font & Body font
      final titleFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 22,
          style: sf.PdfFontStyle.bold);
      final subtitleFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 10,
          style: sf.PdfFontStyle.italic);
      final bodyFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12);

      // Draw Title
      graphics.drawString(
        title,
        titleFont,
        brush: sf.PdfBrushes.darkBlue,
        bounds: Rect.fromLTWH(0, 0, pageSize.width, 30),
      );

      // Draw Timestamp Subtitle
      final timestampStr = 'Created on ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} at ${TimeOfDay.now().format(context)}';
      graphics.drawString(
        timestampStr,
        subtitleFont,
        brush: sf.PdfBrushes.gray,
        bounds: Rect.fromLTWH(0, 32, pageSize.width, 18),
      );

      // Draw Horizontal Line
      graphics.drawLine(
        sf.PdfPen(sf.PdfColor(124, 92, 255), width: 1.5),
        const Offset(0, 54),
        Offset(pageSize.width, 54),
      );

      // Draw Body Text using PdfTextElement for automatic pagination
      final textElement = sf.PdfTextElement(
        text: bodyText.isEmpty ? 'No notes content.' : bodyText,
        font: bodyFont,
        brush: sf.PdfBrushes.black,
      );

      final layoutFormat = sf.PdfLayoutFormat(
        layoutType: sf.PdfLayoutType.paginate,
      );

      textElement.draw(
        page: page,
        bounds: Rect.fromLTWH(0, 68, pageSize.width, pageSize.height - 78),
        format: layoutFormat,
      );

      // Save PDF to Local Storage
      final bytes = await doc.save();
      doc.dispose();

      final dir = await getApplicationDocumentsDirectory();
      final safeName = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final outPath = '${dir.path}/${safeName}_Note_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final file = File(outPath);
      await file.writeAsBytes(bytes);

      // Record in Recents under 'Notes'
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
        FileService.instance.open(outPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving note: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        actions: [
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
                '${now.day} ${months[now.month - 1]} ${now.year} · saved as a PDF in Files › Notes',
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
