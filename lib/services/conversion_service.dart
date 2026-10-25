import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' show Rect;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:image/image.dart' as img;
import 'document_text_service.dart';
import 'raster_service.dart';
import 'tool_notes.dart';
import 'unicode_text_layout.dart';

/// PDF → Word output style. Each mode shows every page's content once.
enum PdfToWordMode {
  /// Real paragraphs you can edit (layout approximate, images dropped).
  editable,

  /// Each page as a picture — looks identical, but not editable.
  layout,
}

/// Offline document conversions — no cloud, no uploads.
/// PDF ↔ Word (.docx) and PDF → PowerPoint (.pptx).
class ConversionService {
  ConversionService._();
  static final ConversionService instance = ConversionService._();

  Future<String> _outPath(String name, String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}/PDFNova')..createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${out.path}/${name}_$stamp.$ext';
  }

  static Future<List<Uint8List>> _renderJpegs(
      Uint8List pdf, double scale) async {
    final out = <Uint8List>[];
    for (final png
        in await RasterService.instance.renderAll(pdf, scale: scale)) {
      final decoded = img.decodePng(png);
      if (decoded == null) continue;
      // White canvas so transparent pages don't turn black as JPEG.
      final canvas = img.Image(width: decoded.width, height: decoded.height);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(canvas, decoded);
      out.add(Uint8List.fromList(img.encodeJpg(canvas, quality: 90)));
    }
    return out;
  }

  // ── PDF → WORD (.docx) ──────────────────────────────────────────────────

  Future<List<String>> pdfToWord(Uint8List pdfBytes,
      {PdfToWordMode mode = PdfToWordMode.editable}) async {
    final docx = DocxBuilder();
    if (mode == PdfToWordMode.layout) {
      final pages = await _renderJpegs(pdfBytes, 1.8);
      if (pages.isEmpty) throw Exception('Could not render PDF pages');
      for (final (i, jpeg) in pages.indexed) {
        final d = img.decodeJpg(jpeg)!;
        docx.image(jpeg, d.width, d.height);
        if (i < pages.length - 1) docx.pageBreak();
      }
      ToolNotes.add(
          'Exact-look mode: each page is a picture, so the text is not editable.');
    } else {
      final pages =
          await DocumentTextService.instance.extract(pdfBytes, withLines: true);
      final doc = PdfDocument(inputBytes: pdfBytes);
      final widths = [
        for (var i = 0; i < doc.pages.count; i++)
          doc.pages[i].getClientSize().width
      ];
      doc.dispose();
      List<Uint8List>? images; // rendered lazily, only for empty pages
      var pictured = 0;
      for (final (i, p) in pages.indexed) {
        if (p.lines.isNotEmpty) {
          for (final line in p.lines) {
            docx.paragraph(line.text, align: alignFor(line.bounds, widths[i]));
          }
        } else if (!p.isEmpty) {
          for (final l in p.text.split('\n')) {
            docx.paragraph(l);
          }
        } else {
          images ??= await _renderJpegs(pdfBytes, 1.8);
          if (i < images.length) {
            final d = img.decodeJpg(images[i])!;
            docx.image(images[i], d.width, d.height);
            pictured++;
          }
        }
        if (i < pages.length - 1) docx.pageBreak();
      }
      if (pages.any((p) => p.source == TextSource.ocr)) {
        ToolNotes.add(
            'Scanned pages were read with on-device OCR — check names and numbers.');
      }
      if (pictured > 0) {
        ToolNotes.add(
            '$pictured ${pictured == 1 ? 'page has' : 'pages have'} no readable text and ${pictured == 1 ? 'was' : 'were'} added as a picture.');
      }
      ToolNotes.add(
          'Editable mode keeps text and alignment; images and exact layout are not carried over.');
    }
    final bytes = docx.build();
    verifyDocx(bytes);
    final path = await _outPath('pdf_to_word', 'docx');
    await File(path).writeAsBytes(bytes, flush: true);
    return [path];
  }

  // ── WORD → PDF ───────────────────────────────────────────────────────────

  Future<List<String>> wordToPdf(Uint8List docxBytes) async {
    final paragraphs = parseDocx(docxBytes);
    final pdf = PdfDocument();
    final writer = UnicodePdfWriter(pdf);
    await writer.write(paragraphs);
    final bytes = Uint8List.fromList(await pdf.save());
    pdf.dispose();

    // Verify: the result must open and have pages.
    final check = PdfDocument(inputBytes: bytes);
    final ok = check.pages.count > 0;
    check.dispose();
    if (!ok) throw Exception('Generated PDF failed verification');

    final r = writer.report;
    if (r.shaped.isNotEmpty) {
      ToolNotes.add(
          '${r.shaped.map(_scriptLabel).join(', ')} text was shaped for correct display and kept searchable.');
    }
    if (r.unsupported.isNotEmpty) {
      final sample = r.unsupported.take(3).join(' ');
      ToolNotes.add(
          'Some characters ($sample) use scripts PDF Nova has no embedded font for. They are shown using your phone\'s fonts but are not searchable in the PDF.');
    }
    ToolNotes.add(
        'Text, headings and line breaks are kept; images, tables and styling from Word are not.');
    final path = await _outPath('word_to_pdf', 'pdf');
    await File(path).writeAsBytes(bytes, flush: true);
    return [path];
  }

  static String _scriptLabel(NovaScript s) =>
      '${s.name[0].toUpperCase()}${s.name.substring(1)}';

  // ── PDF → POWERPOINT (.pptx) ─────────────────────────────────────────────

  Future<List<String>> pdfToPpt(Uint8List pdfBytes) async {
    final jpegs = await _renderJpegs(pdfBytes, 1.5);
    if (jpegs.isEmpty) throw Exception('Could not render PDF pages');
    final slides = [
      for (final j in jpegs)
        if (img.decodeJpg(j) case final d?) SlideImage(j, d.width, d.height)
    ];
    final bytes = buildPptx(slides);
    verifyPptx(bytes, slides.length);
    final path = await _outPath('pdf_to_ppt', 'pptx');
    await File(path).writeAsBytes(bytes, flush: true);
    return [path];
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Pure builders & parsers (no platform calls — unit-tested)
// ═════════════════════════════════════════════════════════════════════════

String _xmlEscape(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Paragraph alignment from a text line's position on its page.
String? alignFor(Rect bounds, double pageWidth) {
  final center = bounds.left + bounds.width / 2;
  final right = bounds.left + bounds.width;
  if ((center - pageWidth / 2).abs() < 45 &&
      bounds.left > 40 &&
      (pageWidth - right) > 40) {
    return 'center';
  }
  if ((pageWidth - right) < 65 && bounds.left > pageWidth * 0.35) {
    return 'right';
  }
  return null;
}

/// Reads paragraphs from a .docx: text runs, tabs, line breaks and
/// heading styles (Title/Heading1–3). Throws on files that aren't DOCX.
List<DocParagraph> parseDocx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Not a Word (.docx) file');
  }
  final entry = archive.findFile('word/document.xml');
  if (entry == null) throw const FormatException('Invalid DOCX file');
  final xml = utf8.decode(entry.content as List<int>, allowMalformed: true);

  final out = <DocParagraph>[];
  final paraRe = RegExp(r'<w:p[ >].*?</w:p>|<w:p/>', dotAll: true);
  final tokenRe = RegExp(
      r'<w:t(?:\s[^>]*)?>(.*?)</w:t>|<w:tab/>|<w:br(?:\s[^>]*)?/>|<w:cr/>',
      dotAll: true);
  final styleRe = RegExp(r'<w:pStyle w:val="([^"]+)"');
  for (final m in paraRe.allMatches(xml)) {
    final p = m.group(0)!;
    final buf = StringBuffer();
    for (final t in tokenRe.allMatches(p)) {
      final tok = t.group(0)!;
      if (tok.startsWith('<w:tab')) {
        buf.write('    ');
      } else if (tok.startsWith('<w:br') || tok.startsWith('<w:cr')) {
        buf.write('\n');
      } else {
        buf.write(_xmlUnescape(t.group(1) ?? ''));
      }
    }
    final style = styleRe.firstMatch(p)?.group(1)?.toLowerCase() ?? '';
    final heading = style == 'title' || style == 'heading1'
        ? 1
        : style == 'heading2'
            ? 2
            : style == 'heading3'
                ? 3
                : 0;
    out.add(DocParagraph(buf.toString(), heading: heading));
  }
  // Drop trailing empty paragraphs (Word always ends with one).
  while (out.isNotEmpty && out.last.text.trim().isEmpty) {
    out.removeLast();
  }
  return out;
}

