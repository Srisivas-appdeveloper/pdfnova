import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Scripts PDF Nova bundles a font for (Noto Sans family, SIL OFL).
/// [complex] scripts need shaping (vowel-sign reordering, conjuncts) that
/// Syncfusion's PDF text drawing does not perform.
enum NovaScript {
  latin('NotoSans', complex: false), // also Greek, Cyrillic, punctuation
  devanagari('NotoSansDevanagari'),
  bengali('NotoSansBengali'),
  gujarati('NotoSansGujarati'),
  tamil('NotoSansTamil'),
  telugu('NotoSansTelugu'),
  kannada('NotoSansKannada'),
  malayalam('NotoSansMalayalam'),

  /// No bundled font (Arabic, Hebrew, CJK, emoji…). Rendered by the
  /// platform's fonts as an image; not embedded as searchable text.
  other(null);

  const NovaScript(this.family, {this.complex = true});
  final String? family;
  final bool complex;

  String? get asset =>
      family == null ? null : 'assets/fonts/$family-Regular.ttf';
}

/// Script of a code point; null for characters that belong to whatever
/// script surrounds them (spaces, digits, common punctuation, ZWJ/ZWNJ).
NovaScript? scriptOf(int r) {
  if (r <= 0x40 ||
      (r >= 0x5B && r <= 0x60) ||
      (r >= 0x7B && r <= 0xBF) ||
      r == 0x200C ||
      r == 0x200D ||
      r == 0x0964 ||
      r == 0x0965) {
    return null; // shared: ASCII digits/punct, Latin-1 symbols, joiners, danda
  }
  if (r < 0x0530 ||
      (r >= 0x1E00 && r <= 0x1FFF) ||
      (r >= 0x2000 && r <= 0x22FF) ||
      (r >= 0xFB00 && r <= 0xFB06)) {
    return NovaScript.latin; // Latin, IPA, Greek, Cyrillic, punctuation, ₹
  }
  if ((r >= 0x0900 && r <= 0x097F) || (r >= 0xA8E0 && r <= 0xA8FF)) {
    return NovaScript.devanagari;
  }
  if (r >= 0x0980 && r <= 0x09FF) return NovaScript.bengali;
  if (r >= 0x0A80 && r <= 0x0AFF) return NovaScript.gujarati;
  if (r >= 0x0B80 && r <= 0x0BFF) return NovaScript.tamil;
  if (r >= 0x0C00 && r <= 0x0C7F) return NovaScript.telugu;
  if (r >= 0x0C80 && r <= 0x0CFF) return NovaScript.kannada;
  if (r >= 0x0D00 && r <= 0x0D7F) return NovaScript.malayalam;
  return NovaScript.other;
}

/// Splits text into runs of one script; shared characters join the run
/// they sit in (or the next run when they lead).
List<(NovaScript, String)> scriptRuns(String text) {
  final runs = <(NovaScript, String)>[];
  NovaScript? current;
  final buf = StringBuffer();
  final pending = StringBuffer(); // leading shared chars
  for (final r in text.runes) {
    final s = scriptOf(r);
    if (s == null) {
      (current == null ? pending : buf).writeCharCode(r);
      continue;
    }
    if (current == null) {
      current = s;
      buf
        ..write(pending)
        ..writeCharCode(r);
      pending.clear();
    } else if (s == current) {
      buf.writeCharCode(r);
    } else {
      runs.add((current, buf.toString()));
      buf
        ..clear()
        ..writeCharCode(r);
      current = s;
    }
  }
  if (current != null) {
    runs.add((current, buf.toString()));
  } else if (pending.isNotEmpty) {
    runs.add((NovaScript.latin, pending.toString()));
  }
  return runs;
}

bool _rtl(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFEFC)) {
      return true;
    }
    if (scriptOf(r) != null) return false;
  }
  return false;
}

/// One paragraph of a source document.
class DocParagraph {
  const DocParagraph(this.text, {this.heading = 0});
  final String text;

  /// 0 = body, 1–3 = heading levels.
  final int heading;

  double get fontSize =>
      switch (heading) { 1 => 20, 2 => 16, 3 => 14, _ => 12 };
}

/// What happened while laying text out — for honest result notes.
class UnicodeLayoutReport {
  final shaped = <NovaScript>{};
  final unsupported = <String>{};
}

/// Lays paragraphs onto A4 pages of [doc].
///
/// - Text that needs no shaping (Latin/Greek/Cyrillic) is vector text in
///   embedded Noto Sans — sharp and searchable.
/// - Paragraphs in complex scripts are shaped by Flutter's text engine
///   (HarfBuzz) into a 3× image, with an invisible text layer in the
///   matching embedded Noto font so the PDF stays searchable/copyable.
/// - Characters with no bundled font are still drawn (system fonts, in the
///   image) and listed in the report as not searchable.
class UnicodePdfWriter {
  UnicodePdfWriter(this.doc);

  final PdfDocument doc;
  final report = UnicodeLayoutReport();
  final _fontBytes = <NovaScript, Uint8List>{};
  final _fonts = <(NovaScript, double), PdfFont>{};

  static const margin = 56.0;
  static const _scale = 3.0;
  static const _ink = ui.Color(0xFF000000);

  late PdfPage _page;
  late double _y;
  Size get _size => _page.getClientSize();
  double get _width => _size.width - margin * 2;
  double get _bottom => _size.height - margin;

