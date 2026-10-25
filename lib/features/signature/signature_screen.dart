import 'dart:typed_data';
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:signature/signature.dart' as sig;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../services/file_service.dart';
import '../../services/pdf_service.dart';
import '../../services/raster_service.dart';
import '../home/tools.dart';
import '../tool/pick_zone.dart';
import '../tool/tool_bloc.dart';
import '../tool/tool_header.dart';
import '../tool/tool_stages.dart';

/// Sign flow: draw → pick page → drag the signature on a live page preview
/// → resize with a slider → place. Preview coordinates map 1:1 to PDF
/// coordinates (relative centre + relative width). Steps slide sideways.
class SignatureScreen extends StatelessWidget {
  const SignatureScreen({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ToolBloc(),
      child: Scaffold(
        backgroundColor: context.nova.canvas,
        appBar: AppBar(),
        body: BlocConsumer<ToolBloc, ToolState>(
          listener: (context, state) {
            if (state is ToolFailure) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.message)));
            }
          },
          builder: (context, state) => ToolStages(
            state: state,
            processingLabel: 'Placing your signature',
            input: _SignFlow(tool: tool),
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

  int get _step => _signature == null
      ? 0
      : (_pdf == null || _pagePreview == null)
          ? 1
          : 2;

  @override
  Widget build(BuildContext context) {
    final step = _step;
    return Column(children: [
      _Steps(step: step),
      Expanded(
        child: PageTransitionSwitcher(
          duration: NovaMotion.page,
          transitionBuilder: (child, a, b) => SharedAxisTransition(
            animation: a,
            secondaryAnimation: b,
            transitionType: SharedAxisTransitionType.horizontal,
            fillColor: context.nova.canvas,
            child: child,
          ),
          child: KeyedSubtree(
            key: ValueKey(step),
            child: switch (step) {
              0 => _drawStage(context),
              1 => _pickStage(context),
              _ => _placeStage(context),
            },
          ),
        ),
      ),
    ]);
  }

  Widget _drawStage(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          // The pad needs the drag gestures; don't let the list steal them.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ToolHeader(tool: widget.tool, subtitle: 'Draw your signature below'),
            Container(
              height: 230,
              decoration: BoxDecoration(
                color: Colors.white, // paper, in both themes
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 52,
                  child: Container(height: 1, color: const Color(0xFFD9D4CA)),
                ),
                const Positioned(
                  left: 24,
                  bottom: 58,
                  child: Text('×',
                      style: TextStyle(fontSize: 18, color: Color(0xFFB5AFA3))),
                ),
                sig.Signature(
                    controller: _controller,
                    backgroundColor: Colors.transparent),
              ]),
            ).enter(context, delayMs: 200),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _controller.clear,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('Clear', style: t.labelLarge?.copyWith(color: c.accent)),
              ),
            ),
          ],
        ),
      ),
      ToolActionBar(
        child: NovaButton(
            label: 'Use this signature',
            icon: Icons.arrow_forward_rounded,
            onPressed: _captureSignature),
      ),
    ]);
  }

  Widget _pickStage(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Center(
            child: Container(
              height: 90,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.nova.border),
              ),
              child: Image.memory(_signature!),
            ),
          ).enter(context),
          const SizedBox(height: 20),
          PickZone(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Choose the PDF to sign',
            hint: 'You will place the signature on a live preview',
            onTap: _pickPdf,
          ).enter(context, delayMs: 80),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _signature = null),
              child: const Text('Redraw signature'),
            ),
          ),
        ],
      );

  Widget _placeStage(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Center(
            child: AspectRatio(
              aspectRatio: 210 / 297, // preview letterboxed to A4-ish
              child: LayoutBuilder(builder: (context, page) {
                final w = page.maxWidth;
                final h = page.maxHeight;
                final sigW = w * _relW;
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(children: [
                      Positioned.fill(
                          child: Image.memory(_pagePreview!, fit: BoxFit.fill)),
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
                              border: Border.all(color: c.accent, width: 1.5),
                              borderRadius: BorderRadius.circular(6),
                              color: c.accent.withValues(alpha: 0.06),
                            ),
                            child: Image.memory(_signature!, width: sigW),
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              }),
            ),
          ).enter(context),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Icon(Icons.photo_size_select_small_rounded, size: 18, color: c.inkLow),
          Expanded(
            child: Slider(
              value: _relW,
              min: 0.15,
              max: 0.6,
              onChanged: (v) => setState(() => _relW = v),
            ),
          ),
          if (_pageCount > 1) ...[
            IconButton(
                tooltip: 'Previous page',
                onPressed: _page > 1 ? () => _loadPage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded)),
            Text('$_page / $_pageCount', style: t.labelMedium),
            IconButton(
                tooltip: 'Next page',
                onPressed:
                    _page < _pageCount ? () => _loadPage(_page + 1) : null,
                icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ]),
      ),
      ToolActionBar(
        child: NovaButton(
            label: 'Place & save',
            icon: Icons.draw_outlined,
            onPressed: _place),
      ),
    ]);
  }
}

/// "Draw · Choose · Place" progress dots.
class _Steps extends StatelessWidget {
  const _Steps({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(children: [
        for (final (i, label) in const ['Draw', 'Choose PDF', 'Place'].indexed)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: NovaMotion.page,
                  curve: NovaMotion.emphasized,
                  height: 4,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: i <= step ? c.accent : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(label,
                    style: t.labelSmall?.copyWith(
                        color: i == step ? c.ink : c.inkLow,
                        letterSpacing: 0.3)),
              ],
            ),
          ),
      ]),
    );
  }
}
