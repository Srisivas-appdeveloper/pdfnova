import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pdfnova/features/files/file_row.dart';
import 'package:pdfnova/features/files/files_tab.dart';
import 'package:pdfnova/services/file_service.dart';
import 'package:pdfnova/services/storage_service.dart';
import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sandbox = Sandbox();
  final store = StorageService.instance;
  final files = FileService.instance;
  setUp(sandbox.setUp);
  tearDown(sandbox.tearDown);

  File output(String name, [int bytes = 10]) {
    final dir = Directory('${sandbox.docs.path}/PDFNova')..createSync();
    return File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 1));
  }

  group('history', () {
    test('records every output of a run with size and a shared job', () async {
      final a = output('page_1.jpg', 100), b = output('page_2.jpg', 200);
      await store.addOutputs([a.path, b.path], 'PDF → Images');
      final h = store.history;
      expect(h.map((r) => r.path), [a.path, b.path]);
      expect(h.map((r) => r.bytes), [100, 200]);
      expect(h[0].job, isNotNull);
      expect(h[0].job, h[1].job);
    });

    test('caps at historyLimit without touching files', () async {
      final f = output('keep.pdf');
      for (var i = 0; i < StorageService.historyLimit + 5; i++) {
        await store.addOutputs(['${f.path}?$i'], 'Merge');
      }
      expect(store.history, hasLength(StorageService.historyLimit));
      expect(f.existsSync(), isTrue);
    });

    test('upgrades v1 rows (path/tool/time only) without losing any', () async {
      await Hive.close();
      final f = output('legacy.pdf', 42);
      Hive.init('${sandbox.root.path}/hive');
      final box = await Hive.openBox('recents');
      await box.put('list', [
        {'path': f.path, 'tool': 'Merge', 'time': '2026-01-02T03:04:05.000'},
        {'path': '/gone/missing.pdf', 'tool': 'Split', 'time': 'garbage'},
        {'tool': 'broken row without path'},
      ]);
      final settings = await Hive.openBox('settings');
      await settings.delete('recentsSchema');
      await Hive.close();

      await store.init(hivePath: '${sandbox.root.path}/hive');
      final h = store.history;
      expect(h, hasLength(2));
      expect(h[0].bytes, 42);
      expect(h[0].time, DateTime(2026, 1, 2, 3, 4, 5));
      expect(h[1].exists, isFalse);
      expect(h[1].bytes, isNull);
    });

    test('pruneMissing removes only rows whose file is gone', () async {
      final f = output('here.pdf');
      await store.addOutputs(['/nope/1.pdf', f.path, '/nope/2.pdf'], 'Merge');
      expect(await store.pruneMissing(), 2);
      expect(store.history.single.path, f.path);
      expect(f.existsSync(), isTrue);
    });

    test('removing a history row never deletes the file', () async {
      final f = output('stay.pdf');
      await store.addOutputs([f.path], 'Merge');
      await store.removeRecent(f.path);
      expect(store.history, isEmpty);
      expect(f.existsSync(), isTrue);
    });
  });

  group('safe file operations', () {
    test('only app outputs may be deleted', () async {
      final mine = output('mine.pdf');
      final outside = File('${sandbox.root.path}/users_original.pdf')
        ..writeAsBytesSync([1, 2, 3]);
      expect(await files.isAppOutput(mine.path), isTrue);
      expect(await files.isAppOutput(outside.path), isFalse);
      expect(await files.deleteOutput(outside.path), isFalse);
      expect(outside.existsSync(), isTrue);
      expect(await files.deleteOutput(mine.path), isTrue);
      expect(mine.existsSync(), isFalse);
    });

    test('path tricks cannot escape the output folder', () async {
      final outside = File('${sandbox.docs.path}/../escape.pdf')
        ..createSync(recursive: true);
      final sneaky = '${sandbox.docs.path}/PDFNova/../../escape.pdf';
      expect(await files.isAppOutput(sneaky), isFalse);
      expect(await files.deleteOutput(sneaky), isFalse);
      expect(outside.existsSync(), isTrue);
    });

    test('deleting an already-missing output succeeds quietly', () async {
      final f = output('ghost.pdf')..deleteSync();
      expect(await files.deleteOutput(f.path), isTrue);
    });

    test('rename keeps the extension, sanitises, and updates history',
        () async {
      final f = output('merged_123.pdf');
      await store.addOutputs([f.path], 'Merge');
      final to = await files.renameOutput(f.path, 'Tax / 2026: final');
      expect(to.split('/').last, 'Tax _ 2026_ final.pdf');
      expect(File(to).existsSync(), isTrue);
      await store.renameRecent(f.path, to);
      expect(store.history.single.path, to);
    });

    test('rename refuses to overwrite an existing file', () async {
      final a = output('a.pdf', 1), b = output('b.pdf', 2);
      await expectLater(
          files.renameOutput(a.path, 'b'), throwsA(isA<FileSystemException>()));
      expect(b.lengthSync(), 2);
      expect(a.existsSync(), isTrue);
    });

    test('rename rejects empty names and files outside app storage', () async {
      final a = output('a.pdf');
      await expectLater(files.renameOutput(a.path, '  '), throwsArgumentError);
      final outside = File('${sandbox.root.path}/x.pdf')..writeAsBytesSync([1]);
      await expectLater(
          files.renameOutput(outside.path, 'y'), throwsArgumentError);
    });
  });

  group('Files filtering', () {
    OutputRecord rec(String name, int day, int bytes) => OutputRecord(
        path: '/x/$name',
        tool: 'T',
        time: DateTime(2026, 1, day),
        bytes: bytes);
    final all = [
      rec('invoice.pdf', 1, 300),
      rec('Notes.docx', 3, 100),
      rec('slides.pptx', 2, 900),
      rec('page_1.jpg', 4, 50),
    ];

    test('search matches file names case-insensitively', () {
      expect(filterRecords(all, query: 'INVO').map((r) => r.name),
          ['invoice.pdf']);
    });

    test('filter by kind', () {
      expect(filterRecords(all, kind: FileKind.word).single.name, 'Notes.docx');
      expect(
          filterRecords(all, kind: FileKind.image).single.name, 'page_1.jpg');
    });

    test('sorts by date, name and size', () {
      expect(filterRecords(all).first.name, 'page_1.jpg');
      expect(
          filterRecords(all, sort: FileSort.oldest).first.name, 'invoice.pdf');
      expect(filterRecords(all, sort: FileSort.name).map((r) => r.name).first,
          'invoice.pdf');
      expect(filterRecords(all, sort: FileSort.size).first.name, 'slides.pptx');
    });

    test('groups by the tool that produced each file', () {
      final g = groupByTool([
        OutputRecord(path: '/a', tool: 'Merge', time: DateTime(2026)),
        OutputRecord(path: '/b', tool: 'Notes', time: DateTime(2026)),
        OutputRecord(path: '/c', tool: 'Merge', time: DateTime(2026)),
      ]);
      expect(g.map((f) => (f.title, f.items.length)),
          [('Merge', 2), ('Notes', 1)]);
      expect(g[1].tool?.title, 'Quick Notes');
    });

    test('byte formatting', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