  Future<PdfFont?> _font(NovaScript s, double size) async {
    if (s.asset == null) return null;
    final key = (s, size);
    if (_fonts[key] != null) return _fonts[key];
    final bytes = _fontBytes[s] ??=
        (await rootBundle.load(s.asset!)).buffer.asUint8List();
    return _fonts[key] = PdfTrueTypeFont(bytes, size);
  }

  Future<void> write(List<DocParagraph> paragraphs) async {
    doc.pageSettings.size = PdfPageSize.a4;
    doc.pageSettings.margins.all = 0;
    _page = doc.pages.add();
    _y = margin;
    for (final p in paragraphs) {
      if (p.text.trim().isEmpty) {
        _y += p.fontSize;
        continue;
      }
      for (final r in p.text.runes) {
        if (scriptOf(r) == NovaScript.other) {
          report.unsupported.add(String.fromCharCode(r));
        }
      }
      final runs = scriptRuns(p.text);
      final simple = runs.every((r) => !r.$1.complex);
      if (simple) {
        await _vector(p);
      } else {
        await _shaped(p);
      }
      _y += p.fontSize * 0.6; // paragraph gap
    }
  }

  void _newPage() {
    _page = doc.pages.add();
    _y = margin;
  }

  Future<void> _vector(DocParagraph p) async {
    final font = (await _font(NovaScript.latin, p.fontSize))!;
    if (_y + p.fontSize * 1.4 > _bottom) _newPage();
    final result = PdfTextElement(
      text: p.text,
      font: font,
      brush: PdfSolidBrush(PdfColor(0, 0, 0)),
      format: PdfStringFormat(lineSpacing: p.fontSize * 0.35),
    ).draw(
      page: _page,
      bounds: Rect.fromLTWH(margin, _y, _width, _bottom - _y),
      format: PdfLayoutFormat(
        layoutType: PdfLayoutType.paginate,
        breakType: PdfLayoutBreakType.fitPage,
        paginateBounds:
            Rect.fromLTWH(margin, margin, _width, _size.height - margin * 2),
      ),
    );
    if (result != null) {
      _page = result.page;
      _y = result.bounds.bottom;
    }
  }

  Future<void> _shaped(DocParagraph p) async {
    final rtl = _rtl(p.text);
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: p.fontSize * _scale,
      height: 1.5,
      textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: _ink,
        fontSize: p.fontSize * _scale,
        fontFamily: NovaScript.latin.family,
        fontFamilyFallback: [
          for (final s in NovaScript.values)
            if (s.family != null) s.family!
        ],
      ))
      ..addText(p.text);
    final para = builder.build()
      ..layout(ui.ParagraphConstraints(width: _width * _scale));
    final lines = para.computeLineMetrics();

    var i = 0;
    while (i < lines.length) {
      // Take as many lines as fit on the current page.
      final top = lines[i].baseline - lines[i].ascent;
      var j = i;
      while (j < lines.length) {
        final bottom = lines[j].baseline + lines[j].descent;
        if (_y + (bottom - top) / _scale > _bottom && j > i) break;
        j++;
      }
      if (j == i + 1 &&
          _y + lines[i].height / _scale > _bottom &&
          _y > margin) {
        _newPage();
        continue; // retry this line on the fresh page
      }
      final bottom = lines[j - 1].baseline + lines[j - 1].descent;
      await _drawChunk(para, top, bottom);
      await _textLayer(para, lines.sublist(i, j), top, p);
      _y += (bottom - top) / _scale;
      i = j;
      if (i < lines.length) _newPage();
    }
    report.shaped
        .addAll(scriptRuns(p.text).map((r) => r.$1).where((s) => s.complex));
  }

  Future<void> _drawChunk(ui.Paragraph para, double top, double bottom) async {
    final w = (_width * _scale).ceil();
    final h = (bottom - top).ceil().clamp(1, 1 << 15);
    final rec = ui.PictureRecorder();
    ui.Canvas(rec)
      ..translate(0, -top)
      ..drawParagraph(para, Offset.zero);
    final image = await rec.endRecording().toImage(w, h);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return;
    _page.graphics.drawImage(PdfBitmap(png.buffer.asUint8List()),
        Rect.fromLTWH(margin, _y, w / _scale, h / _scale));
  }

  /// Invisible text matching each shaped line, so search, copy and text
  /// extraction work. Positions are per line, approximate within it.
  Future<void> _textLayer(ui.Paragraph para, List<ui.LineMetrics> lines,
      double chunkTop, DocParagraph p) async {
    final g = _page.graphics;
    final state = g.save();
    g.setTransparency(0);
    for (final line in lines) {
      final pos =
          para.getPositionForOffset(Offset(1, line.baseline - line.ascent / 2));
      final range = para.getLineBoundary(pos);
      final text = range.textInside(p.text);
      var x = margin;
      final y = _y + (line.baseline - line.ascent - chunkTop) / _scale;
      for (final (script, run) in scriptRuns(text)) {
        final font = await _font(script, p.fontSize);
        if (font == null) continue; // no embeddable font: image only
        final w = font.measureString(run).width;
        g.drawString(run, font,
            brush: PdfSolidBrush(PdfColor(0, 0, 0)),
            bounds: Rect.fromLTWH(x, y, w + 2, line.height / _scale));
        x += w;
      }
    }
    g.restore(state);
  }
}
