import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:signature/signature.dart' as sig;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/gradient_background.dart';
import '../../services/file_service.dart';
import '../../services/pdf_service.dart';
import '../../services/raster_service.dart';
import '../home/tools.dart';
import '../tool/tool_bloc.dart';
import '../tool/processing_view.dart';
import '../tool/success_view.dart';

/// Sign flow: draw → pick page → drag the signature on a live page preview
/// → pinch-free resize with a slider → place. Preview coordinates map 1:1
/// to PDF coordinates (relative centre + relative width).
class SignatureScreen extends StatelessWidget {
  const SignatureScreen({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ToolBloc(),
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(tool.title)),
          body: BlocConsumer<ToolBloc, ToolState>(
            listener: (context, state) {
              if (state is ToolFailure) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message)));
              }
            },
            builder: (context, state) => PopScope(
              canPop: state is! ToolProcessing,
              child: switch (state) {
                ToolProcessing s => ProcessingView(
                    progress: s.progress, label: 'Placing your signature'),
                ToolSuccess s => SuccessView(paths: s.paths),
                _ => _SignFlow(tool: tool),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SignFlow extends StatefulWidget {
  const _SignFlow({required this.tool});
  final Tool tool;

  @override
  State<_SignFlow> createState() => _SignFlowState();
}

class _SignFlowState extends State<_SignFlow> {
  final _controller = sig.SignatureController(
    penStrokeWidth: 3.5,
    penColor: const Color(0xFF16233F),
    exportBackgroundColor: Colors.transparent,
  );
  Uint8List? _pdf;
  Uint8List? _signature;
  Uint8List? _pagePreview;
  int _pageCount = 1;
  int _page = 1;
  // Signature centre as fraction of preview, and width fraction.
  double _relX = 0.7, _relY = 0.8, _relW = 0.34;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final picked = await FileService.instance.pickPdfs();
    if (picked.isEmpty) return;
    _pdf = picked.first.bytes;
    _pageCount = await RasterService.instance.pageCount(_pdf!);
    await _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    final preview =
        await RasterService.instance.renderPage(_pdf!, page, scale: 1.5);
    setState(() {
      _page = page;
      _pagePreview = preview;
    });
  }

  Future<void> _captureSignature() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw your signature first')),
      );
      return;
    }
    final png = await _controller.toPngBytes();
    if (png != null) {
      setState(() => _signature = png);
    }
  }

  void _place() {
    context.read<ToolBloc>().add(ToolStarted(
          widget.tool,
          () => PdfService.instance
              .placeSignature(_pdf!, _signature!, _page, _relX, _relY, _relW),
        ));
  }

  @override
  Widget build(BuildContext context) {
    // Stage 1: draw
    if (_signature == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text('Draw your signature',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          GlassCard(
            strong: true,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                color: Colors.white,
                height: 220,
                child: sig.Signature(
                    controller: _controller,
                    backgroundColor: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            TextButton(
              onPressed: _controller.clear,
              child: const Text('Clear',
                  style: TextStyle(color: AppColors.cyan)),
            ),
            const Spacer(),
          ]),
          const Spacer(),
          AuroraButton(
              label: 'Use this signature',
              icon: Icons.check_rounded,
              onPressed: _captureSignature),
        ]),
      );
    }
    // Stage 2: pick PDF
    if (_pdf == null || _pagePreview == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            frosted: true,
            strong: true,
            onTap: _pickPdf,
            padding:
                const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.picture_as_pdf_rounded,
                  color: AppColors.cyan, size: 40),
              const SizedBox(height: 12),
              Text('Choose the PDF to sign',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
          ),
        ),
      );
    }
    // Stage 3: position on preview
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            return Center(
              child: AspectRatio(
                aspectRatio: 210 / 297, // preview letterboxed to A4-ish
                child: LayoutBuilder(builder: (context, page) {
                  final w = page.maxWidth;
                  final h = page.maxHeight;
                  final sigW = w * _relW;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(children: [
                      Positioned.fill(
                          child:
                              Image.memory(_pagePreview!, fit: BoxFit.fill)),
                      Positioned(
                        left: _relX * w - sigW / 2,
                        top: _relY * h - sigW * 0.35,
                        child: GestureDetector(
                          onPanUpdate: (d) => setState(() {
                            _relX = (_relX + d.delta.dx / w).clamp(0.05, 0.95);
                            _relY = (_relY + d.delta.dy / h).clamp(0.05, 0.95);
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.violet, width: 1.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Image.memory(_signature!, width: sigW),
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.photo_size_select_small_rounded,
              size: 18, color: AppColors.cyan),
          Expanded(
            child: Slider(
              value: _relW,
              min: 0.15,
              max: 0.6,
              activeColor: AppColors.violet,
              onChanged: (v) => setState(() => _relW = v),
            ),
          ),
        ]),
        if (_pageCount > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                onPressed:
                    _page > 1 ? () => _loadPage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded)),
            Text('Page $_page / $_pageCount',
                style: Theme.of(context).textTheme.bodyLarge),
            IconButton(
                onPressed:
                    _page < _pageCount ? () => _loadPage(_page + 1) : null,
                icon: const Icon(Icons.chevron_right_rounded)),
          ]),
        const SizedBox(height: 8),
        AuroraButton(
            label: 'Place & save',
            icon: Icons.draw_rounded,
            onPressed: _place),
      ]),
    );
  }
}