/// Minimal, spec-valid .docx writer.
class DocxBuilder {
  final _body = StringBuffer();
  final _images = <Uint8List>[];

  /// Usable width at 1" margins on US Letter / A4, in EMU (6.5").
  static const _maxW = 5943600;
  static const _maxH = 8229600; // 9"

  int get imageCount => _images.length;

  void paragraph(String text, {String? align}) {
    final t = text.trim();
    if (t.isEmpty) return;
    final jc = align == null ? '' : '<w:pPr><w:jc w:val="$align"/></w:pPr>';
    _body.write(
        '<w:p>$jc<w:r><w:t xml:space="preserve">${_xmlEscape(t)}</w:t></w:r></w:p>');
  }

  void pageBreak() =>
      _body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');

  /// Adds a picture scaled to fit the page, keeping its aspect ratio.
  void image(Uint8List jpeg, int widthPx, int heightPx) {
    _images.add(jpeg);
    final id = _images.length;
    var cx = _maxW;
    var cy = (cx * heightPx / widthPx).round();
    if (cy > _maxH) {
      cy = _maxH;
      cx = (cy * widthPx / heightPx).round();
    }
    _body.write('<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="$id" name="Page $id"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="Page $id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rIdImg$id"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>');
  }

  Uint8List build() {
    final archive = Archive();
    void text(String name, String content) {
      final b = utf8.encode(content);
      archive.addFile(ArchiveFile(name, b.length, b));
    }

    text(
        '[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Default Extension="jpeg" ContentType="image/jpeg"/>'
            '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
            '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
            '</Types>');
    text(
        '_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
            '</Relationships>');
    final rels = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdStyle" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
    for (var i = 1; i <= _images.length; i++) {
      archive.addFile(ArchiveFile(
          'word/media/image$i.jpeg', _images[i - 1].length, _images[i - 1]));
      rels.write(
          '<Relationship Id="rIdImg$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image$i.jpeg"/>');
    }
    rels.write('</Relationships>');
    text('word/_rels/document.xml.rels', rels.toString());
    text(
        'word/styles.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            '<w:style w:type="paragraph" w:styleId="Normal" w:default="1"><w:name w:val="Normal"/>'
            '<w:rPr><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:style></w:styles>');
    text(
        'word/document.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
            ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
            ' xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"'
            ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
            ' xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            '<w:body>$_body<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
            '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
            '</w:sectPr></w:body></w:document>');
    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw Exception('Failed to build DOCX');
    return Uint8List.fromList(zip);
  }
}

