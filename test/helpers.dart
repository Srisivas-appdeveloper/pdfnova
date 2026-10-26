import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;
import 'package:hive/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdfnova/services/pdf_service.dart';
import 'package:pdfnova/services/storage_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Points path_provider at a throwaway directory.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.root);
  final Directory root;

  Directory _sub(String name) =>
      Directory('${root.path}/$name')..createSync(recursive: true);

  @override
  Future<String?> getApplicationDocumentsPath() async => _sub('docs').path;
  @override
  Future<String?> getTemporaryPath() async => _sub('tmp').path;
  @override
  Future<String?> getApplicationSupportPath() async => _sub('support').path;
  @override
  Future<String?> getApplicationCachePath() async => _sub('cache').path;
}

/// Fresh temp sandbox with fake app directories and a Hive store.
class Sandbox {
  late Directory root;
  late Directory docs;

  Future<void> setUp() async {
    PdfService.runInline = true;
    root = Directory.systemTemp.createTempSync('pdfnova_test_');
    PathProviderPlatform.instance = FakePathProvider(root);
    docs = Directory(
        (await PathProviderPlatform.instance.getApplicationDocumentsPath())!);
    await StorageService.instance.init(hivePath: '${root.path}/hive');
  }

  Future<void> tearDown() async {
    await Hive.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// A PDF whose page N contains the text "Page N <label>".
Uint8List samplePdf(int pages,
    {String label = 'sample', bool landscape = false}) {
  final doc = PdfDocument();
  if (landscape) doc.pageSettings.orientation = PdfPageOrientation.landscape;
  final font = PdfStandardFont(PdfFontFamily.helvetica, 14);
  for (var i = 1; i <= pages; i++) {
    doc.pages.add().graphics.drawString('Page $i $label', font,
        bounds: const Offset(40, 40) & const Size(400, 40));
  }
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

/// A one-page AcroForm: empty `full_name`, and `city` = "Chennai".
Uint8List formPdf() {
  final doc = PdfDocument();
  final page = doc.pages.add();
  doc.form.fields.add(
      PdfTextBoxField(page, 'full_name', const Rect.fromLTWH(40, 40, 200, 24)));
  doc.form.fields.add(PdfTextBoxField(
      page, 'city', const Rect.fromLTWH(40, 80, 200, 24),
      text: 'Chennai'));
  final b = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return b;
}

/// Text via line extraction — the same path the app uses (Syncfusion's
/// plain extractText() mis-decodes text after a font switch).
String textOf(Uint8List pdf, {int? page}) {
  final doc = PdfDocument(inputBytes: pdf);
  final ex = PdfTextExtractor(doc);
  final lines = page == null
      ? ex.extractTextLines()
      : ex.extractTextLines(startPageIndex: page - 1, endPageIndex: page - 1);
  doc.dispose();
  return lines.map((l) => l.text).join('\n');
}

int pageCount(Uint8List pdf, {String? password}) {
  final doc = PdfDocument(inputBytes: pdf, password: password);
  final n = doc.pages.count;
  doc.dispose();
  return n;
}

Uint8List readBytes(String path) => File(path).readAsBytesSync();
