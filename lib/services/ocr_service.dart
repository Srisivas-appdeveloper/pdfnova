import 'dart:convert';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'pdf_service.dart';
import 'raster_service.dart';
import 'tool_errors.dart';

/// On-device OCR: render each PDF page to PNG, run ML Kit recognition,
/// emit a .txt with page markers. Devanagari script instance is used as a
/// second pass when Latin finds almost nothing (covers Hindi documents).
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  Future<List<String>> ocrPdf(Uint8List pdfBytes) async {
    final pageTexts = await ocrPdfToPageTexts(pdfBytes);
    final buffer = StringBuffer();
    for (final (i, text) in pageTexts.indexed) {
      buffer.writeln('───── Page ${i + 1} ─────');
      buffer.writeln(text);
      buffer.writeln();
    }
    final text = buffer.toString();
    if (text.replaceAll(RegExp(r'[─\s]|Page \d+'), '').isEmpty) {
      throw Exception('NoText: nothing recognisable on these pages');
    }
    final path = await PdfService.instance.outPath('ocr', ext: 'txt');
    await writeAtomic(path, utf8.encode(text));
    return [path];
  }

  /// OCR helper to recognize text on each page and return page-by-page texts
  Future<List<String>> ocrPdfToPageTexts(Uint8List pdfBytes) async {
    final pages = await RasterService.instance.renderAll(pdfBytes, scale: 2.0);
    final tmp = await getTemporaryDirectory();
    final latin = TextRecognizer(script: TextRecognitionScript.latin);
    final devanagari = TextRecognizer(script: TextRecognitionScript.devanagiri);
    final pageTexts = <String>[];
    try {
      for (final (i, png) in pages.indexed) {
        final f = File('${tmp.path}/ocr_temp_$i.png');
        await f.writeAsBytes(png, flush: true);
        final image = InputImage.fromFilePath(f.path);
        var result = await latin.processImage(image);
        if (result.text.trim().length < 8) {
          final second = await devanagari.processImage(image);
          if (second.text.trim().length > result.text.trim().length) {
            result = second;
          }
        }
        pageTexts.add(result.text.trim());
        try {
          await f.delete();
        } catch (_) {}
      }
    } finally {
      await latin.close();
      await devanagari.close();
    }
    return pageTexts;
  }
}
