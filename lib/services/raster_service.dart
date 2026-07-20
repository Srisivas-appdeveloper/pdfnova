import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as px;

/// Renders PDF pages to bitmaps via PDFium (pdfx). Used by: page thumbnails,
/// PDF→Images, fit-to-size compression, OCR, signature preview.
class RasterService {
  RasterService._();
  static final RasterService instance = RasterService._();

  /// Render every page. [scale] 1.0 ≈ 72dpi; 2.0 ≈ 144dpi.
  Future<List<Uint8List>> renderAll(Uint8List pdfBytes,
      {double scale = 2.0}) async {
    final doc = await px.PdfDocument.openData(pdfBytes);
    final out = <Uint8List>[];
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final img = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: px.PdfPageImageFormat.png,
          );
          if (img != null) out.add(img.bytes);
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    return out;
  }

  /// Render one page (1-based) — for previews.
  Future<Uint8List?> renderPage(Uint8List pdfBytes, int pageNumber,
      {double scale = 2.0}) async {
    final doc = await px.PdfDocument.openData(pdfBytes);
    try {
      if (pageNumber < 1 || pageNumber > doc.pagesCount) return null;
      final page = await doc.getPage(pageNumber);
      try {
        final img = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: px.PdfPageImageFormat.png,
        );
        return img?.bytes;
      } finally {
        await page.close();
      }
    } finally {
      await doc.close();
    }
  }

  Future<int> pageCount(Uint8List pdfBytes) async {
    final doc = await px.PdfDocument.openData(pdfBytes);
    final n = doc.pagesCount;
    await doc.close();
    return n;
  }

  /// Write rendered pages to JPEG files with clean white background in an output folder; returns paths.
  Future<List<String>> renderToFiles(Uint8List pdfBytes,
      {double scale = 2.0, String prefix = 'page'}) async {
    final pages = await renderAll(pdfBytes, scale: scale);
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final folder = Directory('${dir.path}/PDFNova/images_$stamp')
      ..createSync(recursive: true);
    final paths = <String>[];
    for (final (i, pngBytes) in pages.indexed) {
      final decoded = img.decodePng(pngBytes);
      Uint8List finalBytes;
      if (decoded != null) {
        final whiteCanvas = img.Image(width: decoded.width, height: decoded.height);
        img.fill(whiteCanvas, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(whiteCanvas, decoded);
        finalBytes = Uint8List.fromList(img.encodeJpg(whiteCanvas, quality: 92));
      } else {
        finalBytes = pngBytes;
      }
      final path = '${folder.path}/${prefix}_${i + 1}.jpg';
      await File(path).writeAsBytes(finalBytes, flush: true);
      paths.add(path);
    }
    return paths;
  }
}
