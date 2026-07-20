import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' show Rect;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:image/image.dart' as img;
import 'raster_service.dart';
import 'ocr_service.dart';

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

  static String _xmlEscape(String s) {
    final cleaned = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x84\x86-\x9F]'), '');
    return cleaned
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static List<int> _u(String s) => utf8.encode(s);

  // ── PDF → WORD (.docx) ──────────────────────────────────────────────────

  Future<List<String>> pdfToWord(Uint8List pdfBytes) async {
    final doc = PdfDocument(inputBytes: pdfBytes);
    final extractor = PdfTextExtractor(doc);
    final pageTexts = <String>[];
    var totalChars = 0;

    for (var i = 0; i < doc.pages.count; i++) {
      final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
      pageTexts.add(text);
      totalChars += text.trim().length;
    }

    // Is it a scanned PDF (virtually no selectable text layer)?
    final isScanned = totalChars < 15 * pageTexts.length;

    List<String> finalPageTexts;
    if (isScanned) {
      try {
        finalPageTexts = await OcrService.instance.ocrPdfToPageTexts(pdfBytes);
      } catch (_) {
        finalPageTexts = pageTexts;
      }
    } else {
      finalPageTexts = pageTexts;
    }

    // Render high-res page images for layout & picture preservation
    final pageImages = await RasterService.instance.renderAll(pdfBytes, scale: 1.8);
    final jpegs = <Uint8List>[];
    for (final png in pageImages) {
      final decoded = img.decodePng(png);
      if (decoded != null) {
        // Paint solid white canvas to prevent transparent PNGs from turning pitch black when saved as JPEG
        final whiteCanvas = img.Image(width: decoded.width, height: decoded.height);
        img.fill(whiteCanvas, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(whiteCanvas, decoded);
        jpegs.add(Uint8List.fromList(img.encodeJpg(whiteCanvas, quality: 90)));
      }
    }

    final archive = Archive();
    final wordRelsXml = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdStyle" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');

    final bodyXml = StringBuffer();

    // Standard A4 width/height in EMUs (1 inch = 914,400 EMUs)
    const cx = 5800000;
    const cy = 7600000;

    final numPages = jpegs.isNotEmpty ? jpegs.length : finalPageTexts.length;

    // Writes plain paragraphs from a raw text blob (used for OCR'd pages
    // and as the fallback when rich line extraction fails).
    void writePlainLines(String text) {
      for (final line in text.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final cleaned = _xmlEscape(t);
        if (cleaned.isNotEmpty) {
          bodyXml.write(
              '<w:p><w:r><w:t xml:space="preserve">$cleaned</w:t></w:r></w:p>');
        }
      }
    }

    for (var i = 0; i < numPages; i++) {
      final imgId = i + 1;
      final relId = 'rId_img_$imgId';

      if (i < jpegs.length) {
        archive.addFile(ArchiveFile('word/media/image_page_$imgId.jpeg', jpegs[i].length, jpegs[i]));
        wordRelsXml.write(
            '<Relationship Id="$relId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image_page_$imgId.jpeg"/>');

        // Full OpenXML spec-compliant picture drawing with effectExtent & cNvGraphicFramePr
        bodyXml.write('''<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>
<wp:inline distT="0" distB="0" distL="0" distR="0">
  <wp:extent cx="$cx" cy="$cy"/>
  <wp:effectExtent l="0" t="0" r="0" b="0"/>
  <wp:docPr id="$imgId" name="Page $imgId"/>
  <wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>
  <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
    <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
      <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <pic:nvPicPr><pic:cNvPr id="$imgId" name="Page $imgId"/><pic:cNvPicPr/></pic:nvPicPr>
        <pic:blipFill><a:blip r:embed="$relId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
      </pic:pic>
    </a:graphicData>
  </a:graphic>
</wp:inline>
</w:drawing></w:r></w:p>''');
      }

      // 2. Add text lines for this page with alignment preservation (center, right, left)
      final pageWidth = (i < doc.pages.count) ? doc.pages[i].getClientSize().width : 595.0;
      final pageCenter = pageWidth / 2;

      if (isScanned) {
        // Scanned PDF: there is no selectable text layer, so the extractor
        // path below would produce nothing. Use the OCR'd text — otherwise
        // the DOCX would contain only page images.
        if (i < finalPageTexts.length) writePlainLines(finalPageTexts[i]);
      } else {
        try {
          final List<TextLine> textLines =
              extractor.extractTextLines(startPageIndex: i, endPageIndex: i);

          for (final line in textLines) {
            final t = line.text.trim();
            if (t.isEmpty) continue;
            final cleaned = _xmlEscape(t);
            if (cleaned.isEmpty) continue;

            final bounds = line.bounds;
            final lineCenter = bounds.left + (bounds.width / 2);
            final lineRight = bounds.left + bounds.width;

            String jcXml = '';
            // Detect Center Alignment
            if ((lineCenter - pageCenter).abs() < 45 &&
                bounds.left > 40 &&
                (pageWidth - lineRight) > 40) {
              jcXml = '<w:pPr><w:jc w:val="center"/></w:pPr>';
            }
            // Detect Right Alignment
            else if ((pageWidth - lineRight) < 65 &&
                bounds.left > (pageWidth * 0.35)) {
              jcXml = '<w:pPr><w:jc w:val="right"/></w:pPr>';
            }

            bodyXml.write(
                '<w:p>$jcXml<w:r><w:t xml:space="preserve">$cleaned</w:t></w:r></w:p>');
          }
        } catch (_) {
          // Fallback if line info extraction fails for a page
          if (i < finalPageTexts.length) writePlainLines(finalPageTexts[i]);
        }
      }

      if (i < numPages - 1) {
        bodyXml.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }

    doc.dispose();
    wordRelsXml.write('</Relationships>');

    final docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"'
        ' xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
        ' xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"'
        ' xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
        ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
        ' xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"'
        ' mc:Ignorable="w14 w15 wp14">'
        '<w:body>$bodyXml<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
        '</w:sectPr></w:body></w:document>';

    const ctXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '</Types>';

    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';

    const stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:style w:type="paragraph" w:styleId="Normal" w:default="1">'
        '<w:name w:val="Normal"/>'
        '<w:rPr><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>'
        '</w:style></w:styles>';

    void addText(String n, String c) { final b = _u(c); archive.addFile(ArchiveFile(n, b.length, b)); }
    addText('[Content_Types].xml', ctXml);
    addText('_rels/.rels', rootRels);
    addText('word/_rels/document.xml.rels', wordRelsXml.toString());
    addText('word/document.xml', docXml);
    addText('word/styles.xml', stylesXml);

    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw Exception('Failed to build DOCX');
    final path = await _outPath('pdf_to_word', 'docx');
    await File(path).writeAsBytes(zip, flush: true);
    return [path];
  }

  static String _xmlUnescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

  static String _sanitizeForStandardFont(String s) {
    return s
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('•', '*')
        .replaceAll('…', '...')
        .replaceAll('™', '(TM)')
        .replaceAll('©', '(C)')
        .replaceAll('®', '(R)')
        .replaceAll(RegExp(r'[^\x00-\xFF]'), ' '); // replace non-Latin-1 chars
  }

  static double _safeMeasureWidth(PdfFont font, String text) {
    try {
      return font.measureString(text).width;
    } catch (_) {
      final safe = _sanitizeForStandardFont(text);
      try {
        return font.measureString(safe).width;
      } catch (_) {
        return text.length * 7.0; // fallback width estimation
      }
    }
  }

  static void _safeDrawString(PdfGraphics graphics, String text, PdfFont font,
      {required PdfBrush brush, required Rect bounds}) {
    try {
      graphics.drawString(text, font, brush: brush, bounds: bounds);
    } catch (_) {
      final safe = _sanitizeForStandardFont(text);
      try {
        graphics.drawString(safe, font, brush: brush, bounds: bounds);
      } catch (_) {
        final asciiOnly = safe.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ');
        graphics.drawString(asciiOnly, font, brush: brush, bounds: bounds);
      }
    }
  }

  // ── WORD → PDF ───────────────────────────────────────────────────────────

  Future<List<String>> wordToPdf(Uint8List docxBytes) async {
    final archive = ZipDecoder().decodeBytes(docxBytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) throw Exception('Invalid DOCX file');

    final xmlStr = utf8.decode(entry.content as List<int>);
    final paragraphs = <String>[];
    final paraRe = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
    final textRe = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);

    for (final para in paraRe.allMatches(xmlStr)) {
      final buf = StringBuffer();
      for (final t in textRe.allMatches(para.group(0)!)) {
        buf.write(_xmlUnescape(t.group(1) ?? ''));
      }
      final text = _sanitizeForStandardFont(buf.toString().trim());
      if (text.isNotEmpty) paragraphs.add(text);
    }

    final pdf = PdfDocument();
    final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    const margin = 60.0;
    const lineH = 20.0;

    PdfPage page = pdf.pages.add();
    var y = margin;
    final pageW = page.getClientSize().width;
    final pageH = page.getClientSize().height;

    for (final para in paragraphs) {
      final words = para.split(' ');
      var line = '';
      for (final word in words) {
        final test = line.isEmpty ? word : '$line $word';
        if (_safeMeasureWidth(font, test) > pageW - margin * 2 && line.isNotEmpty) {
          if (y + lineH > pageH - margin) { page = pdf.pages.add(); y = margin; }
          _safeDrawString(page.graphics, line, font, brush: brush,
              bounds: Rect.fromLTWH(margin, y, pageW - margin * 2, lineH));
          y += lineH;
          line = word;
        } else {
          line = test;
        }
      }
      if (line.isNotEmpty) {
        if (y + lineH > pageH - margin) { page = pdf.pages.add(); y = margin; }
        _safeDrawString(page.graphics, line, font, brush: brush,
            bounds: Rect.fromLTWH(margin, y, pageW - margin * 2, lineH));
        y += lineH;
      }
      y += lineH * 0.5;
    }

    final bytes = await pdf.save();
    pdf.dispose();
    final path = await _outPath('word_to_pdf', 'pdf');
    await File(path).writeAsBytes(bytes, flush: true);
    return [path];
  }

  // ── PDF → POWERPOINT (.pptx) ─────────────────────────────────────────────

  Future<List<String>> pdfToPpt(Uint8List pdfBytes) async {
    final pages = await RasterService.instance.renderAll(pdfBytes, scale: 1.5);
    if (pages.isEmpty) throw Exception('Could not render PDF pages');

    final jpegs = <Uint8List>[];
    for (final png in pages) {
      final decoded = img.decodePng(png);
      if (decoded == null) continue;
      final whiteCanvas = img.Image(width: decoded.width, height: decoded.height);
      img.fill(whiteCanvas, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(whiteCanvas, decoded);
      jpegs.add(Uint8List.fromList(img.encodeJpg(whiteCanvas, quality: 90)));
    }
    if (jpegs.isEmpty) throw Exception('No pages could be rendered');

    final n = jpegs.length;
    const cx = 9144000; // 4:3 slide width EMU
    const cy = 6858000; // slide height EMU

    final archive = Archive();
    void addText(String name, String c) { final b = _u(c); archive.addFile(ArchiveFile(name, b.length, b)); }
    void addBytes(String name, List<int> b) => archive.addFile(ArchiveFile(name, b.length, b));

    // [Content_Types].xml
    final slideOverrides = StringBuffer();
    for (var i = 1; i <= n; i++) {
      slideOverrides.write('<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }
    addText('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '$slideOverrides</Types>');

    addText('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
        '</Relationships>');

    final sldIdList = StringBuffer();
    for (var i = 1; i <= n; i++) {
      sldIdList.write('<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>');
    }
    addText('ppt/presentation.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
        ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>$sldIdList</p:sldIdLst>'
        '<p:sldSz cx="$cx" cy="$cy"/>'
        '<p:notesSz cx="6858000" cy="9144000"/>'
        '</p:presentation>');

    final presRels = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="slideLayouts/slideLayout1.xml"/>');
    for (var i = 1; i <= n; i++) {
      presRels.write('<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>');
    }
    presRels.write('</Relationships>');
    addText('ppt/_rels/presentation.xml.rels', presRels.toString());

    addText('ppt/slideMasters/slideMaster1.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
        ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>'
        '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree></p:cSld>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
        '<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>'
        '</p:sldMaster>');

    addText('ppt/slideMasters/_rels/slideMaster1.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '</Relationships>');

    addText('ppt/slideLayouts/slideLayout1.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
        ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" type="blank">'
        '<p:cSld name="Blank"><p:spTree><p:nvGrpSpPr>'
        '<p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree></p:cSld></p:sldLayout>');

    addText('ppt/slideLayouts/_rels/slideLayout1.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
        '</Relationships>');

    for (var i = 0; i < n; i++) {
      final idx = i + 1;
      addBytes('ppt/media/image$idx.jpeg', jpegs[i]);

      addText('ppt/slides/slide$idx.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
          ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
          ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>'
          '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
          '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
          '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
          '<p:pic><p:nvPicPr>'
          '<p:cNvPr id="2" name="Page $idx"/>'
          '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/>'
          '</p:nvPicPr>'
          '<p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
          '<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
          '</p:pic></p:spTree></p:cSld>'
          '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
          '</p:sld>');

      addText('ppt/slides/_rels/slide$idx.xml.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image$idx.jpeg"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
          '</Relationships>');
    }

    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw Exception('Failed to build PPTX');
    final path = await _outPath('pdf_to_ppt', 'pptx');
    await File(path).writeAsBytes(zip, flush: true);
    return [path];
  }
}
