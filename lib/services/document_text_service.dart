import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'ocr_service.dart';

/// Where a page's text came from.
enum TextSource { textLayer, ocr, none }

/// Text of one page, with its 1-based page number kept attached — the unit
/// that search, conversion and (later) document Q&A all build on.
class PageText {
  const PageText({
    required this.page,
    required this.text,
    required this.source,
    this.lines = const [],
  });

  final int page;
  final String text;
  final TextSource source;

  /// Positioned lines from the text layer (empty for OCR'd pages).
  final List<TextLine> lines;

  bool get isEmpty => text.trim().isEmpty;
}

/// Reusable per-page text extraction: the PDF's own text layer first, and
/// on-device OCR only for the pages that have (almost) none.
class DocumentTextService {
  DocumentTextService({Future<List<String>> Function(Uint8List)? ocr})
      : _ocr = ocr ?? OcrService.instance.ocrPdfToPageTexts;

  static final DocumentTextService instance = DocumentTextService();

  final Future<List<String>> Function(Uint8List) _ocr;

  /// [minChars] — pages with fewer extracted characters count as scanned.
  Future<List<PageText>> extract(Uint8List pdf,
      {bool ocrFallback = true,
      bool withLines = false,
      int minChars = 15}) async {
    final doc = PdfDocument(inputBytes: pdf);
    final extractor = PdfTextExtractor(doc);
    final pages = <PageText>[];
    try {
      for (var i = 0; i < doc.pages.count; i++) {
        // Line extraction is preferred: Syncfusion's plain extractText()
        // mis-decodes text that follows a font switch on the same page
        // (verified against poppler's pdftotext), which real-world PDFs
        // with several fonts hit constantly.
        List<TextLine> lines = const [];
        try {
          lines =
              extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
        } catch (_) {}
        final text = lines.isNotEmpty
            ? lines.map((l) => l.text).join('\n')
            : extractor.extractText(startPageIndex: i, endPageIndex: i);
        final hasText = text.trim().length >= minChars;
        pages.add(PageText(
          page: i + 1,
          text: text,
          source: hasText ? TextSource.textLayer : TextSource.none,
          lines: withLines && hasText ? lines : const [],
        ));
      }
    } finally {
      doc.dispose();
    }

    if (!ocrFallback || pages.every((p) => p.source == TextSource.textLayer)) {
      return pages;
    }
    List<String> ocr;
    try {
      ocr = await _ocr(pdf);
    } catch (_) {
      return pages; // OCR unavailable (e.g. iOS simulator) — keep what we have
    }
    return [
      for (final p in pages)
        if (p.source == TextSource.none &&
            p.page <= ocr.length &&
            ocr[p.page - 1].trim().isNotEmpty)
          PageText(page: p.page, text: ocr[p.page - 1], source: TextSource.ocr)
        else
          p
    ];
  }
}
