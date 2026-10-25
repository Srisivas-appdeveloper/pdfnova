import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfnova/services/document_text_service.dart';
import 'package:pdfnova/services/notes_store.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../helpers.dart';

void main() {
  group('NotesStore', () {
    late MemoryNoteBackend backend;
    late NotesStore store;
    setUp(() {
      backend = MemoryNoteBackend();
      store = NotesStore(backend: backend);
    });

    test('saves when nobody else changed the note', () async {
      final base = (await store.load()).updatedAt;
      final r = await store.save('buy milk', baseVersion: base);
      expect(r.merged, isFalse);
      expect((await store.load()).text, 'buy milk');
    });

    test('a widget edit made meanwhile is merged, never lost', () async {
      final base = (await store.load()).updatedAt;
      await backend.write('call the bank'); // edited from the widget
      final r = await store.save('buy milk', baseVersion: base);
      expect(r.merged, isTrue);
      expect(r.note.text, contains('buy milk'));
      expect(r.note.text, contains('call the bank'));
    });

    test('merge does not duplicate text that is already included', () {
      expect(NotesStore.mergeNotes('a\nb', 'b'), 'a\nb');
      expect(NotesStore.mergeNotes('', 'theirs'), 'theirs');
      expect(NotesStore.mergeNotes('mine', ''), 'mine');
    });
  });

  group('DocumentTextService', () {
    Uint8List mixed() {
      // Page 1 has text; page 2 is blank (like a scanned image page).
      final doc = PdfDocument();
      doc.pages.add().graphics.drawString(
          'Invoice 2041 total 1,250.00 due 30 June',
          PdfStandardFont(PdfFontFamily.helvetica, 12));
      doc.pages.add();
      final b = Uint8List.fromList(doc.saveSync());
      doc.dispose();
      return b;
    }

    test('keeps page numbers attached to text', () async {
      final pages = await DocumentTextService(ocr: (_) async => [])
          .extract(samplePdf(3), minChars: 5);
      expect(pages.map((p) => p.page), [1, 2, 3]);
      expect(pages[1].text, contains('Page 2'));
      expect(pages.every((p) => p.source == TextSource.textLayer), isTrue);
    });

    test('runs OCR only when a page lacks text, and labels it', () async {
      var calls = 0;
      final svc = DocumentTextService(ocr: (_) async {
        calls++;
        return ['ignored', 'scanned words'];
      });
      final pages = await svc.extract(mixed());
      expect(calls, 1);
      expect(pages[0].source, TextSource.textLayer);
      expect(pages[0].text, contains('Invoice 2041'));
      expect(pages[1].source, TextSource.ocr);
      expect(pages[1].text, 'scanned words');
    });

    test('no OCR call for fully digital PDFs', () async {
      var calls = 0;
      await DocumentTextService(ocr: (_) async {
        calls++;
        return [];
      }).extract(samplePdf(2), minChars: 5);
      expect(calls, 0);
    });

    test('OCR failure keeps the text that was found', () async {
      final pages = await DocumentTextService(
          ocr: (_) async => throw Exception('no ML Kit')).extract(mixed());
      expect(pages[0].text, contains('Invoice'));
      expect(pages[1].source, TextSource.none);
    });
  });
}
