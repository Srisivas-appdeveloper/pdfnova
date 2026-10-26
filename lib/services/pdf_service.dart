import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'raster_service.dart';
import 'document_text_service.dart';
import 'tool_errors.dart';
import 'tool_notes.dart';

/// All PDF operations. Pure Dart via Syncfusion (Community License) plus
/// PDFium rendering (pdfx) for raster-based features. Every byte stays
/// on-device.
class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  Future<String> outPath(String name, {String ext = 'pdf'}) async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}/PDFNova');
    if (!out.existsSync()) out.createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${out.path}/${name}_$stamp.$ext';
  }

  /// Saves [doc] as a new output — verified and written atomically.
  /// The saved bytes are re-opened (with [password] if the output is
  /// protected) and must contain every page the document had; only then is
  /// the file written, via a temp file, so no half or broken output is ever
  /// left in the PDFNova folder.
  Future<String> _save(PdfDocument doc, String name, {String? password}) async {
    final expected = doc.pages.count;
    var bytes = await doc.save();
    doc.dispose();
    verifyPdf(bytes, expectedPages: expected, password: password);
    // Encrypted output is already written as one revision.
    if (password == null) bytes = _singleRevision(bytes, expected);
    final path = await outPath(name);
    await writeAtomic(path, bytes);
    return path;
  }

  /// Rewrites [bytes] as one clean revision. A normal save appends to the
  /// source, keeping it as an earlier revision inside the output — cutting
  /// the file at its first %%EOF then recovers the un-watermarked, unstamped
  /// or unfilled original. Done as reload + full save because a full save
  /// straight after flattening form fields corrupts the page tree; falls
  /// back to [bytes] if the rewrite doesn't verify.
  static List<int> _singleRevision(List<int> bytes, int expectedPages) {
    try {
      final d = PdfDocument(inputBytes: bytes);
      d.fileStructure.incrementalUpdate = false;
      final out = d.saveSync();
      d.dispose();
      verifyPdf(out, expectedPages: expectedPages);
      return out;
    } catch (_) {
      return bytes;
    }
  }

  /// Throws [UserFacingError] unless [bytes] open as a PDF with
  /// [expectedPages] pages (when given) and at least one page.
  static void verifyPdf(List<int> bytes,
      {int? expectedPages, String? password}) {
    final PdfDocument check;
    try {
      check = PdfDocument(inputBytes: bytes, password: password);
    } catch (_) {
      throw const UserFacingError(
          'The result could not be re-opened, so it was not saved. Try again or use another copy of the file.');
    }
    final n = check.pages.count;
    check.dispose();
    if (n == 0 || (expectedPages != null && n != expectedPages)) {
      throw const UserFacingError(
          'The result failed its page check, so it was not saved.');
    }
  }

  /// Adds a page with its own size and rotation. Syncfusion applies page
  /// settings per *section*, so changing `doc.pageSettings` between pages of
  /// one section would give later pages the first page's size/rotation
  /// (mixed-size merges, landscape photos, rotated pages). One section per
  /// page keeps every page exactly as requested.
  static PdfPage _newPage(PdfDocument doc, Size size,
      {PdfPageRotateAngle rotate = PdfPageRotateAngle.rotateAngle0}) {
    final section = doc.sections!.add();
    section.pageSettings
      // Orientation must match or Syncfusion swaps width/height back to
      // portrait.
      ..orientation = size.width > size.height
          ? PdfPageOrientation.landscape
          : PdfPageOrientation.portrait
      ..size = size
      ..margins.all = 0
      ..rotate = rotate;
    return section.pages.add();
  }

  void _copyPage(PdfDocument out, PdfPage srcPage,
      {PdfPageRotateAngle rotate = PdfPageRotateAngle.rotateAngle0}) {
    _newPage(out, srcPage.size, rotate: rotate).graphics.drawPdfTemplate(
        srcPage.createTemplate(), const Offset(0, 0), srcPage.size);
  }

  // ============================ PHASE 1 =================================

  Future<List<String>> merge(List<Uint8List> inputs) async {
    final out = PdfDocument();
    out.pageSettings.margins.all = 0;
    for (final bytes in inputs) {
      final src = PdfDocument(inputBytes: bytes);
      for (var i = 0; i < src.pages.count; i++) {
        _copyPage(out, src.pages[i]);
      }
      src.dispose();
    }
    return [await _save(out, 'merged')];
  }

  Future<List<String>> split(Uint8List input, int from, int to) async {
    if (from > to) {
      throw UserFacingError('"From" page ($from) is after "To" page ($to).');
    }
    final src = PdfDocument(inputBytes: input);
    final last = src.pages.count;
    if (from > last) {
      src.dispose();
      throw UserFacingError(
          'This PDF has only $last ${last == 1 ? 'page' : 'pages'}.');
    }
    final start = from.clamp(1, last);
    final end = to.clamp(start, last);
    final out = PdfDocument();
    out.pageSettings.margins.all = 0;
    for (var i = start - 1; i <= end - 1; i++) {
      _copyPage(out, src.pages[i]);
    }
    src.dispose();
    return [await _save(out, 'split_${start}_$end')];
  }

  /// Smart compress: tries Syncfusion stream-level compression first.
  /// If the reduction is < 20 % (typical for image-heavy / scanned PDFs),
  /// falls back to raster-JPEG at quality 82 which genuinely shrinks images.
  /// Returns whichever result is smaller.
  ///
  /// Runs on a background isolate — the Syncfusion parse/save and JPEG
  /// re-encode are seconds of pure CPU that would otherwise freeze the
  /// progress UI (hang → jump to 100%).
  Future<List<String>> compress(Uint8List input) async {
    final r = await _offUi(() => _compressImpl(input));
    final path = r.first, mode = r.last;
    _checkSameLength(input, path);
    final before = input.length, after = File(path).lengthSync();
    final saved = before == 0 ? 0 : ((before - after) / before * 100).round();
    ToolNotes.add(saved > 0
        ? 'Reduced from ${_fmt(before)} to ${_fmt(after)} ($saved% smaller).'
        : 'This PDF was already well compressed — the result is about the same size (${_fmt(after)}).');
    if (mode == 'raster') {
      ToolNotes.add(
          'To shrink it, pages were re-encoded as images: text in the result can no longer be selected or searched.');
    }
    return [path];
  }

  /// Every compression result must keep all pages of the source.
  static void _checkSameLength(Uint8List input, String outPath) {
    final src = PdfDocument(inputBytes: input);
    final n = src.pages.count;
    src.dispose();
    try {
      verifyPdf(File(outPath).readAsBytesSync(), expectedPages: n);
    } catch (_) {
      try {
        File(outPath).deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  static String _fmt(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).round()} KB';

  /// Tests set this: flutter_tester provides a root isolate token but can't
  /// host background-isolate platform channels.
  @visibleForTesting
  static bool runInline = false;

  /// Runs heavy conversion work on a background isolate so the UI isolate
  /// keeps pumping frames. Platform channels (pdfx raster, path_provider)
  /// are re-attached inside the isolate via the root token.
  static Future<List<String>> _offUi(Future<List<String>> Function() work) {
    final token = RootIsolateToken.instance;
    if (token == null || runInline) return work();
    return Isolate.run(() {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      return work();
    });
  }

  Future<List<String>> unlock(Uint8List input, String password) async {
    final doc = PdfDocument(inputBytes: input, password: password);
    doc.security.userPassword = '';
    doc.security.ownerPassword = '';
    return [await _save(doc, 'unlocked')];
  }

  static String aadhaarPassword(String name, String year) {
    final clean = name.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
    final four = clean.length >= 4 ? clean.substring(0, 4) : clean;
    return '$four$year';
  }

  Future<List<String>> protect(Uint8List input, String password) async {
    final doc = PdfDocument(inputBytes: input);
    doc.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
    doc.security.userPassword = password;
    final path = await _save(doc, 'protected', password: password);
    // The output must NOT open without the password.
    var opensWithout = false;
    try {
      PdfDocument(inputBytes: File(path).readAsBytesSync()).dispose();
      opensWithout = true;
    } catch (_) {}
    if (opensWithout) {
      File(path).deleteSync();
      throw const UserFacingError(
          'Protection could not be verified, so the file was not saved.');
    }
    return [path];
  }

  void _addFormattedPage(PdfDocument doc, Uint8List imageBytes,
      {int? imgW, int? imgH}) {
    final bitmap = PdfBitmap(imageBytes);
    final width = (imgW ?? bitmap.width).toDouble();
    final height = (imgH ?? bitmap.height).toDouble();
    final isLandscape = width > height;

    // Standard A4 document dimensions (595.28 x 841.89 pt)
    final pageSize =
        isLandscape ? const Size(841.89, 595.28) : const Size(595.28, 841.89);

    final page = _newPage(doc, pageSize);

    // Use page.getClientSize() to guarantee 100% fit within the drawable page canvas
    final clientW = page.getClientSize().width;
    final clientH = page.getClientSize().height;

    // Fit image inside canvas while strictly preserving aspect ratio
    final scaleW = clientW / width;
    final scaleH = clientH / height;
    final scale = scaleW < scaleH ? scaleW : scaleH;

    final drawW = width * scale;
    final drawH = height * scale;

    // Center image on the page
    final x = (clientW - drawW) / 2;
    final y = (clientH - drawH) / 2;

    page.graphics.drawImage(bitmap, Rect.fromLTWH(x, y, drawW, drawH));
  }

  Future<List<String>> imagesToPdf(List<Uint8List> images) async {
    final doc = PdfDocument();
    for (final bytes in images) {
      Uint8List jpgBytes;
      int width;
      int height;
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) throw Exception('Decode failed');
        jpgBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
        width = decoded.width;
        height = decoded.height;
      } catch (_) {
        final bitmap = PdfBitmap(bytes);
        jpgBytes = bytes;
        width = bitmap.width;
        height = bitmap.height;
      }
      _addFormattedPage(doc, jpgBytes, imgW: width, imgH: height);
    }
    return [await _save(doc, 'images')];
  }

  // ============================ PHASE 2 =================================

  /// Rebuild the PDF with pages in [order] (0-based source indices, deleted
  /// pages simply absent) and per-page quarter-turn [rotations].
  Future<List<String>> organize(
      Uint8List input, List<int> order, Map<int, int> rotations) async {
    final src = PdfDocument(inputBytes: input);
    final out = PdfDocument();
    out.pageSettings.margins.all = 0;
    const angles = [
      PdfPageRotateAngle.rotateAngle0,
      PdfPageRotateAngle.rotateAngle90,
      PdfPageRotateAngle.rotateAngle180,
      PdfPageRotateAngle.rotateAngle270,
    ];
    for (final i in order) {
      if (i < 0 || i >= src.pages.count) continue;
      _copyPage(out, src.pages[i], rotate: angles[(rotations[i] ?? 0) % 4]);
    }
    src.dispose();
    return [await _save(out, 'organized')];
  }

  /// Compress under [targetBytes] by rasterising pages to JPEG and stepping
  /// quality/scale down until the total fits. Output is image-based (like a
  /// scan) — the honest trade for guaranteed size, stated in the UI.
  /// Runs on a background isolate (see [compress]).
  Future<List<String>> compressToTarget(
      Uint8List input, int targetBytes) async {
    final r = await _offUi(() => _compressToTargetImpl(input, targetBytes));
    final path = r.first, mode = r.last;
    _checkSameLength(input, path);
    final size = File(path).lengthSync();
    // Report the measured size — never claim the target without checking.
    ToolNotes.add(size <= targetBytes
        ? 'Result is ${_fmt(size)} — under your ${_fmt(targetBytes)} target.'
        : 'Could not get under ${_fmt(targetBytes)}: the smallest readable result is ${_fmt(size)}.');
    ToolNotes.add(mode == 'raster'
        ? 'To reach the size, pages were re-encoded as images: text in the result can no longer be selected or searched.'
        : 'Text is kept sharp and selectable.');
    return [path];
  }

  Future<List<String>> imagesToPdfNamed(
      List<Uint8List> images, String name) async {
    final doc = PdfDocument();
    for (final bytes in images) {
      _addFormattedPage(doc, bytes);
    }
    return [await _save(doc, name)];
  }

  /// Diagonal translucent text watermark on every page.
  Future<List<String>> watermark(Uint8List input, String text,
      {double opacity = 0.25}) async {
    final doc = PdfDocument(inputBytes: input);
    final font =
        PdfStandardFont(PdfFontFamily.helvetica, 48, style: PdfFontStyle.bold);
    for (var i = 0; i < doc.pages.count; i++) {
      final page = doc.pages[i];
      final g = page.graphics;
      final size = page.getClientSize();
      final state = g.save();
      g.setTransparency(opacity);
      g.translateTransform(size.width / 2, size.height / 2);
      g.rotateTransform(-40);
      final width = font.measureString(text).width;
      g.drawString(text, font,
          brush: PdfBrushes.gray,
          bounds: Rect.fromLTWH(-width / 2, -24, width, 60));
      g.restore(state);
    }
    return [await _save(doc, 'watermarked')];
  }

  /// Strip document information + XMP so shared files carry no history.
  Future<List<String>> stripMetadata(Uint8List input) async {
    final doc = PdfDocument(inputBytes: input);
    final info = doc.documentInformation;
    info.author = '';
    info.title = '';
    info.subject = '';
    info.keywords = '';
    info.creator = '';
    info.producer = '';
    try {
      info.removeModificationDate();
    } catch (_) {/* not exposed in every lib version */}
    doc.fileStructure.incrementalUpdate = false;
    return [await _save(doc, 'clean')];
  }

  /// PDF → PNG per page (returns many files).
  /// [sourceName] names the images after their PDF (`Report_page_1.jpg`) so
  /// pages saved to Downloads from different files can be told apart.
  Future<List<String>> pdfToImages(Uint8List input, {String? sourceName}) {
    final base = sourceName
        ?.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^\w\-. ]+'), '_')
        .trim();
    return RasterService.instance.renderToFiles(input,
        scale: 2.0,
        prefix: base == null || base.isEmpty ? 'page' : '${base}_page');
  }

  /// PDF → plain text. Uses each page's text layer, and on-device OCR only
  /// for pages without one (scanned pages).
  Future<List<String>> pdfToText(Uint8List input) async {
    final pages = await DocumentTextService.instance.extract(input);
    if (pages.every((p) => p.isEmpty)) {
      throw Exception('NoText: nothing recognisable on these pages');
    }
    final text = pages.length == 1
        ? pages.first.text
        : [
            for (final p in pages)
              '───── Page ${p.page} ─────\n${p.text.trim()}\n'
          ].join('\n');
    if (pages.any((p) => p.source == TextSource.ocr)) {
      ToolNotes.add(
          'Some pages were scanned images and were read with on-device OCR — check names and numbers.');
    }
    final path = await outPath('extracted', ext: 'txt');
    await writeAtomic(path, utf8.encode(text));
    return [path];
  }

  // ============================ PHASE 4 =================================

  /// Page numbers bottom-centre: "1 / N".
  Future<List<String>> pageNumbers(Uint8List input) async {
    final doc = PdfDocument(inputBytes: input);
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final n = doc.pages.count;
    for (var i = 0; i < n; i++) {
      final page = doc.pages[i];
      final size = page.getClientSize();
      final label = '${i + 1} / $n';
      final w = font.measureString(label).width;
      page.graphics.drawString(label, font,
          brush: PdfBrushes.dimGray,
          bounds:
              Rect.fromLTWH((size.width - w) / 2, size.height - 26, w + 4, 16));
    }
    return [await _save(doc, 'numbered')];
  }

  /// Corner stamp like PAID / APPROVED — bold, rotated, coloured.
  Future<List<String>> stamp(Uint8List input, String text, Color color) async {
    final doc = PdfDocument(inputBytes: input);
    final font =
        PdfStandardFont(PdfFontFamily.helvetica, 26, style: PdfFontStyle.bold);
    final argb = color.toARGB32();
    final pdfColor =
        PdfColor((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
    final brush = PdfSolidBrush(pdfColor);
    final pen = PdfPen(pdfColor, width: 2);
    for (var i = 0; i < doc.pages.count; i++) {
      final g = doc.pages[i].graphics;
      final w = font.measureString(text).width;
      final state = g.save();
      g.setTransparency(0.85);
      g.translateTransform(doc.pages[i].getClientSize().width - w - 60, 70);
      g.rotateTransform(-12);
      g.drawRectangle(pen: pen, bounds: Rect.fromLTWH(-10, -8, w + 20, 44));
      g.drawString(text, font,
          brush: brush, bounds: Rect.fromLTWH(0, 0, w + 10, 34));
      g.restore(state);
    }
    return [await _save(doc, 'stamped')];
  }

  /// Place a signature PNG on one page. [relX]/[relY] are the CENTRE of the
  /// signature as a fraction of page width/height; [relWidth] its width
  /// fraction. Matches the drag-preview coordinates 1:1.
  Future<List<String>> placeSignature(Uint8List input, Uint8List signaturePng,
      int pageNumber, double relX, double relY, double relWidth) async {
    final doc = PdfDocument(inputBytes: input);
    final idx = (pageNumber - 1).clamp(0, doc.pages.count - 1);
    final page = doc.pages[idx];
    final size = page.getClientSize();
    final bitmap = PdfBitmap(signaturePng);
    final w = size.width * relWidth;
    final h = w * (bitmap.height / bitmap.width);
    page.graphics.drawImage(
        bitmap,
        Rect.fromLTWH(
            size.width * relX - w / 2, size.height * relY - h / 2, w, h));
    return [await _save(doc, 'signed')];
  }

  // ---- Forms -----------------------------------------------------------
  /// List fillable text fields: (index, name, current value).
  List<(int, String, String)> listFormFields(Uint8List input) {
    final doc = PdfDocument(inputBytes: input);
    final fields = <(int, String, String)>[];
    for (var i = 0; i < doc.form.fields.count; i++) {
      final f = doc.form.fields[i];
      if (f is PdfTextBoxField) {
        fields.add(
            (i, fieldLabel(f.name, f.tooltip) ?? 'Field ${i + 1}', f.text));
      }
    }
    doc.dispose();
    return fields;
  }

  Future<List<String>> fillForm(
      Uint8List input, Map<int, String> values, bool flatten) async {
    final doc = PdfDocument(inputBytes: input);
    values.forEach((i, v) {
      if (i < doc.form.fields.count) {
        final f = doc.form.fields[i];
        if (f is PdfTextBoxField) f.text = v;
      }
    });
    if (flatten) {
      try {
        doc.form.flattenAllFields();
      } catch (_) {/* older lib versions: leave interactive */}
    }
    return [await _save(doc, 'filled')];
  }
}

// ---- Background-isolate implementations ----------------------------------
// Top-level so Isolate.run sends only the raw input bytes — singletons like
// PdfService.instance / RasterService.instance resolve fresh inside the
// spawned isolate, so nothing non-sendable crosses the port.

Future<List<String>> _compressImpl(Uint8List input) async {
  final pdf = PdfService.instance;
  // --- Pass 1: stream-level compression (lossless, keeps text selectable) ---
  final doc1 = PdfDocument(inputBytes: input);
  doc1.compressionLevel = PdfCompressionLevel.best;
  doc1.fileStructure.incrementalUpdate = false;
  final compressed1 = Uint8List.fromList(await doc1.save());
  doc1.dispose();

  final originalSize = input.length;
  final pass1Size = compressed1.length;
  final reduction = (originalSize - pass1Size) / originalSize;

  // If stream compression reduced by ≥ 20 %, it's good enough.
  if (reduction >= 0.20) {
    final path = await pdf.outPath('compressed');
    await writeAtomic(path, compressed1);
    return [path, 'lossless'];
  }

  // --- Pass 2: raster-JPEG (lossy, works on image-based / scanned PDFs) ---
  final pages = await RasterService.instance.renderAll(input, scale: 1.5);
  final jpegs = <Uint8List>[];
  for (final png in pages) {
    final decoded = img.decodePng(png);
    if (decoded == null) break; // a page failed: never drop pages silently
    jpegs.add(Uint8List.fromList(img.encodeJpg(decoded, quality: 82)));
  }

  if (jpegs.isEmpty || jpegs.length != pages.length) {
    // Fallback: the lossless version, even if the gain was small.
    final path = await pdf.outPath('compressed');
    await writeAtomic(path, compressed1);
    return [path, 'lossless'];
  }

  final rasterResult = await pdf.imagesToPdfNamed(jpegs, 'compressed');
  final pass2Size = File(rasterResult.first).lengthSync();

  // Return whichever is smaller — and remove the other attempt's file.
  if (pass2Size < pass1Size) return [rasterResult.first, 'raster'];
  File(rasterResult.first).deleteSync();

  final path = await pdf.outPath('compressed');
  await writeAtomic(path, compressed1);
  return [path, 'lossless'];
}

Future<List<String>> _compressToTargetImpl(
    Uint8List input, int targetBytes) async {
  final pdf = PdfService.instance;
  final name = 'fit_${targetBytes ~/ 1024}kb';
  // Lossless first: if that already fits, keep the text sharp and
  // selectable. Rasterising a small text PDF made it many times *bigger*.
  final doc = PdfDocument(inputBytes: input);
  doc.compressionLevel = PdfCompressionLevel.best;
  doc.fileStructure.incrementalUpdate = false;
  var lossless =
      Uint8List.fromList(doc.saveSync()); // already off the UI isolate
  doc.dispose();
  if (input.length < lossless.length) lossless = input;
  if (lossless.length <= targetBytes) {
    final path = await pdf.outPath(name);
    await writeAtomic(path, lossless);
    return [path, 'lossless'];
  }

  const attempts = [
    (scale: 2.0, quality: 80),
    (scale: 1.6, quality: 70),
    (scale: 1.3, quality: 60),
    (scale: 1.0, quality: 50),
    (scale: 0.85, quality: 40),
    (scale: 0.7, quality: 30),
  ];
  for (final a in attempts) {
    final pages = await RasterService.instance.renderAll(input, scale: a.scale);
    final jpegs = <Uint8List>[];
    var total = 0;
    for (final png in pages) {
      final decoded = img.decodePng(png);
      if (decoded == null) {
        throw const UserFacingError('A page could not be rendered.');
      }
      final jpg =
          Uint8List.fromList(img.encodeJpg(decoded, quality: a.quality));
      jpegs.add(jpg);
      total += jpg.length;
    }
    if (total <= targetBytes * 0.92) {
      // ~8% headroom for PDF structure
      return [(await pdf.imagesToPdfNamed(jpegs, name)).first, 'raster'];
    }
  }
  // Could not reach target — return the smallest result we can make.
  final pages = await RasterService.instance.renderAll(input, scale: 0.7);
  final jpegs = <Uint8List>[];
  for (final png in pages) {
    final d = img.decodePng(png);
    if (d == null) throw const UserFacingError('A page could not be rendered.');
    jpegs.add(Uint8List.fromList(img.encodeJpg(d, quality: 25)));
  }
  final raster = (await pdf.imagesToPdfNamed(jpegs, 'fit_best_effort')).first;
  if (File(raster).lengthSync() < lossless.length) return [raster, 'raster'];
  File(raster).deleteSync();
  final path = await pdf.outPath('fit_best_effort');
  await writeAtomic(path, lossless);
  return [path, 'lossless'];
}

/// A readable label for a form field: the form's own tooltip if it has one,
/// else the internal name made human — `form1[0].page1[0].full_name[0]`
/// → "Full name", `dob` → "Date of birth".
String? fieldLabel(String? name, [String? tooltip]) {
  final tip = tooltip?.trim();
  if (tip != null && tip.isNotEmpty) return tip;
  if (name == null || name.trim().isEmpty) return null;
  final last = name.split('.').last.replaceAll(RegExp(r'\[\d+\]'), '');
  final words = last
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim()
      .toLowerCase();
  if (words.isEmpty) return null;
  const known = {
    'dob': 'Date of birth',
    'pin': 'PIN code',
    'pincode': 'PIN code',
    'addr': 'Address',
    'tel': 'Phone',
    'mob': 'Mobile',
    'email': 'Email',
    'pan': 'PAN',
  };
  return known[words] ?? '${words[0].toUpperCase()}${words.substring(1)}';
}
