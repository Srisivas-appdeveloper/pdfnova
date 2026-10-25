import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../home/tools.dart';
import '../tool/tool_bloc.dart';
import '../tool/processing_view.dart';
import '../tool/success_view.dart';

/// Scan: launches Google's on-device document scanner (auto edge detection,
/// cleanup filters, multi-page) and saves the returned PDF into our output
/// folder. Android only — the tool is hidden from the grid on iOS.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.tool});
  final Tool tool;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final ToolBloc _bloc = ToolBloc();
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  void _scan() {
    _bloc.add(ToolStarted(widget.tool, () async {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.pdf,
          mode: ScannerMode.filter,
          pageLimit: 50,
          isGalleryImport: true,
        ),
      );
      try {
        final result = await scanner.scanDocument();
        final srcUri = result.pdf?.uri;
        if (srcUri == null) return <String>[];
        // Use Uri.parse().toFilePath() — handles both file:// and raw paths
        final srcPath = Uri.parse(srcUri).toFilePath();
        final dir = await getApplicationDocumentsDirectory();
        final out = Directory('${dir.path}/PDFNova')..createSync(recursive: true);
        final dest =
            '${out.path}/scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await File(srcPath).copy(dest);
        return [dest];
      } catch (e) {
        if (e is PlatformException) {
          // User pressed back/cancelled camera scan
          return <String>[];
        }
        rethrow;
      } finally {
        scanner.close();
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        backgroundColor: c.canvas,
        appBar: AppBar(),
        body: BlocConsumer<ToolBloc, ToolState>(
          listener: (context, state) {
            // Cancel returns [] → ToolIdle; failures land here too. Either
            // way the user ends on a retry screen, not a stuck fake spinner
            // or a silent pop.
            if (state is ToolFailure) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.message)));
              setState(() => _cancelled = true);
            }
            if (state is ToolIdle) setState(() => _cancelled = true);
          },
          builder: (context, state) {
            final Widget stage;
            if (state is ToolSuccess) {
              stage = SuccessView(key: const ValueKey('s'), paths: state.paths);
            } else if (_cancelled) {
              stage = Center(
                key: const ValueKey('c'),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    NovaIconTile(
                        icon: Icons.document_scanner_outlined,
                        fg: c.inkMid,
                        bg: c.surfaceAlt,
                        size: 72),
                    const SizedBox(height: 20),
                    Text('Scan cancelled', style: t.headlineMedium),
                    const SizedBox(height: 6),
                    Text('No pages were captured.', style: t.bodyMedium),
                    const SizedBox(height: 26),
                    NovaButton(
                      label: 'Try again',
                      icon: Icons.refresh_rounded,
                      expanded: false,
                      onPressed: () {
                        setState(() => _cancelled = false);
                        _scan();
                      },
                    ),
                  ]).enter(context),
                ),
              );
            } else {
              // While the scanner UI is open the ramp keeps moving; once the
              // PDF is being copied the real progress shows.
              stage = ProcessingView(
                key: const ValueKey('p'),
                progress: state is ToolProcessing ? state.progress : 0.0,
                label: 'Scanner open — capture your pages',
              );
            }
            return AnimatedSwitcher(
              duration: NovaMotion.page,
              switchInCurve: NovaMotion.emphasized,
              child: stage,
            );
          },
        ),
      ),
    );
  }
}