/// Re-opens a generated .docx and checks its structure. Throws if broken.
void verifyDocx(Uint8List bytes) {
  final a = ZipDecoder().decodeBytes(bytes);
  for (final part in [
    '[Content_Types].xml',
    '_rels/.rels',
    'word/document.xml',
    'word/_rels/document.xml.rels',
  ]) {
    if (a.findFile(part) == null) {
      throw Exception('Generated DOCX is missing $part');
    }
  }
  final doc =
      utf8.decode(a.findFile('word/document.xml')!.content as List<int>);
  if (!doc.contains('<w:body>') || !doc.endsWith('</w:document>')) {
    throw Exception('Generated DOCX body is malformed');
  }
  final rels = utf8
      .decode(a.findFile('word/_rels/document.xml.rels')!.content as List<int>);
  for (final m in RegExp(r'r:embed="([^"]+)"').allMatches(doc)) {
    if (!rels.contains('Id="${m.group(1)}"')) {
      throw Exception('Generated DOCX has a broken image link');
    }
  }
}

class SlideImage {
  const SlideImage(this.jpeg, this.width, this.height);
  final Uint8List jpeg;
  final int width;
  final int height;
}

/// Builds a .pptx with one picture per slide. Slide size follows the first
/// page's shape (width 10"), and every page is letterboxed to fit — never
/// stretched — on a white slide.
Uint8List buildPptx(List<SlideImage> slides) {
  if (slides.isEmpty) throw ArgumentError('No slides');
  const cx = 9144000; // 10"
  final first = slides.first;
  final cy = (cx * first.height / first.width)
      .round()
      .clamp(914400, 51206400); // PowerPoint limits: 1"–56"
  final n = slides.length;
  final archive = Archive();
  void text(String name, String c) {
    final b = utf8.encode(c);
    archive.addFile(ArchiveFile(name, b.length, b));
  }

  const ns = ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
      ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
      ' xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
  const relNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const emptyTree =
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';
  const whiteBg =
      '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>';

  text(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Default Extension="jpeg" ContentType="image/jpeg"/>'
          '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
          '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
          '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
          '${[
        for (var i = 1; i <= n; i++)
          '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
      ].join()}'
          '</Types>');
  text(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="$relNs/officeDocument" Target="ppt/presentation.xml"/>'
          '</Relationships>');
  text(
      'ppt/presentation.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation$ns>'
          '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
          '<p:sldIdLst>${[
        for (var i = 1; i <= n; i++)
          '<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>'
      ].join()}</p:sldIdLst>'
          '<p:sldSz cx="$cx" cy="$cy"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>');
  text(
      'ppt/_rels/presentation.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="$relNs/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
          '<Relationship Id="rId2" Type="$relNs/slideLayout" Target="slideLayouts/slideLayout1.xml"/>'
          '${[
        for (var i = 1; i <= n; i++)
          '<Relationship Id="rId${i + 2}" Type="$relNs/slide" Target="slides/slide$i.xml"/>'
      ].join()}'
          '</Relationships>');
  text(
      'ppt/slideMasters/slideMaster1.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldMaster$ns>'
          '<p:cSld>$whiteBg<p:spTree>$emptyTree</p:spTree></p:cSld>'
          '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
          '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
          '<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>');
  text(
      'ppt/slideMasters/_rels/slideMaster1.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="$relNs/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
          '</Relationships>');
  text(
      'ppt/slideLayouts/slideLayout1.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldLayout$ns type="blank">'
          '<p:cSld name="Blank"><p:spTree>$emptyTree</p:spTree></p:cSld></p:sldLayout>');
  text(
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="$relNs/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
          '</Relationships>');

  for (final (i, s) in slides.indexed) {
    final idx = i + 1;
    // Letterbox: fit the page inside the slide, centred, aspect preserved.
    final pageRatio = s.width / s.height;
    var w = cx, h = (cx / pageRatio).round();
    if (h > cy) {
      h = cy;
      w = (cy * pageRatio).round();
    }
    final x = ((cx - w) / 2).round(), y = ((cy - h) / 2).round();
    archive.addFile(
        ArchiveFile('ppt/media/image$idx.jpeg', s.jpeg.length, s.jpeg));
    text(
        'ppt/slides/slide$idx.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld$ns>'
            '<p:cSld>$whiteBg<p:spTree>$emptyTree'
            '<p:pic><p:nvPicPr><p:cNvPr id="2" name="Page $idx"/>'
            '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
            '<p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
            '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>'
            '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>');
    text(
        'ppt/slides/_rels/slide$idx.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="$relNs/image" Target="../media/image$idx.jpeg"/>'
            '<Relationship Id="rId2" Type="$relNs/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
            '</Relationships>');
  }
  final zip = ZipEncoder().encode(archive);
  if (zip == null) throw Exception('Failed to build PPTX');
  return Uint8List.fromList(zip);
}

/// Re-opens a generated .pptx and checks slide count and parts.
void verifyPptx(Uint8List bytes, int expectedSlides) {
  final a = ZipDecoder().decodeBytes(bytes);
  if (a.findFile('ppt/presentation.xml') == null) {
    throw Exception('Generated PPTX is missing its presentation part');
  }
  for (var i = 1; i <= expectedSlides; i++) {
    if (a.findFile('ppt/slides/slide$i.xml') == null ||
        a.findFile('ppt/media/image$i.jpeg') == null) {
      throw Exception('Generated PPTX is missing slide $i');
    }
  }
}
