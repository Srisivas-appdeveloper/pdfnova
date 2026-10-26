import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfnova/features/home/tools.dart';
import 'package:pdfnova/features/tool/tool_bloc.dart';
import 'package:pdfnova/services/storage_service.dart';
import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sandbox = Sandbox();
  setUp(sandbox.setUp);
  tearDown(sandbox.tearDown);
  final tool = allTools.firstWhere((t) => t.id == ToolId.merge);

  Future<List<ToolState>> run(Future<List<String>> Function() task) async {
    final bloc = ToolBloc();
    final states = <ToolState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(ToolStarted(tool, task));
    await bloc.stream.firstWhere(
        (s) => s is ToolSuccess || s is ToolFailure || s is ToolIdle);
    await sub.cancel();
    await bloc.close();
    return states;
  }

  test('success records every output in history and carries notes', () async {
    final f = File('${sandbox.docs.path}/PDFNova/out.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final states = await run(() async {
      ToolNotes.add('heads-up');
      return [f.path];
    });
    final done = states.last as ToolSuccess;
    expect(done.paths, [f.path]);
    expect(done.notes, ['heads-up']);
    expect(StorageService.instance.history.single.tool, 'Merge');
    // No measured progress was reported, so none may be shown.
    expect(states.whereType<ToolProcessing>().map((s) => s.progress),
        everyElement(isNull));
  });

  test('wrong password maps to a helpful message', () async {
    final states = await run(() async => throw Exception('Invalid password'));
    expect((states.last as ToolFailure).message, contains('password'));
  });

  test('no text maps to its own message', () async {
    final states = await run(() async => throw Exception('NoText: nothing'));
    expect((states.last as ToolFailure).message, contains('No readable text'));
  });

  test('anything else gets a calm generic message, not a stack trace',
      () async {
    final states =
        await run(() async => throw const FileSystemException('disk full'));
    final msg = (states.last as ToolFailure).message;
    expect(msg, contains('Something went wrong'));
    expect(msg, isNot(contains('FileSystemException')));
  });

  test('a cancelled task (no outputs) returns to input, records nothing',
      () async {
    final states = await run(() async => <String>[]);
    expect(states.last, isA<ToolIdle>());
    expect(StorageService.instance.history, isEmpty);
  });

  test('ToolNotes outside a run are ignored', () {
    expect(() => ToolNotes.add('nobody listening'), returnsNormally);
  });
}
