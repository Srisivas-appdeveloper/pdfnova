import 'dart:io';
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfnova/core/theme/app_theme.dart';
import 'package:pdfnova/features/home/home_shell.dart';
import 'package:pdfnova/features/home/tools.dart';
import 'package:pdfnova/features/tool/tool_screen.dart';
import 'package:pdfnova/services/storage_service.dart';
import '../helpers.dart';

Widget host(Widget child,
        {ThemeMode mode = ThemeMode.light, double textScale = 1}) =>
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child,
        ),
      ),
    );

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75; // ~393 dp wide, a common phone
  addTearDown(tester.view.reset);
}

void main() {
  final sandbox = Sandbox();
  setUp(sandbox.setUp);
  tearDown(sandbox.tearDown);

  Future<void> seedHistory(WidgetTester tester) => tester.runAsync(() async {
        final dir = Directory('${sandbox.docs.path}/PDFNova')
          ..createSync(recursive: true);
        final f = File('${dir.path}/merged_report_for_the_quarter.pdf')
          ..writeAsBytesSync(samplePdf(1));
        await StorageService.instance.addOutputs([f.path], 'Merge');
      });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('no overflow at ${scale}x text, ${mode.name} — all tabs',
          (tester) async {
        phone(tester);
        await seedHistory(tester);
        await tester
            .pumpWidget(host(const HomeShell(), mode: mode, textScale: scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Tools tab');

        await tester.tap(find.text('Files'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Files (by tool)');
        await tester.tap(find.text('All files'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Files (all)');

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Settings');
      });
    }
  }

  for (final id in [
    ToolId.unlock,
    ToolId.compressTarget,
    ToolId.split,
    ToolId.stamp,
    ToolId.pdfToWord
  ]) {
    testWidgets('tool screen fits at 2x text: ${id.name}', (tester) async {
      phone(tester);
      final tool = allTools.firstWhere((t) => t.id == id);
      await tester.pumpWidget(host(ToolScreen(tool: tool), textScale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduce motion: cards open with a fade, not a growing card',
      (tester) async {
    // Regression: OpenContainer ignored the setting and only ran faster.
    phone(tester);
    await tester.pumpWidget(host(const HomeShell())); // disableAnimations
    await tester.pumpAndSettle();
    expect(find.byType(OpenContainer), findsNothing);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    expect(find.text('Combine PDFs into one'), findsWidgets);
    expect(find.text('Choose a PDF'), findsOneWidget, reason: 'tool opened');
  });

  testWidgets('rename dialog focuses the name field (regression)',
      (tester) async {
    phone(tester);
    await seedHistory(tester);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All files'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.descendant(
        of: find.byType(Dialog), matching: find.byType(TextField)));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'merged_report_for_the_quarter',
        reason: 'extension is kept out of the editable name');
  });

  testWidgets('delete asks first and states originals are unaffected',
      (tester) async {
    phone(tester);
    await seedHistory(tester);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All files'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Remove from history'), findsOneWidget);
    expect(find.text('The file stays on your phone'), findsOneWidget);
    await tester.tap(find.text('Delete file'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this file?'), findsOneWidget);
    expect(find.textContaining('are not affected'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(StorageService.instance.history, hasLength(1));
  });

  testWidgets('long-press enters multi-select with an action bar',
      (tester) async {
    phone(tester);
    await seedHistory(tester);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All files'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('merged_report_for_the_quarter.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
  });
}
