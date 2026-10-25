import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfnova/services/conversion_service.dart';
import 'package:pdfnova/services/tool_notes.dart';
import 'package:pdfnova/services/unicode_text_layout.dart';
import '../helpers.dart';

/// Minimal .docx with the given paragraphs (style id optional).
Uint8List docx(List<(String, String?)> paragraphs) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final body = paragraphs.map((p) {
    final style =
        p.$2 == null ? '' : '<w:pPr><w:pStyle w:val="${p.$2}"/></w:pPr>';
    final runs = p.$1
        .split('\t')
        .map((t) => '<w:r><w:t xml:space="preserve">${esc(t)}</w:t></w:r>')
        .join('<w:r><w:tab/></w:r>');
    return '<w:p>$style$runs</w:p>';
  }).join();
  final xml = '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body<w:p/></w:body></w:document>';
  final a = Archive()
    ..addFile(ArchiveFile(
        'word/document.xml', utf8.encode(xml).length, utf8.encode(xml)));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

Uint8List jpeg(int w, int h) {
  final i = img.Image(width: w, height: h);
  img.fill(i, color: img.ColorRgb8(240, 240, 240));
  return Uint8List.fromList(img.encodeJpg(i));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sandbox = Sandbox();
  setUp(sandbox.setUp);
  tearDown(sandbox.tearDown);

  // The scripts PDF Nova claims to support for Word → PDF.
  const samples = {
    'English': 'Invoice total ₹1,250 — due “30 June”',
    'Tamil': 'வணக்கம் உலகம்',
    'Hindi': 'नमस्ते दुनिया किताब',
    'Telugu': 'నమస్కారం ప్రపంచం',
    'Kannada': 'ನಮಸ್ಕಾರ ಪ್ರಪಂಚ',
    'Malayalam': 'നമസ്കാരം ലോകം',
    'Bengali': 'নমস্কার বিশ্ব',
    'Gujarati': 'નમસ્તે વિશ્વ',
    'Greek/Cyrillic': 'Καλημέρα Привет',
  };

  group('script detection', () {
    test('classifies each supported script', () {
      expect(scriptOf('A'.runes.first), NovaScript.latin);
      expect(scriptOf('வ'.runes.first), NovaScript.tamil);
      expect(scriptOf('न'.runes.first), NovaScript.devanagari);
      expect(scriptOf('న'.runes.first), NovaScript.telugu);
      expect(scriptOf('ನ'.runes.first), NovaScript.kannada);
      expect(scriptOf('ന'.runes.first), NovaScript.malayalam);
      expect(scriptOf('ন'.runes.first), NovaScript.bengali);
      expect(scriptOf('ન'.runes.first), NovaScript.gujarati);
      expect(scriptOf('中'.runes.first), NovaScript.other);
      expect(scriptOf(' '.runes.first), isNull);
    });

    test('splits mixed text into runs, keeping spaces with words', () {
      final runs = scriptRuns('Hello வணக்கம் 2026');
      expect(runs.map((r) => r.$1), [NovaScript.latin, NovaScript.tamil]);
      expect(runs.map((r) => r.$2).join(), 'Hello வணக்கம் 2026');
    });
  });

  group('Word → PDF', () {
    test('parses headings, tabs and drops the trailing empty paragraph', () {
      final p = parseDocx(docx([('Title here', 'Heading1'), ('a\tb', null)]));
      expect(p, hasLength(2));
      expect(p[0].heading, 1);
      expect(p[1].text, 'a    b');
    });

    test('rejects files that are not .docx', () {
      expect(() => parseDocx(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<FormatException>()));
    });

    testWidgets('every supported script survives and stays extractable',
        (tester) async {
      final notes = <String>[];
      final paths = await tester.runAsync(() => ToolNotes.collect(
          notes,
          () => ConversionService.instance.wordToPdf(docx([
                ('Unicode check', 'Title'),
                for (final e in samples.entries) ('${e.key}: ${e.value}', null),
              ]))));
      final pdf = readBytes(paths!.single);
      final text = textOf(pdf);
      for (final e in samples.entries) {
        for (final word in e.value.split(' ')) {
          expect(text, contains(word), reason: '${e.key} word "$word" lost');
        }
      }
      expect(notes.join(), contains('shaped'));
      expect(notes.join(), isNot(contains('no embedded font')));
    });

    testWidgets('unsupported scripts are reported, not silently dropped',
        (tester) async {
      final notes = <String>[];
      final paths = await tester.runAsync(() => ToolNotes.collect(
          notes,
          () => ConversionService.instance
              .wordToPdf(docx([('Chinese: 你好', null)]))));
      expect(pageCount(readBytes(paths!.single)), 1);
      expect(notes.join(), contains('你'));
    });

    testWidgets('long documents paginate', (tester) async {
      final paths = await tester.runAsync(() => ConversionService.instance
              .wordToPdf(docx([
            for (var i = 0; i < 120; i++) ('Line $i of the report', null)
          ])));
      final pdf = readBytes(paths!.single);
      expect(pageCount(pdf) > 1, isTrue);
      expect(textOf(pdf), contains('Line 119'));
    });
  });

  group('PDF → Word package', () {
    test('editable text has paragraphs, no images, and verifies', () {
      final b = DocxBuilder()
        ..paragraph('Hello <world> & “friends”', align: 'center')
        ..pageBreak()
        ..paragraph('வணக்கம்');
      final bytes = b.build();
      verifyDocx(bytes);
      final doc = utf8.decode(ZipDecoder()
          .decodeBytes(bytes)
          .findFile('word/document.xml')!
          .content as List<int>);
      expect(doc, contains('Hello &lt;world&gt; &amp; “friends”'));
      expect(doc, contains('வணக்கம்'));
      expect(doc, contains('<w:jc w:val="center"/>'));
      expect(doc, isNot(contains('<w:drawing>')));
      expect(b.imageCount, 0);
    });

    test('pictures keep their aspect ratio within the page', () {
      final b = DocxBuilder()..image(jpeg(400, 1000), 400, 1000);
      final bytes = b.build();
      verifyDocx(bytes);
      final doc = utf8.decode(ZipDecoder()
          .decodeBytes(bytes)
          .findFile('word/document.xml')!
          .content as List<int>);
      final m = RegExp(r'<wp:extent cx="(\d+)" cy="(\d+)"/>').firstMatch(doc)!;
      final cx = int.parse(m[1]!), cy = int.parse(m[2]!);
      expect(cy, lessThanOrEqualTo(8229600));
      expect(cx / cy, closeTo(0.4, 0.01));
    });

    test('verification catches a broken package', () {
      final a = Archive()..addFile(ArchiveFile('x.txt', 1, [65]));
      expect(() => verifyDocx(Uint8List.fromList(ZipEncoder().encode(a)!)),
          throwsException);
    });

    test('alignment detection', () {
      expect(alignFor(const Rect.fromLTWH(200, 0, 195, 10), 595), 'center');
      expect(alignFor(const Rect.fromLTWH(400, 0, 150, 10), 595), 'right');
      expect(alignFor(const Rect.fromLTWH(50, 0, 300, 10), 595), isNull);
    });
  });

  group('PDF → PowerPoint', () {
    (int, int, int, int) picBox(Uint8List pptx, int slide) {
      final xml = utf8.decode(ZipDecoder()
          .decodeBytes(pptx)
          .findFile('ppt/slides/slide$slide.xml')!
          .content as List<int>);
      final off = RegExp(r'<a:off x="(\d+)" y="(\d+)"/>').allMatches(xml).last;
      final ext =
          RegExp(r'<a:ext cx="(\d+)" cy="(\d+)"/>').allMatches(xml).last;
      return (
        int.parse(off[1]!),
        int.parse(off[2]!),
        int.parse(ext[1]!),
        int.parse(ext[2]!)
      );
    }

    (int, int) slideSize(Uint8List pptx) {
      final xml = utf8.decode(ZipDecoder()
          .decodeBytes(pptx)
          .findFile('ppt/presentation.xml')!
          .content as List<int>);
      final m = RegExp(r'<p:sldSz cx="(\d+)" cy="(\d+)"/>').firstMatch(xml)!;
      return (int.parse(m[1]!), int.parse(m[2]!));
    }

    test('portrait pages get portrait slides, never stretched', () {
      final bytes = buildPptx([SlideImage(jpeg(595, 842), 595, 842)]);
      verifyPptx(bytes, 1);
      final (sw, sh) = slideSize(bytes);
      expect(sh > sw, isTrue);
      final (_, _, w, h) = picBox(bytes, 1);
      expect(w / h, closeTo(595 / 842, 0.01));
    });

    test('mixed orientations are letterboxed, keeping each page ratio', () {
      final bytes = buildPptx([
        SlideImage(jpeg(842, 595), 842, 595),
        SlideImage(jpeg(595, 842), 595, 842),
      ]);
      verifyPptx(bytes, 2);
      final (sw, sh) = slideSize(bytes);
      final (x, y, w, h) = picBox(bytes, 2);
      expect(w / h, closeTo(595 / 842, 0.01));
      expect(h, sh);
      expect(x, ((sw - w) / 2).round());
      expect(y, 0);
    });

    test('verification catches missing slides', () {
      final bytes = buildPptx([SlideImage(jpeg(10, 10), 10, 10)]);
      expect(() => verifyPptx(bytes, 2), throwsException);
    });
  });
}
