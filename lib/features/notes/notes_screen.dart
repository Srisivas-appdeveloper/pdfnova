import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/gradient_background.dart';
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
          title: Row(
            children: [
              const Icon(Icons.note_alt_rounded, color: AppColors.cyan, size: 22),
              const SizedBox(width: 8),
              Text(widget.tool.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _exportNoteToPdf,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(_saving ? 'Saving...' : 'Save PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.violet,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Note Title Field
                GlassCard(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Note Title (e.g. Meeting Minutes)',
                      hintStyle: TextStyle(color: AppColors.textLow, fontSize: 18),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Note Body Text Editor
                Expanded(
                  child: GlassCard(
                    radius: 20,
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Start typing your notes here...\n\nYour notes will be saved into the Notes folder and can be exported as PDF instantly.',
                        hintStyle: TextStyle(color: AppColors.textLow, fontSize: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
