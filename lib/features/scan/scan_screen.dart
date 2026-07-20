import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/gradient_background.dart';
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
    return BlocProvider.value(
      value: _bloc,
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(widget.tool.title)),
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
              if (state is ToolSuccess) return SuccessView(paths: state.paths);
              if (_cancelled) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.document_scanner_rounded,
                          size: 64, color: AppColors.textLow),
                      const SizedBox(height: 16),
                      Text('Scan cancelled',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text('No pages were captured.',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 24),
                      AuroraButton(
                        label: 'Try again',
                        icon: Icons.refresh_rounded,
                        expanded: false,
                        onPressed: () {
                          setState(() => _cancelled = false);
                          _scan();
                        },
                      ),
                    ]),
                  ),
                );
              }
              // While the scanner UI is open the ramp keeps moving; once the
              // PDF is being copied the real progress shows.
              return ProcessingView(
                progress: state is ToolProcessing ? state.progress : 0.0,
                label: 'Scanner open — capture your pages',
              );
            },
          ),
        ),
      ),
    );
  }
}
