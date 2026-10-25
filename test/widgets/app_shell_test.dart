import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfnova/app.dart';
import 'package:pdfnova/core/theme/app_colors.dart';
import 'package:pdfnova/core/theme/app_motion.dart';
import 'package:pdfnova/core/theme/app_theme.dart';
import 'package:pdfnova/features/home/home_shell.dart';
import 'package:pdfnova/services/storage_service.dart';
import '../helpers.dart';

/// Hosts a widget inside the real light/dark themes.
Widget host(Widget child,
        {ThemeMode mode = ThemeMode.light, bool reduce = false}) =>
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: child,
      ),
    );

void main() {
  final sandbox = Sandbox();
  setUp(sandbox.setUp);
  tearDown(sandbox.tearDown);

  group('theme', () {
    test('light and dark themes carry their own Folio tokens', () {
      expect(AppTheme.light.extension<NovaColors>(), same(NovaColors.light));
      expect(AppTheme.dark.extension<NovaColors>(), same(NovaColors.dark));
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.scaffoldBackgroundColor, NovaColors.light.canvas);
    });

    testWidgets('changing the setting re-themes the app and persists',
        (tester) async {
      await tester.pumpWidget(const PdfNovaApp());
      await tester
          .runAsync(() => StorageService.instance.setThemeMode(ThemeMode.dark));
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);

      // Re-open storage: the choice survives a restart.
      await tester.runAsync(() =>
          StorageService.instance.init(hivePath: '${sandbox.root.path}/hive'));
      expect(StorageService.instance.themeMode.value, ThemeMode.dark);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3)); // let splash timers end
    });
  });

  group('reduce motion', () {
    testWidgets('follows the system setting', (tester) async {
      late bool reduced;
      await tester.pumpWidget(host(Builder(builder: (c) {
        reduced = NovaMotion.reduced(c);
        return const SizedBox();
      }), reduce: true));
      expect(reduced, isTrue);
    });

    testWidgets('follows the in-app setting', (tester) async {
      late bool reduced;
      await tester
          .runAsync(() => StorageService.instance.setReduceMotion(true));
      await tester.pumpWidget(host(Builder(builder: (c) {
        reduced = NovaMotion.reduced(c);
        return const SizedBox();
      })));
      expect(reduced, isTrue);
      await tester
          .runAsync(() => StorageService.instance.setReduceMotion(false));
    });

    testWidgets('is off by default', (tester) async {
      late bool reduced;
      await tester.pumpWidget(host(Builder(builder: (c) {
        reduced = NovaMotion.reduced(c);
        return const SizedBox();
      })));
      expect(reduced, isFalse);
    });
  });

  group('navigation', () {
    testWidgets('tabs switch between Tools, Files and Settings',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const HomeShell(), reduce: true));
      await tester.pumpAndSettle();
      // 26 on Android, 25 elsewhere (Scan is Android-only).
      expect(
          find.textContaining(RegExp(r'Search 2[56] tools')), findsOneWidget);

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      expect(find.text('No files yet'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Reduce motion'), findsOneWidget);
      expect(find.text('Everything runs on this phone'), findsOneWidget);
    });

    testWidgets('search filters tools and shows an empty state',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const HomeShell(), reduce: true));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'merge');
      await tester.pumpAndSettle();
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Split'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No tool matches'), findsOneWidget);
    });

    testWidgets('Files shows history with missing-file cleanup',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.runAsync(
          () => StorageService.instance.addOutputs(['/gone/old.pdf'], 'Merge'));
      await tester.pumpWidget(host(const HomeShell(), reduce: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      expect(find.text('Clean up 1'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Clean up 1'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(StorageService.instance.history, isEmpty);
    });

    testWidgets('dark theme renders the shell without errors', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          host(const HomeShell(), mode: ThemeMode.dark, reduce: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
