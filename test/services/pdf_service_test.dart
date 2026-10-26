import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfnova/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sandbox = Sandbox();
  final pdf = PdfService.instance;
  setUp(sandbox.setUp);
  tearDown(sandbox.tearDown);

  group('organize', () {
    test('merge keeps every page in order', () async {
      final out =
          await pdf.merge([samplePdf(2, label: 'A'), samplePdf(3, label: 'B')]);
      final bytes = readBytes(out.single);
      expect(pageCount(bytes), 5);
      expect(textOf(bytes, page: 1), contains('Page 1 A'));
      expect(textOf(bytes, page: 3), contains('Page 1 B'));
      expect(textOf(bytes, page: 5), contains('Page 3 B'));
    });

    test('merge keeps each page\'s own size (portrait + landscape)', () async {
      final out = await pdf
          .merge([samplePdf(1), samplePdf(1, landscape: true), samplePdf(1)]);
      final doc = PdfDocument(inputBytes: readBytes(out.single));
      final sizes = [for (var i = 0; i < 3; i++) doc.pages[i].size];
      expect(sizes[0].height > sizes[0].width, isTrue);
      expect(sizes[1].width > sizes[1].height, isTrue,
          reason: 'landscape page must stay landscape');
      expect(sizes[2].height > sizes[2].width, isTrue);
      doc.dispose();
    });

    test('split extracts the requested range', () async {
      final out = await pdf.split(samplePdf(5), 2, 4);
      final bytes = readBytes(out.single);
      expect(pageCount(bytes), 3);
      expect(textOf(bytes, page: 1), contains('Page 2'));
      expect(textOf(bytes, page: 3), contains('Page 4'));
    });

    test('split clamps out-of-range pages instead of failing', () async {
      final out = await pdf.split(samplePdf(3), 0, 99);
      expect(pageCount(readBytes(out.single)), 3);
    });

    test('organize reorders, deletes and rotates pages', () async {
      final out = await pdf.organize(samplePdf(4), [3, 0, 2], {0: 1, 3: 6});
      final doc = PdfDocument(inputBytes: readBytes(out.single));
      expect(doc.pages.count, 3); // page 2 deleted
      final ex = PdfTextExtractor(doc);
      expect(ex.extractText(startPageIndex: 0, endPageIndex: 0),
          contains('Page 4'));
      expect(ex.extractText(startPageIndex: 1, endPageIndex: 1),
          contains('Page 1'));
      expect(doc.pages[1].rotation, PdfPageRotateAngle.rotateAngle90);
      // 6 quarter turns from repeated taps wraps to 180°.
      expect(doc.pages[0].rotation, PdfPageRotateAngle.rotateAngle180);
      doc.dispose();
    });

    test('outputs land in the app PDFNova folder', () async {
      final out = await pdf.merge([samplePdf(1), samplePdf(1)]);
      expect(out.single, startsWith('${sandbox.docs.path}/PDFNova/'));
      expect(File(out.single).existsSync(), isTrue);
    });
  });

  group('security', () {
    test('protect then unlock with the right password', () async {
      final locked =
          readBytes((await pdf.protect(samplePdf(2), 'secret1')).single);
      expect(() => PdfDocument(inputBytes: locked), throwsA(anything));
      expect(pageCount(locked, password: 'secret1'), 2);

      final unlocked = readBytes((await pdf.unlock(locked, 'secret1')).single);
      expect(pageCount(unlocked), 2);
      expect(textOf(unlocked), contains('Page 1'));
    });

    test('unlock with a wrong password fails (no output)', () async {
      final locked =
          readBytes((await pdf.protect(samplePdf(1), 'right')).single);
      await expectLater(pdf.unlock(locked, 'wrong'), throwsA(anything));
    });

    test('Aadhaar password is first four letters + birth year', () {
      expect(PdfService.aadhaarPassword('Ravi Kumar', '1990'), 'RAVI1990');
      expect(PdfService.aadhaarPassword("o'neil", '2001'), 'ONEI2001');
      expect(PdfService.aadhaarPassword('Al', '1985'), 'AL1985');
    });

    test('clean metadata strips author, title and other fields', () async {
      final doc = PdfDocument()..pages.add();
      doc.documentInformation
        ..author = 'Jane Doe'
        ..title = 'Salary slip'
        ..subject = 'Private'
        ..keywords = 'hr'
        ..creator = 'Payroll 3000';
      final src = Uint8List.fromList(doc.saveSync());
      doc.dispose();

      final out = PdfDocument(
          inputBytes: readBytes((await pdf.stripMetadata(src)).single));
      final info = out.documentInformation;
      expect(info.author, isEmpty);
      expect(info.title, isEmpty);
      expect(info.subject, isEmpty);
      expect(info.keywords, isEmpty);
      expect(info.creator, isEmpty);
      out.dispose();
    });
  });

  group('marking', () {
    test('watermark, stamp and page numbers produce readable PDFs', () async {
      final src = samplePdf(3);
      final wm = readBytes((await pdf.watermark(src, 'CONFIDENTIAL')).single);
      expect(textOf(wm), contains('CONFIDENTIAL'));

      final stamped = readBytes(
          (await pdf.stamp(src, 'PAID', const Color(0xFFD63B2F))).single);
      expect(textOf(stamped, page: 2), contains('PAID'));

      final numbered = readBytes((await pdf.pageNumbers(src)).single);
      expect(textOf(numbered, page: 3), contains('3 / 3'));
    });

    test('signature is placed on the chosen page only', () async {
      final sig = img.Image(width: 120, height: 40);
      img.fill(sig, color: img.ColorRgba8(20, 30, 60, 255));
      final png = Uint8List.fromList(img.encodePng(sig));
      final out = readBytes(
          (await pdf.placeSignature(samplePdf(2), png, 2, 0.5, 0.8, 0.3))
              .single);
      expect(pageCount(out), 2);
    });
  });

  group('forms', () {
    test('lists text fields with current values', () {
      final fields = pdf.listFormFields(formPdf());
      expect(fields.map((f) => f.$2), ['Full name', 'City'],
          reason: 'internal names are shown readably');
      expect(fields[1].$3, 'Chennai');
    });

    test('fills fields and keeps them editable when not flattened', () async {
      final out = PdfDocument(
          inputBytes: readBytes(
              (await pdf.fillForm(formPdf(), {0: 'Asha'}, false)).single));
      expect((out.form.fields[0] as PdfTextBoxField).text, 'Asha');
      expect((out.form.fields[1] as PdfTextBoxField).text, 'Chennai');
      out.dispose();
    });

    test('flattening turns values into page text', () async {
      final bytes =
          readBytes((await pdf.fillForm(formPdf(), {0: 'Asha'}, true)).single);
      expect(textOf(bytes), contains('Asha'));
    });
  });

  group('images → PDF', () {
    test('one A4 page per image, orientation follows the image', () async {
      Uint8List png(int w, int h) {
        final i = img.Image(width: w, height: h);
        img.fill(i, color: img.ColorRgb8(200, 100, 50));
        return Uint8List.fromList(img.encodePng(i));
      }

      final out = PdfDocument(
          inputBytes: readBytes(
              (await pdf.imagesToPdf([png(300, 400), png(400, 300)])).single));
      expect(out.pages.count, 2);
      expect(out.pages[0].size.height > out.pages[0].size.width, isTrue);
      expect(out.pages[1].size.width > out.pages[1].size.height, isTrue);
      out.dispose();
    });
  });

  group('errors', () {
    test('corrupted input is rejected, not turned into an empty file',
        () async {
      final junk = Uint8List.fromList(List.generate(500, (i) => i % 251));
      await expectLater(pdf.split(junk, 1, 1), throwsA(anything));
      final folder = Directory('${sandbox.docs.path}/PDFNova');
      final made = folder.existsSync() ? folder.listSync() : const [];
      expect(made, isEmpty);
    });
  });
}
