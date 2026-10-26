import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfnova/core/theme/app_theme.dart';
import 'package:pdfnova/features/files/files_tab.dart';
import 'package:pdfnova/services/document_index.dart';
import 'package:pdfnova/services/pdf_service.dart';
import 'package:pdfnova/services/storage_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../helpers.dart';

/// PDF whose pages contain the given texts.
Uint8List pdfWith(List<String> pages) {
  final doc = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final t in pages) {
    final p = doc.pages.add();
    if (t.isNotEmpty) {
      p.graphics
          .drawString(t, font, bounds: const Rect.fromLTWH(40, 40, 480, 400));
    }
  }
  final b = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sandbox = Sandbox();
  final index = DocumentIndex.instance;
  final store = StorageService.instance;
  setUp(sandbox.setUp);
  tearDown(sandbox.tearDown);

  File output(String name, List<int> bytes) {
    final d = Directory('${sandbox.docs.path}/PDFNova')..createSync();
    return File('${d.path}/$name')..writeAsBytesSync(bytes);
  }

  group('DocumentIndex', () {
    test('indexes each page with its page number', () async {
      final f = output(
          'contract.pdf',
          pdfWith([
            'Introduction',
            'Payment due within 30 days',
            'Termination clause'
          ]));
      final doc = (await index.indexFile(f.path))!;
      expect(doc.pages.map((p) => p.page), [1, 2, 3]);
      expect(doc.pages[1].text, contains('Payment due'));
    });

    test('search returns the right file, page and a highlighted snippet',
        () async {
      final f = output('contract.pdf',
          pdfWith(['Introduction', 'Payment due within 30 days', 'End']));
      await index.indexFile(f.path);
      final hits = await index.search('PAYMENT due');
      expect(hits, hasLength(1));
      expect(hits.single.path, f.path);
      expect(hits.single.page, 2);
      final h = hits.single;
      expect(h.snippet.substring(h.matchStart, h.matchStart + h.matchLength),
          'Payment due');
    });

    test('unchanged files are not re-extracted; changed files are', () async {
      final f = output('a.pdf', pdfWith(['alpha']));
      final first = (await index.indexFile(f.path))!;
      final again = (await index.indexFile(f.path))!;
      expect(again.indexedAt, first.indexedAt);
      f.writeAsBytesSync(pdfWith(['beta']));
      final changed = (await index.indexFile(f.path))!;
      expect(changed.fingerprint, isNot(first.fingerprint));
      expect(await index.search('alpha'), isEmpty);
      expect(await index.search('beta'), hasLength(1));
    });

    test('skips non-PDFs and locked PDFs; scanned pages are counted', () async {
      final txt = output('n.txt', [104, 105]);
      expect(await index.indexFile(txt.path), isNull);
      final locked =
          await PdfService.instance.protect(pdfWith(['secret']), 'pw');
      expect(await index.indexFile(locked.single), isNull);
      final scan = output('scan.pdf', pdfWith(['', 'Some real text here']));
      expect((await index.indexFile(scan.path))!.unsearchablePages, 1);
    });

    test('sync adds listed PDFs and drops unlisted or missing ones', () async {
      final a = output('a.pdf', pdfWith(['apple'])),
          b = output('b.pdf', pdfWith(['banana']));
      await index.sync([a.path, b.path]);
      expect(await index.all(), hasLength(2));
      b.deleteSync();
      final r = await index.sync([a.path, b.path]);
      expect(r.removed, 1);
      await index.sync([]);
      expect(await index.all(), isEmpty);
    });

    test('clear deletes all indexed text', () async {
      await index.indexFile(output('a.pdf', pdfWith(['apple'])).path);
      await index.clear();
      expect(await index.all(), isEmpty);
      expect(await index.search('apple'), isEmpty);
    });

    test('a corrupt index entry is ignored, not fatal', () async {
      final f = output('a.pdf', pdfWith(['apple']));
      await index.indexFile(f.path);
      final support = Directory('${sandbox.root.path}/support/content_index');
      for (final e in support.listSync().whereType<File>()) {
        e.writeAsStringSync('{not json');
      }
      expect(await index.read(f.path), isNull);
      expect(await index.search('apple'), isEmpty);
      expect((await index.indexFile(f.path))!.pages, isNotEmpty);
    });
  });

  group('kept in step with history', () {
    test('off by default: outputs are not indexed', () async {
      final f = output('a.pdf', pdfWith(['apple']));
      await store.addOutputs([f.path], 'Merge');
      expect(store.contentIndexing.value, isFalse);
      expect(await index.all(), isEmpty);
    });

    test('on: add, rename, remove and prune update the index', () async {
      final a = output('a.pdf', pdfWith(['apple pie']));
      expect(await store.setContentIndexing(true), 0);
      await store.addOutputs([a.path], 'Merge');
      expect(await index.search('apple'), hasLength(1));

      final renamed = '${a.parent.path}/renamed.pdf';
      a.renameSync(renamed);
      await store.renameRecent(a.path, renamed);
      expect((await index.search('apple')).single.path, renamed);

      await store.removeRecents({renamed});
      expect(await index.all(), isEmpty);
      expect(File(renamed).existsSync(), isTrue,
          reason: 'removing from history never deletes the file');
    });

    test('turning it on indexes existing history; off deletes it', () async {
      final a = output('a.pdf', pdfWith(['apple']));
      await store.addOutputs([a.path], 'Merge');
      expect(await store.setContentIndexing(true), 1);
      expect(await index.search('apple'), hasLength(1));
      await store.setContentIndexing(false);
      expect(await index.all(), isEmpty);
    });

    test('pruning missing files removes their index entries', () async {
      final a = output('a.pdf', pdfWith(['apple']));
      await store.setContentIndexing(true);
      await store.addOutputs([a.path], 'Merge');
      a.deleteSync();
      await store.pruneMissing();
      expect(await index.all(), isEmpty);
    });
  });

  testWidgets('Files shows name matches and "Inside files" separately',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final f = output('invoice_march.pdf',
          pdfWith(['Header', 'Total payable 4,500 by 30 June']));
      await store.setContentIndexing(true);
      await store.addOutputs([f.path], 'Merge');
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: FilesTab(onBrowseTools: () {})),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All files'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'payable');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('FILE NAMES'), findsOneWidget);
    expect(find.text('No file names match'), findsOneWidget);
    expect(find.text('INSIDE FILES'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('invoice_march.pdf'), findsOneWidget);
  });
}
