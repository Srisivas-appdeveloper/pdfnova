import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfnova/features/batch/batch_screen.dart';
import 'package:pdfnova/features/home/tools.dart';
import 'package:pdfnova/features/tool/tool_bloc.dart';
import 'package:pdfnova/features/tool/tool_screen.dart';
import 'package:pdfnova/services/file_service.dart';
import 'package:pdfnova/services/pdf_service.dart';
import 'package:pdfnova/services/storage_service.dart';
import 'package:pdfnova/services/tool_errors.dart';
import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sandbox = Sandbox();
  final pdf = PdfService.instance;
  setUp(sandbox.setUp);
  tearDown(sandbox.tearDown);

  List<FileSystemEntity> outputs() {
    final d = Directory('${sandbox.docs.path}/PDFNova');
    return d.existsSync() ? d.listSync() : [];
  }

  group('input validation', () {
    test('split with From after To explains the problem', () async {
      await expectLater(
          pdf.split(samplePdf(5), 4, 2),
          throwsA(isA<UserFacingError>().having(
              (e) => e.message, 'message', contains('"From" page (4)'))));
      expect(outputs(), isEmpty);
    });

    test('split starting past the last page says how many pages exist',
        () async {
      await expectLater(
          pdf.split(samplePdf(3), 7, 9),
          throwsA(isA<UserFacingError>()
              .having((e) => e.message, 'message', contains('only 3 pages'))));
    });

    test('a locked PDF given to merge is reported as locked, not corrupt',
        () async {
      final locked =
          readBytes((await pdf.protect(samplePdf(1), 'pw12')).single);
      Object? error;
      try {
        await pdf.merge([locked, samplePdf(1)]);
      } catch (e) {
        error = e;
      }
      expect(describeToolError(error!), contains('Unlock it first'));
    });
  });

  group('verified, atomic outputs', () {
    test('no temp (.part) files remain after successful operations', () async {
      await pdf.merge([samplePdf(2), samplePdf(1)]);
      await pdf.watermark(samplePdf(1), 'X');
      await pdf.pdfToText(samplePdf(2));
      expect(outputs().where((f) => f.path.endsWith('.part')), isEmpty);
      expect(outputs(), hasLength(3));
    });

    test('outputs carry no earlier revision of the source', () async {
      // Regression: incremental saves kept the clean original inside the
      // watermarked file; cutting at the first %%EOF removed the watermark.
      for (final out in [
        await pdf.watermark(samplePdf(2), 'DRAFT'),
        await pdf.pageNumbers(samplePdf(2)),
        await pdf.fillForm(formPdf(), {0: 'Asha'}, true),
      ]) {
        final raw = latin1.decode(readBytes(out.single));
        expect('%%EOF'.allMatches(raw).length, 1);
      }
    });

    test('protect output is verified to need the password', () async {
      final out = readBytes((await pdf.protect(samplePdf(2), 'secret')).single);
      expect(pageCount(out, password: 'secret'), 2);
    });

    test('verifyPdf rejects garbage and wrong page counts', () {
      expect(() => PdfService.verifyPdf([1, 2, 3]),
          throwsA(isA<UserFacingError>()));
      expect(() => PdfService.verifyPdf(samplePdf(2), expectedPages: 3),
          throwsA(isA<UserFacingError>()));
      expect(() => PdfService.verifyPdf(samplePdf(2), expectedPages: 2),
          returnsNormally);
    });

    test('writeAtomic leaves nothing behind when the write fails', () async {
      final dir = Directory('${sandbox.root.path}/ro')..createSync();
      Process.runSync('chmod', ['555', dir.path]);
      addTearDown(() => Process.runSync('chmod', ['755', dir.path]));
      await expectLater(
          writeAtomic('${dir.path}/out.pdf', [1, 2, 3]), throwsA(anything));
      Process.runSync('chmod', ['755', dir.path]);
      expect(dir.listSync(), isEmpty);
    });

    test('writeAtomic replaces only on success', () async {
      final path = '${sandbox.root.path}/a.bin';
      await writeAtomic(path, [1, 2, 3]);
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      expect(File('$path.part').existsSync(), isFalse);
    });
  });

  group('fit to size', () {
    // Regression: a 6 KB text PDF with a 500 KB target came back as a
    // 456 KB image-only PDF reported as a success.
    test('a PDF already under the target is not rasterised or enlarged',
        () async {
      final input = samplePdf(3, label: 'lease');
      final notes = <String>[];
      final out = await ToolNotes.collect(
          notes, () => pdf.compressToTarget(input, 500 * 1024));
      final bytes = readBytes(out.single);
      expect(bytes.length, lessThanOrEqualTo(input.length));
      expect(textOf(bytes, page: 2), contains('Page 2 lease'));
      expect(notes, contains(contains('under your 500 KB target')));
      expect(notes, contains('Text is kept sharp and selectable.'));
    });
  });

  test('form field labels are readable', () {
    expect(fieldLabel('full_name'), 'Full name');
    expect(fieldLabel('dob'), 'Date of birth');
    expect(fieldLabel('form1[0].page1[0].homeAddress[0]'), 'Home address');
    expect(fieldLabel('x_1', 'Applicant name'), 'Applicant name');
    expect(fieldLabel(''), isNull);
  });

  group('error messages', () {
    test('unlock tool gets the Aadhaar hint, other tools the unlock hint', () {
      final e = Exception('Cannot open an encrypted document without password');
      expect(
          describeToolError(e, isUnlockTool: true), contains('name spelling'));
      expect(describeToolError(e), contains('Unlock it first'));
    });

    test('user-facing errors are shown verbatim', () {
      expect(describeToolError(const UserFacingError('Exact text.')),
          'Exact text.');
    });

    test('out of storage is named, never a stack trace', () {
      const e = FileSystemException(
          'write failed', '/x', OSError('No space left on device', 28));
      final msg = describeToolError(e);
      expect(msg, contains('out of storage'));
      expect(msg, isNot(contains('/x')));
    });

    test('unknown errors stay calm and generic', () {
      final msg = describeToolError(StateError('internal detail 0xdead'));
      expect(msg, contains('Something went wrong'));
      expect(msg, isNot(contains('0xdead')));
    });
  });

  group('batch', () {
    final files = [
      PickedPdf('good1.pdf', samplePdf(1)),
      PickedPdf('broken.pdf', Uint8List.fromList([1, 2, 3])),
      PickedPdf('good2.pdf', samplePdf(2)),
    ];

    test('one bad file does not cost the others; failure is named', () async {
      final notes = <String>[];
      final progress = <String?>[];
      final out = await ToolNotes.collect(
          notes,
          () => ToolProgress.track((_, stage) => progress.add(stage),
              () => runBatch(files, (b) => pdf.watermark(b, 'X'))));
      expect(out, hasLength(2));
      expect(notes.single, contains('2 of 3 files done'));
      expect(notes.single, contains('broken.pdf'));
      expect(progress, ['File 1 of 3', 'File 2 of 3', 'File 3 of 3', 'Done']);
    });

    test('outputs are named after their source files, never overwriting',
        () async {
      final out = await runBatch(
          [files[0], PickedPdf('good1.pdf', samplePdf(3))],
          (b) => pdf.watermark(b, 'X'));
      final names = out.map((p) => p.split('/').last).toList();
      expect(names[0], matches(RegExp(r'^good1_[a-z]+\.pdf$')));
      expect(names[1], names[0].replaceFirst('.pdf', '_2.pdf'),
          reason: 'same source name twice gets a suffix');
      expect(pageCount(readBytes(out[1])), 3);
    });

    test('all files failing is an error, not an empty success', () async {
      await expectLater(runBatch([files[1]], (b) => pdf.watermark(b, 'X')),
          throwsA(isA<UserFacingError>()));
    });
  });

  group('split page count', () {
    // Regression: the first version captured `this` in its isolate closure
    // and silently failed on device.
    test('counts pages off the UI isolate', () async {
      expect(await countPdfPages(samplePdf(4)), 4);
    });

    test('locked or broken PDFs report -1', () async {
      final locked =
          readBytes((await pdf.protect(samplePdf(1), 'pw12')).single);
      expect(await countPdfPages(locked), -1);
      expect(await countPdfPages(Uint8List.fromList([1, 2, 3])), -1);
    });
  });

  group('tool runs', () {
    final tool = allTools.firstWhere((t) => t.id == ToolId.batch);

    test('progress is only what the task reports — no invented numbers',
        () async {
      final bloc = ToolBloc();
      final states = <ToolState>[];
      final sub = bloc.stream.listen(states.add);
      final f = File('${sandbox.docs.path}/PDFNova/r.pdf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(samplePdf(1));
      bloc.add(ToolStarted(tool, () async {
        ToolProgress.report(0.5, stage: 'Half');
        return [f.path];
      }));
      await bloc.stream.firstWhere((s) => s is ToolSuccess);
      await sub.cancel();
      await bloc.close();
      final p = states.whereType<ToolProcessing>().toList();
      expect(p.first.progress, isNull, reason: 'starts indeterminate');
      expect(p.map((s) => s.progress), containsAllInOrder([null, 0.5]));
      expect(p.last.stage, 'Half');
      expect(StorageService.instance.history.single.path, f.path);
    });
  });
}
